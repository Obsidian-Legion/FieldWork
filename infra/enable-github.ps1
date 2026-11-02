param(
    [string]$ResourceGroup = 'rg-fieldwork-eastus',
    [string]$AppName = 'fieldwork',
    [Parameter(Mandatory)][string]$ClientId,
    [Security.SecureString]$ClientSecret
)
$ErrorActionPreference = 'Stop'
function Check-Native { if ($LASTEXITCODE -ne 0) { throw 'GitHub authentication configuration failed; the application remains locked.' } }
if (-not $ClientSecret) { $ClientSecret = Read-Host 'GitHub OAuth client secret' -AsSecureString }
# Configure the platform before enabling trust in its verified identity headers.
az containerapp update -g $ResourceGroup -n $AppName --set-env-vars FIELDWORK_AUTH=locked -o none
Check-Native
$secretPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)
try {
    $secretValue = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secretPointer)
    az containerapp auth github update -g $ResourceGroup -n $AppName --client-id $ClientId --client-secret $secretValue --yes -o none
    Check-Native
} finally {
    $secretValue = $null
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPointer)
}
# Public UI assets and session discovery remain available. Course APIs require login.
az containerapp auth update -g $ResourceGroup -n $AppName --enabled true --action Return401 --require-https true --token-store false --excluded-paths / /style.css /app.js /favicon.svg /api/session /health --set 'identityProviders.gitHub.login.scopes=[]' --yes -o none
Check-Native
$auth = az containerapp auth show -g $ResourceGroup -n $AppName -o json | ConvertFrom-Json
Check-Native
if (-not $auth.properties.platform.enabled -or -not $auth.properties.identityProviders.gitHub.enabled -or $auth.properties.identityProviders.gitHub.registration.clientId -ne $ClientId) {
    throw 'Platform authentication was not verified. The app remains locked.'
}
$url = 'https://' + (az containerapp show -g $ResourceGroup -n $AppName --query properties.configuration.ingress.fqdn -o tsv)
Check-Native
az containerapp update -g $ResourceGroup -n $AppName --set-env-vars FIELDWORK_AUTH=azure "FIELDWORK_ORIGIN=$url" -o none
Check-Native
Write-Host "GitHub sign-up/sign-in configured: $url"
Write-Host 'Complete one sign-in in the browser to verify the GitHub OAuth flow.'
