@description('Resource ID of the Log Analytics workspace to associate with this workbook')
param logAnalyticsWorkspaceId string

@description('Environment prefix for naming')
param prefix string

@description('Deployment location')
param location string = resourceGroup().location

@description('Tags to apply to the workbook resource')
param tags object = {}

// Generate a deterministic GUID for the workbook using the resource group ID and prefix.
// This ensures idempotent deployments — re-running produces the same workbook resource.
var workbookId = guid(resourceGroup().id, 'contoso-meals-dashboard', prefix)

// Load the workbook template from the JSON file in ../workbooks/
var workbookContent = loadTextContent('../workbooks/contoso-meals-dashboard.json')

resource workbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: workbookId
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: '${prefix} - Observability Dashboard'
    category: 'workbook'
    sourceId: logAnalyticsWorkspaceId
    serializedData: workbookContent
    version: '1.0'
  }
}

@description('The resource ID of the deployed workbook')
output workbookId string = workbook.id

@description('The name (GUID) of the deployed workbook')
output workbookName string = workbook.name
