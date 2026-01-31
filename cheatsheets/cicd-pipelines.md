# CI/CD Pipelines Cheatsheet

Deployment workflows, testing strategies, and automation patterns for Databricks.

---

## 🏗️ CI/CD Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Source Control (Git)                        │
│                  (Feature Branches → Main → Tags)                  │
└─────────────────────────┬───────────────────────────────────────────┘
                          │ Push/PR
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      CI Pipeline (Validate)                        │
│  • Lint & Format   • Unit Tests   • Bundle Validate   • Security   │
└─────────────────────────┬───────────────────────────────────────────┘
                          │ On Merge
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      CD Pipeline (Deploy)                          │
│  • Deploy to Dev → Integration Tests → Deploy to Stage → Prod      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 🔐 Authentication Methods

### Personal Access Tokens (PAT)
```yaml
# GitHub Actions - Token auth
- name: Configure Databricks
  env:
    DATABRICKS_HOST: ${{ secrets.DATABRICKS_HOST }}
    DATABRICKS_TOKEN: ${{ secrets.DATABRICKS_TOKEN }}
  run: databricks bundle deploy
```

### OAuth / Service Principal (Recommended)
```yaml
# GitHub Actions - Service Principal (Azure)
- name: Configure Databricks
  env:
    DATABRICKS_HOST: ${{ secrets.DATABRICKS_HOST }}
    ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
    ARM_CLIENT_SECRET: ${{ secrets.AZURE_CLIENT_SECRET }}
    ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
  run: databricks bundle deploy

# AWS - Service Principal
- name: Configure Databricks (AWS)
  env:
    DATABRICKS_HOST: ${{ secrets.DATABRICKS_HOST }}
    DATABRICKS_CLIENT_ID: ${{ secrets.DB_CLIENT_ID }}
    DATABRICKS_CLIENT_SECRET: ${{ secrets.DB_CLIENT_SECRET }}
  run: databricks bundle deploy
```

### OIDC / Workload Identity (Best Practice)
```yaml
# GitHub Actions - OIDC (no secrets stored)
- name: Azure Login
  uses: azure/login@v1
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

- name: Deploy to Databricks
  env:
    DATABRICKS_HOST: ${{ secrets.DATABRICKS_HOST }}
  run: databricks bundle deploy -t prod
```

---

## 🧪 Testing Strategies

### Unit Tests (Local)
```python
# tests/test_transformations.py
import pytest
from pyspark.sql import SparkSession
from chispa import assert_df_equality
from src.transformations import clean_customer_data

@pytest.fixture(scope="session")
def spark():
    return SparkSession.builder \
        .master("local[*]") \
        .appName("unit-tests") \
        .getOrCreate()

def test_clean_customer_data(spark):
    # Arrange
    input_data = [(1, "John Doe", "john@test.com", "2026-01-01")]
    input_df = spark.createDataFrame(input_data, ["id", "name", "email", "signup_date"])
    
    expected_data = [(1, "JOHN DOE", "john@test.com", "2026-01-01")]
    expected_df = spark.createDataFrame(expected_data, ["id", "name", "email", "signup_date"])
    
    # Act
    result_df = clean_customer_data(input_df)
    
    # Assert
    assert_df_equality(result_df, expected_df)
```

```bash
# Run unit tests
pytest tests/ -v --cov=src --cov-report=html
```

### Integration Tests (On Databricks)
```python
# tests/integration/test_pipeline.py
import pytest
from databricks.sdk import WorkspaceClient

@pytest.fixture
def workspace():
    return WorkspaceClient()

def test_pipeline_end_to_end(workspace):
    # Run the job
    run = workspace.jobs.run_now(job_id=12345)
    
    # Wait for completion
    result = workspace.jobs.wait_get_run_output(run.run_id).result
    
    # Validate output table
    df = spark.table("catalog.schema.output_table")
    assert df.count() > 0
    assert "expected_column" in df.columns
```

### Data Quality Tests
```yaml
# resources/dlt_expectations.yml
expectations:
  bronze_events:
    - name: "valid_event_id"
      constraint: "event_id IS NOT NULL"
      action: "drop"
    
    - name: "valid_timestamp"
      constraint: "event_timestamp > '2020-01-01'"
      action: "quarantine"
```

---

## 🚀 GitHub Actions Workflows

### Complete CI/CD Pipeline
```yaml
# .github/workflows/ci-cd.yml
name: Databricks CI/CD

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

env:
  DATABRICKS_HOST: ${{ secrets.DATABRICKS_HOST }}

jobs:
  # ============ CI Jobs ============
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: pip install ruff black mypy
      
      - name: Lint with ruff
        run: ruff check src/
      
      - name: Format check with black
        run: black --check src/
      
      - name: Type check with mypy
        run: mypy src/

  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          pip install pytest pytest-cov chispa pyspark
      
      - name: Run unit tests
        run: pytest tests/unit -v --cov=src

  validate-bundle:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Databricks CLI
        uses: databricks/setup-cli@main
      
      - name: Validate bundle
        env:
          DATABRICKS_TOKEN: ${{ secrets.DATABRICKS_TOKEN }}
        run: databricks bundle validate -t prod

  # ============ CD Jobs ============
  deploy-dev:
    needs: [lint, unit-tests, validate-bundle]
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    environment: development
    steps:
      - uses: actions/checkout@v4
      - uses: databricks/setup-cli@main
      
      - name: Deploy to Dev
        env:
          DATABRICKS_TOKEN: ${{ secrets.DATABRICKS_TOKEN_DEV }}
          DATABRICKS_HOST: ${{ secrets.DATABRICKS_HOST_DEV }}
        run: databricks bundle deploy -t dev
      
      - name: Run integration tests
        run: databricks bundle run integration_tests -t dev

  deploy-staging:
    needs: [lint, unit-tests, validate-bundle]
    if: github.ref == 'refs/heads/develop'
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v4
      - uses: databricks/setup-cli@main
      
      - name: Deploy to Staging
        env:
          DATABRICKS_TOKEN: ${{ secrets.DATABRICKS_TOKEN_STAGE }}
          DATABRICKS_HOST: ${{ secrets.DATABRICKS_HOST_STAGE }}
        run: databricks bundle deploy -t staging

  deploy-production:
    needs: [lint, unit-tests, validate-bundle]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      - uses: databricks/setup-cli@main
      
      - name: Deploy to Production
        env:
          DATABRICKS_TOKEN: ${{ secrets.DATABRICKS_TOKEN_PROD }}
          DATABRICKS_HOST: ${{ secrets.DATABRICKS_HOST_PROD }}
        run: databricks bundle deploy -t prod
```

---

## 🔷 Azure DevOps Pipeline

```yaml
# azure-pipelines.yml
trigger:
  branches:
    include:
      - main
      - develop

variables:
  - group: databricks-credentials

stages:
  - stage: CI
    jobs:
      - job: Validate
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: UsePythonVersion@0
            inputs:
              versionSpec: '3.11'
          
          - script: |
              pip install databricks-cli
              databricks bundle validate -t prod
            displayName: 'Validate Bundle'
            env:
              DATABRICKS_HOST: $(DATABRICKS_HOST)
              DATABRICKS_TOKEN: $(DATABRICKS_TOKEN)

  - stage: DeployStaging
    dependsOn: CI
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/develop'))
    jobs:
      - deployment: DeployToStaging
        environment: staging
        strategy:
          runOnce:
            deploy:
              steps:
                - script: databricks bundle deploy -t staging
                  env:
                    DATABRICKS_HOST: $(DATABRICKS_HOST_STAGE)
                    DATABRICKS_TOKEN: $(DATABRICKS_TOKEN_STAGE)

  - stage: DeployProduction
    dependsOn: CI
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - deployment: DeployToProduction
        environment: production
        strategy:
          runOnce:
            deploy:
              steps:
                - script: databricks bundle deploy -t prod
                  env:
                    DATABRICKS_HOST: $(DATABRICKS_HOST_PROD)
                    DATABRICKS_TOKEN: $(DATABRICKS_TOKEN_PROD)
```

---

## 📋 Best Practices Checklist

| Practice | Description |
|----------|-------------|
| ✅ Branch protection | Require PR reviews for main branch |
| ✅ Environment isolation | Separate workspaces for dev/stage/prod |
| ✅ Service principals | Use SPs instead of user tokens |
| ✅ OIDC authentication | Avoid storing secrets when possible |
| ✅ Automated testing | Unit, integration, and data quality tests |
| ✅ Bundle validation | Validate DABs before deployment |
| ✅ Rollback strategy | Version deployments for quick rollback |
| ✅ Deployment gates | Manual approval for production |
| ✅ Secrets management | Use Azure Key Vault / AWS Secrets Manager |
| ✅ Audit trail | Log all deployments with commit hashes |

---

*Last updated: 2026-01-31*
