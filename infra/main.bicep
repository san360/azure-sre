targetScope = 'subscription'

@description('Deployment region')
param location string = 'eastus2'

@description('Environment prefix')
param prefix string = 'contoso-meals'

@description('Enable Chaos Studio experiments')
param enableChaos bool = true

@description('Enable Azure Load Testing')
param enableLoadTesting bool = true

@description('Enable Jira Service Management deployment')
param enableJira bool = true

@description('PostgreSQL deployment region (eastus is restricted - use swedencentral)')
param postgresLocation string = 'swedencentral'

// Tags applied to ALL resources — SecurityControl=Ignore for demo environments
var tags = {
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
    name: 'kv-${sanitizedPrefix}'
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
      }
    ]
    managedIdentities: {
      systemAssigned: true
    }
    disableLocalAccounts: false
    omsAgentEnabled: true
    monitoringWorkspaceResourceId: logAnalytics.outputs.resourceId
    webApplicationRoutingEnabled: true
    tags: tags
  }
}

// Container App Environment — hosts menu-api, jira-sm, mcp-atlassian (AVM)
module containerAppEnv 'br/public:avm/res/app/managed-environment:0.8.1' = {
  scope: rg
  name: 'container-app-env'
  params: {
    name: 'cae-${prefix}'
    location: location
    logAnalyticsWorkspaceResourceId: logAnalytics.outputs.resourceId
    zoneRedundant: false
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
    tags: union(tags, { 'azd-service-name': 'menu-api' })
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
    location: 'centralus' // Using centralus due to Cosmos DB capacity constraints in eastus2/westus2
    enableFreeTier: false
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

// Jira Service Management Container App (AVM)
module jiraSm 'br/public:avm/res/app/container-app:0.12.0' = if (enableJira) {
  scope: rg
  name: 'jira-sm'
  params: {
    name: 'jira-sm'
    environmentResourceId: containerAppEnv.outputs.resourceId
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
          cpu: json('2')
          memory: '4Gi'
        }
        env: [
          // JDBC URL must reference the PostgreSQL FQDN with SSL enabled
          // The server name is psql-${prefix}-db, FQDN is psql-${prefix}-db.postgres.database.azure.com
          { name: 'ATL_JDBC_URL', value: 'jdbc:postgresql://${postgres.outputs.fqdn}:5432/jiradb?sslmode=require' }
          { name: 'ATL_JDBC_USER', value: 'contosoadmin' }
          { name: 'ATL_JDBC_PASSWORD', secretRef: 'jira-db-password' }
          { name: 'ATL_DB_DRIVER', value: 'org.postgresql.Driver' }
          { name: 'ATL_DB_TYPE', value: 'postgres72' }
          { name: 'JVM_MINIMUM_MEMORY', value: '1024m' }
          { name: 'JVM_MAXIMUM_MEMORY', value: '2048m' }
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
    aksResourceId: aks.outputs.resourceId
    logAnalyticsWorkspaceId: logAnalytics.outputs.resourceId
    prefix: prefix
    tags: tags
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

// Chaos Studio (optional)
module chaos './modules/chaos.bicep' = if (enableChaos) {
  scope: rg
  name: 'chaos-studio'
  params: {
    aksClusterName: aks.outputs.name
    prefix: prefix
    tags: tags
  }
}

// Outputs
output resourceGroupName string = rg.name
output aksClusterName string = aks.outputs.name
output menuApiFqdn string = menuApi.outputs.fqdn
output postgresServerName string = postgres.outputs.name
output postgresServerFqdn string = postgres.outputs.fqdn
output cosmosDbAccountName string = cosmosdb.outputs.name
output logAnalyticsWorkspaceId string = logAnalytics.outputs.resourceId
output containerAppEnvDefaultDomain string = containerAppEnv.outputs.defaultDomain
output jiraSmFqdn string = enableJira ? jiraSm.outputs.fqdn : ''
output mcpAtlassianFqdn string = enableJira ? mcpAtlassian.outputs.fqdn : ''

// azd-convention outputs (used by azd for service deployment)
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.outputs.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = 'acr${sanitizedPrefix}'
output AZURE_AKS_CLUSTER_NAME string = aks.outputs.name
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_CONTAINER_APPS_ENVIRONMENT_ID string = containerAppEnv.outputs.resourceId
