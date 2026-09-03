# ============================================================
# outputs.tf — Values exported after apply
# ============================================================

output "adb_id" {
  description = "OCID of the managed Autonomous Database"
  value       = oci_database_autonomous_database.adb.id
}

output "database_tools" {
  description = "Database Tools configured on the Autonomous Database"
  value       = oci_database_autonomous_database.adb.db_tools_details
}

output "mongo_db_url" {
  description = "MongoDB API endpoint URL, when MongoDB API is enabled"
  value       = try(one(oci_database_autonomous_database.adb.connection_urls).mongo_db_url, null)
}
