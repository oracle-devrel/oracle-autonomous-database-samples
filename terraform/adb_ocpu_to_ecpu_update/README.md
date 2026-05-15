# Terraform — Migrate Autonomous Database from OCPU to ECPU

Migrates an existing Autonomous Database (ADB) from the OCPU compute model to the ECPU compute model. Supports all workload types: ATP, ADW, AJD, and APEX.

## Files

| File | Description |
|---|---|
| `main.tf` | ADB resource with ECPU compute model configuration |
| `variables.tf` | All configurable parameters |
| `outputs.tf` | Values exported after apply |
| `versions.tf` | Terraform and provider version requirements |
| `provider.tf` | OCI provider configuration |
| `terraform.tfvars` | Your actual values |

## Quick Start

```bash
# 1. Edit terraform.tfvars with your real values
#    (tenancy_ocid, user_ocid, fingerprint, private_key_path, adb_ocid, etc.)

# 2. Initialize Terraform
terraform init

# 3. Import the existing ADB into the Terraform state
terraform import oci_database_autonomous_database.adb <ADB_OCID>

# 4. Review the plan before applying
terraform plan

# 5. Apply the migration
terraform apply
```

## Variables

| Variable | Description | Default |
|---|---|---|
| `tenancy_ocid` | OCID of the OCI tenancy | — |
| `user_ocid` | OCID of the OCI user | — |
| `fingerprint` | Fingerprint of the API key | — |
| `private_key_path` | Path to the private key file (.pem) | — |
| `region` | OCI region where the ADB resides | — |
| `compartment_ocid` | OCID of the compartment where the ADB resides | — |
| `adb_display_name` | Display name in the OCI console | — |
| `adb_db_name` | Technical database name (max 14 chars) | — |
| `adb_admin_password` | ADMIN password — not used during migration (see note below) | — |
| `adb_workload_type` | Workload type: `OLTP`, `DW`, `AJD`, `APEX` | — |
| `adb_cpu_core_count` | Number of ECPUs (min 2, multiples of 2) | `2` |
| `adb_storage_tbs` | Storage in terabytes | `1` |
| `adb_auto_scaling` | Enable ECPU auto-scaling | `false` |

## Outputs

| Output | Description |
|---|---|
| `adb_id` | OCID of the Autonomous Database |
| `compute_model` | Compute model after migration (`ECPU`) |
| `compute_count` | Number of ECPUs assigned |
| `adb_state` | Current lifecycle state of the ADB |

## Notes

- **terraform import:** The database already exists, so it must be imported into the Terraform state before applying. Without this step, `terraform apply` would try to create a new database instead of updating the existing one.
- **admin_password:** The `lifecycle { ignore_changes = [admin_password] }` block is set in `main.tf`. Terraform ignores this field during apply. The value in `terraform.tfvars` is required by the provider schema but has no effect on the migration.
- **ECPU count:** Minimum value is 2. Must be set in multiples of 2. Reference: 1 OCPU ≈ 2 ECPUs.
- **Workload types:** The migration works for all ADB workload types — ATP (`OLTP`), ADW (`DW`), AJD (`AJD`), and APEX.
