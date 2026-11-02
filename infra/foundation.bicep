param location string = resourceGroup().location
param prefix string = 'fieldwork'
var suffix = uniqueString(resourceGroup().id)

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${prefix}-identity'
  location: location
}
resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: 'olfw${suffix}'
  location: location
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: false }
}
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'olfw${suffix}'
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
  }
}
resource blobs 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    isVersioningEnabled: true
    deleteRetentionPolicy: { enabled: true, days: 7 }
    containerDeleteRetentionPolicy: { enabled: true, days: 7 }
  }
}
resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobs
  name: 'fieldwork'
  properties: { publicAccess: 'None' }
}
resource blobAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(container.id, identity.id, 'blob-contributor')
  scope: container
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
resource imageAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, identity.id, 'image-pull')
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
resource environment 'Microsoft.App/managedEnvironments@2025-01-01' = {
  name: '${prefix}-environment'
  location: location
  properties: {
    workloadProfiles: [{ name: 'Consumption', workloadProfileType: 'Consumption' }]
  }
}
output registryName string = registry.name
output registryHost string = registry.properties.loginServer
output storageUrl string = '${storage.properties.primaryEndpoints.blob}fieldwork'
output environmentId string = environment.id
output identityId string = identity.id
output identityClientId string = identity.properties.clientId
