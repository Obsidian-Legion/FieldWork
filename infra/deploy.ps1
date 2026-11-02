param(
    [string]$ResourceGroup = 'rg-fieldwork-eastus',
    [string]$Location = 'eastus',
    [string]$AppName = 'fieldwork',
    [string]$DependencyCache = '',
    [Parameter(Mandatory)][string]$AdminGitHubIds,
    [string]$ImageTag = ('release-' + (Get-Date -Format 'yyyyMMddHHmmss'))
)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath (Split-Path $PSScriptRoot -Parent)
New-Item -ItemType Directory -Force '.runtime' | Out-Null
function Check-Native { if ($LASTEXITCODE -ne 0) { throw 'Deployment command failed.' } }
function Build-Bicep([string]$Source, [string]$Output) {
    if (Test-Path -LiteralPath '.runtime/tools/bicep.exe') { & '.runtime/tools/bicep.exe' build $Source --outfile $Output }
    else { az bicep build --file $Source --outfile $Output }
    Check-Native
}
Build-Bicep 'infra/foundation.bicep' '.runtime/foundation.json'
Build-Bicep 'infra/app.bicep' '.runtime/app.json'
az group create --name $ResourceGroup --location $Location --tags project=fieldwork sponsor=obsidian-legion --output none
Check-Native
az deployment group create --resource-group $ResourceGroup --name fieldwork-foundation --template-file '.runtime/foundation.json' --output none
Check-Native
$foundation = az deployment group show --resource-group $ResourceGroup --name fieldwork-foundation --query properties.outputs --output json | ConvertFrom-Json
Check-Native
$registry = $foundation.registryName.value
$registryHost = $foundation.registryHost.value
if ($DependencyCache) {
    $cachePath = (Resolve-Path -LiteralPath $DependencyCache).Path
    docker build --build-arg DEPENDENCIES=cached --build-context "unison-codebase=$cachePath" -t "$registryHost/fieldwork:$ImageTag" .
} else { docker build -t "$registryHost/fieldwork:$ImageTag" . }
Check-Native
az acr login --name $registry --output none
Check-Native
docker push "$registryHost/fieldwork:$ImageTag"
Check-Native
# Preserve existing authentication on later releases. New applications start locked.
$existing = az containerapp list --resource-group $ResourceGroup --query "[?name=='$AppName'] | [0]" --output json | ConvertFrom-Json
Check-Native
$origin = ''
$authMode = 'locked'
if ($existing) {
    $origin = 'https://' + $existing.properties.configuration.ingress.fqdn
    $currentMode = $existing.properties.template.containers[0].env | Where-Object name -eq 'FIELDWORK_AUTH'
    if ($currentMode.value -eq 'azure') { $authMode = 'azure' }
}
$parameters = @{
    appName = @{value=$AppName}; environmentId = @{value=$foundation.environmentId.value}
    identityId = @{value=$foundation.identityId.value}; identityClientId = @{value=$foundation.identityClientId.value}
    registryHost = @{value=$registryHost}; storageUrl = @{value=$foundation.storageUrl.value}
    imageTag = @{value=$ImageTag}; adminIds = @{value=$AdminGitHubIds}; origin = @{value=$origin}; authMode = @{value=$authMode}
}
$parameterDocument = @{ '$schema'='https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion='1.0.0.0'; parameters=$parameters }
[IO.File]::WriteAllText((Join-Path (Get-Location) '.runtime/app-parameters.json'), ($parameterDocument | ConvertTo-Json -Depth 10))
az deployment group create --resource-group $ResourceGroup --name fieldwork-app --template-file '.runtime/app.json' --parameters '@.runtime/app-parameters.json' --output none
Check-Native
$app = az deployment group show --resource-group $ResourceGroup --name fieldwork-app --query properties.outputs --output json | ConvertFrom-Json
Check-Native
$url = $app.appUrl.value
az containerapp update --resource-group $ResourceGroup --name $AppName --set-env-vars "FIELDWORK_ORIGIN=$url" --output none
Check-Native
$details = @{resourceGroup=$ResourceGroup;appName=$AppName;url=$url;appId=$app.appId.value;registry=$registry;imageTag=$ImageTag;callback="$url/.auth/login/github/callback"}
[IO.File]::WriteAllText((Join-Path (Get-Location) 'infra/deployment.local.json'), ($details | ConvertTo-Json))
Write-Host "FIELDWORK: $url"
Write-Host "GitHub callback: $url/.auth/login/github/callback"
Write-Host "New deployments stay locked until GitHub authentication is configured."
