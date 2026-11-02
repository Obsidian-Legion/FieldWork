param location string = resourceGroup().location
param appName string = 'fieldwork'
param environmentId string
param identityId string
param identityClientId string
param registryHost string
param storageUrl string
param imageTag string
param adminIds string
param origin string = ''
@allowed(['locked', 'azure'])
param authMode string = 'locked'

resource app 'Microsoft.App/containerApps@2025-01-01' = {
  name: appName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identityId}': {} }
  }
  properties: {
    managedEnvironmentId: environmentId
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: { external: true, targetPort: 8787, transport: 'http', allowInsecure: false }
      registries: [{ server: registryHost, identity: identityId }]
    }
    template: {
      containers: [{
        name: 'fieldwork'
        image: '${registryHost}/fieldwork:${imageTag}'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          { name: 'FIELDWORK_AUTH', value: authMode }
          { name: 'FIELDWORK_BIND', value: '0.0.0.0' }
          { name: 'FIELDWORK_ORIGIN', value: origin }
          { name: 'FIELDWORK_ADMIN_IDS', value: adminIds }
          { name: 'FIELDWORK_BLOB_URL', value: storageUrl }
          { name: 'AZURE_CLIENT_ID', value: identityClientId }
        ]
        probes: [
          { type: 'Liveness', httpGet: { path: '/health', port: 8787 }, initialDelaySeconds: 15, periodSeconds: 30 }
          { type: 'Readiness', httpGet: { path: '/health', port: 8787 }, initialDelaySeconds: 5, periodSeconds: 10 }
        ]
      }]
      scale: { minReplicas: 0, maxReplicas: 1 }
    }
  }
}
output appUrl string = 'https://${app.properties.configuration.ingress.fqdn}'
output appId string = app.id
