# Input bindings are passed in via param block.
param($Timer)

## Tags
$zzzrgName = 'to-delete-rg'
$tagAlertNotification = 'ConfigureAlerts'
$tagEnvironment = 'Environment'


## ActionGroup 
$environment = "non-prod"
$agName = "Azure Service Bus alerts - NonProd"
$agShortName = "AzAlerts"
$agEmail = "Azure.ServiceBus@domain.com"
$agEmailName = "Email Notification"

$prodAgName = "Azure Service Bus alerts - Prod"
$prodAgShortName = "AzAlerts"
$prodAgEmail = "Azure.ServiceBus@domain.com"
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

    #region Service Bus
    # Get all Service Bus in current resource group
    $sbColl = Get-AzServiceBusNamespace -ResourceGroupName $rgName

    # If any Service Bus found, move ahead
    if ($sbColl.Count -gt 0) {

        Write-Host "Found $($sbColl.Count) Service Bus('s) in $rgName resource group" -ForegroundColor Cyan
        # Loop over all the Service Bus
        foreach ($sb in $sbColl) {

            # Get Service Bus Account Id
            $sbResourceId = (Get-AzResource -Name $sb.Name).Id

            # Get tags on Service Bus
            $sbTags = (Get-AzResource -Name $sb.Name).Tags

            if ($sbTags.Count -gt 0 -and $sbTags.Keys -eq $tagAlertNotification) {
                foreach ($Key in ($sbTags.GetEnumerator() | Where-Object { $_.Key -eq $tagAlertNotification } )) {

                    if ($Key.Value.ToLower() -eq 'yes') {
                        
                        if ($environment -eq 'non-prod') {

                            # Get thresholds from tags  
                            if ($null -eq $sbTags.DLQMessagesThreshold) {
                                $tag = @{'DLQMessagesThreshold' = '100' }
                                Write-Host "No threshold tag(s) found on $($sb.Name) in $rgName resource group" -ForegroundColor Green
                                Update-AzTag -ResourceId $sbResourceId -Tag $tag -Operation Merge
                                Write-Host "Added threshold tag(s) on $($sb.Name) in $rgName resource group" -ForegroundColor Green
                                $sbNonProdDLQMessages = "100" # Number of DLQ messages in Queue/Topic in Non-PROD
                            }
                            else {
                                Write-Host "Found threshold tag(s) on $($sb.Name) in $rgName resource group" -ForegroundColor Green
                                $sbNonProdDLQMessages = $sbTags.DLQMessagesThreshold
                            }
                            # alert threshold for non-prod Service Bus                         
                            $sbCondition = New-AzMetricAlertRuleV2Criteria -MetricName 'DeadletteredMessages' -TimeAggregation Maximum -Operator GreaterThan -Threshold $sbNonProdDLQMessages
                        
                            # Add alert
                            Add-AzMetricAlertRuleV2 -Name "$($sbCondition.MetricName) for $($sb.Name)" -ResourceGroupName $rgName -WindowSize (New-TimeSpan -Hours 1) -Frequency (New-TimeSpan -Hours 1) -TargetResourceId $sbResourceId `
                                -Condition $sbCondition -ActionGroupId $actionGroupId -Severity 1 -Description $($sbCondition.MetricName)

                            Write-Host "Configured alerts on $($sb.Name) in $rgName resource group" -ForegroundColor Green
                        }
                        elseif ($environment -eq 'prod') {

                             # Get thresholds from tags  
                             if ($null -eq $sbTags.DLQMessagesThreshold) {
                                $tag = @{'DLQMessagesThreshold' = '50' }
                                Write-Host "No threshold tag(s) found on $($sb.Name) in $rgName resource group" -ForegroundColor Green
                                Update-AzTag -ResourceId $sbResourceId -Tag $tag -Operation Merge
                                Write-Host "Added threshold tag(s) on $($sb.Name) in $rgName resource group" -ForegroundColor Green
                                $sbProdDLQMessages = "50" # Number of DLQ messages in Queue/Topic in PROD
                            }
                            else {
                                Write-Host "Found threshold tag(s) on $($sb.Name) in $rgName resource group" -ForegroundColor Green
                                $sbProdDLQMessages = $sbTags.DLQMessagesThreshold
                            }
                            # alert threshold for prod Service Bus
                            $sbProdCondition = New-AzMetricAlertRuleV2Criteria -MetricName 'DeadletteredMessages' -TimeAggregation Maximum -Operator GreaterThan -Threshold $sbProdDLQMessages
                        
                            # Add alert
                            Add-AzMetricAlertRuleV2 -Name "$($sbProdCondition.MetricName) for $($sb.Name)" -ResourceGroupName $rgName -WindowSize (New-TimeSpan -Hours 1) -Frequency (New-TimeSpan -Hours 1) -TargetResourceId $sbResourceId `
                                -Condition $sbProdCondition -ActionGroupId $prodActionGroupId -Severity 1 -Description $($sbProdCondition.MetricName)
                    

                            Write-Host "Configured alerts on $($sb.Name) in $rgName resource group" -ForegroundColor Green
                        }                                             
                    }       
                }
            }
            else {
                Write-Host "No alerts configured on $($sb.Name) in $rgName resource group as no tags found" -ForegroundColor DarkBlue
            }
        }
    }
    else {
        Write-Host "No Service Bus found in $rgName resource group" -ForegroundColor DarkBlue
    }
    #endregion Service Bus
}
