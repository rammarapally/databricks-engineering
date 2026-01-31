# versions.tf - Provider requirements

terraform {
  required_version = ">= 1.5"

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.40"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }

  backend "azurerm" {
    # Configure in terraform.tfvars or CI/CD
    # resource_group_name  = "rg-terraform-state"
    # storage_account_name = "tfstate"
    # container_name       = "databricks"
    # key                  = "prod.tfstate"
  }
}

provider "azurerm" {
  features {}
}

provider "databricks" {
  alias = "workspace"
  host  = azurerm_databricks_workspace.this.workspace_url
}

provider "databricks" {
  alias = "account"
  host  = "https://accounts.azuredatabricks.net"
}
