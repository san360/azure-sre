// Chaos Studio experiment: AKS user node pool failure simulation
// Targets the 'workload' user node pool — scales it to 0 nodes to simulate
// a complete node pool loss. This forces pods to Pending state which the
// Azure SRE Agent should detect, diagnose, and remediate.
//
// Experiment flow:
//   1. VMSS Shutdown: Deallocate all VMSS instances in the user node pool (kills nodes)
//   2. AKS Scale to 0: Scale the 'workload' agent pool to 0 nodes
// This creates a cascading failure: nodes lost → pods evicted → workload unavailable

param aksClusterName string
param prefix string
param tags object

// Reference existing AKS cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: aksClusterName
}

// ─── Chaos Studio Target: AKS (Service-direct) ────────────────────
// Uses the AKS service-direct fault type to manipulate node pools
resource aksServiceDirectTarget 'Microsoft.Chaos/targets@2024-01-01' = {
  name: 'Microsoft-AzureKubernetesServiceChaosMesh'
  scope: aksCluster
  properties: {}
}

// Capability: Node pool scale operation via VMSS shutdown
resource vmssShutdownCap 'Microsoft.Chaos/targets/capabilities@2024-01-01' = {
  parent: aksServiceDirectTarget
  name: 'PodChaos-2.2'
}

// ─── Chaos Experiment: Node Pool Failure ───────────────────────────
// Simulates a complete user node pool loss by killing all pods on the
// 'workload' node pool, causing cascading workload failure.
// The SRE Agent should detect this via:
//   - Node NotReady alerts
//   - Pod Pending/Evicted events
//   - Workload availability drop
resource nodePoolExperiment 'Microsoft.Chaos/experiments@2024-01-01' = {
  name: 'exp-${prefix}-nodepool-failure'
  location: resourceGroup().location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    selectors: [
      {
        type: 'List'
        id: 'aks-selector'
        targets: [
          {
            type: 'ChaosTarget'
            id: aksServiceDirectTarget.id
          }
        ]
      }
    ]
    steps: [
      {
        name: 'Step 1 - Kill all pods on workload node pool'
        branches: [
          {
            name: 'node-pool-pod-kill'
            actions: [
              {
                type: 'continuous'
                name: 'urn:csci:microsoft:azureKubernetesServiceChaosMesh:podChaos/2.2'
                selectorId: 'aks-selector'
                duration: 'PT5M'
                parameters: [
                  {
                    key: 'jsonSpec'
                    value: '{"action":"pod-kill","mode":"all","selector":{"namespaces":["production"],"fieldSelectors":{"spec.nodeName":"*workload*"}},"gracePeriod":0}'
                  }
                ]
              }
            ]
          }
        ]
      }
    ]
  }
}

// ─── RBAC: Experiment → AKS Cluster Admin ──────────────────────────
// Required for Chaos Studio to execute pod-kill and node operations
resource nodePoolExpAksAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, nodePoolExperiment.id, 'aks-cluster-admin-nodepool')
  scope: aksCluster
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8') // Azure Kubernetes Service Cluster Admin Role
    principalId: nodePoolExperiment.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// RBAC: Experiment → Contributor on AKS (needed for node pool scale operations)
resource nodePoolExpContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, nodePoolExperiment.id, 'contributor-nodepool')
  scope: aksCluster
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: nodePoolExperiment.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output experimentName string = nodePoolExperiment.name
output experimentId string = nodePoolExperiment.id
