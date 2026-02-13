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

// ─── Node Pool Failure Alerts ──────────────────────────────────────

// Node NotReady Alert — fires when workload nodes go NotReady
resource nodeNotReadyAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-node-not-ready-${prefix}'
  location: resourceGroup().location
  tags: tags
  properties: {
    displayName: 'AKS Workload Node Pool - Node NotReady'
    severity: 1
    enabled: true
    scopes: [logAnalyticsWorkspaceId]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: 'KubeNodeInventory | where Status contains "NotReady" | where Computer contains "workload" | summarize NotReadyCount = dcount(Computer) by bin(TimeGenerated, 5m) | where NotReadyCount > 0'
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

// Node Pool Scaled to Zero — fires when workload node pool has 0 ready nodes
resource nodePoolZeroAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-nodepool-zero-${prefix}'
  location: resourceGroup().location
  tags: tags
  properties: {
    displayName: 'AKS Workload Node Pool Scaled to Zero Nodes'
    severity: 1
    enabled: true
    scopes: [logAnalyticsWorkspaceId]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: 'KubeNodeInventory | where Computer contains "workload" | summarize NodeCount = dcount(Computer) by bin(TimeGenerated, 5m) | where NodeCount == 0'
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

// Pod Unschedulable Alert — fires when pods cannot be scheduled due to no nodes
resource podUnschedulableAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-pod-unschedulable-${prefix}'
  location: resourceGroup().location
  tags: tags
  properties: {
    displayName: 'AKS Pods Unschedulable - No Available Nodes'
    severity: 1
    enabled: true
    scopes: [logAnalyticsWorkspaceId]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: 'KubeEvents | where Namespace == "production" | where Reason in ("FailedScheduling", "Unschedulable") | where Message contains "nodes are available" or Message contains "Insufficient" | summarize EventCount = count() by bin(TimeGenerated, 5m) | where EventCount > 0'
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
