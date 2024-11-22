param location string = resourceGroup().location

@secure()
param adb_secret_scope_name string
param adb_cluster_name string = 'cluster-01'
param adb_workspace_id string
param adb_workspace_url string
param adb_workspace_managed_identity_id string

param adb_spark_version string = '15.4.x-scala2.12'
param adb_node_type string = 'Standard_DS3_v2'
param adb_min_worker string = '1'
param adb_num_worker string = '2'
param adb_max_worker string = '3'
param adb_auto_terminate_min string = '30'

param force_update string = utcNow()

resource createAdbCluster 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'createAdbCluster'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${adb_workspace_managed_identity_id}': {}
    }
  }
  properties: {
    azCliVersion: '2.26.0'
    timeout: 'PT5M'
    retentionInterval: 'PT1H'
    cleanupPreference: 'OnExpiration'
    forceUpdateTag: force_update
    environmentVariables: [
      { name: 'ADB_WORKSPACE_URL', value: adb_workspace_url }
      { name: 'ADB_WORKSPACE_ID', value: adb_workspace_id }
      { name: 'ADB_SECRET_SCOPE_NAME', value: adb_secret_scope_name }
      { name: 'DATABRICKS_CLUSTER_NAME', value: adb_cluster_name }
      { name: 'DATABRICKS_SPARK_VERSION', value: adb_spark_version }
      { name: 'DATABRICKS_NODE_TYPE', value: adb_node_type }
      { name: 'DATABRICKS_NUM_WORKERS', value: adb_num_worker }
      { name: 'DATABRICKS_AUTO_TERMINATE_MINUTES', value: adb_auto_terminate_min }
      { name: 'DATABRICKS_MIN_WORKERS', value: adb_min_worker }
      { name: 'DATABRICKS_MAX_WORKERS', value: adb_max_worker }
    ]
    scriptContent: loadTextContent('../deployment/create_cluster.sh')
  }
}
