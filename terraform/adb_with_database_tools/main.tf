# ============================================================
# main.tf — Autonomous Database with Database Tools
# ============================================================

resource "oci_database_autonomous_database" "adb" {
  compartment_id           = var.compartment_ocid
  display_name             = var.adb_display_name
  db_name                  = var.adb_db_name
  admin_password           = var.adb_admin_password
  db_workload              = var.adb_workload_type
  db_version               = var.adb_db_version
  compute_model            = "ECPU"
  compute_count            = var.adb_ecpu_count
  data_storage_size_in_tbs = var.adb_storage_tbs
  is_auto_scaling_enabled  = var.adb_auto_scaling

  # Database Tools, including MongoDB API, require an ACL or a private endpoint.
  # This example uses a public endpoint protected by the ACL below.
  whitelisted_ips             = var.acl_allowed_cidrs
  is_mtls_connection_required = var.require_mtls

  # The valid tool names are: MONGODB_API, APEX, DATABASE_ACTIONS, ORDS,
  # DLA, DATA_TRANSFORMS, GRAPH_STUDIO, and OML.
  dynamic "db_tools_details" {
    for_each = var.db_tools

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
}
