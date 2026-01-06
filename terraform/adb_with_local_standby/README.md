# Autonomous AI Database with a local standby

This Terraform example creates an Autonomous AI Database with a local standby.

You can run it by updating the file _terraform.tfvars_ file with the settings you want. 

Enter your tenancy OCID, user OCID, user fingerprint, private key file path, region name, and compartment OCID. Change the other settings like database name and compute count to your liking.

```tenancy_ocid     = ""
user_ocid        = ""
fingerprint      = ""
private_key_path = ""
region           = "us-ashburn-1"
  
compartment_ocid = ""

db_name        = "primarydb"
display_name  = "primarydb"
admin_password = "WelcomeADB26"
compute_count = 2
data_storage_tbs = 1
db_workload = "OLTP"
```



