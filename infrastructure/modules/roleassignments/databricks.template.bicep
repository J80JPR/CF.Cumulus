// Input parameters
param adb_workspace_managed_identity_id object 
param adb_workspace_name string
param dataFactoryName string

// Other
var ownerRoleDefId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' // "Owner"
var StorageBlobDataContributorId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor

// Role Assignments
resource ownerRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-08-01-preview' = {
  name: guid(ownerRoleDefId, resourceGroup().id)
  scope: resourceGroup()
  properties: {
    principalType: 'ServicePrincipal'
    principalId: adb_workspace_managed_identity_id.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', ownerRoleDefId)
  }
}

resource storageBlobDataContributor 'Microsoft.Authorization/roleAssignments@2020-08-01-preview' = {
  name: guid('storage-blob-data-contributor', resourceGroup().id)
  scope: resourceGroup()
  properties: {
    principalType: 'ServicePrincipal'
    principalId: adb_workspace_managed_identity_id.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', StorageBlobDataContributorId)
  }
}

// Reference to existing Databricks workspace
resource databricks 'Microsoft.Databricks/workspaces@2024-05-01' existing = {
  name: adb_workspace_name
}

// ADF-Databricks Integration
resource adfDatabricksContributor 'Microsoft.Authorization/roleAssignments@2020-08-01-preview' = {
  name: guid('adf-databricks-contributor', resourceGroup().id)
  scope: databricks
  properties: {
    principalType: 'ServicePrincipal'
    principalId: reference(resourceId('Microsoft.DataFactory/factories', dataFactoryName), '2018-06-01', 'Full').identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  }
}

// // Storage Account Network Rules
// resource storageNetworkRules 'Microsoft.Storage/storageAccounts/networkRules@2023-01-01' = {
//   name: storageAccountName
//   properties: {
//     //defaultAction: 'Deny'
//     virtualNetworkRules: [
//       {
//         id: '${vnet.id}/subnets/${names.subnets.workerNodes}'
//         action: 'Allow'
//       }
//       {
//         id: '${vnet.id}/subnets/${names.subnets.controlPlane}'
//         action: 'Allow'
//       }
//       {
//         id: '${vnet.id}/subnets/${names.subnets.serviceEndpoint}'
//         action: 'Allow'
//       }
//     ]
//   }
// }
