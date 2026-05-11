# ── OCI Credentials ──────────────────────────────────────────
tenancy_ocid     = ""
user_ocid        = ""
fingerprint      = ""
private_key_path = ""
region           = "us-ashburn-1"

compartment_ocid = ""

# ── ADB Configuration ─────────────────────────────────────────
adb_display_name   = ""
adb_db_name        = ""
adb_admin_password = ""
adb_workload_type  = "DW"    # OLTP=ATP | DW=ADW | AJD=JSON | APEX
adb_db_version     = "26ai"
adb_cpu_core_count = 2
adb_storage_tbs    = 1
adb_auto_scaling   = false

# ── ACLs ──────────────────────────────────────────────────────
# Add all IPs or ranges that should have access
acl_allowed_cidrs = [
  ""
]

# ── Security ──────────────────────────────────────────────────
require_mtls = false
