# MLflow & Model Registry Cheatsheet

Experiment tracking, model versioning, deployment, and serving patterns for Databricks.

---

## 🔬 Experiment Tracking

### Basic Experiment Setup
```python
import mlflow

# Set tracking URI (Databricks default)
mlflow.set_tracking_uri("databricks")

# Create/set experiment
mlflow.set_experiment("/Users/user@company.com/my_experiment")

# Or by name
experiment = mlflow.create_experiment(
    name="/Shared/team_experiments/fraud_detection",
    artifact_location="dbfs:/mlflow/artifacts"
)
mlflow.set_experiment(experiment_id=experiment)
```

### Logging Parameters, Metrics, Artifacts
```python
import mlflow
from mlflow.models import infer_signature
import pandas as pd

with mlflow.start_run(run_name="xgboost_v1") as run:
    # Log parameters
    mlflow.log_param("max_depth", 6)
    mlflow.log_param("learning_rate", 0.1)
    mlflow.log_params({
        "n_estimators": 100,
        "min_child_weight": 1,
        "subsample": 0.8
    })
    
    # Train model
    model = train_model(X_train, y_train)
    predictions = model.predict(X_test)
    
    # Log metrics
    mlflow.log_metric("rmse", 0.87)
    mlflow.log_metric("mae", 0.65)
    mlflow.log_metrics({
        "r2": 0.92,
        "accuracy": 0.95,
        "f1_score": 0.89
    })
    
    # Log metric over time (for learning curves)
    for epoch in range(100):
        mlflow.log_metric("loss", loss_value, step=epoch)
    
    # Log artifacts
    mlflow.log_artifact("feature_importance.png")
    mlflow.log_artifacts("./plots/")  # Log entire directory
    
    # Log model with signature
    signature = infer_signature(X_test, predictions)
    mlflow.sklearn.log_model(model, "model", signature=signature)
    
    print(f"Run ID: {run.info.run_id}")
```

### Auto-logging
```python
# Enable auto-logging for supported frameworks
mlflow.autolog()  # Generic
mlflow.sklearn.autolog()
mlflow.tensorflow.autolog()
mlflow.pytorch.autolog()
mlflow.xgboost.autolog()
mlflow.lightgbm.autolog()
mlflow.spark.autolog()

# Then train as usual
from sklearn.ensemble import RandomForestClassifier
model = RandomForestClassifier(n_estimators=100, max_depth=5)
model.fit(X_train, y_train)
# All parameters, metrics, and model are logged automatically
```

---

## 📦 Unity Catalog Model Registry

### Register Model
```python
import mlflow

# Set registry URI for Unity Catalog
mlflow.set_registry_uri("databricks-uc")

# Log and register model
with mlflow.start_run() as run:
    mlflow.sklearn.log_model(
        model,
        "model",
        signature=signature,
        registered_model_name="catalog.schema.my_model"
    )

# Or register existing run
model_uri = f"runs:/{run.info.run_id}/model"
mlflow.register_model(model_uri, "catalog.schema.my_model")
```

### Model Versioning & Aliases
```python
from mlflow import MlflowClient

client = MlflowClient()

# List model versions
versions = client.search_model_versions("name='catalog.schema.my_model'")
for v in versions:
    print(f"Version {v.version}: {v.current_stage}")

# Set alias (replaces stages in UC)
client.set_registered_model_alias(
    name="catalog.schema.my_model",
    alias="production",
    version=3
)

client.set_registered_model_alias(
    name="catalog.schema.my_model",
    alias="champion",
    version=3
)

client.set_registered_model_alias(
    name="catalog.schema.my_model",
    alias="challenger",
    version=4
)

# Delete alias
client.delete_registered_model_alias(
    name="catalog.schema.my_model",
    alias="challenger"
)
```

### Load Model by Alias
```python
import mlflow

# Load production model
model = mlflow.pyfunc.load_model("models:/catalog.schema.my_model@production")

# Load by version
model = mlflow.pyfunc.load_model("models:/catalog.schema.my_model/3")

# Load latest version
model = mlflow.pyfunc.load_model("models:/catalog.schema.my_model/latest")

# Use model for inference
predictions = model.predict(X_test)
```

---

## 🚀 Model Serving

### Enable Model Serving (REST API)
```python
from databricks.sdk import WorkspaceClient
from databricks.sdk.service.serving import EndpointCoreConfigInput, ServedEntityInput

w = WorkspaceClient()

# Create serving endpoint
endpoint = w.serving_endpoints.create_and_wait(
    name="fraud-detection-endpoint",
    config=EndpointCoreConfigInput(
        served_entities=[
            ServedEntityInput(
                entity_name="catalog.schema.fraud_model",
                entity_version="3",
                workload_size="Small",
                scale_to_zero_enabled=True
            )
        ]
    )
)
```

### Query Serving Endpoint
```python
import requests
import json

# Get endpoint URL
url = f"https://{workspace_url}/serving-endpoints/fraud-detection-endpoint/invocations"

headers = {
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json"
}

data = {
    "dataframe_records": [
        {"feature1": 1.0, "feature2": 2.0, "feature3": 3.0}
    ]
}

response = requests.post(url, headers=headers, json=data)
predictions = response.json()
```

### Batch Inference with Spark
```python
import mlflow

# Load model as Spark UDF
model_uri = "models:/catalog.schema.my_model@production"
predict_udf = mlflow.pyfunc.spark_udf(spark, model_uri)

# Apply to Spark DataFrame
df_predictions = df.withColumn("prediction", predict_udf(*feature_columns))

# Save predictions
df_predictions.write.mode("overwrite").saveAsTable("catalog.schema.predictions")
```

---

## 🎯 Feature Store

### Create Feature Table
```python
from databricks.feature_store import FeatureStoreClient

fs = FeatureStoreClient()

# Create feature table
fs.create_table(
    name="catalog.schema.customer_features",
    primary_keys=["customer_id"],
    timestamp_keys=["feature_timestamp"],
    df=feature_df,
    description="Customer behavioral features for ML"
)

# Write features
fs.write_table(
    name="catalog.schema.customer_features",
    df=new_features_df,
    mode="merge"
)
```

### Training with Features
```python
from databricks.feature_store import FeatureLookup

# Define feature lookups
feature_lookups = [
    FeatureLookup(
        table_name="catalog.schema.customer_features",
        feature_names=["total_purchases", "avg_order_value"],
        lookup_key="customer_id",
        timestamp_lookup_key="event_timestamp"
    ),
    FeatureLookup(
        table_name="catalog.schema.product_features",
        feature_names=["category", "price"],
        lookup_key="product_id"
    )
]

# Create training set
training_set = fs.create_training_set(
    df=labels_df,
    feature_lookups=feature_lookups,
    label="is_churned",
    exclude_columns=["customer_id", "event_timestamp"]
)

# Get training DataFrame
training_df = training_set.load_df()

# Train model
model = train_model(training_df)

# Log model with feature metadata
fs.log_model(
    model=model,
    artifact_path="model",
    flavor=mlflow.sklearn,
    training_set=training_set,
    registered_model_name="catalog.schema.churn_model"
)
```

### Batch Scoring with Feature Store
```python
# Score with automatic feature lookup
predictions = fs.score_batch(
    model_uri="models:/catalog.schema.churn_model@production",
    df=scoring_df  # Only needs primary keys
)
```

---

## 🔄 Model Deployment Patterns

### A/B Testing (Traffic Splitting)
```python
from databricks.sdk.service.serving import TrafficConfig, Route

# Update endpoint with traffic split
w.serving_endpoints.update_config(
    name="fraud-detection-endpoint",
    config=EndpointCoreConfigInput(
        served_entities=[
            ServedEntityInput(
                entity_name="catalog.schema.fraud_model",
                entity_version="3",  # Champion
                scale_to_zero_enabled=False
            ),
            ServedEntityInput(
                entity_name="catalog.schema.fraud_model", 
                entity_version="4",  # Challenger
                scale_to_zero_enabled=False
            )
        ],
        traffic_config=TrafficConfig(
            routes=[
                Route(served_model_name="catalog.schema.fraud_model-3", traffic_percentage=90),
                Route(served_model_name="catalog.schema.fraud_model-4", traffic_percentage=10)
            ]
        )
    )
)
```

### Canary Deployment
```python
# Start with small traffic percentage
# Monitor performance metrics
# Gradually increase if metrics are good

traffic_percentages = [5, 25, 50, 100]

for percentage in traffic_percentages:
    update_traffic_split(new_version, percentage)
    
    # Wait and evaluate
    time.sleep(3600)  # 1 hour
    
    if not check_performance_metrics():
        rollback_to_previous_version()
        break
```

---

## 📊 Model Monitoring

### Performance Monitoring
```sql
-- Query inference table for monitoring
SELECT
    timestamp,
    COUNT(*) as request_count,
    AVG(latency_ms) as avg_latency,
    PERCENTILE(latency_ms, 0.95) as p95_latency,
    SUM(CASE WHEN status_code != 200 THEN 1 ELSE 0 END) as errors
FROM catalog.schema.endpoint_inference_logs
WHERE timestamp >= current_date() - INTERVAL 1 DAY
GROUP BY DATE_TRUNC('hour', timestamp)
ORDER BY timestamp;
```

### Data Drift Detection
```python
from databricks.sdk import WorkspaceClient

# Enable inference tables for drift monitoring
w.serving_endpoints.update_config(
    name="fraud-detection-endpoint",
    config=EndpointCoreConfigInput(
        # ... existing config
        auto_capture_config={
            "catalog_name": "catalog",
            "schema_name": "ml_inference",
            "table_name_prefix": "fraud_model"
        }
    )
)

# Query for drift analysis
drift_df = spark.sql("""
    SELECT 
        feature_name,
        AVG(current_mean - baseline_mean) as mean_drift,
        AVG(current_std - baseline_std) as std_drift
    FROM catalog.ml_inference.fraud_model_drift
    WHERE window_end >= current_date() - INTERVAL 7 DAYS
    GROUP BY feature_name
    HAVING ABS(mean_drift) > 0.1
""")
```

---

## 📋 MLflow Best Practices

| Practice | Description |
|----------|-------------|
| ✅ Use experiments | Organize runs by project/feature |
| ✅ Log signatures | Always include input/output schema |
| ✅ Use aliases | Never hardcode version numbers |
| ✅ Auto-logging | Enable for supported frameworks |
| ✅ Feature Store | Use for feature reuse and lineage |
| ✅ Model validation | Test before promoting to production |
| ✅ Inference tables | Enable for monitoring |
| ✅ A/B testing | Validate new models with traffic split |
| ✅ Unity Catalog | Use UC registry for governance |

---

*Last updated: 2026-01-31*
