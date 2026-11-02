param(
    [string]$ResourceGroup = 'rg-fieldwork-eastus',
    [string]$AppName = 'fieldwork',
    [Parameter(Mandatory)][string]$ClientId,
    [Security.SecureString]$ClientSecret,
    [string]$ClientSecretFile
)
$ErrorActionPreference = 'Stop'
function Check-Native { if ($LASTEXITCODE -ne 0) { throw 'GitHub authentication configuration failed; the application remains locked.' } }
if ($ClientSecretFile) { $ClientSecret = ConvertTo-SecureString ([IO.File]::ReadAllText((Resolve-Path -LiteralPath $ClientSecretFile).Path)) -AsPlainText -Force }
if (-not $ClientSecret) { $ClientSecret = Read-Host 'GitHub OAuth client secret' -AsSecureString }
if ($ClientSecret.Length -eq 0) { throw 'The GitHub client secret is empty.' }
# Configure the platform before enabling trust in its verified identity headers.
$currentMode = az containerapp show -g $ResourceGroup -n $AppName --query "properties.template.containers[0].env[?name=='FIELDWORK_AUTH'].value | [0]" -o tsv
Check-Native
if ($currentMode -ne 'locked') {
    az containerapp update -g $ResourceGroup -n $AppName --set-env-vars FIELDWORK_AUTH=locked -o none
    Check-Native
}
$secretPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)
$secretName = 'fieldwork-github-client-secret'
try {
    # Keep credentials in memory, never in native process arguments or logs.
    $stage = 'read app identity'
    $appId = az containerapp show -g $ResourceGroup -n $AppName --query id -o tsv
    Check-Native
    $azureToken = az account get-access-token --resource 'https://management.azure.com/' --query accessToken -o tsv
    Check-Native
    $azureHeaders = @{ Authorization = "Bearer $azureToken" }
    $appEndpoint = "https://management.azure.com$appId"
    $stage = 'read existing secret metadata'
    $existingSecrets = Invoke-RestMethod -Method Post -Uri "$appEndpoint/listSecrets?api-version=2025-01-01" -Headers $azureHeaders -ContentType 'application/json' -Body '{}'
    $secretValue = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secretPointer)
    $secretValues = @($existingSecrets.value | Where-Object name -ne $secretName) + @(@{name=$secretName;value=$secretValue})
    $secretBody = @{properties=@{configuration=@{secrets=$secretValues}}} | ConvertTo-Json -Depth 20
    $stage = 'store credential'
    $null = Invoke-RestMethod -Method Patch -Uri "${appEndpoint}?api-version=2025-01-01" -Headers $azureHeaders -ContentType 'application/json' -Body $secretBody
    $stored = $false
    for ($attempt=0; $attempt -lt 60; $attempt++) {
        $appState = Invoke-RestMethod -Method Get -Uri "${appEndpoint}?api-version=2025-01-01" -Headers $azureHeaders
        if ($appState.properties.provisioningState -eq 'Succeeded') { $stored=$true; break }
        if ($appState.properties.provisioningState -eq 'Failed') { throw 'Secret update failed.' }
        Start-Sleep -Seconds 2
    }
    if (-not $stored) { throw 'Secret update did not finish.' }
} catch {
    $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
    $azureCode = ''
    try { $azureCode = ($_.ErrorDetails.Message | ConvertFrom-Json).error.code } catch { }
    throw "Azure credential setup failed at '$stage' (HTTP $status, code $azureCode). The application remains locked."
} finally {
    $secretValue = $null
    $secretBody = $null
    $secretValues = $null
    $existingSecrets = $null
    $azureHeaders = $null
    $azureToken = $null
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPointer)
}
# Public UI assets remain available. Session discovery and course APIs require login.
$publicPaths = @('/','/style.css','/app.js','/favicon.svg','/health')
$authDocument = @{properties=@{
    platform=@{enabled=$true}
    globalValidation=@{unauthenticatedClientAction='Return401';excludedPaths=$publicPaths}
    httpSettings=@{requireHttps=$true}
    identityProviders=@{gitHub=@{enabled=$true;registration=@{clientId=$ClientId;clientSecretSettingName=$secretName};login=@{scopes=@()}}}
    login=@{tokenStore=@{enabled=$false};preserveUrlFragmentsForLogins=$false}
}}
# This document contains only public configuration and a secret reference.
$authFile = Join-Path ([IO.Path]::GetTempPath()) ('fieldwork-auth-' + [Guid]::NewGuid().ToString() + '.json')
try {
    [IO.File]::WriteAllText($authFile, ($authDocument | ConvertTo-Json -Depth 15))
    az rest --method put --url "$appEndpoint/authConfigs/current?api-version=2025-01-01" --body "@$authFile" -o none
    Check-Native
} finally { Remove-Item -LiteralPath $authFile -Force }
$auth = az containerapp auth show -g $ResourceGroup -n $AppName -o json | ConvertFrom-Json
Check-Native
if ($auth.properties) { $auth = $auth.properties }
if (-not $auth.platform.enabled -or $auth.identityProviders.gitHub.enabled -eq $false -or $auth.identityProviders.gitHub.registration.clientId -ne $ClientId -or $auth.identityProviders.gitHub.registration.clientSecretSettingName -ne $secretName -or $auth.globalValidation.unauthenticatedClientAction -ne 'Return401' -or -not $auth.httpSettings.requireHttps -or $auth.login.tokenStore.enabled -eq $true -or @($auth.identityProviders.gitHub.login.scopes).Count -ne 0) {
    throw 'Platform authentication was not verified. The app remains locked.'
}
if (@(Compare-Object $publicPaths @($auth.globalValidation.excludedPaths)).Count -ne 0) { throw 'Public paths were not verified. The app remains locked.' }
$url = 'https://' + (az containerapp show -g $ResourceGroup -n $AppName --query properties.configuration.ingress.fqdn -o tsv)
Check-Native
az containerapp update -g $ResourceGroup -n $AppName --set-env-vars FIELDWORK_AUTH=azure "FIELDWORK_ORIGIN=$url" -o none
Check-Native
Write-Host "GitHub sign-up/sign-in configured: $url"
Write-Host 'Complete one sign-in in the browser to verify the GitHub OAuth flow.'
