# Security & Compliance Cheatsheet

Security controls, data protection, audit logging, and compliance patterns for Databricks.

---

## 🔐 Authentication & Identity

### Identity Provider Integration (SCIM)
```bash
# Azure AD SCIM provisioning
# Configure in Azure AD → Enterprise Applications → Databricks

# SCIM Token Generation (Account Console)
# Account → User provisioning → Generate token

# Okta SCIM Setup
# Assign Databricks app → Configure provisioning → SCIM token
```

### Service Principal Setup
```bash
# Azure - Create service principal
az ad sp create-for-rbac --name sp-databricks-cicd \
  --role contributor \
  --scopes /subscriptions/{sub}/resourceGroups/{rg}

# Add to Databricks workspace
databricks service-principals create \
  --application-id {client-id} \
  --display-name sp-cicd
```

### OAuth Configuration
```python
# Use OAuth for programmatic access (recommended over PAT)
from databricks.sdk import WorkspaceClient

# Environment variables:
# DATABRICKS_HOST
# DATABRICKS_CLIENT_ID  
# DATABRICKS_CLIENT_SECRET

w = WorkspaceClient()
```

---

## 🛡️ Network Security

### Private Link / Private Endpoints
```hcl
# Terraform: Azure Private Link
resource "azurerm_private_endpoint" "databricks" {
  name                = "pe-databricks"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private.id

  private_service_connection {
    name                           = "psc-databricks"
    private_connection_resource_id = azurerm_databricks_workspace.this.id
    subresource_names              = ["databricks_ui_api"]
    is_manual_connection           = false
  }
}
```

### IP Access Lists
```python
from databricks.sdk import AccountClient

client = AccountClient()

# Create IP access list
client.ip_access_lists.create(
    label="corporate-vpn",
    list_type="ALLOW",
    ip_addresses=["10.0.0.0/8", "192.168.1.0/24"]
)

# Enable IP access lists
client.settings.patch_setting(
    setting_name="enableIpAccessLists",
    setting_value="true"
)
```

### VNet/VPC Peering
```hcl
# VNet injection for Azure Databricks
resource "azurerm_databricks_workspace" "this" {
  # ...
  custom_parameters {
    no_public_ip        = true
    virtual_network_id  = azurerm_virtual_network.this.id
    private_subnet_name = azurerm_subnet.private.name
    public_subnet_name  = azurerm_subnet.public.name
  }
}
```

---

## 🔒 Data Protection

### Encryption at Rest
```sql
-- Customer-managed keys (CMK) configuration
-- Set at workspace level via Terraform or console

-- Verify encryption
DESCRIBE EXTENDED catalog.schema.sensitive_table;
-- Check: delta.columnMapping.mode, encryption settings
```

### Encryption in Transit
```python
# All connections use TLS 1.2+ by default
# JDBC/ODBC connections automatically encrypted

# JDBC with SSL
jdbc_url = "jdbc:databricks://{host}:443/{catalog}?transportMode=http;ssl=1"
```

### Column-Level Encryption
```sql
-- Encrypt sensitive columns with UDF
CREATE FUNCTION encrypt_pii(value STRING)
RETURNS STRING
LANGUAGE PYTHON
AS $$
from cryptography.fernet import Fernet
key = dbutils.secrets.get("encryption", "key")
f = Fernet(key)
return f.encrypt(value.encode()).decode()
$$;

-- Apply during insert
INSERT INTO secure_data
SELECT id, encrypt_pii(ssn) as ssn_encrypted
FROM raw_data;
```

### Dynamic Data Masking
```sql
-- Create masking function
CREATE FUNCTION mask_credit_card(card STRING)
RETURNS STRING
RETURN CASE
    WHEN is_account_group_member('pci_admins') THEN card
    ELSE CONCAT('****-****-****-', RIGHT(card, 4))
END;

-- Apply column mask
ALTER TABLE catalog.schema.transactions
ALTER COLUMN credit_card SET MASK mask_credit_card;
```

---

## 📋 Audit Logging

### Query Audit Logs
```sql
-- All data access events
SELECT
    event_time,
    user_identity.email as user,
    source_ip_address,
    action_name,
    request_params.full_name_arg as resource,
    response.status_code,
    response.error_message
FROM system.access.audit
WHERE event_date >= current_date() - INTERVAL 7 DAYS
ORDER BY event_time DESC;

-- Failed authentication attempts
SELECT
    event_time,
    user_identity.email,
    source_ip_address,
    action_name,
    response.error_message
FROM system.access.audit
WHERE response.status_code >= 400
    AND action_name LIKE '%auth%'
    AND event_date >= current_date() - INTERVAL 1 DAY;

-- Data modification events
SELECT
    event_time,
    user_identity.email,
    action_name,
    request_params.full_name_arg as table_name
FROM system.access.audit
WHERE action_name IN ('createTable', 'deleteTable', 'alterTable', 
                      'insertIntoTable', 'updateTable', 'deleteFromTable')
    AND event_date >= current_date() - INTERVAL 7 DAYS;
```

### Export Audit Logs
```python
# Configure audit log delivery to cloud storage
# Account Console → Audit Logs → Configure delivery

# AWS: S3 bucket
# Azure: Azure Event Hubs or Storage Account
# GCP: Cloud Storage
```

---

## 🏛️ Compliance Frameworks

### GDPR Compliance
```sql
-- Data subject access request
SELECT * FROM catalog.schema.customers
WHERE email = 'user@example.com';

-- Right to erasure
DELETE FROM catalog.schema.customers
WHERE user_id = 'xxx';

-- Time travel for audit trail
SELECT * FROM catalog.schema.customers VERSION AS OF 10
WHERE user_id = 'xxx';

-- Data lineage for impact assessment
SELECT * FROM system.access.table_lineage
WHERE target_table_full_name LIKE '%customers%';
```

### HIPAA Controls
```sql
-- PHI access monitoring
SELECT
    event_time,
    user_identity.email,
    action_name,
    request_params.full_name_arg
FROM system.access.audit
WHERE request_params.full_name_arg LIKE '%phi_%'
    OR request_params.full_name_arg LIKE '%patient%'
ORDER BY event_time DESC;

-- Row-level security for PHI
CREATE FUNCTION phi_access_filter(provider_id STRING)
RETURNS BOOLEAN
RETURN (
    is_account_group_member('phi_admins') OR
    current_user() = (SELECT email FROM providers WHERE id = provider_id)
);

ALTER TABLE catalog.schema.patient_records
SET ROW FILTER phi_access_filter ON (provider_id);
```

### SOC 2 Monitoring
```sql
-- Privileged access monitoring
SELECT
    event_time,
    user_identity.email,
    action_name
FROM system.access.audit
WHERE action_name IN ('createGrant', 'revokeGrant', 
                      'createServicePrincipal', 'deleteUser')
    AND event_date >= current_date() - INTERVAL 30 DAYS;

-- Change management audit
SELECT *
FROM system.access.audit
WHERE service_name = 'jobs'
    AND action_name IN ('create', 'update', 'delete')
    AND event_date >= current_date() - INTERVAL 30 DAYS;
```

---

## 🔑 Secrets Management

### Databricks Secret Scopes
```bash
# Create secret scope
databricks secrets create-scope --scope prod-secrets

# Azure Key Vault backed scope
databricks secrets create-scope --scope kv-secrets \
  --scope-backend-type AZURE_KEYVAULT \
  --resource-id /subscriptions/.../resourceGroups/.../providers/Microsoft.KeyVault/vaults/my-vault \
  --dns-name https://my-vault.vault.azure.net/

# Add secret
databricks secrets put --scope prod-secrets --key db-password \
  --string-value "secure-password"

# List secrets
databricks secrets list --scope prod-secrets
```

### Using Secrets in Code
```python
# Access secrets in notebooks/jobs
password = dbutils.secrets.get("prod-secrets", "db-password")

# Secrets are redacted in logs
print(password)  # Shows [REDACTED]

# Use in Spark config
spark.conf.set("spark.jdbc.password", 
               dbutils.secrets.get("prod-secrets", "db-password"))
```

---

## 🛑 Access Control Best Practices

### Principle of Least Privilege
```sql
-- Grant minimal required permissions
GRANT USE CATALOG ON CATALOG prod_catalog TO analysts;
GRANT USE SCHEMA ON SCHEMA prod_catalog.gold TO analysts;
GRANT SELECT ON TABLE prod_catalog.gold.report_data TO analysts;

-- Don't do this:
-- GRANT ALL PRIVILEGES ON CATALOG prod_catalog TO analysts;
```

### Role-Based Access Pattern
```sql
-- Create functional groups
CREATE GROUP data_readers;
CREATE GROUP data_writers;
CREATE GROUP data_admins;

-- Assign permissions to groups
GRANT SELECT ON SCHEMA prod_catalog.gold TO data_readers;
GRANT SELECT, MODIFY ON SCHEMA prod_catalog.silver TO data_writers;
GRANT ALL PRIVILEGES ON CATALOG prod_catalog TO data_admins;

-- Add users to groups (via SCIM or manually)
ALTER GROUP data_readers ADD USER 'analyst@company.com';
```

---

## 📋 Security Checklist

| Category | Control | Status |
|----------|---------|--------|
| **Identity** | SCIM provisioning enabled | ☐ |
| **Identity** | Service principals for automation | ☐ |
| **Identity** | PAT disabled for interactive users | ☐ |
| **Network** | Private Link/VNet injection | ☐ |
| **Network** | IP access lists configured | ☐ |
| **Network** | No public IPs on clusters | ☐ |
| **Data** | Customer-managed keys (CMK) | ☐ |
| **Data** | Column masking for PII | ☐ |
| **Data** | Row-level security for sensitive tables | ☐ |
| **Audit** | Audit log delivery configured | ☐ |
| **Audit** | Regular access reviews | ☐ |
| **Secrets** | Key Vault integration | ☐ |
| **Access** | Least privilege enforcement | ☐ |
| **Access** | Group-based permissions | ☐ |

---

*Last updated: 2026-01-31*
