# Delta Lake Optimization Cheatsheet

Performance tuning, table maintenance, and best practices for Delta Lake.

---

## ⚡ Quick Optimization Commands

```sql
-- Essential optimizations
OPTIMIZE my_table;                                    -- Compact small files
OPTIMIZE my_table ZORDER BY (col1, col2);             -- Compact + data skipping
VACUUM my_table;                                      -- Remove old files (7 days default)
ANALYZE TABLE my_table COMPUTE STATISTICS FOR ALL COLUMNS;  -- Update statistics
```

---

## 🔧 OPTIMIZE Operations

### Basic Optimization
```sql
-- Compact small files into larger ones (target ~1GB each)
OPTIMIZE catalog.schema.my_table;

-- Optimize specific partitions
OPTIMIZE catalog.schema.events
WHERE event_date >= '2026-01-01' AND event_date < '2026-02-01';

-- View optimization metrics
DESCRIBE HISTORY catalog.schema.my_table LIMIT 5;
```

### Z-ORDER Clustering
```sql
-- Z-ORDER for frequently filtered columns (2-4 columns max)
OPTIMIZE catalog.schema.fact_sales
ZORDER BY (customer_id, sale_date);

-- Z-ORDER with partition filter
OPTIMIZE catalog.schema.events
WHERE event_date = current_date()
ZORDER BY (user_id, event_type);

-- Best candidates for Z-ORDER:
-- ✅ High cardinality columns (IDs, timestamps)
-- ✅ Frequently used in WHERE clauses
-- ❌ Already partitioned columns (don't Z-ORDER these)
-- ❌ Too many columns (diminishing returns)
```

### Liquid Clustering (DBR 13.3+)
```sql
-- Create table with liquid clustering
CREATE TABLE catalog.schema.events (
    event_id STRING,
    user_id STRING,
    event_type STRING,
    event_date DATE,
    payload STRING
)
CLUSTER BY (user_id, event_date);

-- Convert existing table to liquid clustering
ALTER TABLE catalog.schema.existing_table
CLUSTER BY (col1, col2);

-- Remove clustering
ALTER TABLE catalog.schema.my_table CLUSTER BY NONE;

-- Liquid Clustering Benefits:
-- ✅ Incremental - no full rewrite
-- ✅ Automatic maintenance
-- ✅ Better for streaming tables
-- ✅ Replaces partitioning in many cases
```

---

## 🧹 VACUUM Operations

### Basic Vacuum
```sql
-- Remove files older than 7 days (default retention)
VACUUM catalog.schema.my_table;

-- Specify retention period (minimum 7 days)
VACUUM catalog.schema.my_table RETAIN 168 HOURS;

-- Dry run (preview files to be deleted)
VACUUM catalog.schema.my_table DRY RUN;
```

### Aggressive Vacuum (Use with Caution)
```sql
-- Override safety check (dangerous - breaks time travel)
SET spark.databricks.delta.retentionDurationCheck.enabled = false;
VACUUM catalog.schema.my_table RETAIN 0 HOURS;
SET spark.databricks.delta.retentionDurationCheck.enabled = true;
```

---

## 📊 Table Statistics

```sql
-- Compute statistics for all columns
ANALYZE TABLE catalog.schema.my_table COMPUTE STATISTICS FOR ALL COLUMNS;

-- Compute for specific columns
ANALYZE TABLE catalog.schema.my_table COMPUTE STATISTICS FOR COLUMNS customer_id, amount;

-- View table statistics
DESCRIBE EXTENDED catalog.schema.my_table;

-- View column statistics
DESCRIBE EXTENDED catalog.schema.my_table customer_id;
```

---

## ⚙️ Table Properties

### Performance Properties
```sql
-- Enable auto-optimization
ALTER TABLE catalog.schema.my_table SET TBLPROPERTIES (
    'delta.autoOptimize.optimizeWrite' = 'true',      -- Better file sizing
    'delta.autoOptimize.autoCompact' = 'true'         -- Auto compaction
);

-- Enable deletion vectors (faster deletes/updates)
ALTER TABLE catalog.schema.my_table SET TBLPROPERTIES (
    'delta.enableDeletionVectors' = 'true'
);

-- Enable predictive optimization
ALTER TABLE catalog.schema.my_table SET TBLPROPERTIES (
    'delta.tuneFileSizesForRewrites' = 'true'
);

-- Configure target file size
ALTER TABLE catalog.schema.my_table SET TBLPROPERTIES (
    'delta.targetFileSize' = '128mb'  -- Smaller for frequent updates
);
```

### Data Retention Properties
```sql
-- Configure log retention
ALTER TABLE catalog.schema.my_table SET TBLPROPERTIES (
    'delta.logRetentionDuration' = 'interval 30 days',
    'delta.deletedFileRetentionDuration' = 'interval 7 days'
);

-- Enable Change Data Feed
ALTER TABLE catalog.schema.my_table SET TBLPROPERTIES (
    'delta.enableChangeDataFeed' = 'true'
);
```

---

## 🗂️ Partitioning Strategies

### When to Partition
```sql
-- Good partition candidates:
-- ✅ Low cardinality (< 10,000 distinct values)
-- ✅ Frequently filtered on
-- ✅ Date/datetime columns for time-series
-- ✅ Partition eliminates significant data

-- Create partitioned table
CREATE TABLE catalog.schema.events (
    event_id STRING,
    user_id STRING,
    event_type STRING,
    event_timestamp TIMESTAMP,
    event_date DATE GENERATED ALWAYS AS (CAST(event_timestamp AS DATE))
)
PARTITIONED BY (event_date);
```

### Partition Pruning
```sql
-- Query with partition pruning (efficient)
SELECT * FROM catalog.schema.events
WHERE event_date = '2026-01-31';  -- Only scans one partition

-- Avoid dynamic partition values (no pruning)
SELECT * FROM catalog.schema.events
WHERE event_date = (SELECT MAX(event_date) FROM other_table);  -- Scans all partitions
```

---

## 🔍 Data Skipping

### Statistics-Based Skipping
```sql
-- Delta automatically collects min/max stats on first 32 columns
-- Reorder columns to put filterable ones first

CREATE TABLE catalog.schema.optimized_events (
    -- High-value filter columns first
    event_date DATE,
    user_id STRING,
    event_type STRING,
    -- Other columns
    event_id STRING,
    payload STRING
);

-- Increase column stats limit if needed
SET spark.databricks.delta.stats.collect = true;
SET spark.databricks.delta.stats.limitPushdown.enabled = true;
```

### Bloom Filters
```sql
-- Enable bloom filters for equality lookups on high-cardinality columns
ALTER TABLE catalog.schema.my_table SET TBLPROPERTIES (
    'delta.dataSkippingNumIndexedCols' = 32
);

-- Create table with bloom filter index
CREATE TABLE catalog.schema.events (
    event_id STRING,
    user_id STRING,
    event_type STRING
)
TBLPROPERTIES (
    'delta.bloomFilter.columns' = 'user_id,event_id',
    'delta.bloomFilter.fpp' = '0.01'  -- False positive probability
);
```

---

## 📈 Query Performance

### Photon Acceleration
```sql
-- Enable Photon (cluster configuration)
-- "spark.databricks.photon.enabled": "true"

-- Best for:
-- ✅ SQL workloads
-- ✅ Aggregations and joins
-- ✅ Parquet/Delta scanning
-- ❌ Python UDFs (use Pandas UDFs when possible)
```

### Adaptive Query Execution
```sql
SET spark.sql.adaptive.enabled = true;
SET spark.sql.adaptive.coalescePartitions.enabled = true;
SET spark.sql.adaptive.skewJoin.enabled = true;
SET spark.sql.adaptive.localShuffleReader.enabled = true;

-- Auto-optimize shuffle partitions
SET spark.sql.adaptive.coalescePartitions.initialPartitionNum = 8192;
SET spark.sql.adaptive.coalescePartitions.minPartitionSize = 64MB;
```

### Join Optimization
```sql
-- Broadcast hint for small tables
SELECT /*+ BROADCAST(dim_product) */ 
    f.*, d.product_name
FROM fact_sales f
JOIN dim_product d ON f.product_id = d.product_id;

-- Increase broadcast threshold
SET spark.sql.autoBroadcastJoinThreshold = 100000000;  -- 100MB

-- Shuffle hash join for medium tables
SELECT /*+ SHUFFLE_HASH(orders) */ 
    * FROM orders JOIN customers ON orders.customer_id = customers.id;
```

---

## 🔄 Merge Optimization

```sql
-- Efficient MERGE pattern
MERGE INTO target t
USING (
    SELECT * FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts DESC) as rn
        FROM source
    ) WHERE rn = 1
) s ON t.id = s.id
WHEN MATCHED AND s.ts > t.ts THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;

-- Enable low-shuffle merge
SET spark.databricks.delta.merge.enableLowShuffle = true;

-- Enable optimized write for merge
ALTER TABLE target SET TBLPROPERTIES (
    'delta.autoOptimize.optimizeWrite' = 'true'
);
```

---

## 📋 Maintenance Schedule

| Task | Frequency | Command |
|------|-----------|---------|
| OPTIMIZE | Daily/Weekly | `OPTIMIZE table [ZORDER BY ...]` |
| VACUUM | Weekly | `VACUUM table RETAIN 168 HOURS` |
| ANALYZE | After major loads | `ANALYZE TABLE table COMPUTE STATISTICS` |
| History cleanup | Monthly | Check `DESCRIBE HISTORY table` |

### Automated Maintenance Job
```python
from pyspark.sql import SparkSession

tables_to_maintain = [
    "catalog.schema.table1",
    "catalog.schema.table2"
]

for table in tables_to_maintain:
    spark.sql(f"OPTIMIZE {table}")
    spark.sql(f"VACUUM {table} RETAIN 168 HOURS")
    spark.sql(f"ANALYZE TABLE {table} COMPUTE STATISTICS FOR ALL COLUMNS")
```

---

## 🩺 Diagnostic Queries

```sql
-- Table size and file count
DESCRIBE DETAIL catalog.schema.my_table;

-- File size distribution
SELECT 
    ROUND(size / 1024 / 1024, 2) as size_mb,
    COUNT(*) as file_count
FROM (
    SELECT input_file_name() as file_path, MAX(size) as size
    FROM delta.`/path/to/table`
    GROUP BY 1
)
GROUP BY 1
ORDER BY 1;

-- Check for small files problem
SELECT 
    COUNT(*) as total_files,
    ROUND(AVG(size) / 1024 / 1024, 2) as avg_size_mb,
    ROUND(MIN(size) / 1024 / 1024, 2) as min_size_mb,
    ROUND(MAX(size) / 1024 / 1024, 2) as max_size_mb
FROM (SELECT size FROM DESCRIBE DETAIL catalog.schema.my_table);
```

---

*Last updated: 2026-01-31*
