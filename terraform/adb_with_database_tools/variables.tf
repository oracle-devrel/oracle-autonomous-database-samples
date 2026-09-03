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

  validation {
    condition     = can(regex("^[A-Za-z0-9]{1,14}$", var.adb_db_name))
    error_message = "adb_db_name must contain only alphanumeric characters and be no more than 14 characters long."
  }
}

variable "adb_admin_password" {
  description = "ADMIN user password (min 12 chars, uppercase, number and symbol required)"
  type        = string
  sensitive   = true
}

variable "adb_workload_type" {
  description = "Workload type for the elastic pool leader: OLTP (ATP), DW (ADW), AJD (JSON), APEX, LH (Lakehouse)"
  type        = string
  default     = "LH"

  validation {
    condition     = contains(["OLTP", "DW", "AJD", "APEX", "LH"], var.adb_workload_type)
    error_message = "Must be one of: OLTP, DW, AJD, APEX, LH."
  }
}

variable "adb_db_version" {
  description = "Oracle database version"
  type        = string
  default     = "26ai"
}

variable "adb_ecpu_count" {
  description = "Number of ECPUs for the Autonomous Database"
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

# ── Network Access ────────────────────────────────────────────
variable "acl_allowed_cidrs" {
  description = <<-EOT
    List of allowed IPs, CIDR ranges, or VCN OCIDs for the public ADB endpoint.
    An ACL or private endpoint is required to use Database Tools.
    Examples:
      - "203.0.113.50"       → individual IP
      - "203.0.113.0/24"     → network range
      - "ocid1.vcn.oc1...."  → full OCI VCN
  EOT
  type        = list(string)

  validation {
    condition     = length(var.acl_allowed_cidrs) > 0
    error_message = "Specify at least one ACL entry, or use a private-endpoint-based example instead."
  }
}

variable "require_mtls" {
  description = "Require mutual TLS authentication (mTLS). false = standard TLS"
  type        = bool
  default     = false
}

# ── Database Tools ────────────────────────────────────────────
variable "db_tools" {
  description = <<-EOT
    Database Tools configuration, keyed by OCI tool name. Set is_enabled to false
    for any tool that should remain disabled. compute_count and
    max_idle_time_in_minutes apply to tools with dedicated compute.
  EOT
  type = map(object({
    is_enabled               = bool
    compute_count            = number
    max_idle_time_in_minutes = number
  }))

  default = {
    MONGODB_API      = { is_enabled = false, compute_count = 0, max_idle_time_in_minutes = 0 }
    APEX             = { is_enabled = false, compute_count = 0, max_idle_time_in_minutes = 0 }
    DATABASE_ACTIONS = { is_enabled = false, compute_count = 0, max_idle_time_in_minutes = 0 }
    ORDS             = { is_enabled = false, compute_count = 0, max_idle_time_in_minutes = 0 }
    DLA              = { is_enabled = false, compute_count = 32, max_idle_time_in_minutes = 10 }
    DATA_TRANSFORMS  = { is_enabled = false, compute_count = 8, max_idle_time_in_minutes = 30 }
    GRAPH_STUDIO     = { is_enabled = false, compute_count = 8, max_idle_time_in_minutes = 60 }
    OML              = { is_enabled = false, compute_count = 8, max_idle_time_in_minutes = 60 }
  }

  validation {
    condition = alltrue([
      for name in keys(var.db_tools) :
      contains(["MONGODB_API", "APEX", "DATABASE_ACTIONS", "ORDS", "DLA", "DATA_TRANSFORMS", "GRAPH_STUDIO", "OML"], name)
    ])
    error_message = "db_tools may contain only the supported Autonomous Database Tools names."
  }

  validation {
    condition = alltrue([
      for name in ["APEX", "DATABASE_ACTIONS", "MONGODB_API"] :
      !try(var.db_tools[name].is_enabled, false) || try(var.db_tools["ORDS"].is_enabled, false)
    ])
    error_message = "Enable ORDS before enabling APEX, DATABASE_ACTIONS, or MONGODB_API."
  }
}
