# Terraform — Oracle Autonomous Database with Public Endpoint and ACLs

Creates an Autonomous Database (ADB) with a public endpoint and ACLs.

## Files

| File | Description |
|---|---|
| `main.tf` | Main ADB resource |
| `variables.tf` | All configurable parameters |
| `outputs.tf` | Values exported after apply |
| `versions.tf` | Terraform and provider version requirements |
| `provider.tf` | OCI provider configuration |
| `terraform.tfvars` | Your actual values |

## Quick Start

```bash
# 1. Edit terraform.tfvars with your real values:
#    (tenancy_ocid, user_ocid, fingerprint, private_key_path, ACLs, etc.)

# 2. Initialize Terraform
terraform init

# 3. Review the plan before applying
terraform plan

# 4. Create the ADB
terraform apply
```