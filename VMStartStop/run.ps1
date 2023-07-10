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
A script used to provide an alternative Start/Stop solution for all Azure VM resources.

.DESCRIPTION
A script used to provide an alternative Start/Stop solution for all Azure VM resources.

.Notes
Created   : 2022-06-14
Updated   : 2022-06-25
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

## Required Time variables for Start Stop

$TestTime = get-date ([System.TimeZoneInfo]::ConvertTimeFromUtc($CurrentUTCTime, $TimeZone)) -Format HH:mm
$Day = $DateTimeNow.DayOfWeek

# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled

if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

# Write an information log with the current time

Write-Host "PowerShell timer trigger function ran! TIME: $DateTimeNow"
Write-Host " "

##

## Start/Stop VMs with an operational window ##

## Set client name ##

$ClientName = ""

## Must be 59 or below ##

[int]$StartStopWindow = 15 

## Define Startup/Shutdown Tags below ##

$TagShutdown = "Shutdown"
$TagStartup = "Startup"

## Don't run on weekends ##

if ($Day -eq 'Saturday' -or $Day -eq 'Sunday') {
            write-output ("It's " + $Day + ". Virtual Machines will have to be manually Start/Stopped as the schedule doesn't run on weekends")
            Write-Host " "
            Exit
        }

## Set Context/Scope. Where-Object may help limit Subs if needed ##

$Tenant = Get-AzTenant -WarningAction SilentlyContinue
$Subscriptions = Get-AzSubscription #| Where-Object { $_.Name -match 'AZ 2.0' } //filter subscriptions you want to include or exclude

## Iterate through subscriptions ##

foreach ($Subscription in $Subscriptions) {

    Set-AzContext -Tenant $Tenant.Id -SubscriptionId $Subscription.Id

## Iterate through resource groups ##
        
    $ResourceGroups = (Get-AzResourceGroup).ResourceGroupName

    foreach ($ResourceGroup in $ResourceGroups) {

        Write-Host "Checking Resource Group $($ResourceGroup) for qualifying VMs"
        Write-Host " "      

## Find de-allocated VMs with a Startup Tag ##

        $VirtualMachines = Get-AzVm -ResourceGroupName $ResourceGroup | Where-Object { $_.Tags.Keys -eq $TagStartup } | Where-Object { $_.PowerState -ne "VM running" }

                foreach ($VirtualMachine in $VirtualMachines) {

                $Location = ($VirtualMachine.Location)

                Write-Host "Found qualifying deallocated VM $($VirtualMachine)"
                Write-Host " "

                }

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
Write-Host "Virtual Machine Name: $($Resource)"
Write-Host "Resource Group: $($ResourceGroup)"
Write-Host "Resource Location: $($Location)"
Write-Host "Resource Type: $($ResourceType)"
Write-Host " "
Write-Host "Current Virtual Machine Name: $($VirtualMachine)"
Write-Host " "
        
## Iterate through virtual machines ##
        
        foreach ($VirtualMachine in $VirtualMachines) {
   
            # Let's start 'em up
    
            $Tags = Get-AzTag -ResourceId (Get-AzResource -Name $VirtualMachine.Name).ResourceId
            $TagValue = get-date([datetime]($Tags.Properties.TagsProperty[$TagStartup])) -Format HH:mm
            $Diff = New-TimeSpan -Start $TagValue -End $TestTime 

            $Location = ($VirtualMachine.Location)

            Write-Host "Found $($VirtualMachine.Name)"
            Write-Host " "
            Write-Host "Current Time: $($TestTime)"
            Write-Host "Start Tag Time: $($TagValue)"
            Write-Host "Difference: $($Diff.Minutes)"
            Write-Host " "
                                    
            try {
                $StartTime = [datetime]($Tags.Properties.TagsProperty[$TagStartup]) 
            }
            catch { $StartTime = $null }
            if ($Diff.hours -eq 0 -and $Diff.Minutes -gt 0 -and $Diff.Minutes -lt $StartStopWindow -and $TagValue -ne $null ) {

                Write-Host "Starting $($VirtualMachine.Name)"
                Write-Host " "

                Start-AzVM -Name $VirtualMachine.Name -ResourceGroupName $VirtualMachine.ResourceGroupName -AsJob
            }
        }

## Find allocated VMs with a Startup Tag ##
    
        $VirtualMachines = Get-AzVm -ResourceGroupName $ResourceGroup | Where-Object { $_.Tags.Keys -eq $TagShutdown } | Where-Object { $_.PowerState -ne "VM deallocated" }

## Iterate through virtual machines ##
            
        foreach ($VirtualMachine in $VirtualMachines) {
        
                Write-Host "Found qualifying allocated VM $($VirtualMachine)"
                Write-Host " "
        
            # Let's shut 'em down
                        
            $Tags = Get-AzTag -ResourceId (Get-AzResource -Name $VirtualMachine.Name).ResourceId
            $TagValue = get-date([datetime]($Tags.Properties.TagsProperty[$TagShutDown])) -Format HH:mm
            $Diff = New-TimeSpan -Start $TagValue -End $TestTime 

            write-output "Found $($VirtualMachine.Name)"
            Write-Host " "
            Write-Host "Current Time: $($TestTime)"
            Write-Host "Shutdown Tag Time: $($TagValue)"
            Write-Host "Difference: $($Diff.Minutes)"
            Write-Host " "
            
            try {
                $ShutdownTime = [datetime]($Tags.Properties.TagsProperty[$TagShutdown])
            }
            catch { $ShutdownTime = $null }
            if ($Diff.hours -eq 0 -and $Diff.Minutes -gt 0 -and $Diff.Minutes -lt $StartStopWindow -and $TagValue -ne $null ) {
                
                write-output "Stopping $($VirtualMachine.Name)"
                Write-Host " "      

                Stop-AzVM -Name $VirtualMachine.Name -ResourceGroupName $VirtualMachine.ResourceGroupName -Force -AsJob
            }
        }
    }
}


