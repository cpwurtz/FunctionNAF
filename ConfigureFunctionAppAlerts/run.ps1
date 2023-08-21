# Input bindings are passed in via param block.
param($Timer)

## Tags
$zzzrgName = 'to-delete-rg'
$tagAlertNotification = 'ConfigureAlerts'
$tagEnvironment = 'Environment'


## ActionGroup 
$environment = "non-prod"
$agName = "Azure Function App alerts - NonProd"
$agShortName = "AzAlerts"
$agEmail = "Azure.FunctionApp@domain.com"
$agEmailName = "Email Notification"

$prodAgName = "Azure Function App alerts - Prod"
$prodAgShortName = "AzAlerts"
$prodAgEmail = "Azure.FunctionApp@domain.com"
$prodAgEmailName = "Email Notification"
$prodSmsName = "smsReceiver"
$prodSmsPhoneNumber = "4255550123"

## Function App thresholds
#$fnProdHttpErrors = "5" # Count of Http Server errors

#$fnNonProdHttpErrors = "50" # Count of Http Server errors

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

    #region Function App
    # Get all Function App's in current resource group
    $fnColl = Get-AzFunctionApp -ResourceGroupName $rgName

    # If any Function App found, move ahead
    if ($fnColl.Count -gt 0) {

        Write-Host "Found $($fnColl.Count) Function App(s)  in $rgName resource group" -ForegroundColor Cyan
        # Loop over all the Function Apps
        foreach ($fn in $fnColl) {

            # Get Function App Account Id
            $fnResourceId = (Get-AzResource -Name $fn.Name).Id

            # Get tags on Function App
            $fnTags = (Get-AzResource -Name $fn.Name).Tags

            if ($fnTags.Count -gt 0 -and $fnTags.Keys -eq $tagAlertNotification) {
                foreach ($Key in ($fnTags.GetEnumerator() | Where-Object { $_.Key -eq $tagAlertNotification } )) {

                    if ($Key.Value.ToLower() -eq 'yes') {
                        
                        if ($environment -eq 'non-prod') {

                            # Get thresholds from tags  
                            if ($null -eq $fnTags.HttpErrorsThreshold) {
                                $tag = @{'HttpErrorsThreshold' = '50' }
                                Write-Host "No threshold tag(s) found on $($fn.Name) in $rgName resource group" -ForegroundColor Green
                                Update-AzTag -ResourceId $fnResourceId -Tag $tag -Operation Merge
                                Write-Host "Added threshold tag(s) on $($fn.Name) in $rgName resource group" -ForegroundColor Green
                                $fnNonProdHttpErrors = "50" # Count of Http Server errors
                            }
                            else {
                                Write-Host "Found threshold tag(s) on $($fn.Name) in $rgName resource group" -ForegroundColor Green
                                $fnNonProdHttpErrors = $fnTags.HttpErrorsThreshold
                            }

                            # alert threshold for non-prod Function App                        
                            $fnCondition = New-AzMetricAlertRuleV2Criteria -MetricName 'Http5xx' -TimeAggregation Total -Operator GreaterThan -Threshold $fnNonProdHttpErrors
                        
                            # Add alert
                            Add-AzMetricAlertRuleV2 -Name "$($fnCondition.MetricName) for $($fn.Name)" -ResourceGroupName $rgName -WindowSize (New-TimeSpan -Hours 1) -Frequency (New-TimeSpan -Hours 1) -TargetResourceId $fnResourceId `
                                -Condition $fnCondition -ActionGroupId $actionGroupId -Severity 1 -Description $($fnCondition.MetricName)

                            Write-Host "Configured alerts on $($fn.Name) in $rgName resource group" -ForegroundColor Green
                        }
                        elseif ($environment -eq 'prod') {

                            # Get thresholds from tags  
                            if ($null -eq $fnTags.HttpErrorsThreshold) {
                                $tag = @{'HttpErrorsThreshold' = '5' }
                                Write-Host "No threshold tag(s) found on $($fn.Name) in $rgName resource group" -ForegroundColor Green
                                Update-AzTag -ResourceId $fnResourceId -Tag $tag -Operation Merge
                                Write-Host "Added threshold tag(s) on $($fn.Name) in $rgName resource group" -ForegroundColor Green
                                $fnProdHttpErrors = "5" # Count of Http Server errors
                            }
                            else {
                                Write-Host "Found threshold tag(s) on $($fn.Name) in $rgName resource group" -ForegroundColor Green
                                $fnProdHttpErrors = $fnTags.HttpErrorsThreshold
                            }

                            # alert threshold for prod Function App
                            $fnProdCondition = New-AzMetricAlertRuleV2Criteria -MetricName 'Http5xx' -TimeAggregation Total -Operator GreaterThan -Threshold $fnProdHttpErrors
                        
                            # Add alert
                            Add-AzMetricAlertRuleV2 -Name "$($fnProdCondition.MetricName) for $($fn.Name)" -ResourceGroupName $rgName -WindowSize (New-TimeSpan -Hours 1) -Frequency (New-TimeSpan -Hours 1) -TargetResourceId $fnResourceId `
                                -Condition $fnProdCondition -ActionGroupId $prodActionGroupId -Severity 1 -Description $($fnProdCondition.MetricName)
                    

                            Write-Host "Configured alerts on $($fn.Name) in $rgName resource group" -ForegroundColor Green
                        }                                             
                    }       
                }
            }
            else {
                Write-Host "No alerts configured on $($fn.Name) in $rgName resource group as no tags found" -ForegroundColor DarkBlue
            }
        }
    }
    else {
        Write-Host "No Function Apps found in $rgName resource group" -ForegroundColor DarkBlue
    }
    #endregion Function App
}
