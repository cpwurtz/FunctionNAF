<#
.Synopsis
A script used to use LifeCycle Management to move storage accounts to cool storage. It goes through all subscriptions and adds a policy to move to cool storage after a certain number of days.

.DESCRIPTION
A script used to use LifeCycle Management to move storage accounts to cool storage. It goes through all subscriptions and adds a policy to move to cool storage after a certain number of days.

.Notes
Created   : 2022-07-27
Updated   : 2022-07-27
Version   : 1.0
Author    : @Neudesic, an IBM Company
Twitter   : @neudesic.com
Web       : https://neudesic.com

Disclaimer: This script is provided "AS IS" with no warranties.
#>

# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format.
$currentUTCtime = (Get-Date).ToUniversalTime()

# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"

# Add LifeCycle Management to Storage accounts that don't have one.
# scroll towards the bottom to see the function call and customizations
function storage {
    param (
        $sub,
        $environment,
        $days
    )
        set-azcontext -Subscription $sub.Name | Out-Null
        write-ouput ""
        write-ouput $sub.Name
        write-ouput $environment
        write-ouput "**********"
        write-ouput ""
        $storageaccts = Get-AzStorageAccount
        foreach ($acct in $storageaccts)
            {
            $policy = Get-AzStorageAccountManagementPolicy -ResourceGroupName $acct.ResourceGroupName -StorageAccountName $acct.StorageAccountName -ErrorAction SilentlyContinue
            if (!$policy)
                {
                Write-Host $acct.StorageAccountName "doesn't have a policy, writing policy"
                if ($acct.Kind -notmatch "FileStorage")
                    {
                    Write-Host "writing policy for " $acct.StorageAccountName
                    $action = Add-AzStorageAccountManagementPolicyAction -BaseBlobAction TierToCool -daysAfterModificationGreaterThan $days
                    $filter = New-AzStorageAccountManagementPolicyFilter -BlobType blockBlob
                    $rule1 = New-AzStorageAccountManagementPolicyRule -Name "to-cool" -Action $action -Filter $filter
                    Set-AzStorageAccountManagementPolicy -ResourceGroupName $acct.ResourceGroupName -StorageAccountName $acct.StorageAccountName -Rule $rule1
                    }
                else
                    {
                    write-host $acct.StorageAccountName "is incompatible for life cycle management"
                    }

                }
            else
                {
                Write-Host $acct.StorageAccountName "already has policy"
                }
            <#
            
            #>
            }
}


$subs = Get-AzSubscription #| Where-Object { $_.Name -match 'AZ 2.0' } //put a filter in if you only want to run against certain subscriptions

foreach ($sub in $subs)
    {
    
    if ($sub.Name -match "Non-Prod" -or $sub.Name -match "Pre-Prod") # Only iterate through subscriptions which are not Non Prod, change this to your naming convention
        {
        storage -sub $sub -environment "NonProd" -days 365  #days to move to cool storage, change the days to whatever you want
        }
    else
        {
        storage -sub $sub -environment "Production" -days 1095 #days to move to cool storage, change the days to whatever you want
        }
    }
