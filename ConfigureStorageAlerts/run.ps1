# Input bindings are passed in via param block.
param($Timer)

# REGION TO BE DELETED
$zzzrgName = 'to-delete-rg'
$tagAlertNotification = 'ConfigureAlerts'
$tagEnvironment = 'Environment'
# END REGION TO BE DELETED

## ActionGroup 
$environment = "non-prod"
$agName = "Azure Storage alerts - NonProd"
$agShortName = "AzAlerts"
$agEmail = "Azure.Storage@domain.com"
$agEmailName = "Email Notification"

$prodAgName = "Azure Storage alerts - Prod"
$prodAgShortName = "AzAlerts"
$prodAgEmail = "Azure.Storage@domain.com"
$prodAgEmailName = "Email Notification"
$prodSmsName = "smsReceiver"
$prodSmsPhoneNumber = "4255550123"

## Get list of subscriptions 
$subscriptions = (Get-AzSubscription).Id
$WarningPreference = 'SilentlyContinue'

ForEach ($subscription in $subscriptions) {
    # Get the subscription 
    #Connect-AzAccount -Subscription $subscription
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

    #region Storage Accounts
    # Get all storage accounts in current resource group
    $stgAccColl = Get-AzStorageAccount -ResourceGroupName $rgName

    # If any storage accounts found, move ahead
    if ($stgAccColl.Count -gt 0) {

        Write-Host "Found $($stgAccColl.Count) Storage account(s) in $rgName resource group" -ForegroundColor Cyan
        # Loop over all the storage accounts
        foreach ($stgAcc in $stgAccColl) {
            # Get Storage Account Id
            $stgResourceId = (Get-AzResource -Name $stgAcc.StorageAccountName).Id

            # Get tags on Storage Account
            $stgTags = (Get-AzResource -Name $stgAcc.StorageAccountName).Tags

            if ($stgTags.Count -gt 0 -and $stgTags.Keys -eq $tagAlertNotification) {
                foreach ($Key in ($stgTags.GetEnumerator() | Where-Object { $_.Key -eq $tagAlertNotification } )) {

                    if ($Key.Value.ToLower() -eq 'yes') {
                        
                        if ($environment -eq 'non-prod') {
                            # Check if threshold tag exists on resource
                            if ($null -eq $stgTags.UsedCapacityThreshold) {
                                $tag = @{'UsedCapacityThreshold' = '5368709120' }
                                Update-AzTag -ResourceId $stgResourceId -Tag $tag -Operation Merge
                                $stgNonProdCapacity = "5368709120" #5GB
                            }
                            else {
                                $stgNonProdCapacity = $stgTags.UsedCapacityThreshold
                            }
                            # alert threshold for non-prod storage accounts                           
                            $stgCondition = New-AzMetricAlertRuleV2Criteria -MetricName 'UsedCapacity' -TimeAggregation Average -Operator GreaterThan -Threshold $stgNonProdCapacity

                            # Add alert
                            Add-AzMetricAlertRuleV2 -Name "$($stgCondition.MetricName) for $($stgAcc.StorageAccountName)" -ResourceGroupName $rgName -WindowSize (New-TimeSpan -Hours 1) -Frequency (New-TimeSpan -Hours 1) -TargetResourceId $stgResourceId `
                                -Condition $stgCondition -ActionGroupId $actionGroupId -Severity 1 -Description $($stgCondition.MetricName)

                            Write-Host "Configured alerts on $($stgAcc.StorageAccountName) in $rgName resource group" -ForegroundColor Green
                        }
                        elseif ($environment -eq 'prod') {
                            
                            # Get thresholds from tags
                            if ($null -eq $stgTags.UsedCapacityThreshold) {
                                $tag = @{'UsedCapacityThreshold' = '4294967296' }
                                Write-Host "No threshold tag(s) found on $($stgAcc.StorageAccountName) in $rgName resource group" -ForegroundColor Green
                                Update-AzTag -ResourceId $stgResourceId -Tag $tag -Operation Merge
                                Write-Host "Added threshold tag(s) on $($stgAcc.StorageAccountName) in $rgName resource group" -ForegroundColor Green
                                $stgProdCapacity = "4294967296" #4GB
                            }
                            else {
                                Write-Host "Found threshold tag(s) on $($stgAcc.StorageAccountName) in $rgName resource group" -ForegroundColor Green
                                $stgProdCapacity = $stgTags.UsedCapacityThreshold
                            }
                            # alert threshold for prod storage accounts
                            $stgCondition = New-AzMetricAlertRuleV2Criteria -MetricName 'UsedCapacity' -TimeAggregation Average -Operator GreaterThan -Threshold $stgProdCapacity

                            # Add alert
                            Add-AzMetricAlertRuleV2 -Name "$($stgCondition.MetricName) for $($stgAcc.StorageAccountName)" -ResourceGroupName $rgName -WindowSize (New-TimeSpan -Hours 1) -Frequency (New-TimeSpan -Hours 1) -TargetResourceId $stgResourceId `
                                -Condition $stgCondition -ActionGroupId $prodActionGroupId -Severity 1 -Description $($stgCondition.MetricName)

                            Write-Host "Configured alerts on $($stgAcc.StorageAccountName) in $rgName resource group" -ForegroundColor Green
                        }                                             
                    }       
                }
            }
            else {
                Write-Host "No alerts configured on $($stgAcc.StorageAccountName) in $rgName resource group as no tags found" -ForegroundColor DarkBlue
            }
        }
    }
    else {
        Write-Host "No storage accounts found in $rgName resource group" -ForegroundColor DarkBlue
    }
    #endregion Storage Accounts 
}
