<h1 align="center">Automated Backup System</h1>

<p align="center">
  <b>Centralized and automated disaster recovery infrastructure in AWS built with Terraform and GitHub Actions.</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white" alt="Terraform">
  <img src="https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white" alt="AWS">
  <img src="https://img.shields.io/badge/GitHub%20Actions-%2320232a.svg?style=for-the-badge&logo=githubactions&logoColor=white" alt="GitHub Actions">
  <img src="https://img.shields.io/badge/Bash-%234EAA25.svg?style=for-the-badge&logo=gnu-bash&logoColor=white" alt="Bash">
  <img src="https://img.shields.io/badge/TFLint-%233776AB.svg?style=for-the-badge&logo=tflint&logoColor=white" alt="TFLint">
  <img src="https://img.shields.io/badge/Checkov-%23000000.svg?style=for-the-badge&logo=checkov&logoColor=white" alt="Checkov">
</p>

---

<p align="center">
  <img src="./assets/p2-aws-lm-def (1).svg" alt="Light Mode Architecture Diagram" width="100%">
</p>
<p align="center">
  <img src="./assets/p2-aws-dm-def (1).svg" alt="Dark Mode Architecture Diagram" width="100%">
</p>

---

## 🎥 Video Demo & Walkthrough

Click on the image below to watch the full demonstration and technical explanation of the project on YouTube:

[![Watch the video](https://img.youtube.com/vi/rF1hhSFqJtg/hqdefault.jpg)](https://youtu.be/rF1hhSFqJtg)

---

## Overview
This repository provisions a fully automated, centralized, and immutable disaster recovery infrastructure in AWS using Terraform and GitHub Actions. It enforces compliance and ransomware protection through AWS Backup Vault Lock (WORM model) and implements zero-trust authentication via OpenID Connect (OIDC).

The architecture includes a sample multi-tier workload (EC2, RDS PostgreSQL, and S3) deployed within an isolated VPC using AWS PrivateLink (VPC Endpoints) and encrypted via Customer Managed KMS Keys.

## Key Features
* **GitOps & Zero-Trust CI/CD:** Automated provisioning via GitHub Actions. Uses OIDC to assume AWS roles, eliminating static credentials (`AWS_ACCESS_KEY_ID`).
* **Security & Quality Scanning:** Infrastructure code is validated by **TFLint** (for syntax, provider rules, and logic) & **Checkov** (for security compliance) during the CI pipeline to prevent provisioning insecure resources.
* **Centralized Backup Orchestration:** Dynamic resource assignment. AWS Backup automatically protects any resource in the account carrying the `Backup = "true"` tag.
* **Ransomware Protection (WORM):** AWS Backup Vault Lock is configured in Compliance mode. Backups cannot be encrypted, altered, or deleted prematurely by any user, including the root account.
* **Automated Restore Simulations:** Weekly automated restore testing in isolated environments to validate RTO and RPO metrics.
* **Observability & Auditing:** Real-time alerting for backup/restore job state changes via Amazon EventBridge and SNS. Continuous compliance validation using AWS Config.

## Repository Structure
```text
/
├── .github/workflows/      # GitHub Actions pipeline definition
├── assets/                 # Architecture diagrams and visual media
├── bootstrap/              # Initial state backend and OIDC configuration
│   ├── main.tf
│   ├── providers.tf
│   └── variables.tf
├── ops/
│   └── trigger-backups.sh  # Asynchronous backup execution script
├── .gitignore
├── .terraform.lock.hcl
├── .tflint.hcl             # TFLint configuration and AWS ruleset
├── LICENSE
├── README.md
├── audit.tf                # AWS Config and Compliance framework
├── iam.tf                  # Service roles and KMS policies
├── main.tf                 # Backup vault, plan, and lock configuration
├── notifications.tf        # EventBridge and SNS alerting
├── providers.tf            # Remote backend configuration
├── setup.sh                # Zero-touch provisioning orchestration script
├── teardown.sh             # Automated teardown script
├── terraform.tfvars.example # Environment variables template
├── variables.tf
└── workload.tf             # EC2, RDS, S3 workloads and isolated VPC network
````

Prerequisites
-
AWS Account with Administrator access.

AWS CLI installed and configured locally.

Terraform (>= 1.5.0) installed locally.

TFLint installed locally (optional, for local linting).

GitHub repository to host this code.

GitHub CLI (```gh```) installed and authenticated locally.


Deployment Instructions
-
> **1. Fork and Clone the Repository**

Since this project uses GitHub Actions with OIDC for automated deployment, you must host the code in your own GitHub repository.

Go to the top right of this repository page and click the Fork button to copy this project to your own GitHub account.

Clone your newly created fork onto your local machine:

```
git clone https://github.com/YOUR_GITHUB_USERNAME/YOUR_REPOSITORY_NAME.git
cd YOUR_REPOSITORY_NAME
```
**2. Configure Variables**

Copy the example variables file and populate it with your specific environment data. This file is ignored by Git to protect sensitive configurations.

```
cp terraform.tfvars.example terraform.tfvars
```
Edit ```terraform.tfvars``` with your specific AWS region, project name, GitHub organization/username, repository name, notification email, and retention policies.

> **3. Authenticate CLIs**

Ensure your terminal session has active credentials for both AWS and GitHub.

```
# Verify AWS authentication
aws sts get-caller-identity

# Authenticate GitHub CLI (Select HTTPS/SSH and login via browser/token)
gh auth login
```
> **4. Execute Zero-Touch Provisioning**
Run the platform orchestration script. This script will automatically provision the S3 backend and DynamoDB lock tables, configure the AWS OIDC provider, inject all required secrets and variables into your GitHub repository, and trigger the GitHub Actions pipeline.

```
chmod +x setup.sh
./setup.sh
```
> **5. Monitor CI/CD Pipeline**
Once the script completes, control is transferred to GitHub Actions. Navigate to the Actions tab in your GitHub repository to monitor the static code analysis (TFLint and Checkov) and the final infrastructure provisioning (taking approximately 15 minutes).

> **6. Operational Testing**
By default, backups execute automatically via scheduled cron jobs. To force an immediate backup of the infrastructure (S3, EC2, RDS) for testing or demonstration purposes without accessing the AWS Console, execute the operations script:

```
cd ops
chmod +x trigger-backups.sh
./trigger-backups.sh
```
Check your configured email inbox. You will receive an initial SNS subscription confirmation (which must be accepted manually) and subsequent EventBridge alerts as each asynchronous backup job transitions to a ```COMPLETED``` state.

> [!CAUTION]
> **Important: Teardown & Irreversible Costs (Vault Lock)**
> This project configures AWS Backup Vault Lock in Compliance Mode. This enforces true WORM immutability at the infrastructure level to protect against ransomware.

> [!WARNING]
> * Once deployed, neither the account administrator nor the AWS root user can delete the Backup Vault or its recovery points until the `vault_lock_min_retention_days` period expires.
> * Running a standard `terraform destroy` directly will fail when attempting to delete the Backup Vault due to API access denial.

Automated Teardown Process
To safely remove state tracking of locked resources, stop billing for high-cost compute/database resources (EC2, RDS, VPC), and clean up the environment, run the automated teardown script from the root of the project:

```
chmod +x teardown.sh
./teardown.sh
```
What this script does automatically:

Dynamically detects your AWS account ID, region, and project configuration.

Initializes the remote Terraform backend dynamically.

Unbinds (```terraform state rm```) the immutable backup vault and lock configurations from the state tracking.

Destroys the remaining workload resources (```terraform destroy```).

Destroys the bootstrap infrastructure (S3 backend and OIDC roles).

> [!NOTE]
>  You will continue to be billed for the Backup Vault's underlying storage costs until the retention period expires, at which point you can delete the vault manually via the AWS Management Console.
