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
<#
.Synopsis
A script used to provide Resource Locks to Resource Groups nightly.

.DESCRIPTION
A script used to provide Resource Locks to Resource Groups nightly.

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

param($Timer)

## Get the current Universal Time in the default string format, apply Time Zone and derive Local Time ##
## Use Get-TimeZone -ListAvailable for a lst of valid Time Zones ""

$TimeZoneName = "Mountain Standard Time"
$CurrentUTCTime = (Get-Date).ToUniversalTime()
$TimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneName)
$DateTimeNow = Get-Date ([System.TimeZoneInfo]::ConvertTimeFromUtc($CurrentUTCTime, $TimeZone))

# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled

if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

# Write an information log with the current time

Write-Host "PowerShell timer trigger function ran! TIME: $DateTimeNow"
Write-Host " "

## Set client name ##

$ClientName = ""
$rglockName = $ClientName+"Lock"
## Set Context/Scope. Where-Object may help limit Subs if needed ##

$Tenant = Get-AzTenant -WarningAction SilentlyContinue
$Subscriptions = Get-AzSubscription #| Where-Object { $_.Name -match 'AZ 2.0' } //put a filter in if you only want to run against certain subscriptions

## Iterate through subscriptions ##

foreach ($Subscription in $Subscriptions) {

    Set-AzContext -Tenant $Tenant.Id -SubscriptionId $Subscription.Id

    ## Iterate through resource groups ##
    ## AzureBackups must be excluded from this process, otherwise they fail ##
    $ResourceGroups = (Get-AzResourceGroup).ResourceGroupName | Where-Object {$_ -notlike "AzureBackupRG*"} # // put a filter in if you only want to run against certain resource groups

    foreach ($ResourceGroup in $ResourceGroups) {

        ## Customer Message ##
            
        Write-Host " "
        Write-Host " "
        Write-Host "Prepared for $($ClientName) by Neudesic, an IBM Company | The Trusted Technology Partner in Business Innovation"
        Write-Host " "
        Write-Host "Subscription Name: $($Subscription.Name)"
        Write-Host "Tenant ID: $($Tenant.Id)"
        Write-Host "Subscription ID: $($Subscription.Id)"
        Write-Host "Time Zone: $($TimeZoneName)"
        Write-Host " "
        Write-Host "Resource Group: $($ResourceGroup)"
        Write-Host " "
        
        New-AzResourceLock -LockLevel CanNotDelete -LockNotes "Locks applied/reapplied at 10pm MDT nightly" -LockName $rglockName -ResourceGroupName $ResourceGroup -Force
        
    } ## End Resource Group Loop
} ## End Subscription Loop