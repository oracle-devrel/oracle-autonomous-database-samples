# ── OCI Credentials ──────────────────────────────────────────
tenancy_ocid     = ""
user_ocid        = ""
fingerprint      = ""
private_key_path = ""
region           = "us-ashburn-1"

compartment_ocid = ""

# ── VCN ──────────────────────────────────────────────────────
vcn_display_name = ""
vcn_cidr         = "10.0.0.0/16"
vcn_dns_label    = ""

# ── Subnet ────────────────────────────────────────────────────
subnet_display_name = ""
subnet_cidr         = "10.0.1.0/24"
subnet_dns_label    = ""

# ── NSG ───────────────────────────────────────────────────────
nsg_display_name = ""

# ── ADB Configuration ─────────────────────────────────────────
adb_display_name           = ""
adb_db_name                = ""
adb_admin_password         = ""
adb_workload_type          = "DW"   # OLTP=ATP | DW=ADW | AJD=JSON | APEX
adb_db_version             = "26ai"
adb_cpu_core_count         = 2
adb_storage_tbs            = 1
adb_auto_scaling           = false
adb_private_endpoint_label = "adbprivate"

# ── Security ──────────────────────────────────────────────────
require_mtls = false
