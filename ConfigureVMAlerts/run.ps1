# Input bindings are passed in via param block.
param($Timer)

## Tags
$zzzrgName = 'to-delete-rg'
$tagAlertNotification = 'ConfigureAlerts'
$tagEnvironment = 'Environment'


## ActionGroup 
$environment = "non-prod"
$agName = "Azure VM alerts - NonProd"
$agShortName = "AzAlerts"
$agEmail = "Azure.vm@domain.com"
$agEmailName = "Email Notification"

$prodAgName = "Azure VM alerts - Prod"
$prodAgShortName = "AzAlerts"
$prodAgEmail = "Azure.vm@domain.com"
$prodAgEmailName = "Email Notification"
$prodSmsName = "smsReceiver"
$prodSmsPhoneNumber = "4255550123"

## VM thresholds
$cpuPercent = 90
$osDiskBandwidth = 90
$networkInTotal = 500000000000 # 500GB
$networkOutTotal = 200000000000 # 200GB
$osDiskIOPS = 95
$dataDiskIOPS = 95
$avblMemory = 1000000000 # 1000MB

$prodCpuPercent = 80
$prodOsDiskBandwidth = 80
$prodNetworkInTotal = 500000000000 # 500GB
$prodNetworkOutTotal = 200000000000 # 200GB
$prodOsDiskIOPS = 80
$prodDataDiskIOPS = 80
$prodAvblMemory = 1000000000 # 1000MB

## Get list of subscriptions 
$subscriptions = (Get-AzSubscription).Id
$WarningPreference = 'SilentlyContinue'

ForEach ($subscription in $subscriptions) {
    # Get the subscription 
    Get-AzSubscription -SubscriptionId $subscription
    Set-AzContext -SubscriptionId $subscription

    $subTags = Get-AzTag -ResourceId /subscriptions/$subscription
   
    foreach ($tagKey in $subTags.Properties.TagsProperty.Keys) {
        # $tagKey contains the tag key
        $tagValue = $subTags.Properties.TagsProperty[$tagEnvironment]

        if ($tagValue.ToLower() -eq 'prod') {
            $environment = 'prod'
        }
        else {
            $environment = 'non-prod'
        }
    }
}
# Get all resource groups in subscription
$rgNames = (Get-AzResourceGroup).ResourceGroupName
foreach ($rgName in $rgNames) { 

    #region Action Groups
    ## Create Action group in each Resource Group
    if ($environment -eq 'non-prod') {

        # Check if Action Group exists in current RG
        $ag = Get-AzActionGroup -ResourceGroupName $rgName -Name $agName -ErrorVariable notPresent -ErrorAction SilentlyContinue

        if ($notPresent) {

            $email1 = New-AzActionGroupReceiver -Name $agEmailName -EmailReceiver -EmailAddress $agEmail
            $actionGroup = Set-AzActionGroup -ResourceGroupName $rgName -ShortName $agShortName -Name $agName -Receiver $email1
            Write-Host "Provisioned action group - $agName in $rgName resource group" -ForegroundColor Green
    
            # Get ActionGroup Id
            $actionGroupId = $actionGroup.Id
        }

        else {
            Write-Host "Action group - $agName in $rgName resource group already exists" -ForegroundColor Green
            # Get ActionGroup Id
            $actionGroupId = $ag.Id
        } 

    }
    elseif ($environment -eq 'prod') {

        # Check if Action Group exists in current RG
        $agProd = Get-AzActionGroup -ResourceGroupName $rgName -Name $prodAgName -ErrorVariable notPresent -ErrorAction SilentlyContinue

        if ($notPresent) {
            $email2 = New-AzActionGroupReceiver -Name $prodAgEmailName -EmailReceiver -EmailAddress $prodAgEmail
            $smsReceiver = New-AzActionGroupReceiver -Name $prodSmsName -SmsReceiver -CountryCode '1' -PhoneNumber $prodSmsPhoneNumber
            $prodActionGroup = Set-AzActionGroup -ResourceGroupName $rgName -ShortName $prodAgShortName -Name $prodAgName -Receiver $email2, $smsReceiver
            Write-Host "Provisioned action group - $prodAgName in $rgName resource group" -ForegroundColor Green

            # Get ActionGroup Id      
            $prodActionGroupId = $prodActionGroup.Id
        }
        else {
            Write-Host "Action group - $prodAgName in $rgName resource group already exists" -ForegroundColor Green
            # Get ActionGroup Id      
            $prodActionGroupId = $agProd.Id

        }
    }
    #endregion Action Groups 

    #region Virtual Machines

    # Get all VM's in current resource group
    $vmColl = Get-AzVM -ResourceGroupName $rgName
    if ($vmColl.Count -gt 0) {

        Write-Host "Found $($vmColl.Count) Virtual machine(s) in $rgName resource group" -ForegroundColor Cyan
        # Loop over all the vm's
        foreach ($vm in $vmColl) {
            $vmConditions = @(0..7)
            $prodVmConditions = @(0..7)
            # Get vm Account Id
            $vmResourceId = (Get-AzResource -Name $vm.Name).Id
  
            # Get tags on vm
            $vmTags = (Get-AzResource -Name $vm.Name).Tags
  
            if ($vmTags.Count -gt 0 -and $vmTags.Keys -eq $tagAlertNotification) {
                foreach ($Key in ($vmTags.GetEnumerator() | Where-Object { $_.Key -eq $tagAlertNotification } )) {
  
                    if ($Key.Value.ToLower() -eq 'yes') {
                                              
                        if ($environment -eq 'non-prod') {

                            # Get thresholds from tags  
                            if (($null -eq $vmTags.CpuPercentThreshold) -or ($null -eq $vmTags.OSDiskThreshold) -or ($null -eq $vmTags.NetworkInThreshold) -or ($null -eq $vmTags.NetworkOutThreshold) -or ($null -eq $vmTags.OSDiskIOPSThreshold) -or ($null -eq $vmTags.DataDiskIOPSThreshold) -or ($null -eq $vmTags.AvailableMemoryThreshold)) {
                                $tag = @{'CpuPercentThreshold' = '90'; 'OSDiskThreshold' = '90'; 'NetworkInThreshold' = '500000000000'; 'NetworkOutThreshold' = '200000000000'; 'OSDiskIOPSThreshold' = '95'; 'DataDiskIOPSThreshold' = '95'; 'AvailableMemoryThreshold' = '1000000000' }
                                Write-Host "No threshold tag(s) found on $($vm.Name) in $rgName resource group" -ForegroundColor Green
                                Update-AzTag -ResourceId $vmResourceId -Tag $tag -Operation Merge
                                Write-Host "Added threshold tag(s) on $($vm.Name) in $rgName resource group" -ForegroundColor Green
                                $cpuPercent = 90
                                $osDiskBandwidth = 90
                                $networkInTotal = 500000000000 # 500GB
                                $networkOutTotal = 200000000000 # 200GB
                                $osDiskIOPS = 95
                                $dataDiskIOPS = 95
                                $avblMemory = 1000000000 # 1000MB
                            }
                            else {
                                Write-Host "Found threshold tag(s) on $($vm.Name) in $rgName resource group" -ForegroundColor Green
                                $cpuPercent = $vmTags.CpuPercentThreshold
                                $osDiskBandwidth = $vmTags.OSDiskThreshold
                                $networkInTotal = $vmTags.NetworkInThreshold
                                $networkOutTotal = $vmTags.NetworkOutThreshold
                                $osDiskIOPS = $vmTags.OSDiskIOPSThreshold
                                $dataDiskIOPS = $vmTags.DataDiskIOPSThreshold
                                $avblMemory = $vmTags.AvailableMemoryThreshold
                            }
                            # alert threshold for non-prod Virtual machine                           
                            $vmConditions[0] = New-AzMetricAlertRuleV2Criteria -MetricName 'VmAvailabilityMetric' -TimeAggregation Average -Operator LessThan -Threshold 1
                            $vmConditions[1] = New-AzMetricAlertRuleV2Criteria -MetricName 'Percentage CPU' -TimeAggregation Average -Operator GreaterThan -Threshold $cpuPercent
                            $vmConditions[2] = New-AzMetricAlertRuleV2Criteria -MetricName 'OS Disk Bandwidth Consumed Percentage' -TimeAggregation Average -Operator GreaterThan -Threshold $osDiskBandwidth
                            $vmConditions[3] = New-AzMetricAlertRuleV2Criteria -MetricName 'Network In Total' -TimeAggregation Total -Operator GreaterThan -Threshold $networkInTotal
                            $vmConditions[4] = New-AzMetricAlertRuleV2Criteria -MetricName 'Network Out Total' -TimeAggregation Total -Operator GreaterThan -Threshold $networkOutTotal
                            $vmConditions[5] = New-AzMetricAlertRuleV2Criteria -MetricName 'OS Disk IOPS Consumed Percentage' -TimeAggregation Average -Operator GreaterThan -Threshold $osDiskIOPS
                            $vmConditions[6] = New-AzMetricAlertRuleV2Criteria -MetricName 'Data Disk IOPS Consumed Percentage' -TimeAggregation Average -Operator GreaterThan -Threshold $dataDiskIOPS
                            $vmConditions[7] = New-AzMetricAlertRuleV2Criteria -MetricName 'Available Memory Bytes' -TimeAggregation Average -Operator LessThan -Threshold $avblMemory

                            # Add alert
                            for ($i = 0; $i -lt $vmConditions.Length; $i++) {
                                Add-AzMetricAlertRuleV2 -Name "$($vmConditions[$i].MetricName) alerts for $($vm.Name)" -ResourceGroupName $rgName -WindowSize (New-TimeSpan -Minutes 15) -Frequency (New-TimeSpan -Minutes 15) -TargetResourceId $vmResourceId `
                                    -Condition $vmConditions[$i] -ActionGroupId $actionGroupId -Severity 3 -Description $($vmConditions[$i].MetricName)
                            }

                        }
                        elseif ($environment -eq 'prod') {

                            # Get thresholds from tags  
                            if (($null -eq $vmTags.CpuPercentThreshold) -or ($null -eq $vmTags.OSDiskThreshold) -or ($null -eq $vmTags.NetworkInThreshold) -or ($null -eq $vmTags.NetworkOutThreshold) -or ($null -eq $vmTags.OSDiskIOPSThreshold) -or ($null -eq $vmTags.DataDiskIOPSThreshold) -or ($null -eq $vmTags.AvailableMemoryThreshold)) {
                                $tag = @{'CpuPercentThreshold' = '80'; 'OSDiskThreshold' = '80'; 'NetworkInThreshold' = '500000000000'; 'NetworkOutThreshold' = '200000000000'; 'OSDiskIOPSThreshold' = '80'; 'DataDiskIOPSThreshold' = '80'; 'AvailableMemoryThreshold' = '1000000000' }
                                Write-Host "No threshold tag(s) found on $($vm.Name) in $rgName resource group" -ForegroundColor Green
                                Update-AzTag -ResourceId $vmResourceId -Tag $tag -Operation Merge
                                Write-Host "Added threshold tag(s) on $($vm.Name) in $rgName resource group" -ForegroundColor Green
                                $prodCpuPercent = 80
                                $prodOsDiskBandwidth = 80
                                $prodNetworkInTotal = 500000000000 # 500GB
                                $prodNetworkOutTotal = 200000000000 # 200GB
                                $prodOsDiskIOPS = 80
                                $prodDataDiskIOPS = 80
                                $prodAvblMemory = 1000000000 # 1000MB
                            }
                            else {
                                Write-Host "Found threshold tag(s) on $($vm.Name) in $rgName resource group" -ForegroundColor Green
                                $prodCpuPercent = $vmTags.CpuPercentThreshold
                                $prodOsDiskBandwidth = $vmTags.OSDiskThreshold
                                $prodNetworkInTotal = $vmTags.NetworkInThreshold
                                $prodNetworkOutTotal = $vmTags.NetworkOutThreshold
                                $prodOsDiskIOPS = $vmTags.OSDiskIOPSThreshold
                                $prodDataDiskIOPS = $vmTags.DataDiskIOPSThreshold
                                $prodAvblMemory = $vmTags.AvailableMemoryThreshold
                            }
                            # alert threshold for prod Virtual machine
                            $prodVmConditions[0] = New-AzMetricAlertRuleV2Criteria -MetricName 'VmAvailabilityMetric' -TimeAggregation Average -Operator LessThan -Threshold 1
                            $prodVmConditions[1] = New-AzMetricAlertRuleV2Criteria -MetricName 'Percentage CPU' -TimeAggregation Average -Operator GreaterThan -Threshold $prodCpuPercent
                            $prodVmConditions[2] = New-AzMetricAlertRuleV2Criteria -MetricName 'OS Disk Bandwidth Consumed Percentage' -TimeAggregation Average -Operator GreaterThan -Threshold $prodOsDiskBandwidth
                            $prodVmConditions[3] = New-AzMetricAlertRuleV2Criteria -MetricName 'Network In Total' -TimeAggregation Total -Operator GreaterThan -Threshold $prodNetworkInTotal
                            $prodVmConditions[4] = New-AzMetricAlertRuleV2Criteria -MetricName 'Network Out Total' -TimeAggregation Total -Operator GreaterThan -Threshold $prodNetworkOutTotal
                            $prodVmConditions[5] = New-AzMetricAlertRuleV2Criteria -MetricName 'OS Disk IOPS Consumed Percentage' -TimeAggregation Average -Operator GreaterThan -Threshold $prodOsDiskIOPS
                            $prodVmConditions[6] = New-AzMetricAlertRuleV2Criteria -MetricName 'Data Disk IOPS Consumed Percentage' -TimeAggregation Average -Operator GreaterThan -Threshold $prodDataDiskIOPS
                            $prodVmConditions[7] = New-AzMetricAlertRuleV2Criteria -MetricName 'Available Memory Bytes' -TimeAggregation Average -Operator LessThan -Threshold $prodAvblMemory

                            # Add alert
                            for ($i = 0; $i -lt $prodVmConditions.Length; $i++) {
                                Add-AzMetricAlertRuleV2 -Name "$($prodVmConditions[$i].MetricName) for $($vm.Name)" -ResourceGroupName $rgName -WindowSize (New-TimeSpan -Minutes 15) -Frequency (New-TimeSpan -Minutes 15) -TargetResourceId $vmResourceId `
                                    -Condition $prodVmConditions[$i] -ActionGroupId $prodActionGroupId -Severity 3 -Description $($prodVmConditions[$i].MetricName)
                            }
                        }                             
                        Write-Host "Configured alerts on $($vm.Name) in $rgName resource group" -ForegroundColor Green
                                                
                    }       
                }
            }
            else {
                Write-Host "No alerts configured on $($vm.Name) in $rgName resource group as no tags found" -ForegroundColor DarkBlue
            }
        }
    }
    else {
        Write-Host "No Virtual machines found in $rgName resource group" -ForegroundColor DarkBlue
    }
    #endregion Virtual Machines
}
