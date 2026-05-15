# ============================================================
# outputs.tf — Values exported after apply
# ============================================================

output "adb_id" {
  description = "OCID of the Autonomous Database"
  value       = oci_database_autonomous_database.adb.id
}

output "compute_model" {
  description = "Compute model in use after migration (ECPU)"
  value       = oci_database_autonomous_database.adb.compute_model
}

output "compute_count" {
  description = "Number of ECPUs assigned after migration"
  value       = oci_database_autonomous_database.adb.compute_count
}

output "adb_state" {
  description = "Current lifecycle state of the Autonomous Database"
  value       = oci_database_autonomous_database.adb.state
}
