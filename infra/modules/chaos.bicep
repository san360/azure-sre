param aksClusterName string
param prefix string
param tags object

// Reference existing AKS cluster for Chaos Studio targeting
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: aksClusterName
}

// NOTE: Chaos Mesh is installed via Helm in post-provision.sh because the
// Microsoft.KubernetesConfiguration/extensions 'Microsoft.Chaos' extension type
// is not supported in all regions (e.g. swedencentral).

// Chaos Studio Target for AKS
resource chaosTarget 'Microsoft.Chaos/targets@2024-01-01' = {
  name: 'Microsoft-AzureKubernetesServiceChaosMesh'
  scope: aksCluster
  properties: {}
}

// Capability: Pod Chaos
resource podChaosCap 'Microsoft.Chaos/targets/capabilities@2024-01-01' = {
  parent: chaosTarget
  name: 'PodChaos-2.2'
}

// Capability: Network Chaos (required for latency injection)
resource networkChaosCap 'Microsoft.Chaos/targets/capabilities@2024-01-01' = {
  parent: chaosTarget
  name: 'NetworkChaos-2.2'
}

// Experiment: Multi-step payment-service incident simulation
// Step 1: Network latency injection (triggers P95 latency alerts)
// Step 2: Pod failure / CrashLoopBackOff (triggers pod restart alerts)
resource experiment 'Microsoft.Chaos/experiments@2024-01-01' = {
  name: 'exp-${prefix}-payment-incident'
  location: resourceGroup().location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    selectors: [
      {
        type: 'List'
        id: 'selector1'
        targets: [
          {
            type: 'ChaosTarget'
            id: chaosTarget.id
          }
        ]
      }
    ]
    steps: [
      {
        name: 'Step 1 - Network latency degradation'
        branches: [
          {
            name: 'network-latency'
            actions: [
              {
                type: 'continuous'
                name: 'urn:csci:microsoft:azureKubernetesServiceChaosMesh:networkChaos/2.2'
                selectorId: 'selector1'
                duration: 'PT3M'
                parameters: [
                  {
                    key: 'jsonSpec'
                    value: '{"action":"delay","mode":"all","selector":{"namespaces":["production"],"labelSelectors":{"app":"payment-service"}},"delay":{"latency":"3000ms","jitter":"500ms","correlation":"50"},"direction":"to","duration":"180s"}'
                  }
                ]
              }
            ]
          }
        ]
      }
      {
        name: 'Step 2 - Pod failure (CrashLoopBackOff)'
        branches: [
          {
            name: 'pod-failure'
            actions: [
              {
                type: 'continuous'
                name: 'urn:csci:microsoft:azureKubernetesServiceChaosMesh:podChaos/2.2'
                selectorId: 'selector1'
                duration: 'PT5M'
                parameters: [
                  {
                    key: 'jsonSpec'
                    value: '{"action":"pod-failure","mode":"all","selector":{"namespaces":["production"],"labelSelectors":{"app":"payment-service"}},"duration":"120s"}'
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

// Role assignment: Chaos experiment identity → AKS Cluster Admin
// Required for Chaos Mesh pod-kill experiments on AKS
resource experimentAksClusterAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, experiment.id, 'aks-cluster-admin')
  scope: aksCluster
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8') // Azure Kubernetes Service Cluster Admin Role
    principalId: experiment.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
