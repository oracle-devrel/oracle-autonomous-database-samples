output "adb_id" {
  description = "OCID of the existing Autonomous Database"
  value       = oci_database_autonomous_database.adb.id
}

output "adb_state" {
  description = "Database lifecycle state"
  value       = oci_database_autonomous_database.adb.state
}

output "maintenance_window" {
  description = "Maintenance window reported by OCI"
  value       = oci_database_autonomous_database.adb.autonomous_database_maintenance_window
}

output "scheduled_maintenance_window" {
  description = "Pending maintenance window reported by OCI"
  value       = oci_database_autonomous_database.adb.scheduled_maintenance_window
}

output "time_scheduled_maintenance_window_update" {
  description = "Time OCI reports for the window change operation"
  value       = oci_database_autonomous_database.adb.time_scheduled_maintenance_window_update
}
