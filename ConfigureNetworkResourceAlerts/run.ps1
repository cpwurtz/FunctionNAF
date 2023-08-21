# Input bindings are passed in via param block.
param($Timer)

# REGION TO BE DELETED
$zzzrgName = 'to-delete-rg'
$tagAlertNotification = 'ConfigureAlerts'
$tagEnvironment = 'Environment'
# END REGION TO BE DELETED

## ActionGroup 
$environment = "non-prod"
$agName = "Azure Network alerts - NonProd"
$agShortName = "AzAlerts"
$agEmail = "Azure.Network@domain.com"
$agEmailName = "Email Notification"

$prodAgName = "Azure Network alerts - Prod"
$prodAgShortName = "AzAlerts"
$prodAgEmail = "Azure.Network@domain.com"
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
            $actionGroupId = New-AzActivityLogAlertActionGroupObject -Id $actionGroup.Id
        }

        else {
            Write-Host "Action group - $agName in $rgName resource group already exists" -ForegroundColor Green
            # Get ActionGroup Id
            $actionGroupId = New-AzActivityLogAlertActionGroupObject -Id $ag.Id
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
            $prodActionGroupId =  New-AzActivityLogAlertActionGroupObject -Id $prodActionGroup.Id
        }
        else {
            Write-Host "Action group - $prodAgName in $rgName resource group already exists" -ForegroundColor Green
            # Get ActionGroup Id      
            $prodActionGroupId = New-AzActivityLogAlertActionGroupObject -Id $agProd.Id

        }
    }
    #endregion Action Groups 

    #region Virtual Networks

    # Get all Virutal Networks in current resource group
    $vnColl = Get-AzVirtualNetwork -ResourceGroupName $rgName
    if ($vnColl.Count -gt 0) {

        Write-Host "Found $($vnColl.Count) Virtual network(s) in $rgName resource group" -ForegroundColor Cyan
        # Loop over all the virtual network's
        foreach ($vn in $vnColl) {
            # Get vm Account Id
            $vnResourceId = (Get-AzResource -Name $vn.Name).Id
               
            # Get tags on virtual networks
            $vnTags = (Get-AzResource -Name $vn.Name).Tags
  
            if ($vnTags.Count -gt 0 -and $vnTags.Keys -eq $tagAlertNotification) {
                foreach ($Key in ($vnTags.GetEnumerator() | Where-Object { $_.Key -eq $tagAlertNotification } )) {
  
                    if ($Key.Value.ToLower() -eq 'yes') {
                          
                        if ($environment -eq 'non-prod') {
                            # alert threshold for non-prod Virtual networks                   
                            $vnCondition1 = New-AzActivityLogAlertAlertRuleLeafConditionObject -Field 'category' -Equal 'Administrative'
                            $vnCondition2 = New-AzActivityLogAlertAlertRuleLeafConditionObject -Field 'operationName' -Equal 'Microsoft.Network/virtualNetworks/delete'

                            # Add alert
                              
                            New-AzActivityLogAlert -ResourceGroupName $rgName -Condition $vnCondition1, $vnCondition2 `
                                -Location 'Global' -Scope $vnResourceId -Name "Activity Log alert on $($vn.Name)" -Action $actionGroupId -Enabled $true

                        }
                        elseif ($environment -eq 'prod') {
                            # alert threshold for prod Virtual networks
                            $prodVnCondition1 = New-AzActivityLogAlertAlertRuleLeafConditionObject -Field 'Category' -Equal 'Administrative'
                            $prodVnCondition2 = New-AzActivityLogAlertAlertRuleLeafConditionObject -Field 'OperationName' -Equal 'Microsoft.Network/virtualNetworks/delete'
                                   
                            # Add alert
                            New-AzActivityLogAlert -ResourceGroupName $rgName -Condition $prodVnCondition1, $prodVnCondition2 `
                                -Location 'Global' -Scope $vnResourceId -Name "Activity Log alert on $($vn.Name)" -Action $prodActionGroupId -Enabled $true

                        }                             
                        Write-Host "Configured alerts on $($vn.Name) in $rgName resource group" -ForegroundColor Green                   
                    }       
                }
            }
            else {
                Write-Host "No alerts configured on $($vn.Name) in $rgName resource group as no tags found" -ForegroundColor DarkBlue
            }
        }
    }
    else {
        Write-Host "No Virtual networks found in $rgName" -ForegroundColor DarkBlue
    }
    #endregion Virtual Networks 

    #region Network Watcher

    # Get all Network watchers in current resource group
    $nwColl = Get-AzNetworkWatcher -ResourceGroupName $rgName
    if ($nwColl.Count -gt 0) {

        Write-Host "Found $($nwColl.Count) network watcher(s) in $rgName" -ForegroundColor Cyan
        # Loop over all the network watcher's
        foreach ($nw in $nwColl) {
            # Get network watcher's Account Id
            $nwResourceId = (Get-AzResource -Name $nw.Name).Id
               
            # Get tags on network watchers
            $nwTags = (Get-AzResource -Name $nw.Name).Tags
  
            if ($nwTags.Count -gt 0 -and $nwTags.Keys -eq $tagAlertNotification) {
                foreach ($Key in ($nwTags.GetEnumerator() | Where-Object { $_.Key -eq $tagAlertNotification } )) {
  
                    if ($Key.Value.ToLower() -eq 'yes') {
                          
                        if ($environment -eq 'non-prod') {
                            # alert threshold for non-prod network watchers                           
                            $nwCondition1 = New-AzActivityLogAlertAlertRuleLeafConditionObject -Field 'category' -Equal 'Administrative'
                            $nwCondition2 = New-AzActivityLogAlertAlertRuleLeafConditionObject -Field 'operationName' -Equal 'Microsoft.Network/networkWatchers/azureReachabilityReport/action'

                            # Add alert
                              
                            New-AzActivityLogAlert -ResourceGroupName $rgName -Condition $nwCondition1, $nwCondition2 `
                                -Location 'Global' -Scope $nwResourceId -Name "Activity Log alert on $($nw.Name)" -Action $actionGroupId -Enabled $true

                        }
                        elseif ($environment -eq 'prod') {
                            # alert threshold for prod network watchers
                            $prodNwCondition1 = New-AzActivityLogAlertAlertRuleLeafConditionObject -Field 'Category' -Equal 'Administrative'
                            $prodNwCondition2 = New-AzActivityLogAlertAlertRuleLeafConditionObject -Field 'OperationName' -Equal 'Microsoft.Network/networkWatchers/azureReachabilityReport/action'
                                   
                            # Add alert
                            New-AzActivityLogAlert -ResourceGroupName $rgName -Condition $prodNwCondition1, $prodNwCondition2 `
                                -Location 'Global' -Scope $nwResourceId -Name "Activity Log alert on $($nw.Name)" -Action $prodActionGroupId -Enabled $true

                        }                             
                        Write-Host "Configured alerts on $($nw.Name) in $rgName resource group" -ForegroundColor Green                    
                    }       
                }
            }
            else {
                Write-Host "No alerts configured on $($nw.Name) in $rgName resource group as no tags found" -ForegroundColor DarkBlue
            }
        }
    }
    else {
        Write-Host "No Network watchers found in $rgName resource group" -ForegroundColor DarkBlue
    }
    #endregion Network Watcher 

    #region Network Security Group

    # Get all NSG's in current resource group
    $nsgColl = Get-AzNetworkSecurityGroup -ResourceGroupName $rgName
    if ($nsgColl.Count -gt 0) {

        Write-Host "Found $($nsgColl.Count) network security group(s) in $rgName resource group" -ForegroundColor Cyan
        # Loop over all the NSG's
        foreach ($nsg in $nsgColl) {
            # Get NSG's Account Id
            $nsgResourceId = (Get-AzResource -Name $nsg.Name).Id
               
            # Get tags on NSG
            $nsgTags = (Get-AzResource -Name $nsg.Name).Tags
  
            if ($nsgTags.Count -gt 0 -and $nsgTags.Keys -eq $tagAlertNotification) {
                foreach ($Key in ($nsgTags.GetEnumerator() | Where-Object { $_.Key -eq $tagAlertNotification } )) {
  
                    if ($Key.Value.ToLower() -eq 'yes') {
                          
                        if ($environment -eq 'non-prod') {
                            # alert threshold for non-prod nsg                           
                            $nsgCondition1 = New-AzActivityLogAlertAlertRuleLeafConditionObject -Field 'category' -Equal 'Administrative'
                            $nsgCondition2 = New-AzActivityLogAlertAlertRuleLeafConditionObject -Field 'operationName' -Equal 'Microsoft.Network/networkSecurityGroups/delete'

                            # Add alert
                              
                            New-AzActivityLogAlert -ResourceGroupName $rgName -Condition $nsgCondition1, $nsgCondition2 `
                                -Location 'Global' -Scope $nsgResourceId -Name "Activity Log alert on $($nsg.Name)" -Action $actionGroupId -Enabled $true

                        }
                        elseif ($environment -eq 'prod') {
                            # alert threshold for prod nsg
                            $prodNsgCondition1 = New-AzActivityLogAlertAlertRuleLeafConditionObject -Field 'Category' -Equal 'Administrative'
                            $prodNsgCondition2 = New-AzActivityLogAlertAlertRuleLeafConditionObject -Field 'OperationName' -Equal 'Microsoft.Network/networkSecurityGroups/delete'
                                   
                            # Add alert
                            New-AzActivityLogAlert -ResourceGroupName $rgName -Condition $prodNsgCondition1, $prodNsgCondition2 `
                                -Location 'Global' -Scope $nsgResourceId -Name "Activity Log alert on $($nsg.Name)" -Action $prodActionGroupId -Enabled $true

                        }                             
                        Write-Host "Configured alerts on $($nsg.Name) in $rgName resource group" -ForegroundColor Green                   
                    }       
                }
            }
            else {
                Write-Host "No alerts configured on $($nsg.Name) in $rgName resource group as no tags found" -ForegroundColor DarkBlue
            }
        }
    }
    else {
        Write-Host "No Network Security Groups found in $rgName resource group" -ForegroundColor DarkBlue
    }
    #endregion Network Security Group

    #region Network Interface

    # Get all Network Interface's in current resource group
    $niColl = Get-AzNetworkInterface -ResourceGroupName $rgName
    if ($niColl.Count -gt 0) {

        Write-Host "Found $($niColl.Count) network Interface(s) in $rgName resource group" -ForegroundColor Cyan
        # Loop over all the Network Interface's
        foreach ($ni in $niColl) {
            # Get Network Interface's Account Id
            $niResourceId = (Get-AzResource -Name $ni.Name).Id
               
            # Get tags on Network Interface
            $niTags = (Get-AzResource -Name $ni.Name).Tags
  
            if ($niTags.Count -gt 0 -and $niTags.Keys -eq $tagAlertNotification) {
                foreach ($Key in ($niTags.GetEnumerator() | Where-Object { $_.Key -eq $tagAlertNotification } )) {
  
                    if ($Key.Value.ToLower() -eq 'yes') {
                          
                        if ($environment -eq 'non-prod') {
                            # alert threshold for non-prod Network Interface                           
                            $niCondition1 = New-AzActivityLogAlertAlertRuleLeafConditionObject -Field 'category' -Equal 'Administrative'
                            $niCondition2 = New-AzActivityLogAlertAlertRuleLeafConditionObject -Field 'operationName' -Equal 'Microsoft.Network/networkInterfaces/delete'

                            # Add alert
                              
                            New-AzActivityLogAlert -ResourceGroupName $rgName -Condition $niCondition1, $niCondition2 `
                                -Location 'Global' -Scope $niResourceId -Name "Activity Log alert on $($ni.Name)" -Action $actionGroupId -Enabled $true

                        }
                        elseif ($environment -eq 'prod') {
                            # alert threshold for prod Network Interface
                            $prodNiCondition1 = New-AzActivityLogAlertAlertRuleLeafConditionObject -Field 'Category' -Equal 'Administrative'
                            $prodNiCondition2 = New-AzActivityLogAlertAlertRuleLeafConditionObject -Field 'OperationName' -Equal 'Microsoft.Network/networkInterfaces/delete'
                                   
                            # Add alert
                            New-AzActivityLogAlert -ResourceGroupName $rgName -Condition $prodNiCondition1, $prodNiCondition2 `
                                -Location 'Global' -Scope $niResourceId -Name "Activity Log alert on $($ni.Name)" -Action $prodActionGroupId -Enabled $true

                        }                             
                        Write-Host "Configured alerts on $($ni.Name) in $rgName resource group" -ForegroundColor Green                    
                    }       
                }
            }
            else {
                Write-Host "No alerts configured on $($ni.Name) in $rgName resource group as no tags found" -ForegroundColor DarkBlue
            }
        }
    }
    else {
        Write-Host "No Network Interface found in $rgName resource group" -ForegroundColor DarkBlue
    }
    #endregion Network Interface
}
