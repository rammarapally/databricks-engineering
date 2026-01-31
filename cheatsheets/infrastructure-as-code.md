# Infrastructure as Code Cheatsheet

Terraform modules, Databricks Asset Bundles (DABs), and automation patterns.

---

## 🏗️ Terraform Basics

### Provider Configuration
```hcl
# versions.tf
terraform {
  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.40"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstate"
    container_name       = "databricks"
    key                  = "prod.tfstate"
  }
}

# providers.tf
provider "databricks" {
  alias = "account"
  host  = "https://accounts.azuredatabricks.net"
}

provider "databricks" {
  alias = "workspace"
  host  = azurerm_databricks_workspace.this.workspace_url
}
```

---

## 📦 Workspace Provisioning

### Azure Databricks Workspace
```hcl
# workspace.tf
resource "azurerm_databricks_workspace" "this" {
  name                        = "dbw-${var.environment}"
  resource_group_name         = azurerm_resource_group.this.name
  location                    = var.location
  sku                         = "premium"
  managed_resource_group_name = "dbw-managed-${var.environment}"

  custom_parameters {
    no_public_ip                                      = true
    virtual_network_id                                = azurerm_virtual_network.this.id
    private_subnet_name                               = azurerm_subnet.private.name
    public_subnet_name                                = azurerm_subnet.public.name
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.private.id
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.public.id
  }

  tags = var.tags
}
```

### AWS Databricks Workspace
```hcl
# workspace.tf
resource "databricks_mws_workspaces" "this" {
  provider       = databricks.account
  account_id     = var.databricks_account_id
  workspace_name = "dbw-${var.environment}"
  
  aws_region   = var.region
  
  credentials_id           = databricks_mws_credentials.this.credentials_id
  storage_configuration_id = databricks_mws_storage_configurations.this.storage_configuration_id
  network_id               = databricks_mws_networks.this.network_id
  
  token {
    comment = "Terraform provisioning token"
  }
}
```

---

## 🔐 Unity Catalog Setup

```hcl
# unity_catalog.tf
resource "databricks_metastore" "this" {
  provider      = databricks.account
  name          = "metastore-${var.region}"
  storage_root  = "s3://${aws_s3_bucket.metastore.id}/metastore"
  region        = var.region
  owner         = "account users"
  
  delta_sharing_scope                                = "INTERNAL_AND_EXTERNAL"
  delta_sharing_recipient_token_lifetime_in_seconds = 604800  # 7 days
}

resource "databricks_metastore_assignment" "this" {
  provider             = databricks.account
  workspace_id         = databricks_mws_workspaces.this.workspace_id
  metastore_id         = databricks_metastore.this.id
  default_catalog_name = "main"
}

# Catalogs
resource "databricks_catalog" "prod" {
  provider    = databricks.workspace
  name        = "prod"
  comment     = "Production catalog"
  depends_on  = [databricks_metastore_assignment.this]
}

resource "databricks_catalog" "dev" {
  provider    = databricks.workspace
  name        = "dev"
  comment     = "Development catalog"
  depends_on  = [databricks_metastore_assignment.this]
}

# Schemas
resource "databricks_schema" "bronze" {
  provider     = databricks.workspace
  catalog_name = databricks_catalog.prod.name
  name         = "bronze"
  comment      = "Raw ingestion layer"
}

resource "databricks_schema" "silver" {
  provider     = databricks.workspace
  catalog_name = databricks_catalog.prod.name
  name         = "silver"
  comment      = "Cleansed data layer"
}

resource "databricks_schema" "gold" {
  provider     = databricks.workspace
  catalog_name = databricks_catalog.prod.name
  name         = "gold"
  comment      = "Business-ready data"
}
```

---

## 🔧 Cluster Configuration

### Cluster Policies
```hcl
# cluster_policies.tf
resource "databricks_cluster_policy" "production" {
  name = "Production Policy"
  definition = jsonencode({
    "spark_version" : {
      "type" : "regex",
      "pattern" : "14\\.[0-9]+\\.x-scala.*"
    },
    "node_type_id" : {
      "type" : "allowlist",
      "values" : ["Standard_DS3_v2", "Standard_DS4_v2", "Standard_DS5_v2"]
    },
    "driver_node_type_id" : {
      "type" : "fixed",
      "value" : "Standard_DS3_v2"
    },
    "autotermination_minutes" : {
      "type" : "range",
      "minValue" : 10,
      "maxValue" : 60,
      "defaultValue" : 30
    },
    "custom_tags.Environment" : {
      "type" : "fixed",
      "value" : "Production"
    },
    "custom_tags.CostCenter" : {
      "type" : "fixed",
      "value" : var.cost_center
    }
  })
}

resource "databricks_permissions" "production_policy" {
  cluster_policy_id = databricks_cluster_policy.production.id
  
  access_control {
    group_name       = "data-engineers"
    permission_level = "CAN_USE"
  }
}
```

### Instance Pools
```hcl
# instance_pools.tf
resource "databricks_instance_pool" "general" {
  instance_pool_name = "general-pool"
  
  min_idle_instances          = 2
  max_capacity                = 50
  node_type_id                = "Standard_DS3_v2"
  idle_instance_autotermination_minutes = 10
  
  preloaded_spark_versions = ["14.3.x-scala2.12"]
  
  azure_attributes {
    availability       = "SPOT_WITH_FALLBACK_AZURE"
    spot_bid_max_price = -1  # Use on-demand price as cap
  }

  custom_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
```

---

## 👥 Access Management

```hcl
# groups.tf
resource "databricks_group" "data_engineers" {
  display_name = "data-engineers"
}

resource "databricks_group" "data_scientists" {
  display_name = "data-scientists"
}

# Service principals
resource "databricks_service_principal" "etl" {
  display_name = "sp-etl-pipeline"
}

# Grants
resource "databricks_grants" "prod_catalog" {
  catalog = databricks_catalog.prod.name
  
  grant {
    principal  = databricks_group.data_engineers.display_name
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY"]
  }
  
  grant {
    principal  = databricks_group.data_scientists.display_name
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
  }
  
  grant {
    principal  = databricks_service_principal.etl.application_id
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY"]
  }
}
```

---

## 📦 Databricks Asset Bundles (DABs)

### Bundle Configuration
```yaml
# databricks.yml
bundle:
  name: data-pipeline-bundle

include:
  - resources/*.yml

variables:
  catalog:
    description: Target catalog
    default: dev
  
  warehouse_id:
    description: SQL Warehouse ID

artifacts:
  default:
    type: whl
    path: ./dist

targets:
  dev:
    mode: development
    default: true
    workspace:
      host: https://adb-dev.azuredatabricks.net
    variables:
      catalog: dev

  staging:
    mode: development
    workspace:
      host: https://adb-stage.azuredatabricks.net
    variables:
      catalog: stage

  prod:
    mode: production
    workspace:
      host: https://adb-prod.azuredatabricks.net
      root_path: /Shared/.bundle/prod/${bundle.name}
    run_as:
      service_principal_name: sp-prod-pipelines
    variables:
      catalog: prod
```

### Resources Configuration
```yaml
# resources/jobs.yml
resources:
  jobs:
    daily_etl_pipeline:
      name: "daily-etl-${bundle.target}"
      
      schedule:
        quartz_cron_expression: "0 0 6 * * ?"
        timezone_id: "America/New_York"
      
      email_notifications:
        on_failure:
          - data-alerts@company.com
      
      tasks:
        - task_key: bronze_ingestion
          notebook_task:
            notebook_path: ./src/notebooks/bronze_ingestion.py
            base_parameters:
              catalog: ${var.catalog}
          new_cluster:
            spark_version: "14.3.x-scala2.12"
            node_type_id: "Standard_DS3_v2"
            num_workers: 2
            spark_conf:
              "spark.databricks.delta.preview.enabled": "true"
        
        - task_key: silver_transformation
          depends_on:
            - task_key: bronze_ingestion
          notebook_task:
            notebook_path: ./src/notebooks/silver_transform.py
          job_cluster_key: shared_cluster
        
        - task_key: gold_aggregation
          depends_on:
            - task_key: silver_transformation
          notebook_task:
            notebook_path: ./src/notebooks/gold_aggregate.py
          job_cluster_key: shared_cluster
      
      job_clusters:
        - job_cluster_key: shared_cluster
          new_cluster:
            spark_version: "14.3.x-scala2.12"
            node_type_id: "Standard_DS4_v2"
            autoscale:
              min_workers: 2
              max_workers: 8
```

### DLT Pipeline Bundle
```yaml
# resources/pipelines.yml
resources:
  pipelines:
    streaming_pipeline:
      name: "streaming-dlt-${bundle.target}"
      
      target: "${var.catalog}.silver"
      
      development: ${bundle.target == "dev"}
      continuous: ${bundle.target == "prod"}
      
      channel: CURRENT
      photon: true
      
      libraries:
        - notebook:
            path: ./src/dlt/bronze_streaming.py
        - notebook:
            path: ./src/dlt/silver_validation.py
      
      clusters:
        - label: default
          autoscale:
            min_workers: 1
            max_workers: 5
            mode: ENHANCED
```

### DAB Commands
```bash
# Validate bundle configuration
databricks bundle validate

# Deploy to development
databricks bundle deploy -t dev

# Deploy to production
databricks bundle deploy -t prod

# Run a job
databricks bundle run daily_etl_pipeline -t dev

# Destroy deployment
databricks bundle destroy -t dev
```

---

## 🔄 CI/CD Integration

### GitHub Actions
```yaml
# .github/workflows/deploy.yml
name: Deploy Databricks Bundle

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  DATABRICKS_HOST: ${{ secrets.DATABRICKS_HOST }}

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Databricks CLI
        uses: databricks/setup-cli@main
      
      - name: Authenticate
        run: |
          databricks configure --token <<EOF
          ${{ secrets.DATABRICKS_HOST }}
          ${{ secrets.DATABRICKS_TOKEN }}
          EOF
      
      - name: Validate Bundle
        run: databricks bundle validate -t prod

  deploy-staging:
    needs: validate
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v4
      - uses: databricks/setup-cli@main
      
      - name: Deploy to Staging
        run: databricks bundle deploy -t staging

  deploy-prod:
    needs: validate
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      - uses: databricks/setup-cli@main
      
      - name: Deploy to Production
        run: databricks bundle deploy -t prod
```

---

## 📋 Module Structure

```
terraform/
├── modules/
│   ├── workspace/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   ├── unity-catalog/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── cluster-policies/
│   │   └── ...
│   └── access-management/
│       └── ...
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf
│   ├── staging/
│   │   └── ...
│   └── prod/
│       └── ...
└── shared/
    └── global.tfvars
```

---

*Last updated: 2026-01-31*
