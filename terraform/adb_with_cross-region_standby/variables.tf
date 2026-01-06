variable "tenancy_ocid"     { type = string }
variable "user_ocid"        { type = string }
variable "fingerprint"      { type = string }
variable "private_key_path" { type = string }

variable "compartment_ocid" { type = string }

variable "primary_region" { type = string }
variable "standby_region" { type = string }

variable "adb_display_name" { type = string }
variable "adb_db_name"      { type = string }

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "db_workload" {
  type    = string
}

variable "compute_model" {
  type    = string
  default = "ECPU"
}

variable "compute_count" {
  type    = number
}

variable "data_storage_size_in_tbs" {
  type    = number
}

