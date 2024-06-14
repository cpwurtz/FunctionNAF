# Input bindings are passed in via param block.
param($Timer)

## Tags
$zzzrgName = 'to-delete-rg'
$tagAlertNotification = 'ConfigureAlerts'
$tagEnvironment = 'Environment'


## ActionGroup 
$environment = "non-prod"
$agName = "Azure App Service Plan alerts - NonProd"
$agShortName = "AzAlerts"
$agEmail = "Azure.ASP@domain.com"
$agEmailName = "Email Notification"

$prodAgName = "Azure App Service Plan alerts - Prod"
$prodAgShortName = "AzAlerts"
$prodAgEmail = "Azure.ASP@domain.com"
$prodAgEmailName = "Email Notification"
$prodSmsName = "smsReceiver"
$prodSmsPhoneNumber = "4255550123"

## App Service Plan thresholds
#$aspProdCPUPercentage = "70" # % CPU

#$aspNonProdCPUPercentage = "90" # % CPU

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

    #region App Service Plan
    # Get all App Service Plan's in current resource group
    $aspColl = Get-AzAppServicePlan -ResourceGroupName $rgName

    # If any App Service Plan found, move ahead
    if ($aspColl.Count -gt 0) {

        Write-Host "Found $($aspColl.Count) App Service Plan(s) in $rgName resource group" -ForegroundColor Cyan
        # Loop over all the App Service Plans
        foreach ($asp in $aspColl) {

            # Get App Service Plan Account Id
            $aspResourceId = (Get-AzResource -Name $asp.Name).Id

            # Get tags on App Service Plan
            $aspTags = (Get-AzResource -Name $asp.Name).Tags

            if ($aspTags.Count -gt 0 -and $aspTags.Keys -eq $tagAlertNotification) {
                foreach ($Key in ($aspTags.GetEnumerator() | Where-Object { $_.Key -eq $tagAlertNotification } )) {

                    if ($Key.Value.ToLower() -eq 'yes') {
                        
                        if ($environment -eq 'non-prod') {

                            # Get thresholds from tags  
                            if ($null -eq $aspTags.CpuPercentageThreshold) {
                                $tag = @{'CpuPercentageThreshold' = '90' }
                                Write-Host "No threshold tag(s) found on $($asp.Name) in $rgName resource group" -ForegroundColor Green
                                Update-AzTag -ResourceId $aspResourceId -Tag $tag -Operation Merge
                                Write-Host "Added threshold tag(s) on $($asp.Name) in $rgName resource group" -ForegroundColor Green
                                $aspNonProdCPUPercentage = '90'
                            }
                            else {
                                Write-Host "Found threshold tag(s) on $($asp.Name) in $rgName resource group" -ForegroundColor Green
                                $aspNonProdCPUPercentage = $aspTags.CpuPercentageThreshold
                            }

                            # alert threshold for non-prod App Service Plan                       
                            $aspCondition = New-AzMetricAlertRuleV2Criteria -MetricName 'CpuPercentage' -TimeAggregation Average -Operator GreaterThan -Threshold $aspNonProdCPUPercentage
                        
                            # Add alert
                            Add-AzMetricAlertRuleV2 -Name "$($aspCondition.MetricName) for $($asp.Name)" -ResourceGroupName $rgName -WindowSize (New-TimeSpan -Hours 1) -Frequency (New-TimeSpan -Hours 1) -TargetResourceId $aspResourceId `
                                -Condition $aspCondition -ActionGroupId $actionGroupId -Severity 1 -Description $($aspCondition.MetricName)

                            Write-Host "Configured alerts on $($asp.Name) in $rgName resource group" -ForegroundColor Green
                        }
                        elseif ($environment -eq 'prod') {

                            # Get thresholds from tags  
                            if ($null -eq $aspTags.CpuPercentageThreshold) {
                                $tag = @{'CpuPercentageThreshold' = '70' }
                                Write-Host "No threshold tag(s) found on $($asp.Name) in $rgName resource group" -ForegroundColor Green
                                Update-AzTag -ResourceId $aspResourceId -Tag $tag -Operation Merge
                                Write-Host "Added threshold tag(s) on $($asp.Name) in $rgName resource group" -ForegroundColor Green
                                $aspProdCPUPercentage = '70'
                            }
                            else {
                                Write-Host "Found threshold tag(s) on $($asp.Name) in $rgName resource group" -ForegroundColor Green
                                $aspProdCPUPercentage = $aspTags.CpuPercentageThreshold
                            }
                            # alert threshold for prod App Service Plan
                            $aspProdCondition = New-AzMetricAlertRuleV2Criteria -MetricName 'CpuPercentage' -TimeAggregation Total -Operator GreaterThan -Threshold $aspProdCPUPercentage
                        
                            # Add alert
                            Add-AzMetricAlertRuleV2 -Name "$($aspProdCondition.MetricName) for $($asp.Name)" -ResourceGroupName $rgName -WindowSize (New-TimeSpan -Hours 1) -Frequency (New-TimeSpan -Hours 1) -TargetResourceId $aspResourceId `
                                -Condition $aspProdCondition -ActionGroupId $prodActionGroupId -Severity 1 -Description $($aspProdCondition.MetricName)
                    

                            Write-Host "Configured alerts on $($asp.Name) in $rgName resource group" -ForegroundColor Green
                        }                                             
                    }       
                }
            }
            else {
                Write-Host "No alerts configured on $($asp.Name) in $rgName resource group as no tags found" -ForegroundColor DarkBlue
            }
        }
    }
    else {
        Write-Host "No App Service Plan found in $rgName resource group" -ForegroundColor DarkBlue
    }
    #endregion App Service Plan
}
