# ============================================================
# nsg.tf — Network Security Group for the ADB private endpoint
# ============================================================

# ── NSG ───────────────────────────────────────────────────────
resource "oci_core_network_security_group" "adb_nsg" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = var.nsg_display_name
}

# ── Ingress: SQL*Net / database connections (port 1521) ───────
resource "oci_core_network_security_group_security_rule" "ingress_sqlnet" {
  network_security_group_id = oci_core_network_security_group.adb_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP

  source      = var.vcn_cidr
  source_type = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 1521
      max = 1522
    }
  }

  description = "Allow SQL*Net database connections from within the VCN"
}

# ── Ingress: HTTPS / Database Actions and APEX (port 443) ────
resource "oci_core_network_security_group_security_rule" "ingress_https" {
  network_security_group_id = oci_core_network_security_group.adb_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP

  source      = var.vcn_cidr
  source_type = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }

  description = "Allow HTTPS traffic for Database Actions and APEX console"
}

# ── Egress: allow all outbound traffic ────────────────────────
resource "oci_core_network_security_group_security_rule" "egress_all" {
  network_security_group_id = oci_core_network_security_group.adb_nsg.id
  direction                 = "EGRESS"
  protocol                  = "all"

  destination      = "0.0.0.0/0"
  destination_type = "CIDR_BLOCK"

  description = "Allow all outbound traffic"
}
