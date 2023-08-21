# Input bindings are passed in via param block.
param($Timer)

## Tags
$zzzrgName = 'to-delete-rg'
$tagAlertNotification = 'ConfigureAlerts'
$tagEnvironment = 'Environment'


## ActionGroup 
$environment = "non-prod"
$agName = "Azure LB alerts - NonProd"
$agShortName = "AzAlerts"
$agEmail = "Azure.LB@domain.com"
$agEmailName = "Email Notification"

$prodAgName = "Azure LB alerts - Prod"
$prodAgShortName = "AzAlerts"
$prodAgEmail = "Azure.LB@domain.com"
$prodAgEmailName = "Email Notification"
$prodSmsName = "smsReceiver"
$prodSmsPhoneNumber = "4255550123"

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

    #region Load Balancers
    # Get all Load balancers in current resource group
    $lbColl = Get-AzLoadBalancer -ResourceGroupName $rgName

    # If any Load balancer found, move ahead
    if ($lbColl.Count -gt 0) {

        Write-Host "Found $($lbColl.Count) Load Balancer(s) in $rgName resource group" -ForegroundColor Cyan
        # Loop over all the LB's
        foreach ($lb in $lbColl) {
            # Get Load balancer Id
            $lbResourceId = (Get-AzResource -Name $lb.Name).Id

            # Get tags on Load balancer
            $lbTags = (Get-AzResource -Name $lb.Name).Tags

            if ($lbTags.Count -gt 0 -and $lbTags.Keys -eq $tagAlertNotification) {
                foreach ($Key in ($lbTags.GetEnumerator() | Where-Object { $_.Key -eq $tagAlertNotification } )) {

                    if ($Key.Value.ToLower() -eq 'yes') {
                        
                        if ($environment -eq 'non-prod') {

                            # Get thresholds from tags  
                            if ($null -eq $lbTags.DipAvailabilityThreshold) {
                                $tag = @{'DipAvailabilityThreshold' = '3' }
                                Write-Host "No threshold tag(s) found on $($lb.Name) in $rgName resource group" -ForegroundColor Green
                                Update-AzTag -ResourceId $lbResourceId -Tag $tag -Operation Merge
                                Write-Host "Added threshold tag(s) on $($lb.Name) in $rgName resource group" -ForegroundColor Green
                                $lbHealthProbeCount = 3
                            }
                            else {
                                Write-Host "Found threshold tag(s) on $($lb.Name) in $rgName resource group" -ForegroundColor Green
                                $lbHealthProbeCount = $lbTags.DipAvailabilityThreshold
                            }
                            # alert threshold for non-prod Load balancer                           
                            $lbCondition = New-AzMetricAlertRuleV2Criteria -MetricName 'DipAvailability' -TimeAggregation Count -Operator GreaterThan -Threshold $lbHealthProbeCount

                            # Add alert
                            Add-AzMetricAlertRuleV2 -Name "$($lbCondition.MetricName) for $($lb.Name)" -ResourceGroupName $rgName -WindowSize (New-TimeSpan -Minutes 5) -Frequency (New-TimeSpan -Minutes 1) -TargetResourceId $lbResourceId `
                                -Condition $lbCondition -ActionGroupId $actionGroupId -Severity 1 -Description $($lbCondition.MetricName)

                            Write-Host "Configured alerts on $($lb.Name) in $rgName resource group" -ForegroundColor Green
                        }
                        elseif ($environment -eq 'prod') {

                            # Get thresholds from tags  
                            if ($null -eq $lbTags.DipAvailabilityThreshold) {
                                $tag = @{'DipAvailabilityThreshold' = '2' }
                                Write-Host "No threshold tag(s) found on $($lb.Name) in $rgName resource group" -ForegroundColor Green
                                Update-AzTag -ResourceId $lbResourceId -Tag $tag -Operation Merge
                                Write-Host "Added threshold tag(s) on $($lb.Name) in $rgName resource group" -ForegroundColor Green
                                $prodLbHealthProbeCount = 2
                            }
                            else {
                                Write-Host "Found threshold tag(s) on $($lb.Name) in $rgName resource group" -ForegroundColor Green
                                $prodLbHealthProbeCount = $lbTags.DipAvailabilityThreshold
                            }
                            # alert threshold for prod Load balancer
                            $lbCondition = New-AzMetricAlertRuleV2Criteria -MetricName 'DipAvailability' -TimeAggregation Count -Operator GreaterThan -Threshold $prodLbHealthProbeCount

                            # Add alert
                            Add-AzMetricAlertRuleV2 -Name "$($lbCondition.MetricName) for $($lb.Name)" -ResourceGroupName $rgName -WindowSize (New-TimeSpan -Hours 1) -Frequency (New-TimeSpan -Hours 1) -TargetResourceId $lbResourceId `
                                -Condition $lbCondition -ActionGroupId $prodActionGroupId -Severity 1 -Description $($lbCondition.MetricName)

                            Write-Host "Configured alerts on $($lb.Name) in $rgName resource group" -ForegroundColor Green
                        }                                                                           
                    }       
                }
            }
            else {
                Write-Host "No alerts configured on $($lb.Name) in $rgName resource group as no tags found" -ForegroundColor DarkBlue
            }
        }
    }
    else {
        Write-Host "No Load Balancers found in $rgName resource group" -ForegroundColor DarkBlue
    }
    #endregion Load Balancers
}
