# Autonomous AI Database with a cross-region standby

This Terraform example creates an Autonomous AI Database with a cross-region standby.

You can run it by updating the file _terraform.tfvars_ file with the settings you want. 

Enter your tenancy OCID, user OCID, user fingerprint, private key file path, region name, and compartment OCID. Change the other settings like database name and compute count to your liking and enter the ADMIN user password you want.

```tenancy_ocid     = ""
user_ocid        = ""
fingerprint      = ""
private_key_path = ""

compartment_ocid = ""

primary_region = "us-ashburn-1"
standby_region = "us-phoenix-1"

adb_display_name = "primarydb"
adb_db_name      = "primarydb"

admin_password = ""
  
db_workload = "OLTP"

compute_count = 2
data_storage_size_in_tbs = 1
```



