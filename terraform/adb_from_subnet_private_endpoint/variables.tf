# ============================================================
# variables.tf — Configurable parameters
# ============================================================

# ── OCI Credentials ──────────────────────────────────────────
variable "tenancy_ocid" {
  description = "OCID of the Oracle Cloud tenancy"
  type        = string
}

variable "user_ocid" {
  description = "OCID of the OCI user"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the user's API key"
  type        = string
}

variable "private_key_path" {
  description = "Path to the private key file (.pem)"
  type        = string
}

variable "region" {
  description = "OCI region where the resources will be created"
  type        = string
  default     = "us-ashburn-1"
}

variable "compartment_ocid" {
  description = "OCID of the compartment where resources will be created"
  type        = string
}

# ── VCN ──────────────────────────────────────────────────────
variable "vcn_display_name" {
  description = "Display name for the VCN"
  type        = string
  default     = "adb-vcn"
}

variable "vcn_cidr" {
  description = "CIDR block for the VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vcn_dns_label" {
  description = "DNS label for the VCN (lowercase letters and numbers only)"
  type        = string
  default     = "adbvcn"
}

# ── Subnet ────────────────────────────────────────────────────
variable "subnet_display_name" {
  description = "Display name for the private subnet"
  type        = string
  default     = "adb-private-subnet"
}

variable "subnet_cidr" {
  description = "CIDR block for the private subnet (must be within the VCN CIDR)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_dns_label" {
  description = "DNS label for the subnet (lowercase letters and numbers only)"
  type        = string
  default     = "adbsubnet"
}

# ── NSG ───────────────────────────────────────────────────────
variable "nsg_display_name" {
  description = "Display name for the Network Security Group"
  type        = string
  default     = "adb-nsg"
}

# ── ADB Configuration ─────────────────────────────────────────
variable "adb_display_name" {
  description = "Display name in the OCI console"
  type        = string
}

variable "adb_db_name" {
  description = "Technical database name (letters/numbers only, max 14 chars)"
  type        = string
}

variable "adb_admin_password" {
  description = "ADMIN user password (min 12 chars, uppercase, number and symbol required)"
  type        = string
  sensitive   = true
}

variable "adb_workload_type" {
  description = "Workload type: OLTP (ATP), DW (ADW), AJD (JSON), APEX"
  type        = string
  default     = "OLTP"

  validation {
    condition     = contains(["OLTP", "DW", "AJD", "APEX"], var.adb_workload_type)
    error_message = "Must be one of: OLTP, DW, AJD, APEX."
  }
}

variable "adb_db_version" {
  description = "Oracle database version"
  type        = string
  default     = "26ai"
}

variable "adb_compute_model" {
  description = "Compute model for the ADB (ECPU is required for new databases)"
  type        = string
  default     = "ECPU"
}

variable "adb_cpu_core_count" {
  description = "Number of ECPUs (minimum 2 in ECPU model)"
  type        = number
  default     = 2
}

variable "adb_storage_tbs" {
  description = "Storage in terabytes (minimum 1)"
  type        = number
  default     = 1
}

variable "adb_auto_scaling" {
  description = "Enable ECPU auto-scaling (up to 3x the configured value)"
  type        = bool
  default     = false
}

variable "adb_private_endpoint_label" {
  description = "Label for the ADB private endpoint (used as DNS hostname within the VCN)"
  type        = string
  default     = "adbprivate"
}

# ── Connection security ───────────────────────────────────────
variable "require_mtls" {
  description = "Require mutual TLS authentication (mTLS). false = standard TLS"
  type        = bool
  default     = false
}