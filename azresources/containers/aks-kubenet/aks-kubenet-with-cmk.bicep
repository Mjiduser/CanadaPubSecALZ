// ----------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
//
// THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, 
// EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES 
// OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
// ----------------------------------------------------------------------------------

@description('Azure Kubernetes Service Name.')
param name string

@description('Azure Kubernetes Service Version.')
param version string

@description('Key/Value pair of tags.')
param tags object = {}

@description('AKS Managed Resource Group Name.')
param nodeResourceGroupName string

@description('User Assigned Managed Identity Resource Id.')
param userAssignedIdentityId string

// System Node Pool
@description('System Node Pool - Boolean to enable auto scaling.')
param systemNodePoolEnableAutoScaling bool

@description('System Node Pool - Minimum Node Count.')
param systemNodePoolMinNodeCount int

@description('System Node Pool - Maximum Node Count.')
param systemNodePoolMaxNodeCount int

@description('System Node Pool - Node SKU.')
param systemNodePoolNodeSize string

// User Node Pool
@description('User Node Pool - Boolean to enable auto scaling.')
param userNodePoolEnableAutoScaling bool

@description('User Node Pool - Minimum Node Count.')
param userNodePoolMinNodeCount int

@description('User Node Pool - Maximum Node Count.')
param userNodePoolMaxNodeCount int

@description('User Node Pool - Node SKU.')
param userNodePoolNodeSize string

// Networking
@description('Subnet Resource Id.')
param subnetId string

@description('DNS Prefix.')
param dnsPrefix string

@description('Private DNS Zone Resource Id.')
param privateDNSZoneId string

// Kubernetes Networking
@description('Pod CIDR.  Default: 11.0.0.0/16')
param podCidr string = '11.0.0.0/16'

@description('Service CIDR.  Default: 20.0.0.0/16')
param serviceCidr string = '20.0.0.0/16'

@description('DNS Service IP. Default: 20.0.0.10')
param dnsServiceIP string = '20.0.0.10'

@description('Docker Bridge CIDR.  Default: 30.0.0.1/16')
param dockerBridgeCidr string = '30.0.0.1/16'

// Container Insights
@description('Log Analytics Workspace Resource Id.  Default: blank')
param containerInsightsLogAnalyticsResourceId string = ''

// Host Encryption
@description('Enable encryption at host (double encryption).  Default: true')
param enableEncryptionAtHost bool = true

// Azure Key Vault
@description('Azure Key Vault Resource Group Name.  Required when useCMK=true.')
param akvResourceGroupName string

@description('Azure Key Vault Name.  Required when useCMK=true.')
param akvName string

resource akv 'Microsoft.KeyVault/vaults@2021-04-01-preview' existing = {
  scope: resourceGroup(akvResourceGroupName)
  name: akvName
}

module akvKey '../../security/key-vault-key-rsa2048.bicep' = {
  name: 'add-cmk-${name}'
  scope: resourceGroup(akvResourceGroupName)
  params: {
      akvName: akvName
      keyName: 'cmk-aks-${name}'
  }
}

resource diskEncryptionSet 'Microsoft.Compute/diskEncryptionSets@2020-12-01' = {
  name: '${name}-disk-encryption-set'
  location: resourceGroup().location
  identity: {
      type: 'SystemAssigned'
  }

  properties: {
      rotationToLatestKeyVersionEnabled: true
      encryptionType: 'EncryptionAtRestWithPlatformAndCustomerKeys'
      activeKey: {
          keyUrl: akvKey.outputs.keyUriWithVersion
      }
  }
}

module diskEncryptionSetRoleAssignmentForCMK '../../iam/resource/key-vault-role-assignment-to-sp.bicep' = {
  name: 'rbac-${diskEncryptionSet.name}-key-vault'
  scope: resourceGroup(akvResourceGroupName)
  params: {
      keyVaultName: akv.name
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'e147488a-f6f5-4113-8e2d-b22465e65bf6') // Key Vault Crypto Service Encryption User
      resourceSPObjectIds: array(diskEncryptionSet.identity.principalId)
  }
}

resource akskubenet 'Microsoft.ContainerService/managedClusters@2021-07-01' = {
  dependsOn: [
    diskEncryptionSetRoleAssignmentForCMK
  ]

  name: name
  location: resourceGroup().location
  tags: tags
  properties: {
    nodeResourceGroup: nodeResourceGroupName
    kubernetesVersion: version
    dnsPrefix: dnsPrefix
    enableRBAC: true
    networkProfile: {
      networkPlugin: 'kubenet'
      podCidr: podCidr
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIP
      dockerBridgeCidr: dockerBridgeCidr
    }
    agentPoolProfiles: [
      {
        count: systemNodePoolMinNodeCount
        minCount: systemNodePoolMinNodeCount
        maxCount: systemNodePoolMaxNodeCount
        enableAutoScaling: systemNodePoolEnableAutoScaling
        vmSize: systemNodePoolNodeSize
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
        type: 'VirtualMachineScaleSets'
        osType: 'Linux'
        vnetSubnetID: subnetId
        name: 'systempool'
        mode: 'System'
        enableEncryptionAtHost: enableEncryptionAtHost
      }
      {
        count: userNodePoolMinNodeCount
        minCount: userNodePoolMinNodeCount
        maxCount: userNodePoolMaxNodeCount
        enableAutoScaling: userNodePoolEnableAutoScaling
        vmSize: userNodePoolNodeSize
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
        type: 'VirtualMachineScaleSets'
        osType: 'Linux'
        vnetSubnetID: subnetId
        name: 'agentpool'
        mode: 'User'
        enableEncryptionAtHost: enableEncryptionAtHost
      }
    ]
    apiServerAccessProfile: {
      enablePrivateCluster: true
      enablePrivateClusterPublicFQDN: false
      privateDNSZone: privateDNSZoneId
    }
    servicePrincipalProfile: {
      clientId: 'msi'
    }
    addonProfiles: {
      'omsagent': (!empty(containerInsightsLogAnalyticsResourceId)) ? {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: containerInsightsLogAnalyticsResourceId
        }
      } : {
          enabled: false
      }
    }
    diskEncryptionSetID: diskEncryptionSet.id
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
}
