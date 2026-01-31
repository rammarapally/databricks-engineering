# outputs.tf - Module outputs

output "workspace_id" {
  description = "Databricks workspace ID"
  value       = azurerm_databricks_workspace.this.workspace_id
}

output "workspace_url" {
  description = "Databricks workspace URL"
  value       = "https://${azurerm_databricks_workspace.this.workspace_url}"
}

output "workspace_resource_id" {
  description = "Azure resource ID of the workspace"
  value       = azurerm_databricks_workspace.this.id
}

output "managed_resource_group_name" {
  description = "Managed resource group name"
  value       = azurerm_databricks_workspace.this.managed_resource_group_name
}

output "private_endpoint_ip" {
  description = "Private endpoint IP address"
  value       = var.enable_private_link ? azurerm_private_endpoint.databricks_ui_api[0].private_service_connection[0].private_ip_address : null
}

output "catalogs_created" {
  description = "List of catalogs created"
  value       = var.enable_unity_catalog ? [for c in databricks_catalog.this : c.name] : []
}

output "cluster_policy_ids" {
  description = "Cluster policy IDs"
  value = var.enable_cluster_policies ? {
    production  = databricks_cluster_policy.production[0].id
    development = databricks_cluster_policy.development[0].id
  } : {}
}
