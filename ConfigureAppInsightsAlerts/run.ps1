# Input bindings are passed in via param block.
param($Timer)

## Tags
$zzzrgName = 'to-delete-rg'
$tagAlertNotification = 'ConfigureAlerts'
$tagEnvironment = 'Environment'


## ActionGroup 
$environment = "non-prod"
$agName = "Azure App Insights alerts - NonProd"
$agShortName = "AzAlerts"
$agEmail = "Azure.AppInsights@domain.com"
$agEmailName = "Email Notification"

$prodAgName = "Azure App Insights alerts - Prod"
$prodAgShortName = "AzAlerts"
$prodAgEmail = "Azure.AppInsights@domain.com"
$prodAgEmailName = "Email Notification"
$prodSmsName = "smsReceiver"
$prodSmsPhoneNumber = "4255550123"

## App Insights thresholds
#$appInsightsProdFailedRequests = "1" # Number of Failed Requests

#$appInsightsNonProdFailedRequests = "50" # Number of Failed Requests

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

    #region App Insights
    # Get all App Insights's in current resource group
    $appInsightsColl = Get-AzApplicationInsights -ResourceGroupName $rgName

    # If any App Insights found, move ahead
    if ($appInsightsColl.Count -gt 0) {

        Write-Host "Found $($appInsightsColl.Count) App Insight(s) in $rgName resource group" -ForegroundColor Cyan
        # Loop over all the App Insights
        foreach ($appInsights in $appInsightsColl) {

            # Get App Insights Account Id
            $appInsightsResourceId = (Get-AzResource -Name $appInsights.Name).Id

            # Get tags on App Insights
            $appInsightsTags = (Get-AzResource -Name $appInsights.Name).Tags

            if ($appInsightsTags.Count -gt 0 -and $appInsightsTags.Keys -eq $tagAlertNotification) {
                foreach ($Key in ($appInsightsTags.GetEnumerator() | Where-Object { $_.Key -eq $tagAlertNotification } )) {

                    if ($Key.Value.ToLower() -eq 'yes') {
                        
                        if ($environment -eq 'non-prod') {

                            # Get thresholds from tags
                            if ($null -eq $appInsightsTags.FailedRequestsThreshold) {
                                $tag = @{'FailedRequestsThreshold' = '50' }
                                Write-Host "No threshold tag(s) found on $($appInsights.Name) in $rgName resource group" -ForegroundColor Green
                                Update-AzTag -ResourceId $appInsightsResourceId -Tag $tag -Operation Merge
                                Write-Host "Added threshold tag(s) on $($appInsights.Name) in $rgName resource group" -ForegroundColor Green
                                $appInsightsNonProdFailedRequests = '50'
                            }
                            else {
                                Write-Host "Found threshold tag(s) on $($appInsights.Name) in $rgName resource group" -ForegroundColor Green
                                $appInsightsNonProdFailedRequests = $appInsightsTags.FailedRequestsThreshold
                            }

                            # alert threshold for non-prod App Insights                       
                            $appInsightsCondition = New-AzMetricAlertRuleV2Criteria -MetricName 'requests/failed' -TimeAggregation Count -Operator GreaterThan -Threshold $appInsightsNonProdFailedRequests
                        
                            # Add alert
                            Add-AzMetricAlertRuleV2 -Name "Failed requests for $($appInsights.Name)" -ResourceGroupName $rgName -WindowSize (New-TimeSpan -Hours 1) -Frequency (New-TimeSpan -Hours 1) -TargetResourceId $appInsightsResourceId `
                                -Condition $appInsightsCondition -ActionGroupId $actionGroupId -Severity 1 -Description $($appInsightsCondition.MetricName)

                            Write-Host "Configured alerts on $($appInsights.Name) in $rgName resource group" -ForegroundColor Green
                        }
                        elseif ($environment -eq 'prod') {

                            # Get thresholds from tags
                            if ($null -eq $appInsightsTags.FailedRequestsThreshold) {
                                $tag = @{'FailedRequestsThreshold' = '1' }
                                Write-Host "No threshold tag(s) found on $($appInsights.Name) in $rgName resource group" -ForegroundColor Green
                                Update-AzTag -ResourceId $appInsightsResourceId -Tag $tag -Operation Merge
                                Write-Host "Added threshold tag(s) on $($appInsights.Name) in $rgName resource group" -ForegroundColor Green
                                $appInsightsProdFailedRequests = '1'
                            }
                            else {
                                Write-Host "Found threshold tag(s) on $($appInsights.Name) in $rgName resource group" -ForegroundColor Green
                                $appInsightsProdFailedRequests = $appInsightsTags.FailedRequestsThreshold
                            }
                            # alert threshold for prod App Insights
                            $appInsightsProdCondition = New-AzMetricAlertRuleV2Criteria -MetricName 'requests/failed' -TimeAggregation Count -Operator GreaterThan -Threshold $appInsightsProdFailedRequests
                        
                            # Add alert
                            Add-AzMetricAlertRuleV2 -Name "Failed requests for $($appInsights.Name)" -ResourceGroupName $rgName -WindowSize (New-TimeSpan -Hours 1) -Frequency (New-TimeSpan -Hours 1) -TargetResourceId $appInsightsResourceId `
                                -Condition $appInsightsProdCondition -ActionGroupId $prodActionGroupId -Severity 1 -Description $($appInsightsProdCondition.MetricName)
                    

                            Write-Host "Configured alerts on $($appInsights.Name) in $rgName resource group" -ForegroundColor Green
                        }                                             
                    }       
                }
            }
            else {
                Write-Host "No alerts configured on $($appInsights.Name) in $rgName resource group as no tags found" -ForegroundColor DarkBlue
            }
        }
    }
    else {
        Write-Host "No App Insights found in $rgName resource group" -ForegroundColor DarkBlue
    }
    #endregion App Insights
}
