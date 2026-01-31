# Databricks CLI & REST API Commands Cheatsheet

Quick reference for Databricks CLI and REST API operations.

---

## 🔧 CLI Installation & Configuration

```bash
# Install Databricks CLI (latest v2)
pip install databricks-cli

# Configure with token
databricks configure --token
# Enter host: https://adb-xxxx.azuredatabricks.net
# Enter token: dapi...

# Configure with OAuth (recommended)
databricks configure --oauth

# Verify configuration
databricks auth env

# Multiple profiles
databricks configure --token --profile production
databricks clusters list --profile production
```

---

## 📁 Workspace Commands

```bash
# List workspace root
databricks workspace ls /

# List with details
databricks workspace ls /Users/user@company.com -l

# Import notebook
databricks workspace import ./local_notebook.py /Shared/notebooks/my_notebook -l PYTHON

# Export notebook
databricks workspace export /Shared/notebooks/my_notebook ./local_notebook.py -f SOURCE

# Recursive export
databricks workspace export_dir /Shared/notebooks ./local_folder

# Delete item
databricks workspace delete /Shared/notebooks/old_notebook

# Create directory
databricks workspace mkdirs /Shared/new_folder
```

---

## 🖥️ Cluster Commands

```bash
# List all clusters
databricks clusters list

# Get cluster details
databricks clusters get --cluster-id 0123-456789-abcdef

# Create cluster from JSON
databricks clusters create --json-file cluster_config.json

# Start cluster
databricks clusters start --cluster-id 0123-456789-abcdef

# Restart cluster
databricks clusters restart --cluster-id 0123-456789-abcdef

# Terminate cluster
databricks clusters delete --cluster-id 0123-456789-abcdef

# Permanent delete
databricks clusters permanent-delete --cluster-id 0123-456789-abcdef

# List cluster events
databricks clusters events --cluster-id 0123-456789-abcdef

# Edit cluster
databricks clusters edit --json-file updated_config.json
```

### Cluster Configuration JSON
```json
{
  "cluster_name": "my-cluster",
  "spark_version": "14.3.x-scala2.12",
  "node_type_id": "Standard_DS3_v2",
  "num_workers": 2,
  "autotermination_minutes": 30,
  "spark_conf": {
    "spark.databricks.delta.preview.enabled": "true"
  },
  "custom_tags": {
    "Environment": "Production",
    "CostCenter": "DataTeam"
  }
}
```

---

## 📋 Jobs Commands

```bash
# List all jobs
databricks jobs list

# Get job details
databricks jobs get --job-id 12345

# Create job
databricks jobs create --json-file job_config.json

# Run job now
databricks jobs run-now --job-id 12345

# Run with parameters
databricks jobs run-now --job-id 12345 --json '{"notebook_params":{"env":"prod"}}'

# Cancel run
databricks runs cancel --run-id 67890

# Get run output
databricks runs get-output --run-id 67890

# Delete job
databricks jobs delete --job-id 12345
```

---

## 📦 DBFS Commands

```bash
# List files
databricks fs ls dbfs:/mnt/data/

# Copy local to DBFS
databricks fs cp ./local_file.csv dbfs:/tmp/data.csv

# Copy DBFS to local
databricks fs cp dbfs:/tmp/data.csv ./local_file.csv

# Recursive copy
databricks fs cp -r ./local_folder dbfs:/mnt/folder/

# Move/Rename
databricks fs mv dbfs:/tmp/old_name.csv dbfs:/tmp/new_name.csv

# Delete file
databricks fs rm dbfs:/tmp/data.csv

# Recursive delete
databricks fs rm -r dbfs:/mnt/old_folder/

# Create directory
databricks fs mkdirs dbfs:/mnt/new_folder/

# View file content
databricks fs cat dbfs:/tmp/small_file.txt
```

---

## 🔐 Secrets Commands

```bash
# Create secret scope
databricks secrets create-scope --scope my-scope

# Create scope with Key Vault backend (Azure)
databricks secrets create-scope --scope kv-scope --scope-backend-type AZURE_KEYVAULT \
  --resource-id /subscriptions/.../resourceGroups/.../providers/Microsoft.KeyVault/vaults/my-vault \
  --dns-name https://my-vault.vault.azure.net/

# List scopes
databricks secrets list-scopes

# Put secret
databricks secrets put --scope my-scope --key my-secret-key --string-value "secret123"

# Put from file
databricks secrets put --scope my-scope --key my-key --binary-file ./secret.bin

# List secrets
databricks secrets list --scope my-scope

# Delete secret
databricks secrets delete --scope my-scope --key my-secret-key

# Manage ACLs
databricks secrets put-acl --scope my-scope --principal users --permission READ
databricks secrets list-acls --scope my-scope
```

---

## 🗃️ Unity Catalog Commands

```bash
# List catalogs
databricks catalogs list

# Create catalog
databricks catalogs create --name new_catalog

# Get catalog
databricks catalogs get --name my_catalog

# List schemas
databricks schemas list --catalog-name my_catalog

# Create schema
databricks schemas create --catalog-name my_catalog --name new_schema

# List tables
databricks tables list --catalog-name my_catalog --schema-name my_schema

# Get table
databricks tables get --full-name my_catalog.my_schema.my_table

# Grant permissions
databricks grants update --securable-type TABLE --full-name cat.schema.table \
  --json '{"changes": [{"principal": "users", "add": ["SELECT"]}]}'

# List grants
databricks grants get --securable-type TABLE --full-name cat.schema.table
```

---

## 🚀 REST API Examples

### Authentication
```bash
# Token-based authentication
curl -X GET "https://adb-xxx.azuredatabricks.net/api/2.0/clusters/list" \
  -H "Authorization: Bearer dapi_xxxx"

# OAuth token
curl -X GET "https://adb-xxx.azuredatabricks.net/api/2.0/clusters/list" \
  -H "Authorization: Bearer ${OAUTH_TOKEN}"
```

### Clusters API
```bash
# List clusters
curl -X GET "https://${DATABRICKS_HOST}/api/2.0/clusters/list" \
  -H "Authorization: Bearer ${TOKEN}"

# Create cluster
curl -X POST "https://${DATABRICKS_HOST}/api/2.0/clusters/create" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "cluster_name": "my-cluster",
    "spark_version": "14.3.x-scala2.12",
    "node_type_id": "Standard_DS3_v2",
    "num_workers": 2
  }'
```

### Jobs API
```bash
# Run a job
curl -X POST "https://${DATABRICKS_HOST}/api/2.1/jobs/run-now" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "job_id": 12345,
    "notebook_params": {"env": "prod", "date": "2026-01-31"}
  }'

# Get run status
curl -X GET "https://${DATABRICKS_HOST}/api/2.1/jobs/runs/get?run_id=67890" \
  -H "Authorization: Bearer ${TOKEN}"
```

### SQL Warehouse API
```bash
# List warehouses
curl -X GET "https://${DATABRICKS_HOST}/api/2.0/sql/warehouses" \
  -H "Authorization: Bearer ${TOKEN}"

# Start warehouse
curl -X POST "https://${DATABRICKS_HOST}/api/2.0/sql/warehouses/${WAREHOUSE_ID}/start" \
  -H "Authorization: Bearer ${TOKEN}"
```

---

## 📊 Python SDK Examples

```python
from databricks.sdk import WorkspaceClient

w = WorkspaceClient()

# List clusters
for c in w.clusters.list():
    print(f"{c.cluster_name}: {c.state}")

# Create job
from databricks.sdk.service.jobs import Task, NotebookTask

j = w.jobs.create(
    name="my-job",
    tasks=[
        Task(
            task_key="main-task",
            notebook_task=NotebookTask(
                notebook_path="/Shared/notebooks/main"
            ),
            existing_cluster_id="0123-456789-abcdef"
        )
    ]
)

# Run job
run = w.jobs.run_now(job_id=j.job_id)
print(f"Started run: {run.run_id}")
```

---

## 💡 Pro Tips

| Tip | Command |
|-----|---------|
| JSON output | `--output JSON` |
| Debug mode | `--debug` |
| Profile switching | `--profile prod` |
| Quiet mode | `-q` or `--quiet` |
| Version check | `databricks --version` |
| Help | `databricks <command> --help` |

---

*Last updated: 2026-01-31*
