# ── OCI Credentials ──────────────────────────────────────────
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaafcue47pqmrf4vigneebgbcmmoy5r7xvoypicjqqge32ewnrcyx2a"
user_ocid        = "ocid1.user.oc1..aaaaaaaatkpdjtfpvqwwpvcexdrfmlyvyk2ywsbs2atlvhqqxw6hkovhjala"
fingerprint      = "bd:13:f4:5a:a1:72:c5:98:00:1e:5a:3f:24:42:a7:fb"
private_key_path = "~/.oci/oci_api_key.pem"
region           = "us-ashburn-1"

compartment_ocid = "ocid1.compartment.oc1..aaaaaaaapz4knoy7df3gvi6trkxd4yffaz6jzbaj6r5grv3b6v33remrw2ta"

# ── VCN ──────────────────────────────────────────────────────
vcn_display_name = "adb-vcn"
vcn_cidr         = "10.0.0.0/16"
vcn_dns_label    = "adbvcn"

# ── Subnet ────────────────────────────────────────────────────
subnet_display_name = "adb-private-subnet"
subnet_cidr         = "10.0.1.0/24"
subnet_dns_label    = "adbsubnet"

# ── NSG ───────────────────────────────────────────────────────
nsg_display_name = "adb-nsg"

# ── ADB Configuration ─────────────────────────────────────────
adb_display_name           = "terravcndb"
adb_db_name                = "terravcndb"
adb_admin_password         = "HolaMundo1330"
adb_workload_type          = "DW"   # OLTP=ATP | DW=ADW | AJD=JSON | APEX
adb_db_version             = "26ai"
adb_cpu_core_count         = 2
adb_storage_tbs            = 1
adb_auto_scaling           = false
adb_private_endpoint_label = "adbprivate"

# ── Security ──────────────────────────────────────────────────
require_mtls = false
