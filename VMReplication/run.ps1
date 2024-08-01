
$startTime = Get-Date
# Set variables
$sourceResourceGroupName = "cisnafrg01"
$targetResourceGroupName = "$sourceResourceGroupName-DR"
$targetRegion = "East US"

$existingRG = Get-AzResourceGroup -Name $targetResourceGroupName -ErrorAction SilentlyContinue 
if (!$existingRG) {
	New-AzResourceGroup -Name $targetResourceGroupName -Location $targetRegion
}

# Get all VMs in the source resource group
$vms = Get-AzVM -ResourceGroupName $sourceResourceGroupName

foreach ($vm in $vms) {
	# Take a snapshot of the OS disk
    function Snapshots {
        param($diskName)
        $osDisk = Get-AzDisk -ResourceGroupName $sourceResourceGroupName -DiskName $diskName
        $snapshotConfig = New-AzSnapshotConfig -SourceUri $osDisk.Id -Location $osDisk.Location -CreateOption Copy -Incremental
        $snapshotName = $diskName + "_Snapshot_" + (Get-Date -Format "yyyyMMddHHmmss")
        $snapshotNameDR = $diskName + "_DR_" + (Get-Date -Format "yyyyMMddHHmmss")
        $osSnapshot = New-AzSnapshot -Snapshot $snapshotConfig -SnapshotName $snapshotName -ResourceGroupName $targetResourceGroupName
        $snapshotconfig = New-AzSnapshotConfig -Location $targetRegion -CreateOption CopyStart -Incremental -SourceResourceId $OsSnapshot.Id
        $drSnapshot = New-AzSnapshot -ResourceGroupName $targetResourceGroupName -SnapshotName $snapshotNameDR -Snapshot $snapshotconfig
    }

    <# do {
        $drSnapshot = Get-AzSnapshot -ResourceGroupName $targetResourceGroupName -SnapshotName $snapshotNameDR
        $drSnapshot.CompletionPercent
        Start-Sleep -Seconds 10
    } while ($drSnapshot.CompletionPercent -lt 100) #>
    Snapshots -diskName $vm.StorageProfile.OsDisk.Name 
    foreach ($dataDisk in $vm.StorageProfile.DataDisks) {
        Snapshots -diskName $dataDisk.Name 
    }
}
do {

     $status = Get-AzSnapshot -ResourceGroupName $targetResourceGroupName | where {$_.CompletionPercent -lt 100 -and $_.Name -like "*DR*"} 
     $status | ft Name, CompletionPercent
    Start-Sleep -Seconds 10
   } while ($status.CompletionPercent -lt 100 -and $status.CompletionPercent -ne $null)
$endTime = Get-Date

#Get-AzSnapshot -ResourceGroupName $targetResourceGroupName | where {$_.Location -eq "westus"} | Remove-AzSnapshot -Force

# Calculate Duration
$duration = $endTime - $startTime

# Display Duration
Write-Output "Total operation time: $($duration.Hours) hours, $($duration.Minutes) minutes, $($duration.Seconds) seconds."