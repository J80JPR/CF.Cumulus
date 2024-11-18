param location string = resourceGroup().location
param managedResourceGroupName string

@allowed([
  'standard'
  'premium'
])
@description('The pricing tier of workspace')
param skuTier string

param namePrefix string 
param nameSuffix string 

// Add VNET parameters
param vnetName string
param privateSubnetName string
param publicSubnetName string

var workspaceName = '${namePrefix}dbw${nameSuffix}'
var ownerRoleDefId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
var managedIdentityName = '${workspaceName}Identity' 

// Reference existing VNET
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: vnetName
}

// Reference existing subnets
resource privateSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' existing = {
  parent: vnet
  name: privateSubnetName
}

resource publicSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' existing = {
  parent: vnet
  name: publicSubnetName
}


resource databricksWorkspace 'Microsoft.Databricks/workspaces@2024-05-01' = {
  name: workspaceName
  location: location
  sku: { name: skuTier }
  properties:{
    managedResourceGroupId: subscriptionResourceId('Microsoft.Resources/resourceGroups', managedResourceGroupName)
    parameters: {
      customVirtualNetworkId: {
        value: vnet.id
      }
      customPublicSubnetName: {
        value: publicSubnetName
      }
      customPrivateSubnetName: {
        value: privateSubnetName
      }
      enableNoPublicIp: {
        value: true
      }
  }
}

resource mIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: managedIdentityName
  location: location
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-08-01-preview' = {
  name:  guid(ownerRoleDefId,resourceGroup().id)
  scope: resourceGroup()
  properties: {
    principalType: 'ServicePrincipal'
    principalId: mIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', ownerRoleDefId)
  }
}

output databricks_workspace_id string = databricksWorkspace.id
output databricks_workspaceUrl string = databricksWorkspace.properties.workspaceUrl
// output databricks_sku_tier string = adbWorkspaceSkuTier
output databricks_dbfs_storage_accountName string = databricksWorkspace.properties.parameters.storageAccountName.value

