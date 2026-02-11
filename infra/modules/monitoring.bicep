param aksResourceId string
param logAnalyticsWorkspaceId string
param prefix string
param tags object

// Action Group for SRE Agent
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-${prefix}-sre'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'SREAgent'
    enabled: true
    // SRE Agent webhook will be configured post-deployment through the portal
  }
}

// AKS Pod Restart Alert
resource podRestartAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-pod-restart-${prefix}'
  location: 'global'
  tags: tags
  properties: {
    severity: 1
    enabled: true
    scopes: [aksResourceId]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'PodRestartCount'
          metricNamespace: 'Insights.Container/pods'
          metricName: 'restartingContainerCount'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
          skipMetricValidation: true
        }
      ]
    }
    actions: [
      { actionGroupId: actionGroup.id }
    ]
  }
}

// Payment Service P95 Latency Alert (scheduled query rule against Log Analytics)
resource paymentLatencyAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-payment-latency-${prefix}'
  location: resourceGroup().location
  tags: tags
  properties: {
    displayName: 'Payment Service P95 Latency > 2s'
    severity: 2
    enabled: true
    scopes: [logAnalyticsWorkspaceId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: 'AppRequests | where Name contains "payment" | summarize percentile(DurationMs, 95) by bin(TimeGenerated, 5m) | where percentile_DurationMs_95 > 2000'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
    }
  }
}
