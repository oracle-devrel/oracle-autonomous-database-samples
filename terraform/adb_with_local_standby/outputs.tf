output "adb_id" { value = oci_database_autonomous_database.primary.id }

output "local_standby_db" {
  value = oci_database_autonomous_database.primary.local_standby_db
}

