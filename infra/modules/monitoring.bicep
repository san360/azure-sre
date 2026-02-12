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

// Pod Restart/Kill Alert (log-based — catches both pod-kill replacements and CrashLoopBackOff)
// Uses KubeEvents which persists regardless of metric scrape timing
resource podRestartLogAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-pod-restart-${prefix}'
  location: resourceGroup().location
  tags: tags
  properties: {
    displayName: 'Payment Service Pod Restarts or Failures Detected'
    severity: 1
    enabled: true
    scopes: [logAnalyticsWorkspaceId]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: 'KubeEvents | where Namespace == "production" | where Name startswith "payment-service" | where Reason in ("Killing", "BackOff", "Unhealthy", "FailedScheduling", "Failed") | summarize EventCount = count() by bin(TimeGenerated, 5m) | where EventCount > 2'
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
    evaluationFrequency: 'PT1M'
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

// Payment Service Error Rate Alert — catches HTTP 5xx errors (e.g. from pod failures)
resource paymentErrorAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-payment-errors-${prefix}'
  location: resourceGroup().location
  tags: tags
  properties: {
    displayName: 'Payment Service Error Rate > 10%'
    severity: 1
    enabled: true
    scopes: [logAnalyticsWorkspaceId]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: 'AppRequests | where Name contains "payment" | summarize Total = count(), Errors = countif(toint(ResultCode) >= 500) by bin(TimeGenerated, 5m) | extend ErrorRate = round(100.0 * Errors / Total, 1) | where ErrorRate > 10'
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
