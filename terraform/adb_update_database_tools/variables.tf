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
  description = "OCI region where the existing ADB is located"
  type        = string
}

# ── Existing ADB ──────────────────────────────────────────────
variable "compartment_ocid" {
  description = "OCID of the compartment containing the existing ADB"
  type        = string
}

variable "adb_db_name" {
  description = "Existing ADB technical name (letters/numbers only, max 14 chars)"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9]{1,14}$", var.adb_db_name))
    error_message = "adb_db_name must contain only alphanumeric characters and be no more than 14 characters long."
  }
}

variable "autonomous_database_ocid" {
  description = "OCID of the existing Autonomous Database to import and update"
  type        = string
}

# ── Database Tools ────────────────────────────────────────────
variable "db_tools" {
  description = <<-EOT
    Database Tool overrides keyed by OCI tool name. Omitted tools retain their
    current configuration on the existing ADB.
  EOT
  type = map(object({
    is_enabled               = bool
    compute_count            = number
    max_idle_time_in_minutes = number
  }))

  validation {
    condition = alltrue([
      for name in keys(var.db_tools) :
      contains(["MONGODB_API", "APEX", "DATABASE_ACTIONS", "ORDS", "DLA", "DATA_TRANSFORMS", "GRAPH_STUDIO", "OML"], name)
    ])
    error_message = "db_tools may contain only supported Autonomous Database Tools names."
  }

  default = {}
}
