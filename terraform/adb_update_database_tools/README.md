# Terraform — Update Database Tools on an Existing Autonomous Database

Imports an existing Autonomous Database into Terraform state and updates its
`db_tools_details` configuration. It does not create a database. The module has
`prevent_destroy = true` to protect the imported ADB from accidental deletion.

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

`ORDS` must be enabled before enabling `APEX`, `DATABASE_ACTIONS`, or
`MONGODB_API`. Declare only the tools you need to change: the example reads the
existing ADB configuration and preserves tools that are omitted from `db_tools`.

ECPU and maximum idle-time values are sent to OCI only for enabled tools. OCI
rejects those parameters when the associated tool is disabled.

> **MongoDB API network prerequisite:** Before enabling `MONGODB_API`, the
> existing ADB must already use an access control list (ACL) or a private
> endpoint. This example intentionally does not change ACL settings because OCI
> does not allow ACL and Database Tool updates in the same operation. The ACL or
> private endpoint requirement applies to MongoDB API, not to the other tools.

> **ORDS dependency:** Enable `ORDS` (Web Access) before enabling `APEX`,
> `DATABASE_ACTIONS`, or `MONGODB_API`. Enabling ORDS later does not
> automatically enable those dependent tools.

## Files

| File | Description |
|---|---|
| `main.tf` | Imported ADB resource and Database Tool configuration |
| `variables.tf` | Credentials, existing ADB, and tool settings |
| `outputs.tf` | ADB, tool configuration, and MongoDB API URL outputs |
| `versions.tf` | Terraform and OCI provider requirements |
| `provider.tf` | OCI provider configuration |
| `terraform.tfvars` | Values to update for your environment |

## Quick Start

1. Update `terraform.tfvars` with your OCI credentials, the ADB compartment,
   technical database name, ADB OCID, and the tools you want to change.

2. Initialize Terraform:

   ```bash
   terraform init
   ```

3. Import the existing ADB OCID into this example's state:

   ```bash
   terraform import oci_database_autonomous_database.adb <autonomous_database_ocid>
   ```

4. Review the update carefully, then apply it:

   ```bash
   terraform plan
   terraform apply
   ```

## Example: Enable MongoDB API on an Existing ADB

```hcl
db_tools = {
  MONGODB_API      = { is_enabled = true, compute_count = 0, max_idle_time_in_minutes = 0 }
  ORDS             = { is_enabled = true, compute_count = 0, max_idle_time_in_minutes = 0 }
}
```

For MongoDB API, the existing ADB must already have an ACL or private endpoint.

## Refresh the MongoDB API URL

After enabling MongoDB API on an existing ADB, the service can finish becoming
available after Terraform has calculated the initial outputs. If `mongo_db_url`
is empty after `terraform apply`, refresh the local Terraform state without
changing OCI resources:

```bash
terraform apply -refresh-only
terraform output -raw mongo_db_url
```
