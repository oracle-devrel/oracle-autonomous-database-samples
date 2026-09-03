# Terraform — Oracle Autonomous Database with Database Tools

Creates an Autonomous Database and configures all tools supported by the
`db_tools_details` block:

| Terraform name | OCI Console name |
|---|---|
| `MONGODB_API` | MongoDB API |
| `APEX` | Oracle APEX |
| `DATABASE_ACTIONS` | Database Actions |
| `ORDS` | Web Access (ORDS) |
| `DLA` | Data Lake Accelerator |
| `DATA_TRANSFORMS` | Data Transforms |
| `GRAPH_STUDIO` | Graph Studio |
| `OML` | Oracle Machine Learning UI |

The `db_tools` variable is a map keyed by these names. All tools are disabled
by default: explicitly set `is_enabled = true` only for the tools required by
your workload. Adjust `compute_count` and `max_idle_time_in_minutes` for tools
that use dedicated compute.

`ORDS` (Web Access) is a dependency: enable it whenever you enable `APEX`,
`DATABASE_ACTIONS`, or `MONGODB_API`.

ECPU and maximum idle-time values are sent to OCI only for enabled tools. This
is required because OCI rejects those settings when the corresponding tool is
disabled.

This example uses a public endpoint protected by `acl_allowed_cidrs`. ADB
Database Tools, including the MongoDB API, require an ACL or private endpoint.
For a private endpoint pattern, see `../adb_from_subnet_private_endpoint`.

## Files

| File | Description |
|---|---|
| `main.tf` | ADB resource and the dynamic `db_tools_details` blocks |
| `variables.tf` | Credentials, ADB settings, ACL, and tool configuration |
| `outputs.tf` | ADB, tool configuration, and MongoDB API URL outputs |
| `versions.tf` | Terraform and OCI provider requirements |
| `provider.tf` | OCI provider configuration |
| `terraform.tfvars` | Values to update for your environment |

## Quick Start

```bash
# 1. Edit terraform.tfvars with your actual OCI credentials and values.
terraform init
terraform plan
terraform apply
```

## Enable only MongoDB API

Add this to `terraform.tfvars` to disable all the other tools:

```hcl
db_tools = {
  MONGODB_API = { is_enabled = true, compute_count = 0, max_idle_time_in_minutes = 0 }
  APEX        = { is_enabled = false, compute_count = 0, max_idle_time_in_minutes = 0 }
  DATABASE_ACTIONS = { is_enabled = false, compute_count = 0, max_idle_time_in_minutes = 0 }
  ORDS             = { is_enabled = true, compute_count = 0, max_idle_time_in_minutes = 0 }
  DLA              = { is_enabled = false, compute_count = 0, max_idle_time_in_minutes = 0 }
  DATA_TRANSFORMS  = { is_enabled = false, compute_count = 0, max_idle_time_in_minutes = 0 }
  GRAPH_STUDIO     = { is_enabled = false, compute_count = 0, max_idle_time_in_minutes = 0 }
  OML              = { is_enabled = false, compute_count = 0, max_idle_time_in_minutes = 0 }
}
```
