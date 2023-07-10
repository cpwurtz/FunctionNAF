<#
.Synopsis
This script setups up backups for all VMs in a subscription that are not already backed up.  It also tags the VMs with a backup tag and a backup policy tag.  
If the VM is already tagged with a backup policy, it will use that policy.  If the VM is not tagged, it will tag the VM with a bronze backup policy.
Backup policies are setup in portal outside this script. The policies are listed below.
Bronze -  nightly, 30 day retention
Silver - twice a day, 90 day retention
Gold - every 4 hours, 180 day retention

.DESCRIPTION
This script setups up backups for all VMs in a subscription that are not already backed up.  It also tags the VMs with a backup tag and a backup policy tag.

.Notes
Created   : 2022-07-27
Updated   : 2022-07-27
Version   : 1.0
Author    : @Neudesic, an IBM Company
Twitter   : @neudesic.com
Web       : https://neudesic.com

Disclaimer: This script is provided "AS IS" with no warranties.
#>

## Input Timer bindings are passed in via param block ##
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

function backups {
    param (
        $vm,
        $vaultname,
        $Tags
    )

    Get-AzRecoveryServicesVault -Name $vaultname | Set-AzRecoveryServicesVaultContext
    $policy = Get-AzRecoveryServicesBackupProtectionPolicy -Name $Tags.Properties.TagsProperty[$BackupTag]
    Enable-AzRecoveryServicesBackupProtection -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Policy $policy

}
$CoreVaultName = "" #put the name of the vaults here
$ProdVaultName = "" #put the name of the vaults here
$PrePrdVaultName = "" #put this in if client wants test enviorments backed up, otherwise leave blank
$location = "westus2"
$BackupTag = "backup"

$subscriptions = Get-AzSubscription #| Where-Object { $_.Name -match 'AZ 2.0' }  //put a filter in if you only want to run against certain subscriptions


foreach ($subscription in $subscriptions)
    {
    if ($subscription.Name -notlike "*Non-Prod*") # Only iterate through subscriptions which are not Non Prod, change this to your naming convention
        {
        if ($subscription.Name -like "*Core*") {$recoveryServicesVaultName = $CoreVaultName} # Set the vault name based on the subscription name
        elseif ($subscription.Name -like "*Production*") {$recoveryServicesVaultName = $ProdVaultName} # Set the vault name based on the subscription name
        elseif ($subscription.Name -like "*Pre-Prod*") {$recoveryServicesVaultName = $PrePrdVaultName} # Set the vault name based on the subscription name
        Set-AzContext -Subscription $subscription | Out-null
        $vaults = Get-AzRecoveryServicesVault -Name $recoveryServicesVaultName
        [System.Collections.ArrayList]$vms = @(Get-AzVM -Location $location)
        $containers=@()
        foreach ($vault in $vaults)
        {
            Set-AzRecoveryServicesVaultContext -Vault $vault
            $containers += Get-AzRecoveryServicesBackupContainer -ContainerType "AzureVM" #-Status "Registered"
            $vaultVMs=@()
            $vaultVMs = $containers.FriendlyName | Select-Object -Unique

            foreach ($vaultVM in $vaultVMs) # Remove the backed-up VMs from the array containing all the VMs in the iterated subscription
            {
                $indexsToRemove = @()
                for ($i=$vms.Count-1; $i -ge 0; $i--)
                {
                    if ($vaultVM -eq $vms[$i].Name)
                    {
                        $indexsToRemove += $i
                    }
                }

                foreach ($indexToRemove in $indexsToRemove) {
                    $vms.RemoveAt($indexToRemove)
                }
            }
        }

        Write-Host ""
        Write-Host "### SUBSCRIPTION $($subscription.Name) ###"
    
        foreach ($vaultVM in $vaultVMs) 
            {
            Write-Host $vaultVM "is being backed up"
            }

        foreach ($vm in $vms) # Print out the VM names which are not backed up in the iterated subscription
            {
            Write-Host "$($vm.name) is not backed up"
            $Tags = Get-AzTag -ResourceId (Get-AzResource -Name $vm.Name).ResourceId
            if ($Tags | oss | Select-String "backup")
                {
                Write-host $vm.Name " is tagged for backup"
                write-host "checking backup tag......"
                if (!$Tags.Properties.TagsProperty[$BackupTag])
                    {
                    $Tag = @{"backup"="Bronze"}
                    New-AzTag -ResourceId $vm.Id -Tag $Tag
                    $Tags = Get-AzTag -ResourceId (Get-AzResource -Name $vm.Name).ResourceId
                    Write-host $vm.Name " has been assigned " $Tags.Properties.TagsProperty[$BackupTag] " policy"
                    Write-Host "Assigning bronze backup policy....."
                    backups -vm $vm -vaultname $recoveryServicesVaultName -Tags $Tags
                    
                    }
                else 
                    {
                    Write-Host $vm.Name " was been tagged with "$Tags.Properties.TagsProperty[$BackupTag] " policy"
                    write-host "Assigning backup policy....."
                    backups -vm $vm -vaultname $recoveryServicesVaultName -Tags $Tags

                    } 
                }
            else 
                {
                Write-host $vm.Name " has not been tagged for backup"
                Write-host $vm.Name "Assigning Tags to VM...."
                $Tag = @{"backup"="Bronze"}
                New-AzTag -ResourceId $vm.Id -Tag $Tag
                $Tags = Get-AzTag -ResourceId (Get-AzResource -Name $vm.Name).ResourceId
                backups -vm $vm -vaultname $recoveryServicesVaultName -Tags $Tags
                 }
            }
        }
        else
            {
            Write-Host ""
            Write-Host "### SUBSCRIPTION $($subscription.Name) ###"
            Write-Host "There are no polices for backing up VMs in Non Prod"
            }
}