// ----------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
//
// THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, 
// EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES 
// OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
// ----------------------------------------------------------------------------------

targetScope = 'managementGroup'

@description('Management Group scope for the policy definition.')
param policyDefinitionManagementGroupId string

@description('Management Group scope for the policy assignment.')
param policyAssignmentManagementGroupId string

@description('Azure DDOS Standard Plan Resource Id.')
param ddosStandardPlanId string

var policyId = 'Network-Deploy-DDoS-Standard'
var assignmentName = 'Custom - Enable DDoS Standard on Virtual Networks'

var scope = tenantResourceId('Microsoft.Management/managementGroups', policyAssignmentManagementGroupId)
var policyScopedId = '/providers/Microsoft.Management/managementGroups/${policyDefinitionManagementGroupId}/providers/Microsoft.Authorization/policyDefinitions/${policyId}'

resource policySetAssignment 'Microsoft.Authorization/policyAssignments@2020-03-01' = {
  name: 'ddos-${uniqueString(policyAssignmentManagementGroupId)}'
  properties: {
    displayName: assignmentName
    policyDefinitionId: policyScopedId
    scope: scope
    notScopes: []
    parameters: {
      planId: {
        value: ddosStandardPlanId
      }
    }
    enforcementMode: 'Default'
  }
  identity: {
    type: 'SystemAssigned'
  }
  location: deployment().location
}

// These role assignments are required to allow Policy Assignment to remediate.
resource policySetRoleAssignmentNetworkContributor 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(policyAssignmentManagementGroupId, 'ddos-standard', 'Network Contributor')
  scope: managementGroup()
  properties: {
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7'
    principalId: policySetAssignment.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
