# ============================================================
# vcn.tf — Virtual Cloud Network and private subnet
# ============================================================

# ── VCN ──────────────────────────────────────────────────────
resource "oci_core_vcn" "vcn" {
  compartment_id = var.compartment_ocid
  display_name   = var.vcn_display_name
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = var.vcn_dns_label
}

# ── Internet Gateway (required for HTTPS outbound from subnet) ──
resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "${var.vcn_display_name}-igw"
  enabled        = true
}

# ── Route Table ───────────────────────────────────────────────
resource "oci_core_route_table" "rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "${var.vcn_display_name}-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

# ── Private Subnet ────────────────────────────────────────────
resource "oci_core_subnet" "private_subnet" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.vcn.id
  display_name               = var.subnet_display_name
  cidr_block                 = var.subnet_cidr
  dns_label                  = var.subnet_dns_label
  prohibit_public_ip_on_vnic = true   # private subnet — no public IPs
  route_table_id             = oci_core_route_table.rt.id
  security_list_ids          = [oci_core_vcn.vcn.default_security_list_id]
}
