# ============================================================
# outputs.tf — Values exported after apply
# ============================================================

output "adb_id" {
  description = "OCID of the created Autonomous Database"
  value       = oci_database_autonomous_database.adb.id
}

output "adb_acl_rules" {
  description = "IPs and CIDRs configured in the ADB ACL"
  value       = oci_database_autonomous_database.adb.whitelisted_ips
}

output "adb_mtls_required" {
  description = "Indicates whether mTLS is required for connections"
  value       = oci_database_autonomous_database.adb.is_mtls_connection_required
}
