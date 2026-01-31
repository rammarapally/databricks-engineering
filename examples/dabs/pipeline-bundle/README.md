# Databricks Asset Bundle: Data Pipeline

Production-ready DAB template for ETL/ELT data pipelines.

## Quick Start

```bash
# Validate bundle
databricks bundle validate -t dev

# Deploy to development
databricks bundle deploy -t dev

# Run the pipeline
databricks bundle run daily_etl_pipeline -t dev

# Deploy to production
databricks bundle deploy -t prod
```

## Structure

```
pipeline-bundle/
├── databricks.yml          # Main bundle configuration
├── resources/
│   ├── jobs.yml            # Job definitions
│   └── pipelines.yml       # DLT pipeline definitions
├── src/
│   └── notebooks/
│       ├── bronze_ingestion.py
│       ├── silver_transform.py
│       └── gold_aggregate.py
└── tests/
    └── test_transforms.py
```

## Environments

| Target | Description | Cluster |
|--------|-------------|---------|
| `dev` | Development sandbox | Small, auto-terminate |
| `staging` | Pre-production testing | Medium |
| `prod` | Production | Large, service principal |
