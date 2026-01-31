# main.tf - Main Databricks workspace resources

# ============ Resource Group ============

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.region
  tags     = var.tags
}

# ============ Databricks Workspace ============

resource "azurerm_databricks_workspace" "this" {
  name                        = "dbw-${var.environment}"
  resource_group_name         = azurerm_resource_group.this.name
  location                    = azurerm_resource_group.this.location
  sku                         = "premium"
  managed_resource_group_name = "dbw-managed-${var.environment}"

  custom_parameters {
    no_public_ip                                         = true
    virtual_network_id                                   = var.vnet_id
    private_subnet_name                                  = var.private_subnet_name
    public_subnet_name                                   = var.public_subnet_name
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.public.id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.private.id
  }

  tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# ============ Private Endpoint (Optional) ============

resource "azurerm_private_endpoint" "databricks_ui_api" {
  count = var.enable_private_link ? 1 : 0

  name                = "pe-databricks-ui-api-${var.environment}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = data.azurerm_subnet.private_endpoint.id

  private_service_connection {
    name                           = "psc-databricks-ui-api"
    private_connection_resource_id = azurerm_databricks_workspace.this.id
    subresource_names              = ["databricks_ui_api"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "databricks-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.databricks.id]
  }

  tags = var.tags
}

resource "azurerm_private_dns_zone" "databricks" {
  name                = "privatelink.azuredatabricks.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "databricks" {
  name                  = "databricks-dns-link"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.databricks.name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
}

# ============ NSG for Subnets ============

resource "azurerm_network_security_group" "databricks" {
  name                = "nsg-databricks-${var.environment}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = data.azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.databricks.id
}

resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = data.azurerm_subnet.private.id
  network_security_group_id = azurerm_network_security_group.databricks.id
}

# ============ Data Sources ============

data "azurerm_subnet" "public" {
  name                 = var.public_subnet_name
  virtual_network_name = data.azurerm_virtual_network.this.name
  resource_group_name  = data.azurerm_virtual_network.this.resource_group_name
}

data "azurerm_subnet" "private" {
  name                 = var.private_subnet_name
  virtual_network_name = data.azurerm_virtual_network.this.name
  resource_group_name  = data.azurerm_virtual_network.this.resource_group_name
}

data "azurerm_subnet" "private_endpoint" {
  name                 = "snet-private-endpoints"
  virtual_network_name = data.azurerm_virtual_network.this.name
  resource_group_name  = data.azurerm_virtual_network.this.resource_group_name
}

data "azurerm_virtual_network" "this" {
  name                = split("/", var.vnet_id)[8]
  resource_group_name = split("/", var.vnet_id)[4]
}
