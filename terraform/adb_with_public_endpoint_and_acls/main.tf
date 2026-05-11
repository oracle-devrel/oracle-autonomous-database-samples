# ============================================================
# main.tf — Autonomous Database with public endpoint and ACLs
# ============================================================

# ============================================================
# Autonomous Database
# ============================================================

resource "oci_database_autonomous_database" "adb" {
  compartment_id           = var.compartment_ocid
  display_name             = var.adb_display_name
  db_name                  = var.adb_db_name
  admin_password           = var.adb_admin_password
  db_workload              = var.adb_workload_type   # OLTP | DW | AJD | APEX
  db_version               = var.adb_db_version
  compute_model            = var.adb_compute_model
  compute_count            = var.adb_cpu_core_count
  data_storage_size_in_tbs = var.adb_storage_tbs
  is_auto_scaling_enabled  = var.adb_auto_scaling

  # ── Public endpoint with ACL-controlled access ───────────
  # "RESTRICTED"   = public endpoint + mandatory ACLs
  # "UNRESTRICTED" = public endpoint without ACLs (not recommended)
  # "PRIVATE"      = private endpoint inside VCN
  whitelisted_ips = var.acl_allowed_cidrs

  # mTLS: false = allows standard TLS connections (more flexible)
  #        true  = requires client certificate (more secure)
  is_mtls_connection_required = var.require_mtls
}
