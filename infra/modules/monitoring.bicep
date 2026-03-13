param logAnalyticsWorkspaceId string
param appInsightsResourceId string
param prefix string
param tags object
param paymentServiceUrl string = ''
param location string = resourceGroup().location

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

// Pod Restart/Kill Alert (log-based — catches both pod-kill replacements and CrashLoopBackOff)
// Uses KubeEvents which persists regardless of metric scrape timing
resource podRestartLogAlert 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: 'alert-pod-restart-${prefix}'
  location: resourceGroup().location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: 'Payment Service Pod Restarts or Failures Detected'
    severity: 1
    enabled: true
    scopes: [logAnalyticsWorkspaceId]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT1M'
    autoMitigate: true
    skipQueryValidation: true
    criteria: {
      allOf: [
        {
          query: 'KubeEvents | where TimeGenerated > ago(2m) | where Namespace == "production" | where Name startswith "payment-service" | where Reason in ("Killing", "BackOff", "Unhealthy", "FailedScheduling", "Failed")'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
    }
  }
}

// Payment Service P95 Latency Alert (scoped to Application Insights for SRE Agent visibility)
resource paymentLatencyAlert 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: 'alert-payment-latency-${prefix}'
  location: resourceGroup().location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: 'Payment Service P95 Latency > 2s'
    severity: 2
    enabled: true
    scopes: [appInsightsResourceId]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    autoMitigate: true
    skipQueryValidation: true
    criteria: {
      allOf: [
        {
          query: 'requests | where timestamp > ago(5m) | where name contains "/pay" | summarize percentile(duration, 95) by bin(timestamp, 1m) | where percentile_duration_95 > 2000'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
    }
  }
}

// Payment Service Error Rate Alert — catches HTTP 5xx errors (scoped to Application Insights)
resource paymentErrorAlert 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: 'alert-payment-errors-${prefix}'
  location: resourceGroup().location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: 'Payment Service Error Rate > 10%'
    severity: 1
    enabled: true
    scopes: [appInsightsResourceId]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    autoMitigate: true
    skipQueryValidation: true
    criteria: {
      allOf: [
        {
          query: 'requests | where timestamp > ago(5m) | where name contains "/pay" | summarize Total = count(), Errors = countif(toint(resultCode) >= 500) by bin(timestamp, 1m) | extend ErrorRate = round(100.0 * Errors / Total, 1) | where ErrorRate > 10'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
    }
  }
}

// ─── Node Pool Failure Alerts ──────────────────────────────────────

// Node NotReady Alert — fires when workload nodes go NotReady
resource nodeNotReadyAlert 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: 'alert-node-not-ready-${prefix}'
  location: resourceGroup().location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: 'AKS Workload Node Pool - Node NotReady'
    severity: 1
    enabled: true
    scopes: [logAnalyticsWorkspaceId]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT1M'
    autoMitigate: true
    skipQueryValidation: true
    criteria: {
      allOf: [
        {
          query: 'KubeNodeInventory | where TimeGenerated > ago(2m) | where Status contains "NotReady" | where Computer contains "workload" | summarize NotReadyCount = dcount(Computer) by bin(TimeGenerated, 1m) | where NotReadyCount > 0'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
    }
  }
}

// Node Pool Scaled to Zero — fires when workload node pool has 0 ready nodes
resource nodePoolZeroAlert 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: 'alert-nodepool-zero-${prefix}'
  location: resourceGroup().location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: 'AKS Workload Node Pool Scaled to Zero Nodes'
    severity: 1
    enabled: true
    scopes: [logAnalyticsWorkspaceId]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT1M'
    autoMitigate: true
    skipQueryValidation: true
    criteria: {
      allOf: [
        {
          query: 'KubeNodeInventory | where TimeGenerated > ago(2m) | where Computer contains "workload" | summarize NodeCount = dcount(Computer) by bin(TimeGenerated, 1m) | where NodeCount == 0'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
    }
  }
}

// Pod Unschedulable Alert — fires when pods cannot be scheduled due to no nodes
resource podUnschedulableAlert 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: 'alert-pod-unschedulable-${prefix}'
  location: resourceGroup().location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: 'AKS Pods Unschedulable - No Available Nodes'
    severity: 1
    enabled: true
    scopes: [logAnalyticsWorkspaceId]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT1M'
    autoMitigate: true
    skipQueryValidation: true
    criteria: {
      allOf: [
        {
          query: 'KubeEvents | where TimeGenerated > ago(2m) | where Namespace == "production" | where Reason in ("FailedScheduling", "Unschedulable") | where Message contains "nodes are available" or Message contains "Insufficient"'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
    }
  }
}

// ─── Application Insights Standard Availability Test ──────────────

// Standard web test that pings the Payment Service /health endpoint
// from multiple Azure regions to monitor uptime and response time.
// Only deployed when a payment service URL is provided.
resource paymentHealthTest 'Microsoft.Insights/webtests@2022-06-15' = if (!empty(paymentServiceUrl)) {
  name: 'webtest-payment-health-${prefix}'
  location: location
  tags: union(tags, {
    // Tag linking the web test to the App Insights resource (required for alert correlation)
    'hidden-link:${appInsightsResourceId}': 'Resource'
  })
  properties: {
    SyntheticMonitorId: 'webtest-payment-health-${prefix}'
    Name: 'Payment Service Health Check'
    Enabled: true
    Frequency: 300       // every 5 minutes
    Timeout: 30          // 30 second timeout
    Kind: 'standard'
    RetryEnabled: true
    Locations: [
      { Id: 'us-va-ash-azr' }       // East US
      { Id: 'emea-nl-ams-azr' }     // West Europe
      { Id: 'emea-gb-db3-azr' }     // UK South
      { Id: 'apac-sg-sin-azr' }     // Southeast Asia
      { Id: 'us-ca-sjc-azr' }       // West US
    ]
    Request: {
      RequestUrl: '${paymentServiceUrl}/health'
      HttpVerb: 'GET'
      ParseDependentRequests: false
      FollowRedirects: true
    }
    ValidationRules: {
      ExpectedHttpStatusCode: 200
      SSLCheck: true
      SSLCertRemainingLifetimeCheck: 7
    }
  }
}

// Alert that fires when the availability test detects failures from 2+ locations
resource paymentAvailabilityAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (!empty(paymentServiceUrl)) {
  name: 'alert-payment-availability-${prefix}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Payment Service health endpoint is failing from multiple locations'
    severity: 1
    enabled: true
    scopes: [
      appInsightsResourceId
      paymentHealthTest.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.WebtestLocationAvailabilityCriteria'
      webTestId: paymentHealthTest.id
      componentId: appInsightsResourceId
      failedLocationCount: 2
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}
