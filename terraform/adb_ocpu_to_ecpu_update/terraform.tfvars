# ── OCI Credentials ──────────────────────────────────────────
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaakc2xkehakt7bmhmipdbhz3tbkej53jzwmrlmuqoloydlotthkrbq"
user_ocid        = "ocid1.user.oc1..aaaaaaaas3nxkab5ct2mhfno7j2ltpcsiyhi5xzrs7xwcprpmpbfoxvsylva"
fingerprint      = "ae:0d:91:96:d9:10:07:81:ba:f4:b2:af:db:48:06:25"
private_key_path = "/Users/davcarde/.oci/oci_api_key_t5.pem"
region           = "us-ashburn-1"

compartment_ocid = "ocid1.tenancy.oc1..aaaaaaaakc2xkehakt7bmhmipdbhz3tbkej53jzwmrlmuqoloydlotthkrbq"

# ── ADB Configuration ─────────────────────────────────────────
adb_display_name   = "xiaTest2"
adb_db_name        = "xiaTest2"
adb_admin_password = "HolaMundo1330"
adb_workload_type  = "AJD"    # OLTP=ATP | DW=ADW | AJD=JSON | APEX
adb_cpu_core_count = 2       # ECPU: minimum 2, multiples of 2
adb_storage_tbs    = 1
adb_auto_scaling   = false
