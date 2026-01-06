variable "tenancy_ocid" {
  type = string
}

variable "user_ocid" {
  type = string
}

variable "fingerprint" {
  type = string
}

variable "private_key_path" {
  type = string
}

variable "region" {
  type = string
}

variable "compartment_ocid" {
  type = string
}

variable "db_name" {
  type = string
}

variable "display_name" {
  type = string
}

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "compute_model" {
  type    = string
  default = "ECPU"
}

variable "compute_count" {
  type    = number
}

variable "data_storage_tbs" {
  type    = number
}

variable "db_workload" {
  type    = string
}

