# ============================================================
# main.tf — Update Database Tools on an existing ADB
# ============================================================

# Import the existing ADB before applying this configuration:
# terraform import oci_database_autonomous_database.adb <autonomous_database_ocid>
data "oci_database_autonomous_database" "current" {
  autonomous_database_id = var.autonomous_database_ocid
}

locals {
  # Preserve every current tool setting unless it is explicitly overridden in
  # var.db_tools. OCI updates the tool list as a whole, not as individual tools.
  current_db_tools = {
    for tool in data.oci_database_autonomous_database.current.db_tools_details :
    tool.name => {
      is_enabled               = tool.is_enabled
      compute_count            = tool.compute_count
      max_idle_time_in_minutes = tool.max_idle_time_in_minutes
    }
  }

  effective_db_tools = merge(local.current_db_tools, var.db_tools)
}

resource "oci_database_autonomous_database" "adb" {
  # These two values must match the existing ADB.
  compartment_id = var.compartment_ocid
  db_name        = var.adb_db_name

  # The current tool state is read above; only entries in var.db_tools override it.
  dynamic "db_tools_details" {
    for_each = local.effective_db_tools

    content {
      name       = db_tools_details.key
      is_enabled = db_tools_details.value.is_enabled

      # OCI rejects compute and idle-time settings for disabled tools.
      compute_count = db_tools_details.value.is_enabled ? db_tools_details.value.compute_count : null
      max_idle_time_in_minutes = db_tools_details.value.is_enabled ? (
        db_tools_details.value.max_idle_time_in_minutes
      ) : null
    }
  }

  # This module manages tool configuration only. Do not allow a destroy of an
  # existing database from this example. Existing ACLs are intentionally not
  # managed here because OCI does not allow ACL and tool updates together.
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [whitelisted_ips]

    precondition {
      condition = alltrue([
        for name in ["APEX", "DATABASE_ACTIONS", "MONGODB_API"] :
        !try(local.effective_db_tools[name].is_enabled, false) || try(local.effective_db_tools["ORDS"].is_enabled, false)
      ])
      error_message = "Enable ORDS before enabling APEX, DATABASE_ACTIONS, or MONGODB_API."
    }
  }
}
