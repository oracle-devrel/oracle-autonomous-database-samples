# ============================================================
# variables.tf — Configurable parameters
# ============================================================

variable "tenancy_ocid" {
  description = "OCID of the OCI tenancy"
  type        = string
}

variable "user_ocid" {
  description = "OCID of the OCI user"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the API signing key"
  type        = string
}

variable "private_key_path" {
  description = "Path to the API signing private key (.pem)"
  type        = string
}

variable "region" {
  description = "OCI region of the existing database"
  type        = string
}

variable "adb_ocid" {
  description = "OCID of the existing ADB-S to import"
  type        = string
}

variable "compartment_ocid" {
  description = "Current compartment OCID; do not change for this operation"
  type        = string
}

variable "adb_db_name" {
  description = "Current technical database name; do not rename"
  type        = string
}

variable "maintenance_day" {
  description = "Day from an available maintenance window"
  type        = string
  validation {
    condition     = contains(["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"], var.maintenance_day)
    error_message = "Use an uppercase day returned by the available windows API."
  }
}

variable "maintenance_start_time" {
  description = "Start of the selected window in UTC, HH:mm"
  type        = string
  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_start_time))
    error_message = "Use a UTC time in HH:mm format."
  }
}

variable "maintenance_end_time" {
  description = "End of the selected window in UTC, HH:mm"
  type        = string
  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_end_time))
    error_message = "Use a UTC time in HH:mm format."
  }
}

variable "maintenance_availability_domain" {
  description = "Exact AD identifier returned with the available window"
  type        = string
}

