// Role assignment: Reader role for SRE Agent user-assigned managed identity
// Scoped to the resource group where this module is deployed

@description('Principal ID of the user-assigned managed identity')
param principalId string

// Reader built-in role
var readerRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, readerRoleDefinitionId)
  properties: {
    principalId: principalId
    roleDefinitionId: readerRoleDefinitionId
    principalType: 'ServicePrincipal'
  }
}
