# 🚀 Databricks Engineering Excellence

[![Databricks](https://img.shields.io/badge/Databricks-FF3621?style=for-the-badge&logo=databricks&logoColor=white)](https://databricks.com)
[![Terraform](https://img.shields.io/badge/Terraform-623CE4?style=for-the-badge&logo=terraform&logoColor=white)](https://terraform.io)
[![Delta Lake](https://img.shields.io/badge/Delta%20Lake-003366?style=for-the-badge&logo=delta&logoColor=white)](https://delta.io)

A comprehensive knowledge base for Databricks platform engineering featuring expert agent definitions, production-ready cheatsheets, and battle-tested examples.

---

## 📚 Table of Contents

- [Agent Definitions](#-agent-definitions)
- [Cheatsheets](#-cheatsheets)
- [Examples](#-examples)
- [Getting Started](#-getting-started)
- [Contributing](#-contributing)

---

## 🤖 Agent Definitions

Expert AI agents with 20+ years of combined experience in Databricks platform engineering.

| Agent | Expertise | Use Cases |
|-------|-----------|-----------|
| [**Databricks Admin**](agents/databricks-admin/AGENT.md) | Platform administration, Unity Catalog governance, security, IaC | Workspace setup, governance policies, infrastructure automation |
| [**Databricks Engineer**](agents/databricks-engineer/AGENT.md) | Data pipelines, Delta Lake, MLflow, performance optimization | ETL development, ML workflows, query optimization |

---

## 📋 Cheatsheets

Quick-reference guides covering all aspects of Databricks platform.

### Administration & Infrastructure
| Cheatsheet | Description |
|------------|-------------|
| [CLI Commands](cheatsheets/cli-commands.md) | Databricks CLI and REST API reference |
| [Unity Catalog Governance](cheatsheets/unity-catalog-governance.md) | Data governance and access control |
| [Infrastructure as Code](cheatsheets/infrastructure-as-code.md) | Terraform and DABs automation |
| [Cost Optimization](cheatsheets/cost-optimization.md) | Cost management strategies |
| [Security & Compliance](cheatsheets/security-compliance.md) | Security controls and audit |

### Development & Data Engineering
| Cheatsheet | Description |
|------------|-------------|
| [Delta Lake Optimization](cheatsheets/delta-lake-optimization.md) | Performance tuning and maintenance |
| [CI/CD Pipelines](cheatsheets/cicd-pipelines.md) | Deployment workflows |
| [MLflow & Model Registry](cheatsheets/mlflow-model-registry.md) | ML experiment tracking and serving |

---

## 💡 Examples

Production-ready templates and modules.

```
examples/
├── terraform/workspace-setup/    # Terraform workspace provisioning
├── dabs/pipeline-bundle/         # Databricks Asset Bundle template
└── notebooks/best-practice-templates/
```

---

## 🚀 Getting Started

### Prerequisites
- Databricks CLI installed (`pip install databricks-cli`)
- Terraform >= 1.0 (for IaC examples)
- Azure/AWS/GCP account with Databricks workspace

### Quick Start
```bash
# Clone the repository
git clone https://github.com/rammarapally/databricks-engineering.git
cd databricks-engineering

# Configure Databricks CLI
databricks configure --token

# Explore cheatsheets
cat cheatsheets/cli-commands.md
```

---

## 🤝 Contributing

Contributions are welcome! Please read our contributing guidelines before submitting PRs.

---

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

---

<p align="center">
  <i>Built with ❤️ for the Databricks community</i>
</p>
