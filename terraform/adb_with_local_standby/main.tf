resource "oci_database_autonomous_database" "primary" {
  compartment_id = var.compartment_ocid

  db_name      = var.db_name
  display_name = var.display_name
  db_workload  = var.db_workload

  admin_password           = var.admin_password
  compute_model            = var.compute_model
  compute_count            = var.compute_count
  data_storage_size_in_tbs = var.data_storage_tbs

  # Local (in-region) standby
  is_local_data_guard_enabled = true
}

