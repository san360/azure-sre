// Azure SRE Agent resource deployment
// Adapted from: https://github.com/microsoft/sre-agent/blob/main/samples/bicep-deployment/
// Deploys the SRE Agent (Microsoft.App/agents@2025-05-01-preview) with App Insights,
// Smart Detection alerts, and SRE Agent Administrator role for the deployer.

@description('Name of the SRE Agent')
param agentName string

@description('Location for the SRE Agent')
param location string

@description('Resource ID of the user-assigned managed identity')
param userAssignedIdentityId string

@description('Application Insights resource ID (for Smart Detection alert scope)')
param appInsightsResourceId string

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

@description('Tags to apply to resources')
param tags object = {}

// Smart Detection Action Group (from official samples)
resource smartDetectionActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'Application Insights Smart Detection'
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'SmartDetect'
    enabled: true
    armRoleReceivers: [
      {
        name: 'Monitoring Contributor'
        roleId: '749f88d5-cbae-40b8-bcfc-e573ddc772fa'
        useCommonAlertSchema: true
      }
      {
        name: 'Monitoring Reader'
        roleId: '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
        useCommonAlertSchema: true
      }
    ]
  }
}

// Failure Anomalies Smart Detector alert rule (from official samples)
resource failureAnomaliesSmartDetector 'Microsoft.AlertsManagement/smartDetectorAlertRules@2021-04-01' = {
  name: 'Failure Anomalies - ${agentName}'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Failure Anomalies notifies you of an unusual rise in the rate of failed HTTP requests or dependency calls.'
    state: 'Enabled'
    severity: 'Sev3'
    frequency: 'PT1M'
    detector: {
      id: 'FailureAnomaliesDetector'
    }
    scope: [
      appInsightsResourceId
    ]
    actionGroups: {
      groupIds: [
        smartDetectionActionGroup.id
      ]
    }
  }
}

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

// Auto-assign SRE Agent Administrator role to the deployer
// Role ID e79298df-d852-4c6d-84f9-5d13249d1e55 = SRE Agent Administrator
#disable-next-line BCP081
resource sreAgentAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sreAgent.id, deployer().objectId, 'e79298df-d852-4c6d-84f9-5d13249d1e55')
  scope: sreAgent
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'e79298df-d852-4c6d-84f9-5d13249d1e55')
    principalId: deployer().objectId
    principalType: 'User'
  }
}

output agentId string = sreAgent.id
output agentName string = sreAgent.name
output agentPortalUrl string = 'https://portal.azure.com/#view/Microsoft_Azure_PaasServerless/AgentFrameBlade.ReactView/id/${replace(sreAgent.id, '/', '%2F')}'
