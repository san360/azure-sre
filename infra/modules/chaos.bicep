param aksClusterName string
param prefix string
param tags object

// Reference existing AKS cluster for Chaos Studio targeting
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: aksClusterName
}

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
                    value: '{"action":"pod-kill","mode":"one","selector":{"namespaces":["production"],"labelSelectors":{"app":"payment-service"}},"scheduler":{"cron":"*/1 * * * *"}}'
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
