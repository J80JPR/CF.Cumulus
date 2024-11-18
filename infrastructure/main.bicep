//  Main infrastructure deployment template for data platform
//  Deploys core services including:
//  - Key Vault, Storage, Data Factory, Databricks, Function Apps, SQL Server
//  - Configures role assignments and dependencies between services

targetScope = 'subscription'

//Parameters for environment configuration
// * These parameters control resource naming and deployment options
// * Required for consistent resource naming across environments

param location string = 'uksouth' //Azure region for deployment
param envName string = 'dev' //Environment name (dev/test/prod)
param domainName string = 'cfc' //Domain prefix for naming convention - Cloud Formations Cumulus
param orgName string = 'tum' //Organization name for naming convention
param uniqueIdentifier string = '01' //Unique suffix for resource names

param datalakeName string = 'dls' //Storage account name prefix
param functionBlobName string = 'st' //Function app storage name prefix


param deploymentTimestamp string = utcNow('yy-MM-dd-HHmm')

//Parameters for optional settings
param firstDeployment bool = false
param deployWorkers bool = false
param deployVM bool = false
param deployADB bool = false

// Mapping of Azure regions to short codes for naming conventions
var locationShortCodes = {
  uksouth: 'uks'
  ukwest: 'ukw'
  eastus: 'eus'
  westus: 'wus'
  westus2: 'wus2'
  centralus: 'cus'
  northcentralus: 'ncus'
  southcentralus: 'scus'
  eastus2: 'eus2'
  westeurope: 'weu'
  northeurope: 'neu'
  francecentral: 'frc'
  germanywestcentral: 'gwc'
  switzerlandnorth: 'swn'
  norwayeast: 'noe'
  brazilsouth: 'brs'
  canadacentral: 'cac'
  canadaeast: 'cae'
}

var locationShortCode = locationShortCodes[location]

// Resource naming convention variables
var namePrefix = '${domainName}${orgName}${envName}'
var nameSuffix = '${locationShortCode}${uniqueIdentifier}'
var rgName = '${namePrefix}rg${nameSuffix}'

//var databaseName string = 'Metadata' //SQL Database name
var databaseName  = '${namePrefix}sqldb${nameSuffix}' //SQL Database name


// Create main resource group for all deployed resources
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
}

/* Service Deployment Sequence
 * Modules are deployed in order of dependencies:
 * 1. Key Vault - Required for secrets
 * 2. App Insights & Log Analytics - Monitoring
 * 3. Storage Accounts - Data lake and function storage
 * 4. Compute Services - ADF, Databricks, Functions
 * 5. Database - SQL Server
 */

 //Deployments without dependencies
module keyVaultDeploy './modules/keyvault.template.bicep' = {
  scope: rg
  name: 'keyvault${deploymentTimestamp}'
  params:{
    keyVaultExists: false
    namePrefix: namePrefix
    nameSuffix: nameSuffix
  }
}

module logAnalyticsDeploy './modules/loganalytics.template.bicep' = {
  scope: rg
  name: 'log-analytics${deploymentTimestamp}'
  params:{
    envName: envName
    namePrefix: namePrefix
    nameSuffix: nameSuffix
  }
}
module appInsightsDeploy './modules/applicationinsights.template.bicep' = {
  scope: rg
  name: 'app-insights${deploymentTimestamp}'
  params:{
    envName: envName
    namePrefix: namePrefix
    nameSuffix: nameSuffix
  }
}

//Deployments with dependencies
module functionBlobDeploy './modules/storage.template.bicep' = {
  name: 'functionStorage${deploymentTimestamp}'
  scope: rg
  params: {
    containers: {}
    envName: envName
    isHnsEnabled: false
    isSftpEnabled: false
    namePrefix: namePrefix
    nameStorage: functionBlobName
    nameSuffix: nameSuffix
  }
  dependsOn: [
    keyVaultDeploy
  ]
}

module functionAppDeploy './modules/functionapp.template.bicep' = {
  scope: rg
  name: 'functionApp${deploymentTimestamp}'
  params: {
    namePrefix: namePrefix
    nameSuffix: nameSuffix
    nameStorage: functionBlobName
  }
  dependsOn: [
    keyVaultDeploy
    appInsightsDeploy
    functionBlobDeploy
  ]
}


module storageAccountDeploy './modules/storage.template.bicep' = {
  name: 'storageaccount${deploymentTimestamp}'
  scope: rg
  params: {
    isHnsEnabled: true
    isSftpEnabled: false
    accessTier: 'Hot'
    namePrefix: namePrefix
    nameSuffix: nameSuffix
    nameStorage: datalakeName
    containers: {
      bronze: {
        name: 'raw'
      }
      silver: {
        name: 'cleansed'
      }
      gold: {
        name: 'curated'
      }
    }
    envName: envName
  }
  dependsOn: [
    keyVaultDeploy
  ]
}

module dataFactoryDeployOrchestrator './modules/datafactory.template.bicep' = {
  scope: rg
  name: 'datafactory-orchestrator${deploymentTimestamp}'
  params:{
    nameFactory: deployWorkers ? 'factory' : 'adf' // if workers adf is being setup we call this one factory, otherwise we call it adf
    namePrefix: namePrefix
    nameSuffix: nameSuffix
    envName: envName
    logAnalyticsWorkspaceId: logAnalyticsDeploy.outputs.resourceId
  }
  dependsOn: [
    keyVaultDeploy
    logAnalyticsDeploy
  ]
}

module dataFactoryDeployWorkers './modules/datafactory.template.bicep' = if (deployWorkers) {
  scope: rg
  name: 'datafactory-workers${deploymentTimestamp}'
  params:{
    nameFactory: 'workers'
    namePrefix: namePrefix
    nameSuffix: nameSuffix
    envName: envName
    logAnalyticsWorkspaceId: logAnalyticsDeploy.outputs.resourceId
  }
  dependsOn: [
    keyVaultDeploy
    logAnalyticsDeploy
  ]
}


// Deploy SQL Server with a basic blank database
module sqlServerDeploy './modules/sqlserver.template.bicep' = {
  scope: rg
  name: 'sql-server${deploymentTimestamp}'
  params: {
    databaseName: databaseName
    namePrefix: namePrefix
    nameSuffix: nameSuffix
  }
  dependsOn: [
    keyVaultDeploy
  ]
}

// Deploy all networking resources as a package
module networkingDeploy './modules/networking.template.bicep' = {
  scope: rg
  name: 'networking${deploymentTimestamp}'
  params: {
    location: location
    namePrefix: namePrefix
    nameSuffix: nameSuffix
  }
}

// Updated databricks deployment to use a VNET
module databricksWorkspaceDeploy './modules/databricks.template.bicep' = if (deployADB) {
  scope: rg
  name: 'databricks${deploymentTimestamp}'
  params: {
    namePrefix: namePrefix
    nameSuffix: nameSuffix
    skuTier: 'standard'
    managedResourceGroupName: '${namePrefix}rgm${nameSuffix}'
    // vnetName: networkingDeploy.outputs.vnetName
    // privateSubnetName: networkingDeploy.outputs.databricksPrivateSubnetName
    // publicSubnetName: networkingDeploy.outputs.databricksPublicSubnetName
  }
  dependsOn: [
    keyVaultDeploy
    networkingDeploy  // Add this dependency
  ]
}

module databricksClusterDeploy './modules/databrickscluster.template.bicep' = if (deployADB) {
  scope: rg
  name: 'databrickscluster${deploymentTimestamp}'
  params: {
    location: location
    adb_workspace_url: databricksWorkspaceDeploy.outputs.databricks_workspaceUrl
    adb_workspace_id: databricksWorkspaceDeploy.outputs.databricks_workspace_id
    adb_secret_scope_name: 'CumulusScope01'
    akv_id: keyVaultDeploy.outputs.keyVaultId
    akv_uri: keyVaultDeploy.outputs.keyVaultURI
    namePrefix: namePrefix
    nameSuffix: nameSuffix
    // LogAWkspId: logAnalyticsDeploy.outputs.resourceId
    // LogAWkspKey: logAnalyticsDeploy.outputs.primarySharedKey
  }
  dependsOn: [
    keyVaultDeploy
    databricksWorkspaceDeploy
  ]
}

module virtualMachineDeploy './modules/virtualmachine.template.bicep' = if (deployVM) {
  scope: rg
  name: 'vm${deploymentTimestamp}'
  params: {
    adminUsername: 'SHIRAdmin'
    envName: envName
    namePrefix: namePrefix
    nameSuffix: nameSuffix
  }
  dependsOn: [
    keyVaultDeploy
  ]
}

/* RBAC Configuration
 * Configures service-to-service permissions:
 * - Data Factory access to storage, functions, and other services
 * - Function App access to required resources
 * Note: firstDeployment parameter controls initial RBAC setup
 */
module dataFactoryOrchestratorRoleAssignmentsDeploy './modules/roleassignments/datafactory.template.bicep' = {
  scope: rg
  name: 'adf-orchestration-roleassignments${deploymentTimestamp}'
  params:{
    nameFactory: 'factory'
    namePrefix: namePrefix
    nameSuffix: nameSuffix
    nameStorage: datalakeName
  }
  dependsOn: [
    dataFactoryDeployOrchestrator
    functionAppDeploy
    storageAccountDeploy
    sqlServerDeploy
    databricksWorkspaceDeploy
    keyVaultDeploy
  ]
}

module dataFactoryWorkersRoleAssignmentsDeploy './modules/roleassignments/datafactory.template.bicep' = if (deployWorkers) {
  scope: rg
  name: 'adf-workers-roleassignments${deploymentTimestamp}'
  params: {
    nameFactory: 'workers'
    namePrefix: namePrefix
    nameSuffix: nameSuffix
    nameStorage: datalakeName
  }
  dependsOn: [
    dataFactoryDeployWorkers
    functionAppDeploy
    storageAccountDeploy
    sqlServerDeploy
    databricksWorkspaceDeploy
    keyVaultDeploy
  ]
}

module functionAppRoleAssignmentsDeploy './modules/roleassignments/functionapp.template.bicep' = {
  scope: rg
  name: 'functionapp-roleassignments${deploymentTimestamp}'
  params: {
    namePrefix: namePrefix
    nameSuffix: nameSuffix
    firstDeployment: firstDeployment
  }
  dependsOn: [
    dataFactoryDeployOrchestrator
    dataFactoryDeployWorkers
    functionAppDeploy
    storageAccountDeploy
    sqlServerDeploy
    databricksWorkspaceDeploy
    keyVaultDeploy
  ]
}
