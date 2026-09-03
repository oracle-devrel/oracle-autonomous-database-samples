# ── OCI Credentials ──────────────────────────────────────────
tenancy_ocid     = ""
user_ocid        = ""
fingerprint      = ""
private_key_path = ""
region           = "us-ashburn-1"

compartment_ocid   = ""
adb_display_name   = ""
adb_db_name        = ""
adb_admin_password = ""
adb_workload_type  = "OLTP"
adb_ecpu_count     = 2
adb_storage_tbs    = 1
adb_auto_scaling   = false

# At least one entry is required. Replace this documentation-only address.
acl_allowed_cidrs = [""]
require_mtls      = false

# Enable only the Database Tools required for this ADB, and adjust ECPU/idle
# settings as required. All tools are disabled by default.
#
# compute_count reserves ECPUs for a tool's dedicated service workload, while
# max_idle_time_in_minutes releases that capacity after the tool is idle. These
# settings are most useful for DLA, Data Transforms, Graph Studio, and OML.
# Use 0 where a tool does not require an explicit compute allocation.
# Disabled tools do not receive either setting in the OCI API request.
db_tools = {
  MONGODB_API      = { is_enabled = true, compute_count = 0, max_idle_time_in_minutes = 0 }
  APEX             = { is_enabled = false, compute_count = 0, max_idle_time_in_minutes = 0 }
  DATABASE_ACTIONS = { is_enabled = false, compute_count = 0, max_idle_time_in_minutes = 0 }
  # ORDS (Web Access) must be enabled when using APEX, Database Actions, or MongoDB API.
  ORDS = { is_enabled = true, compute_count = 0, max_idle_time_in_minutes = 0 }

  # These tools can use dedicated ECPUs. Increase the values only when the
  # enabled tool's workload requires more capacity.
  DLA             = { is_enabled = false, compute_count = 32, max_idle_time_in_minutes = 10 }
  DATA_TRANSFORMS = { is_enabled = false, compute_count = 8, max_idle_time_in_minutes = 30 }
  GRAPH_STUDIO    = { is_enabled = false, compute_count = 8, max_idle_time_in_minutes = 60 }
  OML             = { is_enabled = false, compute_count = 8, max_idle_time_in_minutes = 60 }
}
