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

// Experiment: Kill payment-service pods
resource experiment 'Microsoft.Chaos/experiments@2024-01-01' = {
  name: 'exp-${prefix}-pod-kill'
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
        name: 'Kill payment-service pods'
        branches: [
          {
            name: 'branch1'
            actions: [
              {
                type: 'continuous'
                name: 'urn:csci:microsoft:azureKubernetesServiceChaosMesh:podChaos/2.2'
                selectorId: 'selector1'
                duration: 'PT5M'
                parameters: [
                  {
                    key: 'jsonSpec'
                    value: '{"action":"pod-kill","mode":"all","selector":{"namespaces":["production"],"labelSelectors":{"app":"payment-service"}},"scheduler":{"cron":"*/1 * * * *"}}'
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
