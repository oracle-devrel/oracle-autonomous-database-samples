# ============================================================
# outputs.tf — Values exported after apply
# ============================================================

# ── VCN ──────────────────────────────────────────────────────
output "vcn_id" {
  description = "OCID of the created VCN"
  value       = oci_core_vcn.vcn.id
}

output "subnet_id" {
  description = "OCID of the private subnet"
  value       = oci_core_subnet.private_subnet.id
}

output "nsg_id" {
  description = "OCID of the Network Security Group"
  value       = oci_core_network_security_group.adb_nsg.id
}

# ── ADB ───────────────────────────────────────────────────────
output "adb_id" {
  description = "OCID of the created Autonomous Database"
  value       = oci_database_autonomous_database.adb.id
}

output "adb_private_endpoint" {
  description = "Private endpoint IP address of the ADB"
  value       = oci_database_autonomous_database.adb.private_endpoint_ip
}
