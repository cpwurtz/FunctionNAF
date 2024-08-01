<#
.Synopsis
This script tests AzCopy sync functionality with the binary called from a storage account.

.DESCRIPTION
This script tests AzCopy sync functionality with the binary called from a storage account.
.Notes
Created   : 2024-06-28
Updated   : 2024-07-31
Version   : 1.0.9
Author    : @Neudesic, an IBM Company. Dave West dave.west@neudesic.com
Twitter   : @neudesic.com
Web       : https://neudesic.com

Disclaimer: This script is provided "AS IS" with no warranties.
#>

param($Timer)

function Get-EnvironmentVariables {
    $global:binStorageAccountName = $env:BIN_STORAGE_ACCOUNT_NAME
    $global:binStorageAccountRG = $env:BIN_STORAGE_ACCOUNT_RG
    $global:binStorageAccountSubId = $env:BIN_STORAGE_ACCOUNT_SUB_ID
    Write-Host "Binary storage account: $binStorageAccountName"
    Write-Host "Binary storage account resource group: $binStorageAccountRG"

    $global:containerBins = $env:BINS_CONTAINER_NAME
    Write-Host "Bins container: $containerBins"

    $syncConfigJSON = $env:SYNC_CONFIG_JSON
    $global:syncConfigs = ($syncConfigJSON | ConvertFrom-Json).configs
    Write-Host "Sync configs: $syncConfigs"
    $global:cloudEnvironment = Get-CloudEnvironment
}

function Get-CloudEnvironment {
    $context = Get-AzContext
    if ($null -eq $context) {
        Write-Error "No Azure context found. Please login using Connect-AzAccount."
        return
    }
    $environment = $context.Environment.Name
    Write-Host "Current Azure Cloud Environment: $environment"
    return $environment
}

function Get-StorageContext($resourceGroupName, $storageAccountName) {
    Write-Host "Getting context for storage account: $storageAccountName..."
    $storageAccountKeys = Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName
    $storageAccountKey = $storageAccountKeys[0].Value
    return New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
}

function Generate-SASToken($context, $permission, $startTime, $expiryTime) {
    return New-AzStorageAccountSASToken -Service Blob, File -ResourceType Service, Container, Object -Context $context -Permission $permission -StartTime $startTime -ExpiryTime $expiryTime -Protocol HttpsOnly
}

function Download-AzCopyBinary($context, $container, $blobName, $destinationPath) {
    Set-AzContext -SubscriptionId $binStorageAccountSubId

    Write-Host "Downloading AzCopy binary..."
    Get-AzStorageBlobContent -Container $container -Blob $blobName -Destination $destinationPath -Context $context -Force
    Write-Host "Download complete."
}

function Calculate-TotalDataVolume($context, $containers) {
    $totalSizeInBytes = 0
    foreach ($container in $containers) {
        $blobs = Get-AzStorageBlob -Container $container -Context $context
        foreach ($blob in $blobs) {
            $totalSizeInBytes += $blob.Length
        } 
    }
    return $totalSizeInBytes / 1e+12
}

function Sync-StorageAccounts($syncConfigs, $sourceSyncStorageAccountName, $destSyncStorageAccountName, $azCopyPath, $totalSizeInTerabytes) {
    $totalDurationInSeconds = 0
    $totalSizeInTerabytes = 0
    foreach ($config in $syncConfigs) {
        $sourceResourceGroup = $config.SourceResourceGroup
        $destResourceGroup = $config.DestResourceGroup
        $syncSaPrefix = $config.SyncSaPrefix
        $sourceLocationSuffix = $config.SourceLocationSuffix
        $destLocationSuffix = $config.DestLocationSuffix
        $subscriptionId = $config.SubscriptionId     
        
        Write-Host "config: $config"
        
        Set-AzContext -SubscriptionId $subscriptionId

        $sourceSyncStorageAccountName = "${syncSaPrefix}${sourceLocationSuffix}"
        Write-Host "Source sync storage account: $sourceSyncStorageAccountName"
        $destSyncStorageAccountName = "${syncSaPrefix}${destLocationSuffix}"
        Write-Host "Destination sync storage account: $destSyncStorageAccountName"

        $sourceContext = Get-StorageContext -resourceGroupName $sourceResourceGroup -storageAccountName $sourceSyncStorageAccountName -SubscriptionId $subscriptionId
        $destContext = Get-StorageContext -resourceGroupName $destResourceGroup -storageAccountName $destSyncStorageAccountName

        $containers = Get-AzStorageContainer -Context $sourceContext | Select-Object -ExpandProperty Name

        $totalSizeInTerabytes += Calculate-TotalDataVolume -context $sourceContext -containers $containers

        $duration = (Sync-Containers -containers $containers -sourceSyncStorageAccountName $sourceSyncStorageAccountName -destSyncStorageAccountName $destSyncStorageAccountName -sourceContext $sourceContext -destContext $destContext -azCopyPath $azCopyPath -totalSizeInTerabytes $totalSizeInTerabytes)[-1]

        Write-Host "Duration to sync ${sourceSyncStorageAccountName}: $duration"

        $durationVariableType = $duration.GetType().Name
        Write-Host "Duration variable type: $($durationVariableType.FullName)"

        $totalDurationInSeconds += $duration
    }
    $timePerTerabyte = $totalDurationInSeconds / $totalSizeInTerabytes

    $hours = [math]::Floor($timePerTerabyte / 3600)
    $minutes = [math]::Floor(($timePerTerabyte % 3600) / 60)
    $secondsLeft = $timePerTerabyte % 60
    Write-Host "Total time to sync all containers: $totalDurationInSeconds seconds."
    Write-Host "Total size in terabytes: $totalSizeInTerabytes."
    Write-Host "Time per Terabyte: $hours hours, $minutes minutes, and $secondsLeft seconds."
}

function Sync-Containers ($containers, $sourceSyncStorageAccountName, $destSyncStorageAccountName,  $sourceContext, $destContext, $azCopyPath, $totalSizeInTerabytes) {
    $totalDurationInSeconds = 0
    foreach ($syncContainerName in $containers) {
        $totalSizeInBytes = 0

        $blobs = Get-AzStorageBlob -Container $syncContainerName -Context $sourceContext
        foreach ($blob in $blobs) {
            $totalSizeInBytes += $blob.Length
        }

        Write-Host "Syncing container: $syncContainerName"

        $sourceSASToken = New-AzStorageContainerSASToken -Context $sourceContext -Name $syncContainerName -Permission "rwl" -StartTime (Get-Date).AddHours(-3).ToString("yyyy-MM-ddTHH:mm:ssZ") -ExpiryTime (Get-Date).AddDays(4).ToString("yyyy-MM-ddTHH:mm:ssZ") -Protocol HttpsOnly
        $destinationSASToken = New-AzStorageContainerSASToken -Context $destContext -Name $syncContainerName -Permission "rwl" -StartTime (Get-Date).AddHours(-3).ToString("yyyy-MM-ddTHH:mm:ssZ") -ExpiryTime (Get-Date).AddDays(4).ToString("yyyy-MM-ddTHH:mm:ssZ") -Protocol HttpsOnly

        if ($cloudEnvironment -eq "AzureCloud") {
            $storageBaseUrl = "privatelink.dfs.core.windows.net"
        }
        elseif ($cloudEnvironment -eq "AzureUSGovernment") {
            $storageBaseUrl = "privatelink.dfs.core.usgovcloudapi.net"
        }

        $sourceURL = "https://$sourceSyncStorageAccountName.${storageBaseUrl}/${syncContainerName}?${sourceSASToken}"
        Write-Host "Source URL: $sourceURL"
        $destinationURL = "https://$destSyncStorageAccountName.${storageBaseUrl}/${syncContainerName}?${destinationSASToken}"
        Write-Host "Destination URL: $destinationURL"

        if (!(Get-AzStorageContainer -Name $syncContainerName -Context $destContext -ErrorAction SilentlyContinue)) {
            Write-Host "Creating destination container: $syncContainerName"
            New-AzStorageContainer -Name $syncContainerName -Context $destContext
        }

        $azCopyCommand = { & $using:azCopyPath sync $using:sourceURL $using:destinationURL --recursive }

        $startSyncTime = Get-Date
        $syncJob = Start-ThreadJob -ScriptBlock $azCopyCommand
        $syncJob | Wait-Job
        $syncResult = $syncJob | Receive-Job

        if ($syncJob.State -eq "Failed") {
            Write-Error "An error occurred during the sync operation: $($syncJob.ChildJobs[0].Error[0])"
        }
        else {
            $endSyncTime = Get-Date
            $duration = $endSyncTime - $startSyncTime
            $durationInSeconds = $duration.TotalSeconds
            Write-Output "Synced container $container in $durationInSeconds seconds."
            try {
                $totalDurationInSeconds += $durationInSeconds
            } catch {
                Write-Output "WARN: Failed to add duration to total duration for $syncContainerName."
            }

            Write-Output "Sync operation completed successfully."
            Write-Output $syncResult
        }
    }
    $syncJob | Remove-Job
    Write-Host "Total duration: $totalDurationInSeconds seconds."
    return $totalDurationInSeconds
}

# Main script execution

Get-EnvironmentVariables
If ($AzCopyExists -eq $False)
{
    Write-Host "AzCopy not found. Downloading..."
    
    #Download AzCopy
    Invoke-WebRequest -Uri "https://aka.ms/downloadazcopy-v10-windows" -OutFile AzCopy.zip -UseBasicParsing
 
    #Expand Archive
    write-host "Expanding archive..."
    Expand-Archive ./AzCopy.zip ./AzCopy -Force

    # Copy AzCopy to current dir
    Get-ChildItem ./AzCopy/*/azcopy.exe | Copy-Item -Destination "./AzCopy.exe"
}
else
{
    Write-Host "AzCopy found, skipping download."
}

# Set env values for AzCopy
$env:AZCOPY_LOG_LOCATION = $env:temp+'\.azcopy'
$env:AZCOPY_JOB_PLAN_LOCATION = $env:temp+'\.azcopy'
Set-AzContext -SubscriptionId $binStorageAccountSubId

$binCtx = Get-StorageContext -resourceGroupName $binStorageAccountRG -storageAccountName $binStorageAccountName -SubscriptionId $binStorageAccountSubId

$blobName = "azcopy.exe"
$destinationPath = "D:\local\Temp\$blobName"
Download-AzCopyBinary -context $binCtx -container $containerBins -blobName $blobName -destinationPath $destinationPath

Sync-StorageAccounts -syncConfigs $syncConfigs -sourceSyncStorageAccountName $sourceSyncStorageAccountName -destSyncStorageAccountName $destSyncStorageAccountName -azCopyPath "D:\local\Temp\azcopy.exe" -totalSizeInTerabytes $totalSizeInTerabytes