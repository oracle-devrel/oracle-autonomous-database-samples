# ============================================================
# main.tf — Autonomous Database with private endpoint
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

  # ── Private endpoint ──────────────────────────────────────
  # Removes the public endpoint — access only from within the VCN
  private_endpoint_label = var.adb_private_endpoint_label
  subnet_id              = oci_core_subnet.private_subnet.id
  nsg_ids                = [oci_core_network_security_group.adb_nsg.id]

  # mTLS: false = allows standard TLS connections (more flexible)
  #        true  = requires client certificate (more secure)
  is_mtls_connection_required = var.require_mtls
}
