output "primary_adb_id" {
  value = oci_database_autonomous_database.primary.id
}

output "standby_adb_id" {
  value = oci_database_autonomous_database.standby.id
}

