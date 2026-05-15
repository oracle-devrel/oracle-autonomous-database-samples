# ============================================================
# main.tf — Migrate Autonomous Database from OCPU to ECPU
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
  data_storage_size_in_tbs = var.adb_storage_tbs
  is_auto_scaling_enabled  = var.adb_auto_scaling

  # ── Compute model migration ───────────────────────────────
  # Changing from OCPU to ECPU triggers a brief DB restart (~2-5 min)
  # ECPU minimum is 2, must be set in multiples of 2
  compute_model = "ECPU"
  compute_count = var.adb_cpu_core_count

  lifecycle {
    ignore_changes = [admin_password]
  }
}
