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
  description = "OCI region where the ADB resides"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID of the compartment where the ADB resides"
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

variable "adb_cpu_core_count" {
  description = "Number of ECPUs to assign (minimum 2, must be a multiple of 2)"
  type        = number
  default     = 2

  validation {
    condition     = var.adb_cpu_core_count >= 2 && var.adb_cpu_core_count % 2 == 0
    error_message = "ECPU count must be at least 2 and a multiple of 2."
  }
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
