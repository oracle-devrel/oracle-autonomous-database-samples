# ── OCI Credentials ──────────────────────────────────────────
tenancy_ocid     = ""
user_ocid        = ""
fingerprint      = ""
private_key_path = ""
region           = "us-ashburn-1"

# ── Existing ADB ──────────────────────────────────────────────
compartment_ocid         = ""
adb_db_name              = ""
autonomous_database_ocid = ""

# ── Database Tools ────────────────────────────────────────────
# Declare only the tools that you want to change. Tools omitted from this map
# retain their current setting on the existing ADB.
# ORDS must be enabled when enabling APEX, Database Actions, or MongoDB API.
db_tools = {
  # MONGODB_API      = { is_enabled = true}
  # APEX             = { is_enabled = true}
  # DATABASE_ACTIONS = { is_enabled = true}
  # ORDS             = { is_enabled = true}
  # DLA              = { is_enabled = true,  compute_count = 32, max_idle_time_in_minutes = 10 }
  # DATA_TRANSFORMS  = { is_enabled = true,  compute_count = 8, max_idle_time_in_minutes = 30 }
  # GRAPH_STUDIO     = { is_enabled = true,  compute_count = 8, max_idle_time_in_minutes = 60 }
  # OML              = { is_enabled = true,  compute_count = 8, max_idle_time_in_minutes = 60 }
  MONGODB_API = { is_enabled = true, compute_count = 0, max_idle_time_in_minutes = 0 }
}
