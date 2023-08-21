# Input bindings are passed in via param block.
param($Timer)

## Tags
$zzzrgName = 'to-delete-rg'
$tagAlertNotification = 'ConfigureAlerts'
$tagEnvironment = 'Environment'


## ActionGroup 
$environment = "non-prod"
$agName = "Azure SQL DB alerts - NonProd"
$agShortName = "AzAlerts"
$agEmail = "Azure.DB@domain.com"
$agEmailName = "Email Notification"

$prodAgName = "Azure SQL DB alerts - Prod"
$prodAgShortName = "AzAlerts"
$prodAgEmail = "Azure.DB@domain.com"
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

    #region SQL Databases

    # Get all db's in current resource group
       
    # Get all SQL Servers in current resource group
    $sqlServers = Get-AzSqlServer -ResourceGroupName $rgName
       

    foreach ($server in $sqlServers.ServerName) {
        # Get all db's in current resource group
        $dbColl += Get-AzSqlDatabase -ResourceGroupName $rgName -ServerName $server
    }
        
    if ($dbColl.Count -gt 0) {

        Write-Host "Found $($dbColl.Count) database(s) in $rgName resource group" -ForegroundColor Cyan
        # Loop over all the db's
        foreach ($db in $dbColl) {
            $dbConditions = @(0..3)
            $prodDbConditions = @(0..3)
            # Get db Account Id
            $dbResourceId = (Get-AzResource -Name $db.DatabaseName).ResourceId
  
            # Get tags on db
            $dbTags = (Get-AzResource -Name $db.DatabaseName).Tags
  
            if ($dbTags.Count -gt 0 -and $dbTags.Keys -eq $tagAlertNotification) {
                foreach ($Key in ($dbTags.GetEnumerator() | Where-Object { $_.Key -eq $tagAlertNotification } )) {
  
                    if ($Key.Value.ToLower() -eq 'yes') {
                          
                        if ($environment -eq 'non-prod') {

                            # Get thresholds from tags  
                            if (($null -eq $dbTags.StorageThreshold) -or ($null -eq $dbTags.CpuPercentThreshold) -or ($null -eq $dbTags.ProcessCorePercentThreshold) -or ($null -eq $dbTags.ConnectionErrorsThreshold)) {
                                $tag = @{'StorageThreshold' = '80530636800'; 'CpuPercentThreshold' = '90'; 'ProcessCorePercentThreshold' = '90'; 'ConnectionErrorsThreshold' = '5' }
                                Write-Host "No threshold tag(s) found on $($db.DatabaseName) in $rgName resource group" -ForegroundColor Green
                                Update-AzTag -ResourceId $dbResourceId -Tag $tag -Operation Merge
                                Write-Host "Added threshold tag(s) on $($db.DatabaseName) in $rgName resource group" -ForegroundColor Green
                                $dbStorage = 80530636800 # 75GB
                                $dbCpuPercent = 90
                                $dbProcessCorePercent = 90
                                $dbConnectionErrors = 5
                            }
                            else {
                                Write-Host "Found threshold tag(s) on $($db.DatabaseName) in $rgName resource group" -ForegroundColor Green
                                $dbStorage = $dbTags.StorageThreshold
                                $dbCpuPercent = $dbTags.CpuPercentThreshold
                                $dbProcessCorePercent = $dbTags.ProcessCorePercentThreshold
                                $dbConnectionErrors = $dbTags.ConnectionErrorsThreshold
                            }
                            # alert threshold for non-prod db                           
                            $dbConditions[0] = New-AzMetricAlertRuleV2Criteria -MetricName 'cpu_percent' -TimeAggregation Average -Operator GreaterThan -Threshold $dbCpuPercent
                            $dbConditions[1] = New-AzMetricAlertRuleV2Criteria -MetricName 'sqlserver_process_core_percent' -TimeAggregation Maximum -Operator GreaterThan -Threshold $dbProcessCorePercent
                            $dbConditions[2] = New-AzMetricAlertRuleV2Criteria -MetricName 'connection_failed' -TimeAggregation Total -Operator GreaterThan -Threshold $dbConnectionErrors
                            $dbConditions[3] = New-AzMetricAlertRuleV2Criteria -MetricName 'storage' -TimeAggregation Maximum -Operator GreaterThan -Threshold $dbStorage
                                   
                            # Add alert
                            for ($i = 0; $i -lt $dbConditions.Length; $i++) {
                                Add-AzMetricAlertRuleV2 -Name "$($dbConditions[$i].MetricName) alerts for $($db.DatabaseName)" -ResourceGroupName $rgName -WindowSize (New-TimeSpan -Minutes 15) -Frequency (New-TimeSpan -Minutes 15) -TargetResourceId $dbResourceId `
                                    -Condition $dbConditions[$i] -ActionGroupId $actionGroupId -Severity 3 -Description $($dbConditions[$i].MetricName)
                            }

                        }
                        elseif ($environment -eq 'prod') {

                            # Get thresholds from tags  
                            if (($null -eq $dbTags.StorageThreshold) -or ($null -eq $dbTags.CpuPercentThreshold) -or ($null -eq $dbTags.ProcessCorePercentThreshold) -or ($null -eq $dbTags.ConnectionErrorsThreshold)) {
                                $tag = @{'StorageThreshold' = '107374182400'; 'CpuPercentThreshold' = '80'; 'ProcessCorePercentThreshold' = '80'; 'ConnectionErrorsThreshold' = '2' }
                                Write-Host "No threshold tag(s) found on $($db.DatabaseName) in $rgName resource group" -ForegroundColor Green
                                Update-AzTag -ResourceId $dbResourceId -Tag $tag -Operation Merge
                                Write-Host "Added threshold tag(s) on $($db.DatabaseName) in $rgName resource group" -ForegroundColor Green
                                $ProdDbStorage = 107374182400 # 100GB
                                $ProdDbCpuPercent = 80
                                $ProdDbProcessCorePercent = 80
                                $ProdDbConnectionErrors = 2
                            }
                            else {
                                Write-Host "Found threshold tag(s) on $($db.DatabaseName) in $rgName resource group" -ForegroundColor Green
                                $ProdDbStorage = $dbTags.StorageThreshold
                                $ProdDbCpuPercent = $dbTags.CpuPercentThreshold
                                $ProdDbProcessCorePercent = $dbTags.ProcessCorePercentThreshold
                                $ProdDbConnectionErrors = $dbTags.ConnectionErrorsThreshold
                            }
                            # alert threshold for prod db
                            $prodDbConditions[0] = New-AzMetricAlertRuleV2Criteria -MetricName 'cpu_percent' -TimeAggregation Average -Operator GreaterThan -Threshold $ProdDbCpuPercent
                            $prodDbConditions[1] = New-AzMetricAlertRuleV2Criteria -MetricName 'sqlserver_process_core_percent' -TimeAggregation Maximum -Operator GreaterThan -Threshold $ProdDbProcessCorePercent
                            $prodDbConditions[2] = New-AzMetricAlertRuleV2Criteria -MetricName 'connection_failed' -TimeAggregation Total -Operator GreaterThan -Threshold $ProdDbConnectionErrors
                            $prodDbConditions[3] = New-AzMetricAlertRuleV2Criteria -MetricName 'storage' -TimeAggregation Maximum -Operator GreaterThan -Threshold $ProdDbStorage
                                   
                            # Add alert
                            for ($i = 0; $i -lt $prodDbConditions.Length; $i++) {
                                Add-AzMetricAlertRuleV2 -Name "$($prodDbConditions[$i].MetricName) for $($db.DatabaseName)" -ResourceGroupName $rgName -WindowSize (New-TimeSpan -Minutes 15) -Frequency (New-TimeSpan -Minutes 15) -TargetResourceId $dbResourceId `
                                    -Condition $prodDbConditions[$i] -ActionGroupId $prodActionGroupId -Severity 3 -Description $($prodDbConditions[$i].MetricName)
                            }
                        }                             
                        Write-Host "Configured alerts on $($db.DatabaseName) in $rgName resource group" -ForegroundColor Green                     
                    }       
                }
            }
            else {
                Write-Host "No alerts configured on $($db.DatabaseName) in $rgName resource group database as no tags found" -ForegroundColor DarkBlue
            }
        }
    }
    else {
        Write-Host "No SQL databases found in $rgName resource group" -ForegroundColor DarkBlue
    }
    #endregion SQL Databases 
}
