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

#Replicates KeyVault

$primaryKVName = ""
$primaryRGName = ""
Write-Verbose -Message "Primary Keyvault: $primaryKVName in RG: $primaryRGName" -Verbose 

$SecondaryKVName = ""
$SecondaryRGName = ""
Write-Verbose -Message "Secondary Keyvault: $SecondaryKVName in RG: $SecondaryRGName" -Verbose

Get-AzKeyVaultCertificate -VaultName $primaryKVName | ForEach-Object {
    $CertName = $_.Name
    $SourceCert = Get-AzKeyVaultCertificate -VaultName $primaryKVName -Name $CertName
    $DestinationCert = Get-AzKeyVaultCertificate -VaultName $SecondaryKVName -Name $CertName
    if (!($DestinationCert) -or ($DestinationCert.Updated -lt $SourceCert.Updated))
    {
        $SourceCert | Backup-AzKeyVaultCertificate -OutputFile "$CertName.blob" -Force
        Restore-AzKeyVaultCertificate -VaultName $SecondaryKVName -Inputfile "$CertName.blob"
        Remove-Item -Path "$CertName.blob"
    }
    else
    {
        Write-Verbose -Message "Cert: $CertName already up to date" -Verbose
    }
}

Get-AzKeyVaultSecret -VaultName $primaryKVName | Where-Object { $_.ContentType -ne "application/x-pkcs12" } | ForEach-Object {
    $SecretName = $_.Name
    $SourceSecret = Get-AzKeyVaultSecret -VaultName $primaryKVName -Name $SecretName

    $DestinationSecret = Get-AzKeyVaultSecret -VaultName $SecondaryKVName -Name $SecretName
    if (!($DestinationSecret) -or ($DestinationSecret.Updated -lt $SourceSecret.Updated))
    {
        Set-AzKeyVaultSecret -VaultName $SecondaryKVName -Name $SecretName -SecretValue $SourceSecret.SecretValue -ContentType txt
    }
    else
    {
        Write-Verbose -Message "Secret: $SecretName already up to date" -Verbose
    }
}

Get-AzKeyVaultKey -VaultName $primaryKVName | ForEach-Object {
    $KeyName = $_.Name
    $existingKey = Get-AzKeyVaultKey -VaultName $SecondaryKVName -Name $KeyName

    $SourceKey = Get-AzKeyVaultKey -VaultName $primaryKVName -Name $KeyName
    $DestinationKey = Get-AzKeyVaultKey -VaultName $SecondaryKVName -Name $KeyName
    if (!($DestinationKey) -or ($DestinationKey.Updated -lt $SourceKey.Updated))
    {
        if ($existingKey)
            {
            Write-Verbose -Message "Removing Existing Key" -Verbose
            Remove-AzKeyVaultKey -VaultName $SecondaryKVName -KeyName $KeyName -Force
            Start-Sleep -Seconds 10
            Remove-AzKeyVaultKey -VaultName $SecondaryKVName -KeyName $KeyName -InRemovedState -Force
            Start-Sleep -Seconds 10
            }
        $SourceKey | Backup-AzKeyVaultKey -OutputFile "$KeyName.blob" -Force
        Restore-AzKeyVaultKey -VaultName $SecondaryKVName -Inputfile "$KeyName.blob"
        Remove-Item -Path "$KeyName.blob"
    }
    else
    {
        Write-Verbose -Message "Key: $KeyName already up to date" -Verbose
    }
}