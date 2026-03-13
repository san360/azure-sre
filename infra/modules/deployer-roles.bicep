// Role assignments for the deployer user (current logged-in user)
// Grants AKS cluster admin access and Key Vault administrator access
// Ref: https://github.com/matthansen0/azure-sre-agent-sandbox/blob/main/scripts/configure-rbac.ps1

@description('Object ID of the deployer user')
param deployerPrincipalId string

@description('Name of the AKS cluster')
param aksClusterName string

@description('Name of the Key Vault')
param keyVaultName string

// ─── AKS access for deployer ─────────────────────────────────────

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: aksClusterName
}

// Azure Kubernetes Service Cluster Admin Role — allows kubectl access
resource aksClusterAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, deployerPrincipalId, '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8')
  scope: aksCluster
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8')
    principalId: deployerPrincipalId
    principalType: 'User'
  }
}

// Azure Kubernetes Service RBAC Cluster Admin — full K8s RBAC permissions
resource aksRbacClusterAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, deployerPrincipalId, 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b')
  scope: aksCluster
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b')
    principalId: deployerPrincipalId
    principalType: 'User'
  }
}

// ─── Key Vault access for deployer ───────────────────────────────

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Key Vault Administrator — full Key Vault management
resource keyVaultAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, deployerPrincipalId, '00482a5a-887f-4fb3-b363-3b7fe8e74483')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')
    principalId: deployerPrincipalId
    principalType: 'User'
  }
}
