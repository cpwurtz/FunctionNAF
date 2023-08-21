# Input bindings are passed in via param block.
param($Timer)

## Tags
$zzzrgName = 'to-delete-rg'
$tagAlertNotification = 'ConfigureAlerts'
$tagEnvironment = 'Environment'


## ActionGroup 
$environment = "non-prod"
$agName = "Azure Event Hubs alerts - NonProd"
$agShortName = "AzAlerts"
$agEmail = "Azure.EventHubs@domain.com"
$agEmailName = "Email Notification"

$prodAgName = "Azure Event Hubs alerts - Prod"
$prodAgShortName = "AzAlerts"
$prodAgEmail = "Azure.EventHubs@domain.com"
$prodAgEmailName = "Email Notification"
$prodSmsName = "smsReceiver"
$prodSmsPhoneNumber = "4255550123"

## Event Hubs thresholds
#$ehProdServerErrors = "2" # 2 Server Errors on Event Hub
#$ehProdUserErrors = "2" # 2 Server Errors on Event Hub

#$ehNonProdServerErrors = "5" # 5 Server Errors on Event Hub
#$ehNonProdUserErrors = "5" # 5 Server Errors on Event Hub

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

    #region Event Hubs
    # Get all Event Hubs in current resource group
    $eventHubsColl = Get-AzEventHubNamespace -ResourceGroupName $rgName

    # If any Event Hubs found, move ahead
    if ($eventHubsColl.Count -gt 0) {

        Write-Host "Found $($eventHubsColl.Count) Event Hub(s) in $rgName resource group" -ForegroundColor Cyan
        # Loop over all the Event Hubs
        foreach ($eventHub in $eventHubsColl) {
            $eventHubConditions = @(0..1)
            $eventHubProdConditions = @(0..1)
            # Get Event Hub Account Id
            $eventHubResourceId = (Get-AzResource -Name $eventHub.Name).Id

            # Get tags on Event Hub
            $eventHubTags = (Get-AzResource -Name $eventHub.Name).Tags

            if ($eventHubTags.Count -gt 0 -and $eventHubTags.Keys -eq $tagAlertNotification) {
                foreach ($Key in ($eventHubTags.GetEnumerator() | Where-Object { $_.Key -eq $tagAlertNotification } )) {

                    if ($Key.Value.ToLower() -eq 'yes') {
                        
                        if ($environment -eq 'non-prod') {

                            # Get thresholds from tags  
                            if (($null -eq $eventHubTags.ServerErrorsThreshold) -or ($null -eq $eventHubTags.UserErrorsThreshold)) {
                                $tag = @{'ServerErrorsThreshold' = '5'; 'UserErrorsThreshold' = '5' }
                                Write-Host "No threshold tag(s) found on $($eventHub.Name) in $rgName resource group" -ForegroundColor Green
                                Update-AzTag -ResourceId $eventHubResourceId -Tag $tag -Operation Merge
                                Write-Host "Added threshold tag(s) on $($eventHub.Name) in $rgName resource group" -ForegroundColor Green
                                $ehNonProdServerErrors = "5" # 5 Server Errors on Event Hub
                                $ehNonProdUserErrors = "5" # 5 Server Errors on Event Hub
                            }
                            else {
                                Write-Host "Found threshold tag(s) on $($eventHub.Name) in $rgName resource group" -ForegroundColor Green
                                $ehNonProdServerErrors = $eventHubTags.ServerErrorsThreshold
                                $ehNonProdUserErrors = $eventHubTags.UserErrorsThreshold
                            }

                            # alert threshold for non-prod Event Hubs                          
                            $eventHubConditions[0] = New-AzMetricAlertRuleV2Criteria -MetricName 'ServerErrors' -TimeAggregation Total -Operator GreaterThan -Threshold $ehNonProdServerErrors
                            $eventHubConditions[1] = New-AzMetricAlertRuleV2Criteria -MetricName 'UserErrors' -TimeAggregation Total -Operator GreaterThan -Threshold $ehNonProdUserErrors

                            # Add alert
                            for ($i = 0; $i -lt $eventHubConditions.Length; $i++) {
                                Add-AzMetricAlertRuleV2 -Name "$($eventHubConditions[$i].MetricName) for $($eventHub.Name)" -ResourceGroupName $rgName -WindowSize (New-TimeSpan -Hours 1) -Frequency (New-TimeSpan -Hours 1) -TargetResourceId $eventHubResourceId `
                                    -Condition $eventHubConditions[$i] -ActionGroupId $actionGroupId -Severity 1 -Description $($eventHubConditions[$i].MetricName)
                            }

                            Write-Host "Configured alerts on $($eventHub.Name) in $rgName resource group" -ForegroundColor Green
                        }
                        elseif ($environment -eq 'prod') {

                             # Get thresholds from tags  
                             if (($null -eq $eventHubTags.ServerErrorsThreshold) -or ($null -eq $eventHubTags.UserErrorsThreshold)) {
                                $tag = @{'ServerErrorsThreshold' = '2'; 'UserErrorsThreshold' = '2' }
                                Write-Host "No threshold tag(s) found on $($eventHub.Name) in $rgName resource group" -ForegroundColor Green
                                Update-AzTag -ResourceId $eventHubResourceId -Tag $tag -Operation Merge
                                Write-Host "Added threshold tag(s) on $($eventHub.Name) in $rgName resource group" -ForegroundColor Green
                                $ehProdServerErrors = "2" # 2 Server Errors on Event Hub
                                $ehProdUserErrors = "2" # 2 Server Errors on Event Hub
                            }
                            else {
                                Write-Host "Found threshold tag(s) on $($eventHub.Name) in $rgName resource group" -ForegroundColor Green
                                $ehProdServerErrors = $eventHubTags.ServerErrorsThreshold
                                $ehProdUserErrors = $eventHubTags.UserErrorsThreshold
                            }
                            # alert threshold for prod Event Hubs
                            $eventHubProdConditions[0] = New-AzMetricAlertRuleV2Criteria -MetricName 'ServerErrors' -TimeAggregation Total -Operator GreaterThan -Threshold $ehProdServerErrors
                            $eventHubProdConditions[1] = New-AzMetricAlertRuleV2Criteria -MetricName 'UserErrors' -TimeAggregation Total -Operator GreaterThan -Threshold $ehProdUserErrors

                            # Add alert
                            for ($i = 0; $i -lt $eventHubProdConditions.Length; $i++) {
                                Add-AzMetricAlertRuleV2 -Name "$($eventHubProdConditions[$i].MetricName) for $($eventHub.Name)" -ResourceGroupName $rgName -WindowSize (New-TimeSpan -Hours 1) -Frequency (New-TimeSpan -Hours 1) -TargetResourceId $eventHubResourceId `
                                    -Condition $eventHubProdConditions[$i] -ActionGroupId $prodActionGroupId -Severity 1 -Description $($eventHubProdConditions[$i].MetricName)
                            }

                            Write-Host "Configured alerts on $($eventHub.Name) in $rgName resource group" -ForegroundColor Green
                        }                                             
                    }       
                }
            }
            else {
                Write-Host "No alerts configured on $($eventHub.Name) in $rgName resource group as no tags found" -ForegroundColor DarkBlue
            }
        }
    }
    else {
        Write-Host "No Event Hubs found in $rgName resource group" -ForegroundColor DarkBlue
    }
    #endregion Event Hubs 
}
