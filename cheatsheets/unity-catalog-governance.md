# Unity Catalog Governance Cheatsheet

Comprehensive guide to Unity Catalog data governance, access control, and best practices.

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Account Level                               │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    Unity Catalog Metastore                    │  │
│  │  (One per region - stores metadata for all data assets)      │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                               │                                     │
│      ┌────────────────────────┼────────────────────────┐           │
│      ▼                        ▼                        ▼           │
│  Workspace A             Workspace B             Workspace C        │
│  (Dev)                   (Stage)                 (Prod)            │
└─────────────────────────────────────────────────────────────────────┘

Hierarchy:
Metastore → Catalog → Schema → Table/View/Volume/Function/Model
```

---

## 🔐 Identity Management

### Users & Groups
```sql
-- Users are managed at account level via SCIM
-- Create group (if not using SCIM)
CREATE GROUP data_engineers;

-- Add user to group
ALTER GROUP data_engineers ADD USER 'user@company.com';

-- List group members
SHOW GROUPS LIKE 'data%';

-- Remove user from group
ALTER GROUP data_engineers DROP USER 'user@company.com';
```

### Service Principals
```sql
-- Grant service principal access
GRANT USE CATALOG ON CATALOG prod_catalog TO `sp-etl-pipeline`;
GRANT USE SCHEMA ON SCHEMA prod_catalog.bronze TO `sp-etl-pipeline`;
GRANT SELECT ON TABLE prod_catalog.bronze.raw_events TO `sp-etl-pipeline`;

-- For job accounts, use service principals
-- Configure in job settings: Run as → Service Principal
```

---

## 📦 Catalog Management

### Creating Catalogs
```sql
-- Create managed catalog
CREATE CATALOG IF NOT EXISTS prod_catalog
COMMENT 'Production data catalog';

-- Create catalog with custom storage
CREATE CATALOG stage_catalog
MANAGED LOCATION 's3://my-bucket/stage-catalog/';

-- Create catalog with owner
CREATE CATALOG dev_catalog;
ALTER CATALOG dev_catalog SET OWNER TO `data-platform-admins`;
```

### Catalog Organization Best Practices
```sql
-- Environment-based catalogs
CREATE CATALOG dev_catalog;     -- Development sandbox
CREATE CATALOG stage_catalog;   -- Pre-production testing
CREATE CATALOG prod_catalog;    -- Production data

-- Domain-based catalogs (alternative)
CREATE CATALOG sales_catalog;
CREATE CATALOG marketing_catalog;
CREATE CATALOG finance_catalog;
```

---

## 📂 Schema Management

```sql
-- Create schema
CREATE SCHEMA IF NOT EXISTS prod_catalog.bronze
COMMENT 'Raw ingestion layer';

CREATE SCHEMA IF NOT EXISTS prod_catalog.silver
COMMENT 'Cleansed and validated data'
MANAGED LOCATION 's3://my-bucket/prod/silver/';

CREATE SCHEMA prod_catalog.gold
COMMENT 'Business-ready aggregations';

-- Set schema owner
ALTER SCHEMA prod_catalog.bronze SET OWNER TO `data-engineers`;

-- Drop schema (with cascade)
DROP SCHEMA IF EXISTS dev_catalog.temp_schema CASCADE;
```

---

## 🔒 Access Control (Grants)

### Basic Permissions
```sql
-- Catalog level
GRANT USE CATALOG ON CATALOG prod_catalog TO `analysts`;
GRANT CREATE SCHEMA ON CATALOG prod_catalog TO `data-engineers`;

-- Schema level
GRANT USE SCHEMA ON SCHEMA prod_catalog.gold TO `analysts`;
GRANT CREATE TABLE ON SCHEMA prod_catalog.silver TO `data-engineers`;

-- Table level
GRANT SELECT ON TABLE prod_catalog.gold.dim_customer TO `analysts`;
GRANT MODIFY ON TABLE prod_catalog.silver.cleaned_events TO `data-engineers`;

-- All tables in schema
GRANT SELECT ON SCHEMA prod_catalog.gold TO `analysts`;
```

### Revoke Permissions
```sql
REVOKE SELECT ON TABLE prod_catalog.gold.sensitive_data FROM `analysts`;
REVOKE ALL PRIVILEGES ON SCHEMA prod_catalog.bronze FROM `external-users`;
```

### Show Grants
```sql
-- Show grants on table
SHOW GRANTS ON TABLE prod_catalog.gold.dim_customer;

-- Show grants for principal
SHOW GRANTS TO `data-engineers`;

-- Show grants on catalog
SHOW GRANTS ON CATALOG prod_catalog;
```

---

## 🏷️ Attribute-Based Access Control (ABAC)

### Row-Level Security
```sql
-- Create row filter function
CREATE FUNCTION prod_catalog.security.region_filter(region STRING)
RETURNS BOOLEAN
RETURN (
    is_account_group_member('global_admins') OR
    CASE 
        WHEN is_account_group_member('us_team') AND region = 'US' THEN TRUE
        WHEN is_account_group_member('eu_team') AND region = 'EU' THEN TRUE
        ELSE FALSE
    END
);

-- Apply row filter
ALTER TABLE prod_catalog.gold.sales
SET ROW FILTER prod_catalog.security.region_filter ON (region);

-- Remove row filter
ALTER TABLE prod_catalog.gold.sales DROP ROW FILTER;
```

### Column Masking
```sql
-- Create masking function for PII
CREATE FUNCTION prod_catalog.security.mask_email(email STRING)
RETURNS STRING
RETURN CASE 
    WHEN is_account_group_member('pii_admins') THEN email
    ELSE CONCAT(SUBSTRING(email, 1, 2), '***@***')
END;

-- Create masking function for SSN
CREATE FUNCTION prod_catalog.security.mask_ssn(ssn STRING)
RETURNS STRING
RETURN CASE 
    WHEN is_account_group_member('hr_admins') THEN ssn
    ELSE CONCAT('XXX-XX-', RIGHT(ssn, 4))
END;

-- Apply column mask
ALTER TABLE prod_catalog.gold.customers
ALTER COLUMN email SET MASK prod_catalog.security.mask_email;

ALTER TABLE prod_catalog.gold.employees
ALTER COLUMN ssn SET MASK prod_catalog.security.mask_ssn;

-- Remove column mask
ALTER TABLE prod_catalog.gold.customers ALTER COLUMN email DROP MASK;
```

### Tag-Based Access Control
```sql
-- Create tags
ALTER CATALOG prod_catalog SET TAGS ('environment' = 'production');
ALTER SCHEMA prod_catalog.gold SET TAGS ('classification' = 'public');
ALTER TABLE prod_catalog.gold.pii_data SET TAGS ('classification' = 'confidential', 'pii' = 'true');

-- Query tables by tag
SELECT * FROM system.information_schema.table_tags
WHERE tag_name = 'classification' AND tag_value = 'confidential';
```

---

## 🔗 External Locations & Credentials

### Storage Credentials
```sql
-- Create storage credential (AWS)
CREATE STORAGE CREDENTIAL aws_s3_cred
WITH (
    AWS_IAM_ROLE = 'arn:aws:iam::123456789:role/databricks-s3-access'
);

-- Create storage credential (Azure)
CREATE STORAGE CREDENTIAL azure_blob_cred
WITH (
    AZURE_MANAGED_IDENTITY_APPLICATION_ID = 'xxxx-xxxx-xxxx'
);

-- Grant credential usage
GRANT CREATE EXTERNAL LOCATION ON STORAGE CREDENTIAL aws_s3_cred TO `data-platform-admins`;
```

### External Locations
```sql
-- Create external location
CREATE EXTERNAL LOCATION s3_raw_data
URL 's3://my-bucket/raw-data/'
WITH (STORAGE CREDENTIAL aws_s3_cred)
COMMENT 'Raw data landing zone';

-- Grant access to external location
GRANT READ FILES ON EXTERNAL LOCATION s3_raw_data TO `data-engineers`;
GRANT WRITE FILES ON EXTERNAL LOCATION s3_raw_data TO `etl-service-principal`;

-- Create external table
CREATE TABLE prod_catalog.bronze.external_events
USING DELTA
LOCATION 's3://my-bucket/raw-data/events/';
```

---

## 🔄 Delta Sharing

### Creating Shares
```sql
-- Create a share
CREATE SHARE customer_data_share
COMMENT 'Customer data share for partner integration';

-- Add tables to share
ALTER SHARE customer_data_share 
ADD TABLE prod_catalog.gold.customers AS shared_customers;

-- Add schema to share
ALTER SHARE customer_data_share ADD SCHEMA prod_catalog.gold;

-- Share with history (for time travel)
ALTER SHARE customer_data_share 
ADD TABLE prod_catalog.gold.transactions WITH HISTORY;
```

### Managing Recipients
```sql
-- Create recipient
CREATE RECIPIENT partner_org
COMMENT 'Partner organization'
USING ID 'partner-org-id';

-- Grant share to recipient
GRANT SELECT ON SHARE customer_data_share TO RECIPIENT partner_org;

-- View recipients
SHOW RECIPIENTS;

-- View shares granted to recipient
SHOW GRANTS TO RECIPIENT partner_org;
```

---

## 📊 System Tables for Governance

### Audit Logs
```sql
-- Recent access patterns
SELECT
    event_time,
    user_identity.email,
    action_name,
    request_params.full_name_arg AS object_name,
    response.status_code
FROM system.access.audit
WHERE event_date >= current_date() - INTERVAL 7 DAYS
    AND action_name IN ('getTable', 'createTable', 'deleteTable')
ORDER BY event_time DESC
LIMIT 100;

-- Failed access attempts
SELECT
    event_time,
    user_identity.email,
    action_name,
    request_params.full_name_arg,
    response.error_message
FROM system.access.audit
WHERE response.status_code >= 400
    AND event_date >= current_date() - INTERVAL 1 DAY
ORDER BY event_time DESC;
```

### Data Lineage
```sql
-- Table lineage (upstream)
SELECT 
    source_table_full_name,
    source_type,
    target_table_full_name,
    target_type
FROM system.access.table_lineage
WHERE target_table_full_name = 'prod_catalog.gold.fact_sales'
ORDER BY event_time DESC;

-- Column lineage
SELECT 
    source_table_full_name,
    source_column_name,
    target_table_full_name,
    target_column_name
FROM system.access.column_lineage
WHERE target_table_full_name = 'prod_catalog.gold.dim_customer';
```

### Information Schema
```sql
-- List all catalogs
SELECT * FROM system.information_schema.catalogs;

-- List all schemas
SELECT * FROM system.information_schema.schemata
WHERE catalog_name = 'prod_catalog';

-- List all tables with details
SELECT 
    table_catalog,
    table_schema,
    table_name,
    table_type,
    created,
    last_altered
FROM system.information_schema.tables
WHERE table_catalog = 'prod_catalog'
ORDER BY last_altered DESC;

-- Column information
SELECT 
    table_name,
    column_name,
    data_type,
    is_nullable
FROM system.information_schema.columns
WHERE table_catalog = 'prod_catalog'
    AND table_schema = 'gold';
```

---

## ✅ Governance Best Practices Checklist

| Practice | Description |
|----------|-------------|
| ✅ Least privilege | Grant minimum necessary permissions |
| ✅ Group-based access | Assign permissions to groups, not individuals |
| ✅ SCIM provisioning | Sync users/groups from IdP |
| ✅ Service principals | Use for automated workloads |
| ✅ Managed storage | Prefer managed over external tables |
| ✅ Regional metastore | One metastore per region |
| ✅ Naming conventions | Consistent naming across catalogs |
| ✅ Data classification | Tag sensitive data appropriately |
| ✅ Audit log review | Regularly review access patterns |
| ✅ Lineage tracking | Enable and review data lineage |

---

*Last updated: 2026-01-31*
