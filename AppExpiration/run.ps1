<#
.Synopsis
This script captures all expiring secrets and cert for all (Enterprise, SP) Applications.

.DESCRIPTION
This script captures all expiring secrets and cert for all (Enterprise, SP) Applications
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


#secret expiration date filter (for example 30 days)
$LimitExpirationDays = 14
# Replace with your Workspace ID
$CustomerId = ""  

# Replace with your Primary Key
$SharedKey = ""

# Specify the name of the record type that you'll be creating
$LogType = "AppRegistration"




# Optional name of a field that includes the timestamp for the data. If the time field is not specified, Azure Monitor assumes the time is the message ingestion time
$TimeStampField = ""


#Retrieving the list of secrets that expires in the above range of days
$SecretsToExpire = @()
Get-AzADApplication | ForEach-Object {
    $app = $_
    @(
        Get-AzADAppCredential -ObjectId $_.Id
    ) | Where-Object {
        $_.EndDateTime -lt (Get-Date).AddDays($LimitExpirationDays)
    } | ForEach-Object {
         $expiringSecret = @{
            AppName = $app.DisplayName
            AppObjectID = $app.Id
            AppApplicationId = $app.AppId
            SecretDisplayName = $_.DisplayName
            SecretKeyIdentifier = $_.KeyId
            SecretEndDate = $_.EndDateTime
        }
        $SecretsToExpire += $expiringSecret
    }
}


# Create the function to create the authorization signature
Function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource)
{
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)

    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
    return $authorization
}

# Create the function to create and post the request
Function Post-LogAnalyticsData($customerId, $sharedKey, $body, $logType)
{
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature `
        -customerId $customerId `
        -sharedKey $sharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $customerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $rfc1123date;
        "time-generated-field" = $TimeStampField;
    }

    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
    return $response.StatusCode

}



# Submit the data to the API endpoint
#Sending the list of secrets to Log Analytics
if($SecretsToExpire.Count -eq 0) {
    Write-Output "No secrets found that will expire in this range"
}
else {
    Write-Output "Secrets that will expire in this range:"
    Write-Output $SecretsToExpire.Length
    $body = $SecretsToExpire | ConvertTo-Json
    Write-Output $SecretsToExpire | ConvertTo-Json
    Post-LogAnalyticsData -customerId $customerId -sharedKey $sharedKey -body ([System.Text.Encoding]::UTF8.GetBytes($body)) -logType $logType
}