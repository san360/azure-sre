@description('Name of the Azure Container Registry')
param acrName string

@description('Name of the AKS cluster')
param aksClusterName string

// Reference existing ACR
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// Reference existing AKS cluster to read kubelet identity
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: aksClusterName
}

// AcrPull role assignment: AKS kubelet identity → ACR
// This is equivalent to `az aks update --attach-acr`
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, aksCluster.id, 'acrpull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: aksCluster.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}
