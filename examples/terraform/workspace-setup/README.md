# Terraform: Databricks Workspace Setup

Production-ready Terraform module for Databricks workspace provisioning.

## Usage

```hcl
module "databricks_workspace" {
  source = "./workspace-setup"

  environment         = "prod"
  region              = "eastus"
  resource_group_name = "rg-databricks-prod"
  
  # Network configuration
  vnet_id              = module.network.vnet_id
  private_subnet_name  = "snet-databricks-private"
  public_subnet_name   = "snet-databricks-public"
  
  # Unity Catalog
  enable_unity_catalog = true
  metastore_id         = var.metastore_id
  
  # Cost controls
  enable_cluster_policies = true
  max_dbus_per_hour       = 100
  
  tags = local.common_tags
}
```

## Files

```
workspace-setup/
├── main.tf           # Main resources
├── variables.tf      # Input variables
├── outputs.tf        # Output values
├── versions.tf       # Provider requirements
├── unity_catalog.tf  # UC configuration
├── cluster_policies.tf
└── access.tf         # IAM/permissions
```
