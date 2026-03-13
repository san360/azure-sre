// Azure SRE Agent resource deployment
// Adapted from: https://github.com/microsoft/sre-agent/blob/main/samples/bicep-deployment/
// Deploys the SRE Agent (Microsoft.App/agents@2025-05-01-preview) with App Insights connection.
//
// NOTE: Smart Detection alerts are auto-provisioned by Azure when App Insights is created.
// NOTE: SRE Agent Administrator role is assigned via deploy.sh (CLI is idempotent on re-deployment).

@description('Name of the SRE Agent')
param agentName string

@description('Location for the SRE Agent')
param location string

@description('Resource ID of the user-assigned managed identity')
param userAssignedIdentityId string

@description('Application Insights App ID')
param appInsightsAppId string

@description('Application Insights connection string')
param appInsightsConnectionString string

@description('Access level: High (Contributor) or Low (Reader)')
@allowed(['High', 'Low'])
param accessLevel string = 'High'

@description('Agent mode: Review, Autonomous, ReadOnly')
@allowed(['Review', 'Autonomous', 'ReadOnly'])
param agentMode string = 'Review'

@description('Object ID of the deployer user to assign SRE Agent Administrator role. Empty = skip.')
param deployerPrincipalId string = ''

@description('Tags to apply to resources')
param tags object = {}

// NOTE: Smart Detection Action Group and Failure Anomalies alert rule are NOT deployed here.
// Azure auto-provisions a FailureAnomaliesDetector alert when Application Insights is created.
// Deploying a second one causes "ScopeInUse" errors on re-deployment.

// Azure SRE Agent resource (preview API)
#disable-next-line BCP081
resource sreAgent 'Microsoft.App/agents@2025-05-01-preview' = {
  name: agentName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    knowledgeGraphConfiguration: {
      identity: userAssignedIdentityId
      managedResources: []
    }
    actionConfiguration: {
      accessLevel: accessLevel
      identity: userAssignedIdentityId
      mode: agentMode
    }
    logConfiguration: {
      applicationInsightsConfiguration: {
        appId: appInsightsAppId
        connectionString: appInsightsConnectionString
      }
    }
  }
}

// SRE Agent Administrator role assignment for the deployer
// Role ID: e79298df-d852-4c6d-84f9-5d13249d1e55 (SRE Agent Administrator)
// Ref: https://learn.microsoft.com/en-gb/azure/sre-agent/user-roles
// NOTE: Uses deterministic GUID based on resourceGroup().id to avoid RoleAssignmentExists conflicts
// when the deployer has already been assigned this role via CLI (az role assignment create).
resource sreAgentAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  name: guid(resourceGroup().id, deployerPrincipalId, 'e79298df-d852-4c6d-84f9-5d13249d1e55')
  scope: sreAgent
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'e79298df-d852-4c6d-84f9-5d13249d1e55')
    principalId: deployerPrincipalId
    principalType: 'User'
  }
}

output agentId string = sreAgent.id
output agentName string = sreAgent.name
output agentPortalUrl string = 'https://portal.azure.com/#view/Microsoft_Azure_PaasServerless/AgentFrameBlade.ReactView/id/${replace(sreAgent.id, '/', '%2F')}'
