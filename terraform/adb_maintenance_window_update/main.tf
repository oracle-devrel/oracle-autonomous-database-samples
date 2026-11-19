# ============================================================
# main.tf — Update an existing ADB-S maintenance window
# ============================================================

# Import the existing database; this example is not for provisioning.
import {
  to = oci_database_autonomous_database.adb
  id = var.adb_ocid
}

resource "oci_database_autonomous_database" "adb" {
  compartment_id = var.compartment_ocid
  db_name        = var.adb_db_name

  # Request a target window; do not overwrite the active window.
  # Copy all four values from ListAvailableMaintenanceWindows.
  scheduled_maintenance_window {
    day_of_week {
      name = var.maintenance_day
    }
    maintenance_start_time = var.maintenance_start_time
    maintenance_end_time   = var.maintenance_end_time
    availability_domain    = var.maintenance_availability_domain
  }

  lifecycle {
    prevent_destroy = true
  }
}
