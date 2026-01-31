# variables.tf - Input variables for workspace module

# ============ General ============

variable "environment" {
  description = "Environment name (dev, stage, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "Environment must be dev, stage, or prod."
  }
}

variable "region" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ============ Network ============

variable "vnet_id" {
  description = "VNet ID for workspace injection"
  type        = string
}

variable "private_subnet_name" {
  description = "Private subnet name for worker nodes"
  type        = string
}

variable "public_subnet_name" {
  description = "Public subnet name for NAT gateway"
  type        = string
}

variable "enable_private_link" {
  description = "Enable Private Link for workspace"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "IP ranges allowed to access workspace (if not using Private Link)"
  type        = list(string)
  default     = []
}

# ============ Unity Catalog ============

variable "enable_unity_catalog" {
  description = "Enable Unity Catalog integration"
  type        = bool
  default     = true
}

variable "metastore_id" {
  description = "Unity Catalog metastore ID"
  type        = string
  default     = null
}

variable "create_catalogs" {
  description = "List of catalogs to create"
  type = list(object({
    name    = string
    comment = string
  }))
  default = [
    { name = "dev", comment = "Development catalog" },
    { name = "prod", comment = "Production catalog" }
  ]
}

# ============ Cluster Policies ============

variable "enable_cluster_policies" {
  description = "Enable cluster policies"
  type        = bool
  default     = true
}

variable "max_dbus_per_hour" {
  description = "Maximum DBUs per hour per cluster"
  type        = number
  default     = 100
}

variable "allowed_node_types" {
  description = "Allowed VM sizes for clusters"
  type        = list(string)
  default     = ["Standard_DS3_v2", "Standard_DS4_v2", "Standard_DS5_v2"]
}

variable "auto_termination_minutes" {
  description = "Auto-termination minutes range"
  type = object({
    min     = number
    max     = number
    default = number
  })
  default = {
    min     = 10
    max     = 60
    default = 30
  }
}

# ============ Access Control ============

variable "admin_group_name" {
  description = "Admin group name"
  type        = string
  default     = "databricks-admins"
}

variable "user_groups" {
  description = "User groups to create"
  type = list(object({
    name        = string
    permissions = list(string)
  }))
  default = [
    { name = "data-engineers", permissions = ["CAN_MANAGE"] },
    { name = "data-scientists", permissions = ["CAN_RESTART"] },
    { name = "analysts", permissions = ["CAN_ATTACH_TO"] }
  ]
}
