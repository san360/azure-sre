// Role assignments for SRE Agent on target resource groups
// Adapted from: https://github.com/microsoft/sre-agent/blob/main/samples/bicep-deployment/bicep/role-assignments-target.bicep
// Enables the SRE Agent to monitor resource groups beyond the deployment RG

@description('Principal ID of the user-assigned managed identity')
param userAssignedIdentityPrincipalId string

@description('Access level: High (Reader + Contributor + Log Analytics Reader) or Low (Reader + Log Analytics Reader)')
@allowed(['High', 'Low'])
param accessLevel string

// Role definition IDs based on access level
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

// Create role assignments in the target resource group
resource roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (roleDefinitionId, index) in roleDefinitions[accessLevel]: {
  name: guid(resourceGroup().id, userAssignedIdentityPrincipalId, roleDefinitionId)
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: userAssignedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}]
