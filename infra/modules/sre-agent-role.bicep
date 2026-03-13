// Tiered role assignments for SRE Agent user-assigned managed identity
// Adapted from: https://github.com/matthansen0/azure-sre-agent-sandbox/blob/main/scripts/configure-rbac.ps1
// Scoped to the resource group where this module is deployed

@description('Principal ID of the user-assigned managed identity')
param principalId string

@description('Access level: High (Reader + Contributor + Log Analytics Reader) or Low (Reader + Log Analytics Reader)')
@allowed(['High', 'Low'])
param accessLevel string = 'High'

@description('Enable Key Vault role assignments for the SRE Agent identity')
param enableKeyVault bool = false

@description('Name of the AKS cluster for AKS-specific role assignments')
param aksClusterName string = ''

@description('Name of the ACR for AcrPush role assignment')
param acrName string = ''

// Role definition IDs based on access level
// Low:  Log Analytics Reader + Reader
// High: Log Analytics Reader + Reader + Contributor + Log Analytics Contributor + Monitoring Reader
var roleDefinitions = {
  Low: [
    '92aaf0da-9dab-42b6-94a3-d43ce8d16293' // Log Analytics Reader
    'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
  ]
  High: [
    '92aaf0da-9dab-42b6-94a3-d43ce8d16293' // Log Analytics Reader
    'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
    'b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor
    '73c42c96-874c-492b-b04d-ab87d138a893' // Log Analytics Contributor
    '43d0d8ad-25c7-4714-9337-8ba259a9fe05' // Monitoring Reader
  ]
}

// Create role assignments based on access level
resource roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (roleDefinitionId, index) in roleDefinitions[accessLevel]: {
  name: guid(resourceGroup().id, principalId, roleDefinitionId)
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}]

// ─── AKS-specific roles ──────────────────────────────────────────
// Required for SRE Agent to perform K8s operations (restart pods, scale, kubectl access)
// Ref: https://github.com/matthansen0/azure-sre-agent-sandbox/blob/main/scripts/configure-rbac.ps1

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = if (!empty(aksClusterName)) {
  name: aksClusterName
}

// Azure Kubernetes Service Cluster Admin Role — allows kubectl access
resource aksClusterAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(aksClusterName)) {
  name: guid(aksCluster.id, principalId, '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8')
  scope: aksCluster
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

// Azure Kubernetes Service RBAC Cluster Admin — full K8s RBAC permissions
resource aksRbacClusterAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(aksClusterName)) {
  name: guid(aksCluster.id, principalId, 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b')
  scope: aksCluster
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

// Azure Kubernetes Service Contributor Role — manage AKS resource itself (scale nodes, update config)
resource aksContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(aksClusterName) && accessLevel == 'High') {
  name: guid(aksCluster.id, principalId, 'ed7f3fbd-7b88-4dd4-9017-9adb7ce333f8')
  scope: aksCluster
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ed7f3fbd-7b88-4dd4-9017-9adb7ce333f8')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

// ─── Key Vault roles ─────────────────────────────────────────────

// Key Vault Certificate User role (optional)
resource keyVaultCertificateUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableKeyVault) {
  name: guid(resourceGroup().id, principalId, 'db79e9a7-68ee-4b58-9aeb-b90e7c24fcba')
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'db79e9a7-68ee-4b58-9aeb-b90e7c24fcba')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault Secrets Officer — manage secrets (upgrade from Secrets User per reference script)
resource keyVaultSecretsOfficerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableKeyVault) {
  name: guid(resourceGroup().id, principalId, 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

// ─── ACR roles ───────────────────────────────────────────────────

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = if (!empty(acrName)) {
  name: acrName
}

// AcrPush — push/pull images
resource acrPushRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(acrName)) {
  name: guid(acr.id, principalId, '8311e382-0749-4cb8-b61a-304f252e45ec')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
