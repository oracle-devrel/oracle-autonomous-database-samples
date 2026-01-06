resource "oci_database_autonomous_database" "primary" {
  provider = oci.primary

  compartment_id = var.compartment_ocid

  display_name = var.adb_display_name
  db_name      = var.adb_db_name

  db_workload            = var.db_workload
  compute_model          = var.compute_model
  compute_count          = var.compute_count
  data_storage_size_in_tbs = var.data_storage_size_in_tbs

  admin_password = var.admin_password
}

# Cross-region standby (Autonomous Data Guard)
resource "oci_database_autonomous_database" "standby" {
  provider = oci.standby

  compartment_id = var.compartment_ocid

  # Create standby in another region:
  source    = "CROSS_REGION_DATAGUARD"
  source_id = oci_database_autonomous_database.primary.id

  display_name = "${var.adb_display_name}-standby"
  db_name = oci_database_autonomous_database.primary.db_name

  depends_on = [oci_database_autonomous_database.primary]
}

