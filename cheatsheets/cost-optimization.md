# Cost Optimization Cheatsheet

Strategies and techniques for optimizing Databricks costs while maintaining performance.

---

## 📊 Cost Visibility

### System Tables for Billing
```sql
-- Monthly cost summary by workspace
SELECT
    workspace_id,
    DATE_TRUNC('month', usage_date) as month,
    sku_name,
    SUM(usage_quantity) as total_dbus,
    SUM(usage_quantity * list_price) as estimated_cost
FROM system.billing.usage
WHERE usage_date >= DATE_TRUNC('month', current_date()) - INTERVAL 3 MONTHS
GROUP BY 1, 2, 3
ORDER BY month DESC, estimated_cost DESC;

-- Cost by job/cluster
SELECT
    usage_metadata.job_id,
    usage_metadata.cluster_id,
    SUM(usage_quantity) as total_dbus,
    SUM(usage_quantity * list_price) as estimated_cost
FROM system.billing.usage
WHERE usage_date >= current_date() - INTERVAL 30 DAYS
    AND usage_metadata.job_id IS NOT NULL
GROUP BY 1, 2
ORDER BY estimated_cost DESC
LIMIT 20;

-- Daily cost trend
SELECT
    usage_date,
    sku_name,
    SUM(usage_quantity * list_price) as daily_cost
FROM system.billing.usage
WHERE usage_date >= current_date() - INTERVAL 30 DAYS
GROUP BY 1, 2
ORDER BY usage_date, daily_cost DESC;
```

### Cost Attribution by Tags
```sql
-- Cost by custom tags
SELECT
    custom_tags['CostCenter'] as cost_center,
    custom_tags['Team'] as team,
    SUM(usage_quantity * list_price) as total_cost
FROM system.billing.usage
WHERE usage_date >= current_date() - INTERVAL 30 DAYS
GROUP BY 1, 2
ORDER BY total_cost DESC;
```

---

## 🖥️ Cluster Optimization

### Right-Sizing Clusters
```sql
-- Analyze cluster utilization
SELECT
    cluster_id,
    cluster_name,
    AVG(cpu_utilization) as avg_cpu,
    AVG(memory_utilization) as avg_memory,
    COUNT(*) as sample_count
FROM system.compute.cluster_metrics
WHERE timestamp >= current_date() - INTERVAL 7 DAYS
GROUP BY 1, 2
HAVING avg_cpu < 0.3  -- Under-utilized clusters
ORDER BY sample_count DESC;
```

### Cluster Policy for Cost Control
```json
{
  "spark_version": {
    "type": "regex",
    "pattern": "14\\.[0-9]+\\.x-scala.*"
  },
  "node_type_id": {
    "type": "allowlist",
    "values": ["Standard_DS3_v2", "Standard_DS4_v2"],
    "defaultValue": "Standard_DS3_v2"
  },
  "autotermination_minutes": {
    "type": "range",
    "minValue": 10,
    "maxValue": 60,
    "defaultValue": 20
  },
  "num_workers": {
    "type": "range",
    "minValue": 1,
    "maxValue": 10,
    "defaultValue": 2
  },
  "autoscale.min_workers": {
    "type": "range",
    "minValue": 1,
    "maxValue": 5
  },
  "autoscale.max_workers": {
    "type": "range",
    "minValue": 2,
    "maxValue": 20
  },
  "custom_tags.CostCenter": {
    "type": "fixed",
    "value": "DataPlatform"
  },
  "dbus_per_hour": {
    "type": "range",
    "maxValue": 100
  }
}
```

### Auto-termination Settings
```python
# Set aggressive auto-termination for dev clusters
cluster_config = {
    "cluster_name": "dev-cluster",
    "autotermination_minutes": 15,  # Terminate after 15 mins idle
    # ...
}

# For production jobs, use jobs compute (terminates after job)
```

---

## 💰 Spot Instances & Pools

### Spot Instance Configuration
```json
{
  "aws_attributes": {
    "first_on_demand": 1,
    "availability": "SPOT_WITH_FALLBACK",
    "spot_bid_price_percent": 100
  }
}
```

```json
{
  "azure_attributes": {
    "first_on_demand": 1,
    "availability": "SPOT_WITH_FALLBACK_AZURE",
    "spot_bid_max_price": -1
  }
}
```

### Instance Pool Configuration
```python
# Create cost-optimized instance pool
pool_config = {
    "instance_pool_name": "shared-pool",
    "min_idle_instances": 2,
    "max_capacity": 20,
    "idle_instance_autotermination_minutes": 10,
    "node_type_id": "Standard_DS3_v2",
    "preloaded_spark_versions": ["14.3.x-scala2.12"],
    "azure_attributes": {
        "availability": "SPOT_WITH_FALLBACK_AZURE",
        "spot_bid_max_price": -1
    }
}
```

---

## ⚡ Compute Selection Guide

| Workload | Recommended Compute | Cost Optimization |
|----------|---------------------|-------------------|
| **Ad-hoc SQL** | Serverless SQL Warehouse | Auto-scales, pay per query |
| **Scheduled ETL** | Jobs Compute | Terminates after job |
| **BI Dashboards** | SQL Warehouse (Pro) | Auto-suspend enabled |
| **Interactive Dev** | All-Purpose (with pool) | Instance pools + spot |
| **ML Training** | Jobs Compute + GPU | Preemptible GPUs |
| **Streaming** | Jobs Compute | Continuous cluster |

### Serverless vs Classic
```sql
-- Use Serverless SQL Warehouse for variable workloads
-- No idle cost, sub-second startup, automatic scaling

-- Classic SQL Warehouse sizing guide:
-- T-Shirt Size   | Cluster Size | Use Case
-- 2X-Small       | 1 cluster    | Light BI queries
-- Small          | 2 clusters   | Standard BI
-- Medium         | 4 clusters   | Heavy BI + ETL
-- Large+         | 8+ clusters  | Concurrent users
```

---

## 🔧 Photon Optimization

```sql
-- Enable Photon for SQL workloads (up to 8x faster = less DBU usage)
-- Set at cluster level: spark.databricks.photon.enabled = true

-- Best for:
-- ✅ SQL queries and aggregations
-- ✅ Delta Lake scan/filter/join
-- ✅ Parquet processing
-- ❌ Python UDFs (no acceleration)
```

---

## 📉 Storage Cost Optimization

### Delta Lake Cleanup
```sql
-- Regular VACUUM to remove old files
VACUUM catalog.schema.large_table RETAIN 168 HOURS;

-- Check storage size before/after
DESCRIBE DETAIL catalog.schema.large_table;

-- Automate with scheduled job
-- Run weekly: VACUUM for all tables in catalog
```

### Compression & File Size
```sql
-- Optimize file size (1GB targets)
OPTIMIZE catalog.schema.my_table;

-- For tables with lots of small files
SET spark.databricks.delta.optimize.maxFileSize = 1073741824; -- 1GB
OPTIMIZE catalog.schema.fragmented_table;
```

### Data Retention Policy
```sql
-- Set retention for log files
ALTER TABLE catalog.schema.my_table SET TBLPROPERTIES (
    'delta.logRetentionDuration' = 'interval 30 days',
    'delta.deletedFileRetentionDuration' = 'interval 7 days'
);
```

---

## 📈 Query Optimization

### Expensive Query Detection
```sql
-- Find expensive queries
SELECT
    statement_id,
    executed_by,
    statement_text,
    total_task_duration_ms / 1000 as duration_sec,
    rows_produced,
    FROM system.query.history
WHERE start_time >= current_date() - INTERVAL 7 DAYS
    AND status = 'FINISHED'
ORDER BY total_task_duration_ms DESC
LIMIT 50;
```

### Caching Strategy
```python
# Cache frequently accessed dimension tables
dim_customer = spark.table("catalog.schema.dim_customer").cache()
dim_customer.count()  # Materialize

# Use Delta Cache for repeated scans
spark.conf.set("spark.databricks.io.cache.enabled", "true")
```

---

## 💵 Budgets & Alerts

### Budget Configuration
```python
from databricks.sdk import WorkspaceClient

w = WorkspaceClient()

# Create budget alert
budget = w.budgets.create(
    name="monthly-dbu-budget",
    filter_type="ALL",
    budget_amount=10000,  # $10,000 monthly
    period="MONTH",
    alert_configurations=[
        {
            "trigger_type": "PERCENTAGE",
            "trigger_value": 80,  # Alert at 80%
            "alert_channel": "EMAIL",
            "recipients": ["data-admins@company.com"]
        }
    ]
)
```

### Cost Alerting Query
```sql
-- Daily cost check (schedule as job)
SELECT 
    'ALERT: Daily cost exceeded threshold' as message,
    SUM(usage_quantity * list_price) as daily_cost
FROM system.billing.usage
WHERE usage_date = current_date()
HAVING daily_cost > 1000;  -- $1000 threshold
```

---

## 📋 Cost Optimization Checklist

| Category | Action | Impact |
|----------|--------|--------|
| **Compute** | Use Jobs Compute for scheduled workloads | High |
| **Compute** | Enable Photon for SQL workloads | High |
| **Compute** | Configure auto-termination (10-30 mins) | Medium |
| **Compute** | Use instance pools with spot instances | High |
| **Compute** | Right-size clusters based on metrics | Medium |
| **Storage** | Regular VACUUM operations | Medium |
| **Storage** | OPTIMIZE fragmented tables | Medium |
| **Storage** | Set appropriate data retention | Low |
| **SQL** | Use Serverless SQL Warehouse | High |
| **SQL** | Enable warehouse auto-suspend | Medium |
| **Governance** | Implement cluster policies | High |
| **Governance** | Tag resources for cost attribution | Medium |
| **Governance** | Set up budget alerts | Medium |

---

*Last updated: 2026-01-31*
