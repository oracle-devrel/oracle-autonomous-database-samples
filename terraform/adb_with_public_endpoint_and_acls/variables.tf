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
  description = "OCI region where the ADB will be created"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID of the compartment where the ADB will be created"
  type        = string
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
  description = "Enable ECPU auto-scaling"
  type        = bool
  default     = false
}

# ── ACLs: IP-based access control ────────────────────────────
variable "acl_allowed_cidrs" {
  description = <<-EOT
    List of allowed IPs or CIDR ranges for connecting to the ADB.
    Also accepts VCN OCIDs in the format: ocid1.vcn.oc1...
    Examples:
      - "203.0.113.50"       → individual IP
      - "203.0.113.0/24"     → network range
      - "ocid1.vcn.oc1...."  → full OCI VCN
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.acl_allowed_cidrs) > 0
    error_message = "You must specify at least one IP or CIDR in acl_allowed_cidrs to protect the public endpoint."
  }
}

# ── Connection security ───────────────────────────────────────
variable "require_mtls" {
  description = "Require mutual TLS authentication (mTLS). false = standard TLS"
  type        = bool
  default     = false
}
