# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format.
$currentUTCtime = (Get-Date).ToUniversalTime()

# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"

# This program will cycle through all resources in in every subscriptions, check which resources
# have diagnostic settings enabled, and then check what categories are available for that resource. 
# If logs aren't enabled it will enable them for the resource.
$startTime = Get-Date
$primaryRegion = "westus"

$logAnalyticsPrimary= ""
$logAnalyticsSecondary = ""
$resourceCount = 0
$subscriptions = Get-AzSubscription | Where-Object {$_.SubscriptionName -notlike "Core Services*"}
foreach ($subscription in $subscriptions)
    {
    set-azcontext -SubscriptionId $subscription.Id
    $resources = Get-AzResource #| Out-File C:\temp\diag.txt

    foreach ($resource in $resources) 
        {
            if ($resource.ResourceType -notlike 'Microsoft.Automation/automationAccounts*' -and `
            $resource.ResourceType -notlike 'Microsoft.ApiManagement/service*' -and `
            $resource.ResourceType -notlike 'Microsoft.AzureActiveDirectory/b2cDirectories*' -and `
            $resource.ResourceType -notlike 'microsoft.alertsmanagement/smartDetectorAlertRules*' -and `
            $resource.ResourceType -notlike 'Microsoft.Compute/availabilitySets*' -and `
            $resource.ResourceType -notlike 'Microsoft.Compute/disks*' -and `
            $resource.ResourceType -notlike 'Microsoft.Compute/images*' -and `
            $resource.ResourceType -notlike 'Microsoft.Compute/virtualMachines*' -and `
            $resource.ResourceType -notlike 'Microsoft.Compute/snapshots*' -and `
            $resource.ResourceType -notlike 'Microsoft.Compute/galleries*' -and `
            $resource.ResourceType -notlike 'Microsoft.compute/restorepointcollections*' -and `
            $resource.ResourceType -notlike 'Microsoft.ContainerInstance/containerGroups*' -and `
            $resource.ResourceType -notlike 'Microsoft.DocumentDB/databaseAccounts*' -and `
            $resource.ResourceType -notlike 'Microsoft.DataMigration/SqlMigrationServices*' -and `
            $resource.ResourceType -notlike 'Microsoft.Databricks/workspaces*' -and `
            $resource.ResourceType -notlike 'Microsoft.Databricks/workspaces/privateEndpointConnections*' -and `
            $resource.ResourceType -notlike 'Microsoft.Databricks/workspaces/virtualNetworkPeerings*' -and `
            $resource.ResourceType -notlike 'Microsoft.Web/certificates*' -and `
            $resource.ResourceType -notlike 'Microsoft.SqlVirtualMachine/SqlVirtualMachines*' -and `
            $resource.ResourceType -notlike 'Microsoft.Insights/scheduledqueryrules*' -and `
            $resource.ResourceType -notlike 'Microsoft.Insights/metricalerts*' -and `
            $resource.ResourceType -notlike 'Microsoft.Insights/dataCollectionRules*' -and `
            $resource.ResourceType -notlike 'Microsoft.Insights/components*' -and `
            $resource.ResourceType -notlike 'Microsoft.Insights/actiongroups*' -and `
            $resource.ResourceType -notlike 'Microsoft.Insights/diagnostics*' -and `
            $resource.ResourceType -notlike 'Microsoft.Insights/diagnosticSettings*' -and `
            $resource.ResourceType -notlike 'Microsoft.Insights/*' -and `
            $resource.ResourceType -notlike 'Microsoft.Logic/workflows*' -and `
            $resource.ResourceType -notlike 'Microsoft.maintenance/*' -and `
            $resource.ResourceType -notlike 'microsoft.managedidentity/userassignedidentities*' -and `
            $resource.ResourceType -notlike 'Microsoft.NetApp/netAppAccounts*' -and `
            $resource.ResourceType -notlike 'Microsoft.Network/privateEndpoints*' -and `
            $resource.ResourceType -notlike 'Microsoft.Network/azureFirewalls*' -and `
            $resource.ResourceType -notlike 'Microsoft.network/expressroutegateways*' -and `
            $resource.ResourceType -notlike 'Microsoft.Network/firewallPolicies*' -and `
            $resource.ResourceType -notlike 'Microsoft.Network/localNetworkGateways*' -and `
            $resource.ResourceType -notlike 'Microsoft.Network/natGateways*' -and `
            $resource.ResourceType -notlike 'Microsoft.Network/privateDnsZones*' -and `
            $resource.ResourceType -notlike 'Microsoft.Network/routeTables*' -and `
            $resource.ResourceType -notlike 'Microsoft.Network/networkwatchers*' -and `
            $resource.ResourceType -notlike 'microsoft.network/applicationgatewaywebapplicationfirewallpolicies*' -and `
            $resource.ResourceType -notlike 'microsoft.databricks/accessconnectors*' -and `
            $resource.ResourceType -notlike 'microsoft.network/networkintentpolicies*' -and `
            $resource.ResourceType -notlike 'Microsoft.OperationsManagement/solutions*' -and `
            $resource.ResourceType -notlike 'microsoft.operationalinsights/querypacks*' -and `
            $resource.ResourceType -notlike 'Microsoft.Portal/dashboards*' -and `
            $resource.ResourceType -notlike 'Microsoft.Resources/templateSpecs*' -and `
            $resource.ResourceType -notlike 'Microsoft.Sql/servers/databases*' -and `
            $resource.ResourceType -notlike 'Microsoft.Web/staticSites*' -and `
            $resource.ResourceType -notlike 'Microsoft.Web/customApis*' -and `
            $resource.ResourceType -notlike 'Microsoft.Web/site*s' -and `
            $resource.ResourceType -notlike 'Microsoft.Web/sites/slots*' -and `
            $resource.ResourceType -notlike 'microsoft.visualstudio/account*' -and `
            $resource.ResourceType -notlike 'Microsoft.virtualmachineimages/imagetemplates*' -and `
            $resource.ResourceType -notlike 'microsoft.compute/sshpublickeys*' -and `
            $resource.ResourceType -notlike 'Microsoft.Web/connections*') 
            {
                if ($resource.ResourceType -like 'Microsoft.Storage/storageAccounts*')
                    {
                        $BlobId = -join ($resource.Id, "/blobServices/default")
                        $FileId = -join ($resource.Id, "/fileServices/default")
                        $QueueId = -join ($resource.Id, "/queueServices/default")
                        $TableId = -join ($resource.Id, "/tableServices/default")
                        
                        $Status = Get-AzDiagnosticSetting -ResourceId $resource.Id -ErrorAction SilentlyContinue
                        $blobStatus = Get-AzDiagnosticSetting -ResourceId $BlobId -ErrorAction SilentlyContinue
                        $fileStatus = Get-AzDiagnosticSetting -ResourceId $FileId -ErrorAction SilentlyContinue
                        $queueStatus = Get-AzDiagnosticSetting -ResourceId $QueueId -ErrorAction SilentlyContinue
                        $tableStatus = Get-AzDiagnosticSetting -ResourceId $TableId -ErrorAction SilentlyContinue
                        if ($resource.Location -eq $primaryRegion) {
                            $logAnalyticsWorkspaceId = $logAnalyticsPrimary
                        }
                        else {
                            $logAnalyticsWorkspaceId = $logAnalyticsSecondary
                        }
                        $wrongLogs = $Status.Name | Where-Object {$_ -notLike "all-Logs"}

                        if ($null -ne $wrongLogs)
                            {
                            Remove-AzDiagnosticSetting -ResourceId $resource.Id -Name $wrongLogs -Verbose -WarningAction SilentlyContinue
                            }
                        # Condition checks if the Diagnostic Setting doesn't exist or if any of the Logs and / or Metrics are disabled in the Diagnostic Setting
                        if ($null -eq $Status -or $Status.Logs.Enabled -contains $false -or $Status.Metrics.Enabled -contains $false) {
                                    
                            # Enables all Logs and / or Metrics on the current resource, if supported
                            #Set-AzDiagnosticSetting -ResourceId $Resource.Id -Name "all-logs-metrics" -Enabled $true -WorkspaceId $logAnalyticsWorkspaceId -ExportToResourceSpecific -Verbose -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                            $metric = @()
                            $log = @()
                            $categories = Get-AzDiagnosticSettingCategory -ResourceId $resource.Id
                            $categories | ForEach-Object { if ($_.CategoryType -eq "Metrics") { $metric += New-AzDiagnosticSettingMetricSettingsObject -Enabled $true -Category $_.Name } else { $log += New-AzDiagnosticSettingLogSettingsObject -Enabled $true -Category $_.Name } }
                            New-AzDiagnosticSetting -Name all-Logs -ResourceId $resource.id -WorkspaceId $logAnalyticsWorkspaceId -Log $log -Metric $metric
                        
                        
                        }
                        if ($null -eq $blobStatus -or $blobStatus.Logs.Enabled -contains $false -or $blobStatus.Metrics.Enabled -contains $false) {
                            $metric = @()
                            $log = @()
                            $categories = Get-AzDiagnosticSettingCategory -ResourceId $resource.Id
                            $categories | ForEach-Object { if ($_.CategoryType -eq "Metrics") { $metric += New-AzDiagnosticSettingMetricSettingsObject -Enabled $true -Category $_.Name } else { $log += New-AzDiagnosticSettingLogSettingsObject -Enabled $true -Category $_.Name } }
                            New-AzDiagnosticSetting -Name all-Logs -ResourceId $BlobId -WorkspaceId $logAnalyticsWorkspaceId -Log $log -Metric $metric
                        } 
                        if ($null -eq $fileStatus -or $fileStatus.Logs.Enabled -contains $false -or $fileStatus.Metrics.Enabled -contains $false) {
                            $metric = @()
                            $log = @()
                            $categories = Get-AzDiagnosticSettingCategory -ResourceId $resource.Id
                            $categories | ForEach-Object { if ($_.CategoryType -eq "Metrics") { $metric += New-AzDiagnosticSettingMetricSettingsObject -Enabled $true -Category $_.Name } else { $log += New-AzDiagnosticSettingLogSettingsObject -Enabled $true -Category $_.Name } }
                            New-AzDiagnosticSetting -Name all-Logs -ResourceId $FileId -WorkspaceId $logAnalyticsWorkspaceId -Log $log -Metric $metric
                        }
                        if ($null -eq $queueStatus -or $queueStatus.Logs.Enabled -contains $false -or $queueStatus.Metrics.Enabled -contains $false) {
                            $metric = @()
                            $log = @()
                            $categories = Get-AzDiagnosticSettingCategory -ResourceId $resource.Id
                            $categories | ForEach-Object { if ($_.CategoryType -eq "Metrics") { $metric += New-AzDiagnosticSettingMetricSettingsObject -Enabled $true -Category $_.Name } else { $log += New-AzDiagnosticSettingLogSettingsObject -Enabled $true -Category $_.Name } }
                            New-AzDiagnosticSetting -Name all-Logs -ResourceId $QueueId -WorkspaceId $logAnalyticsWorkspaceId -Log $log -Metric $metric
                        }
                        if ($null -eq $tableStatus -or $tableStatus.Logs.Enabled -contains $false -or $tableStatus.Metrics.Enabled -contains $false) {
                            $metric = @()
                            $log = @()
                            $categories = Get-AzDiagnosticSettingCategory -ResourceId $resource.Id
                            $categories | ForEach-Object { if ($_.CategoryType -eq "Metrics") { $metric += New-AzDiagnosticSettingMetricSettingsObject -Enabled $true -Category $_.Name } else { $log += New-AzDiagnosticSettingLogSettingsObject -Enabled $true -Category $_.Name } }
                            New-AzDiagnosticSetting -Name all-Logs -ResourceId $TableId -WorkspaceId $logAnalyticsWorkspaceId -Log $log -Metric $metric
                        }    
                    }
            
                $resourceCount++
                # Get the diagnostic setting categories for the resource
                $Status = Get-AzDiagnosticSetting -ResourceId $resource.Id -ErrorAction SilentlyContinue

                if ($resource.Location -eq $primaryRegion) {
                    $logAnalyticsWorkspaceId = $logAnalyticsPrimary
                }
                else {
                    $logAnalyticsWorkspaceId = $logAnalyticsSecondary
                }
                $wrongLogs = $Status.Name | Where-Object {$_ -notLike "all-Logs"}
                if ($null -ne $wrongLogs)
                    {
                    Remove-AzDiagnosticSetting -ResourceId $resource.Id -Name $wrongLogs -Verbose -WarningAction SilentlyContinue
                    }
                # Condition checks if the Diagnostic Setting doesn't exist or if any of the Logs and / or Metrics are disabled in the Diagnostic Setting
                if ($null -eq $Status -or $Status.Logs.Enabled -contains $false -or $Status.Metrics.Enabled -contains $false) {
            
                    # Enables all Logs and / or Metrics on the current resource, if supported
                    #Set-AzDiagnosticSetting -ResourceId $Resource.Id -Name "all-logs-metrics" -Enabled $true -WorkspaceId $logAnalyticsWorkspaceId -ExportToResourceSpecific -Verbose -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                    $metric = @()
                    $log = @()
                    $categories = Get-AzDiagnosticSettingCategory -ResourceId $resource.Id
                    $categories | ForEach-Object {if($_.CategoryType -eq "Metrics"){$metric+=New-AzDiagnosticSettingMetricSettingsObject -Enabled $true -Category $_.Name} else{$log+=New-AzDiagnosticSettingLogSettingsObject -Enabled $true -Category $_.Name}}
                    New-AzDiagnosticSetting -Name all-Logs -ResourceId $resource.id -WorkspaceId $logAnalyticsWorkspaceId -Log $log -Metric $metric
                } 
            }
        }
    }

# Stop the timer
$endTime = Get-Date
$totalTime = $endTime - $startTime
$averageTimePerResource = $totalTime.TotalSeconds / $resourceCount

# Output the timing information
Write-Output "Total time: $totalTime"
Write-Output "Total resources: $resourceCount"
Write-Output "Average time per resource: ${averageTimePerResource}s"
