targetScope = 'subscription'

@description('Deployment region')
param location string = 'swedencentral'

@description('Environment prefix')
@minLength(3)
param prefix string = 'contoso-meals'

@description('Enable Chaos Studio experiments')
param enableChaos bool = true

@description('Enable Azure Load Testing')
param enableLoadTesting bool = true

@description('Enable Jira Service Management deployment')
param enableJira bool = true

@description('Enable Azure SRE Agent provisioning via Bicep')
param enableSreAgent bool = true

@description('SRE Agent access level: High (Contributor) or Low (Reader)')
@allowed(['High', 'Low'])
param sreAgentAccessLevel string = 'High'

@description('SRE Agent mode: Review (requires approval), Autonomous, or ReadOnly')
@allowed(['Review', 'Autonomous', 'ReadOnly'])
param sreAgentMode string = 'Review'

@description('External URL of the Payment Service (e.g. http://<LB-IP>). Empty = skip availability test.')
param paymentServiceUrl string = ''

@description('Object ID of the deployer user to assign the SRE Agent Administrator role. Leave empty to skip.')
param deployerPrincipalId string = ''

@description('Additional resource group names the SRE Agent should have access to (cross-RG monitoring)')
param targetResourceGroups array = []

@description('Subscription IDs for target resource groups (parallel array with targetResourceGroups, defaults to deployment subscription)')
param targetSubscriptions array = []

@description('PostgreSQL deployment region')
param postgresLocation string = 'swedencentral'

// Tags applied to ALL resources — CostControl=Ignore, SecurityControl=Ignore for demo environments
var tags = {
  CostControl: 'Ignore'
  SecurityControl: 'Ignore'
  Environment: 'demo'
  Project: prefix
}

// Sanitized prefix for resources that don't allow hyphens
var sanitizedPrefix = replace(prefix, '-', '')

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${prefix}'
  location: location
  tags: tags
}

// Log Analytics Workspace (AVM)
module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.9.1' = {
  scope: rg
  name: 'log-analytics'
  params: {
    name: 'law-${prefix}'
    location: location
    tags: tags
  }
}

// Key Vault (AVM)
module keyVault 'br/public:avm/res/key-vault/vault:0.11.0' = {
  scope: rg
  name: 'key-vault'
  params: {
    name: 'kv-${sanitizedPrefix}sc'
    location: location
    enableRbacAuthorization: true
    tags: tags
  }
}

// Azure Container Registry (AVM) — stores built container images for AKS and Container Apps
module acr 'br/public:avm/res/container-registry/registry:0.6.0' = {
  scope: rg
  name: 'container-registry'
  params: {
    name: 'acr${sanitizedPrefix}'
    location: location
    acrSku: 'Basic'
    acrAdminUserEnabled: true
    tags: tags
  }
}

// Application Insights (AVM) — application-level telemetry for all services
module appInsights 'br/public:avm/res/insights/component:0.4.2' = {
  scope: rg
  name: 'app-insights'
  params: {
    name: 'appi-${prefix}'
    workspaceResourceId: logAnalytics.outputs.resourceId
    location: location
    kind: 'web'
    applicationType: 'web'
    tags: tags
  }
}

// AKS Cluster — hosts order-api and payment-service (AVM)
// System pool: infrastructure workloads (2 nodes)
// User pool (workload): application workloads (1 node, manual scale) — chaos target
module aks 'br/public:avm/res/container-service/managed-cluster:0.12.0' = {
  scope: rg
  name: 'aks-cluster'
  params: {
    name: 'aks-${prefix}'
    location: location
    primaryAgentPoolProfiles: [
      {
        name: 'system'
        count: 2
        vmSize: 'Standard_B2s'
        mode: 'System'
        nodeTaints: [
          'CriticalAddonsOnly=true:NoSchedule'
        ]
      }
    ]
    agentPools: [
      {
        name: 'workload'
        count: 2
        vmSize: 'Standard_B2s'
        mode: 'User'
        osType: 'Linux'
        enableAutoScaling: false
        minCount: null
        maxCount: null
        nodeTaints: []
        nodeLabels: {
          'workload-type': 'application'
        }
      }
    ]
    managedIdentities: {
      systemAssigned: true
    }
    disableLocalAccounts: false
    omsAgentEnabled: true
    monitoringWorkspaceResourceId: logAnalytics.outputs.resourceId
    publicNetworkAccess: 'Enabled'
    webApplicationRoutingEnabled: true
    tags: tags
  }
}

// Container App Environment — hosts menu-api, web-ui, jira-sm, mcp-atlassian (AVM)
// Uses workload profiles to support higher CPU/memory for JIRA
module containerAppEnv 'br/public:avm/res/app/managed-environment:0.8.1' = {
  scope: rg
  name: 'container-app-env'
  params: {
    name: 'cae-${prefix}'
    location: location
    logAnalyticsWorkspaceResourceId: logAnalytics.outputs.resourceId
    zoneRedundant: false
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
      {
        name: 'Dedicated-D4'
        workloadProfileType: 'D4'
        minimumCount: 1
        maximumCount: 1
      }
    ]
    tags: tags
  }
}

// menu-api Container App — restaurant catalog service (AVM)
// NOTE: Cosmos DB and App Insights connection strings are injected post-provision via az containerapp update
module menuApi 'br/public:avm/res/app/container-app:0.12.0' = {
  scope: rg
  name: 'menu-api'
  params: {
    name: 'menu-api'
    environmentResourceId: containerAppEnv.outputs.resourceId
    containers: [
      {
        name: 'menu-api'
        image: 'mcr.microsoft.com/dotnet/samples:aspnetapp'
        resources: {
          cpu: json('0.5')
          memory: '1Gi'
        }
        env: [
          { name: 'CosmosDb__DatabaseName', value: 'catalogdb' }
          { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
        ]
      }
    ]
    managedIdentities: {
      systemAssigned: true
    }
    ingressTargetPort: 8080
    ingressExternal: true
    scaleMinReplicas: 2
    scaleMaxReplicas: 5
    tags: union(tags, { 'azd-service-name': 'menu-api' })
  }
}

// web-ui Container App — React frontend served via Nginx (AVM)
// NOTE: Backend API URLs are injected post-provision via az containerapp update
module webUi 'br/public:avm/res/app/container-app:0.12.0' = {
  scope: rg
  name: 'web-ui'
  params: {
    name: 'web-ui'
    environmentResourceId: containerAppEnv.outputs.resourceId
    containers: [
      {
        name: 'web-ui'
        image: 'mcr.microsoft.com/dotnet/samples:aspnetapp'
        resources: {
          cpu: json('0.5')
          memory: '1Gi'
        }
        env: [
          { name: 'MENU_API_URL', value: 'http://menu-api' }
          { name: 'ORDER_API_URL', value: 'http://order-api:8080' }
          { name: 'PAYMENT_API_URL', value: 'http://payment-service:8080' }
        ]
      }
    ]
    managedIdentities: {
      systemAssigned: true
    }
    ingressTargetPort: 8080
    ingressExternal: true
    scaleMinReplicas: 2
    scaleMaxReplicas: 5
    tags: union(tags, { 'azd-service-name': 'web-ui' })
  }
}

// PostgreSQL — ordersdb for order-api and payment-service, jiradb for Jira SM (Native Bicep)
// IMPORTANT: eastus has LocationIsOfferRestricted for PostgreSQL. Using swedencentral instead.
module postgres './modules/postgres.bicep' = {
  scope: rg
  name: 'postgres'
  params: {
    name: 'psql-${prefix}-db'
    location: postgresLocation
    administratorLogin: 'contosoadmin'
    administratorLoginPassword: 'P@ssw0rd1234!' // TODO: Replace with Key Vault reference for production
    logAnalyticsWorkspaceId: logAnalytics.outputs.resourceId
    tags: tags
  }
}

// Cosmos DB — catalogdb for menu-api (AVM)
module cosmosdb 'br/public:avm/res/document-db/database-account:0.11.0' = {
  scope: rg
  name: 'cosmosdb'
  params: {
    name: 'cosmos-${prefix}'
    location: location
    enableFreeTier: false
    disableLocalAuth: false
    networkRestrictions: {
      publicNetworkAccess: 'Enabled'
      ipRules: []
    }
    capabilitiesToAdd: [
      'EnableServerless'
    ]
    sqlDatabases: [
      {
        name: 'catalogdb'
        containers: [
          {
            name: 'restaurants'
            paths: ['/city']
          }
          {
            name: 'menus'
            paths: ['/restaurantId']
          }
        ]
      }
    ]
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalytics.outputs.resourceId
      }
    ]
    tags: tags
  }
}

// User-Assigned Managed Identity for Azure SRE Agent MCP Connector
// Required: SRE Agent connectors only support user-assigned MI (system-assigned is not fully functional).
// This identity is selected in the SRE Agent portal's connector dropdown and its client ID is
// passed as the AZURE_CLIENT_ID environment variable to the Azure MCP server.
module sreAgentIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  scope: rg
  name: 'sre-agent-identity'
  params: {
    name: 'id-${prefix}-sre-agent'
    location: location
    tags: tags
  }
}

// Role Assignment: Grant the SRE Agent identity tiered access on the resource group
// Adapted from official microsoft/sre-agent samples and azure-sre-agent-sandbox for tiered role assignment
// High: Reader + Contributor + Log Analytics Reader/Contributor + Monitoring Reader + AKS roles + Key Vault + ACR
// Low:  Reader + Log Analytics Reader
module sreAgentRoleAssignment 'modules/sre-agent-role.bicep' = {
  scope: rg
  name: 'sre-agent-role-assignments'
  params: {
    principalId: sreAgentIdentity.outputs.principalId
    accessLevel: sreAgentAccessLevel
    enableKeyVault: true
    aksClusterName: aks.outputs.name
    acrName: 'acr${sanitizedPrefix}'
  }
  dependsOn: [
    acr
  ]
}

// Deployer user role assignments — AKS admin + Key Vault admin for the current deploying user
// Ref: https://github.com/matthansen0/azure-sre-agent-sandbox/blob/main/scripts/configure-rbac.ps1
module deployerRoles 'modules/deployer-roles.bicep' = if (!empty(deployerPrincipalId)) {
  scope: rg
  name: 'deployer-role-assignments'
  params: {
    deployerPrincipalId: deployerPrincipalId
    aksClusterName: aks.outputs.name
    keyVaultName: 'kv-${sanitizedPrefix}sc'
  }
  dependsOn: [
    keyVault
  ]
}

// Azure Load Testing (AVM)
module loadTest 'br/public:avm/res/load-test-service/load-test:0.4.0' = if (enableLoadTesting) {
  scope: rg
  name: 'load-test'
  params: {
    name: 'lt-${prefix}'
    location: location
    loadTestDescription: 'Contoso Meals baseline and lunch rush load tests'
    managedIdentities: {
      systemAssigned: true
    }
    tags: tags
  }
}

// ACR → AKS pull role assignment (replaces az aks update --attach-acr in post-provision)
module acrPullRole 'modules/acr-pull-role.bicep' = {
  scope: rg
  name: 'acr-aks-pull-role'
  params: {
    acrName: 'acr${sanitizedPrefix}'
    aksClusterName: aks.outputs.name
  }
  dependsOn: [
    acr
  ]
}

// Storage Account for Jira home directory (AVM)
module storageAccount 'br/public:avm/res/storage/storage-account:0.14.0' = if (enableJira) {
  scope: rg
  name: 'storage-jira'
  params: {
    name: 'st${sanitizedPrefix}'
    location: location
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    fileServices: {
      shares: [
        {
          name: 'jira-home'
          shareQuota: 10
        }
      ]
    }
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalytics.outputs.resourceId
      }
    ]
    tags: tags
  }
}

// Jira Service Management Container App (AVM) — runs on dedicated D4 workload profile for performance
module jiraSm 'br/public:avm/res/app/container-app:0.12.0' = if (enableJira) {
  scope: rg
  name: 'jira-sm'
  params: {
    name: 'jira-sm'
    environmentResourceId: containerAppEnv.outputs.resourceId
    workloadProfileName: 'Dedicated-D4'
    secrets: {
      secureList: [
        {
          name: 'jira-db-password'
          value: 'P@ssw0rd1234!'
        }
      ]
    }
    containers: [
      {
        name: 'jira'
        image: 'atlassian/jira-servicemanagement:10.0'
        resources: {
          cpu: json('4')
          memory: '8Gi'
        }
        env: [
          // JDBC URL must reference the PostgreSQL FQDN with SSL enabled
          // The server name is psql-${prefix}-db, FQDN is psql-${prefix}-db.postgres.database.azure.com
          { name: 'ATL_JDBC_URL', value: 'jdbc:postgresql://${postgres.outputs.fqdn}:5432/jiradb?sslmode=require' }
          { name: 'ATL_JDBC_USER', value: 'contosoadmin' }
          { name: 'ATL_JDBC_PASSWORD', secretRef: 'jira-db-password' }
          { name: 'ATL_DB_DRIVER', value: 'org.postgresql.Driver' }
          { name: 'ATL_DB_TYPE', value: 'postgres72' }
          { name: 'JVM_MINIMUM_MEMORY', value: '2048m' }
          { name: 'JVM_MAXIMUM_MEMORY', value: '6144m' }
          // Proxy settings for Container Apps ingress
          { name: 'ATL_PROXY_NAME', value: 'jira-sm.${containerAppEnv.outputs.defaultDomain}' }
          { name: 'ATL_PROXY_PORT', value: '443' }
          { name: 'ATL_TOMCAT_SCHEME', value: 'https' }
          { name: 'ATL_TOMCAT_SECURE', value: 'true' }
        ]
      }
    ]
    ingressTargetPort: 8080
    ingressExternal: true
    scaleMinReplicas: 1
    scaleMaxReplicas: 1
    managedIdentities: {
      systemAssigned: true
    }
    tags: tags
  }
}

// mcp-atlassian MCP Server Container App (AVM)
module mcpAtlassian 'br/public:avm/res/app/container-app:0.12.0' = if (enableJira) {
  scope: rg
  name: 'mcp-atlassian'
  params: {
    name: 'mcp-atlassian'
    environmentResourceId: containerAppEnv.outputs.resourceId
    secrets: {
      secureList: [
        {
          name: 'jira-api-token'
          value: 'placeholder-update-after-jira-setup'
        }
      ]
    }
    containers: [
      {
        name: 'mcp-atlassian'
        image: 'ghcr.io/sooperset/mcp-atlassian:latest'
        resources: {
          cpu: json('0.5')
          memory: '1Gi'
        }
        args: [
          '--transport'
          'streamable-http'
          '--stateless'
          '--port'
          '9000'
        ]
        env: [
          { name: 'JIRA_URL', value: 'https://jira-sm.${containerAppEnv.outputs.defaultDomain}' }
          { name: 'JIRA_USERNAME', value: 'admin' }
          { name: 'JIRA_API_TOKEN', secretRef: 'jira-api-token' }
        ]
      }
    ]
    ingressTargetPort: 9000
    ingressExternal: true
    scaleMinReplicas: 2
    scaleMaxReplicas: 5
    managedIdentities: {
      systemAssigned: true
    }
    tags: tags
  }
}

// Monitoring: Alert Rules
module monitoring './modules/monitoring.bicep' = {
  scope: rg
  name: 'monitoring'
  params: {
    logAnalyticsWorkspaceId: logAnalytics.outputs.resourceId
    appInsightsResourceId: appInsights.outputs.resourceId
    prefix: prefix
    tags: tags
    paymentServiceUrl: paymentServiceUrl
    location: location
  }
}

// Observability Dashboard Workbook
module workbook './modules/workbooks.bicep' = {
  scope: rg
  name: 'observability-workbook'
  params: {
    logAnalyticsWorkspaceId: logAnalytics.outputs.resourceId
    prefix: prefix
    location: location
    tags: tags
  }
}

// Chaos Studio (optional) — payment-service pod/network chaos
module chaos './modules/chaos.bicep' = if (enableChaos) {
  scope: rg
  name: 'chaos-studio'
  params: {
    aksClusterName: aks.outputs.name
    prefix: prefix
    tags: tags
  }
}

// Chaos Studio — AKS user node pool failure experiment
// Scales the 'workload' user node pool to 0 / kills all nodes to simulate node failure
module chaosNodePool './modules/chaos-node-pool.bicep' = if (enableChaos) {
  scope: rg
  name: 'chaos-nodepool'
  params: {
    aksClusterName: aks.outputs.name
    prefix: prefix
    tags: tags
  }
}

// ─── Azure SRE Agent (optional) ────────────────────────────────────
// Deploys the SRE Agent resource (Microsoft.App/agents@2025-05-01-preview)
// Adapted from: https://github.com/microsoft/sre-agent/blob/main/samples/bicep-deployment/
// Includes: Smart Detection alerts, SRE Agent Administrator role for deployer,
//           and cross-RG targeting support
module sreAgent './modules/sre-agent.bicep' = if (enableSreAgent) {
  scope: rg
  name: 'sre-agent'
  params: {
    agentName: '${prefix}-sre'
    location: location
    userAssignedIdentityId: sreAgentIdentity.outputs.resourceId
    appInsightsAppId: appInsights.outputs.applicationId
    appInsightsConnectionString: appInsights.outputs.connectionString
    accessLevel: sreAgentAccessLevel
    agentMode: sreAgentMode
    deployerPrincipalId: deployerPrincipalId
    tags: tags
  }
  dependsOn: [
    sreAgentRoleAssignment
  ]
}

// Target resource group role assignments (cross-RG monitoring)
// Grants the SRE Agent identity access to additional resource groups
module targetRoleAssignments 'modules/sre-agent-role-target.bicep' = [for (targetRG, index) in targetResourceGroups: if (enableSreAgent) {
  name: 'sre-agent-target-role-${index}'
  scope: resourceGroup(length(targetSubscriptions) > index ? targetSubscriptions[index] : subscription().subscriptionId, targetRG)
  params: {
    userAssignedIdentityPrincipalId: sreAgentIdentity.outputs.principalId
    accessLevel: sreAgentAccessLevel
  }
}]

// Outputs
output resourceGroupName string = rg.name
output aksClusterName string = aks.outputs.name
output menuApiFqdn string = menuApi.outputs.fqdn
output webUiFqdn string = webUi.outputs.fqdn
output postgresServerName string = postgres.outputs.name
output postgresServerFqdn string = postgres.outputs.fqdn
output cosmosDbAccountName string = cosmosdb.outputs.name
output logAnalyticsWorkspaceId string = logAnalytics.outputs.resourceId
output containerAppEnvDefaultDomain string = containerAppEnv.outputs.defaultDomain
output jiraSmFqdn string = enableJira ? jiraSm!.outputs.fqdn : ''
output mcpAtlassianFqdn string = enableJira ? mcpAtlassian!.outputs.fqdn : ''

// SRE Agent identity outputs — use these when configuring the Azure MCP connector
output sreAgentIdentityName string = sreAgentIdentity.outputs.name
output sreAgentIdentityClientId string = sreAgentIdentity.outputs.clientId
output sreAgentIdentityPrincipalId string = sreAgentIdentity.outputs.principalId
output sreAgentIdentityResourceId string = sreAgentIdentity.outputs.resourceId

// SRE Agent resource outputs (when deployed via Bicep)
output sreAgentId string = enableSreAgent ? sreAgent!.outputs.agentId : ''
output sreAgentPortalUrl string = enableSreAgent ? sreAgent!.outputs.agentPortalUrl : ''

// azd-convention outputs (used by azd for service deployment)
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.outputs.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = 'acr${sanitizedPrefix}'
output AZURE_AKS_CLUSTER_NAME string = aks.outputs.name
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_CONTAINER_APPS_ENVIRONMENT_ID string = containerAppEnv.outputs.resourceId
