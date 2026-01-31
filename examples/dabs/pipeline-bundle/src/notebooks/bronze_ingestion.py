# Databricks notebook source
# MAGIC %md
# MAGIC # Bronze Ingestion Notebook
# MAGIC 
# MAGIC Ingests raw data from source systems into the bronze layer.

# COMMAND ----------

# DBTITLE 1,Setup & Parameters
dbutils.widgets.text("catalog", "dev", "Target Catalog")
dbutils.widgets.text("schema", "bronze", "Target Schema")

catalog = dbutils.widgets.get("catalog")
schema = dbutils.widgets.get("schema")

print(f"Target: {catalog}.{schema}")

# COMMAND ----------

# DBTITLE 1,Configuration
from pyspark.sql.functions import *
from datetime import datetime

# Source configuration
SOURCE_PATH = "/mnt/raw/events/"
CHECKPOINT_PATH = f"/checkpoints/{catalog}/{schema}/events"

# Target table
TARGET_TABLE = f"{catalog}.{schema}.raw_events"

# COMMAND ----------

# DBTITLE 1,Read with Auto Loader
# Use Auto Loader for incremental ingestion
df_raw = (spark.readStream
    .format("cloudFiles")
    .option("cloudFiles.format", "json")
    .option("cloudFiles.schemaLocation", f"{CHECKPOINT_PATH}/_schema")
    .option("cloudFiles.schemaEvolutionMode", "addNewColumns")
    .option("cloudFiles.inferColumnTypes", "true")
    .load(SOURCE_PATH))

# COMMAND ----------

# DBTITLE 1,Add Metadata
df_with_metadata = (df_raw
    .withColumn("_ingestion_timestamp", current_timestamp())
    .withColumn("_source_file", input_file_name())
    .withColumn("_ingestion_date", current_date()))

# COMMAND ----------

# DBTITLE 1,Write to Bronze Table
query = (df_with_metadata.writeStream
    .format("delta")
    .outputMode("append")
    .option("checkpointLocation", CHECKPOINT_PATH)
    .option("mergeSchema", "true")
    .trigger(availableNow=True)
    .toTable(TARGET_TABLE))

query.awaitTermination()

# COMMAND ----------

# DBTITLE 1,Verify Results
df_result = spark.table(TARGET_TABLE)
print(f"Total records: {df_result.count()}")

# Log to MLflow for tracking
import mlflow
mlflow.log_metric("bronze_record_count", df_result.count())

# COMMAND ----------

# MAGIC %md
# MAGIC ## Data Quality Check

# COMMAND ----------

# Basic quality checks
from pyspark.sql.functions import count, when, isnan, isnull

df_quality = df_result.agg(
    count("*").alias("total_rows"),
    count(when(isnull("event_id"), True)).alias("null_event_ids"),
    count(when(isnull("event_timestamp"), True)).alias("null_timestamps")
)

df_quality.display()

# Assert quality thresholds
quality = df_quality.collect()[0]
assert quality.null_event_ids / quality.total_rows < 0.01, "Too many null event IDs"
print("✅ Quality checks passed")
