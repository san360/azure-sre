// Tiered role assignments for SRE Agent user-assigned managed identity
// Adapted from: https://github.com/microsoft/sre-agent/blob/main/samples/bicep-deployment/bicep/role-assignments-minimal.bicep
// Scoped to the resource group where this module is deployed

@description('Principal ID of the user-assigned managed identity')
param principalId string

@description('Access level: High (Reader + Contributor + Log Analytics Reader) or Low (Reader + Log Analytics Reader)')
@allowed(['High', 'Low'])
param accessLevel string = 'High'

@description('Enable Key Vault role assignments for the SRE Agent identity')
param enableKeyVault bool = false

// Role definition IDs based on access level
// Low:  Log Analytics Reader + Reader
// High: Log Analytics Reader + Reader + Contributor
var roleDefinitions = {
  Low: [
    '92aaf0da-9dab-42b6-94a3-d43ce8d16293' // Log Analytics Reader
    'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
  ]
  High: [
    '92aaf0da-9dab-42b6-94a3-d43ce8d16293' // Log Analytics Reader
    'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
    'b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor
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

// Key Vault Certificate User role (optional)
resource keyVaultCertificateUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableKeyVault) {
  name: guid(resourceGroup().id, principalId, 'db79e9a7-68ee-4b58-9aeb-b90e7c24fcba')
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'db79e9a7-68ee-4b58-9aeb-b90e7c24fcba')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault Secrets User role (optional)
resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableKeyVault) {
  name: guid(resourceGroup().id, principalId, '4633458b-17de-408a-b874-0445c86b69e6')
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
