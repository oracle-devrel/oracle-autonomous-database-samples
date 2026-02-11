# Migrate Databases to Autonomous AI Database using Transportable Tablespaces

Transportable Tablespaces feature can be used to migrate Oracle database tablespaces from customer on-premise or another Oracle Database Cloud Service into Oracle Autonomous AI Database Cloud Service. User tablespaces along with the necessary schemas can be migrated using the Transportable Tablespaces mechanism. 

Transportable Tablespaces mechanism uses RMAN Backup/Restore and Data Pump Export/Import to transport data and metadata between source databse and Autonomous AI Database. Customers can migrate both bigfile and smallfile tabalespaces. Tablespaces in source database be can encrypted or unencrypted. Migration can be done in full or incremental modes. Customers can use Oracle Cloud Infrastructure (OCI) Object Storage or File Storage Service (FSS) as intermediary for the migration. Source database can be of version 11g or higher. Tablespaces can be migrated to Oracle Autonomous AI Database version 19c or 23ai.

Refer to  [Notes for Users Migrating from Other Oracle Databases to Autonomous AI Database](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/migrating-from-other-oracle-database.html) before starting the migration.

## Transport Tablespaces using OCI Object Storage

Use the following steps to transport tablespaces from a source database to an Autonomous AI Database using Oracle Cloud Infrastructure (OCI) Object Storage.

### Step-by-step guide
Transporting Tablespaces involves below high level steps.

1.  Create OCI Object Storage Buckets
2.  Backup tablespaces on source database using Oracle-provided Backup Utility.
3.  Create Dynamic Group and Policy to allow Resource Principal access to the object storage buckets.
4.  Provision an Autonomous AI Database by providing migration inputs.


### Create Object Storage Buckets

Transportable Tablespaces needs two OCI object storage buckets - one for backups and another for metadata. Create the buckets in your Oracle Storage Cloud Service account. Note the URLs of the buckets as they are needed as inputs for the operation. Use [Oracle Cloud Infrastructure Object Storage Native URI Format](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/file-uri-formats.html#GUID-26978C37-BFCE-4E0B-8C39-8AF399F2067B) for the URL.

Example:
[https://objectstorage.region.oraclecloud.com/n/\<namespace-string\>/b/\<bucket-name\>](https://objectstorage.region.oraclecloud.com/n/namespace-string/b/bucket/o/filename)

To make Object Storage URI work, please [generate an API signing key](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#two). Download the private key .pem file and the API signing key config file with below contents to source database host.

```
    [DEFAULT]

    user=ocid1.user.oc1..xxxxx
    fingerprint=f6:d6:e5:xxxxx
    tenancy=ocid1.tenancy.oc1..xxxxx
    region=us-ashburn-1
    key_file=<path to the downloaded private key file>
```

Note - User should have read and write access to the object storage buckets.

### Backup Tablespaces on Source Database

#### Pre-requisites

- Create a Project Directory that will used as staging location on the host running the source database.
- Download [Oracle Database Backup Cloud Module](https://www.oracle.com/database/technologies/oracle-cloud-backup-downloads.html) to the Project Directory. Unzip the downloaded opc_installer.zip in the project directory.
- Download [Transportable Tablespaces Backup Utility](https://github.com/oracle-devrel/oracle-autonomous-database-samples/tree/main/migration-tools/tts-backup-python) files to the project directory.
- Provide inputs for backup in the tts-backup-env.txt file.

#### Inputs to Backup Utility

Open tts-backup-env.txt file downloaded to the project directory and provide the following inputs in the file.

##### Project and Tablespace inputs

***PROJECT_NAME*** : (REQUIRED INPUT) Name for transport tablespace project. \
***DATABASE_NAME*** : (REQUIRED INPUT) Database Name containing the tablespaces. \
***TABLESPACES*** : (OPTIONAL INPUT) List of comma separated tablespaces to be transported.  Leave empty to transport all user tablespaces. \
***SCHEMAS*** : (OPTIONAL INPUT) List of comma separated schemas to be exported. Leave empty to export all non-common schemas.

##### Database connection inputs

***HOSTNAME*** : (REQUIRED INPUT) Host where database is running, used for connecting to the database. \
***LSNR_PORT*** : (REQUIRED INPUT) Listener port, used for connecting to the database. \
***DB_SVC_NAME*** : (REQUIRED INPUT) Database service name, used for connecting to the database.  \
***ORAHOME*** : (REQUIRED INPUT) Database home, \$ORACLE_HOME. \
***DBUSER*** : (REQUIRED INPUT) Username for connecting to the database. User should have sysdba privileges. \
***DBPASSWORD*** : (RUNTIME INPUT) Password for connection to the database. DO NOT provide in the file. Provide as CLI runtime input when prompted. \
***DB_VERSION*** : (REQUIRED INPUT) DB Version, supported values are 11g, 12c, 19c, 23ai.

##### OCI Object Storage (OSS) inputs 

***TTS_BACKUP_URL*** : (REQUIRED INPUT) Object storage bucket uri for backup files. \
***TTS_BUNDLE_URL*** : (REQUIRED INPUT) Object storage bucket uri for transportable tablespace bundle. \
***OCI_INSTALLER_PATH*** : (REQUIRED INPUT) Path to oci_install.jar. \
***CONFIG_FILE*** : (REQUIRED INPUT) Path to dowloaded API keys config file. Make sure to update the key_file parameter with the file path to your private key in the config file. \
***COMPARTMENT_OCID*** : (REQUIRED INPUT) Compartment OCID of bucket  (TTS_BACKUP_URL) that stores backup files. \
***OCI_PROXY_HOST*** : (OPTIONAL INPUT) HTTP proxy server. \
***OCI_PROXY_HOST*** : (OPTIONAL INPUT)  HTTP proxy server connection port.

##### TDE keys inputs

***TDE_WALLET_STORE_PASSWORD*** : (RUNTIME INPUT) Provide TDE wallet store password if any of the tablespaces being transported are encrypted. DO NOT provide in the file. Provide as CLI runtime input when prompted.

##### Run type inputs 

***FINAL_BACKUP*** : (REQUIRED INPUT) Accepted values TRUE/true or FALSE/false. Value should be TRUE for a non-incremental migration. For incremental migration, value should be FALSE for all incremental backups including the first backup. Set the value to TRUE for final backup of an incremental migration. Tablespaces being transported must be set to READ-ONLY when FINAL_BACKUP is set to TRUE. Tablespace and Schema metadata will be exported only when FINAL_BAKCUP is set to TRUE. \

***DRY_RUN*** : (OPTIONAL INPUT) Accepted values TRUE/true or FALSE/false. When set to TRUE, the backup script runs in validation mode only and does not perform the actual backup. Use DRY_RUN to detect potential problems with transport and fix them before running the actual backup. If the input parameter is not provided, value defaults to FALSE.

##### Performance inputs     

***PARALLELISM*** : (REQUIRED INPUT) Number of channels to be used for backup.

***CLUSTER_MODE*** : (OPTIONAL INPUT)  Accepted values TRUE/true or FALSE/false. If set to TRUE, RMAN allocates backup channels across all open RAC instances (channels_per_host = parallelism / num_rac_instances). If the input parameter is not provided or set to FALSE, all the channels (as specified by parallelism) are allocated only on host where backup tool is run.

Leave these a blank unless really needed.

##### Miscellaneous Inputs

***EXCLUDE_TABLES*** : (OPTIONAL INPUT) List of comma separated tables to exclude. Validation checks are skipped for these tables and tables along with their dependent objects are excluded during Data Pump export of metadata. Leave empty to not exclude any tables. Note that table names are case-sensitive.

***EXCLUDE_STATISTICS*** : (OPTIONAL INPUT) Accepted values TRUE/true or FALSE/false. When set to TRUE, statistics (table, index, and related statistics) are excluded during tablespace metadata export. If the input parameter is not provided, value defaults to FALSE.

***TRANSPORT_TABLES_PROTECTED_BY_REDACTION_POLICIES*** - (OPTIONAL INPUT) Accepted values TRUE/true or FALSE/false. Explicit consent to transport tables protected by redaction policies. If redaction protected tables are detected in the source database and this parameter is set to TRUE/true, the backup process will proceed with the understanding that the corresponding redaction policies will be created user in the target Autonomous AI Database. Redacted data will be unprotected after migration if the policies are not created in the target database. If the input parameter is not provided or set to FALSE/false, backup validations will fail when redaction protected tables are found in the source database.

***TRANSPORT_TABLES_PROTECTED_BY_OLS_POLICIES*** - (OPTIONAL INPUT) Accepted values TRUE/true or FALSE/false. Explicit consent to transport tables that are protected by Oracle Label Security (OLS) policies. If OLS protected tables are detected and this parameter is set to TRUE/true, the backup process will proceed with the understanding that OLS policies will be created by user in the target Autonomous AI Database. Data protected by OLS will be unprotected after migration if the policies are not created in the target database. If the input parameter is not provided or set to FALSE/false, backup validations will fail when OLS protected tables are found in the source database.

***TRANSPORT_DB_PROTECTED_BY_DATABASE_VAULT*** - (OPTIONAL INPUT) Accepted values TRUE/true or FALSE/false. Explicit consent to transport tablespaces from a database protected by Oracle Database Vault. If Database Vault Operations Control is detected and this parameter is set to TRUE/true, the backup process will proceed with the understanding that Database Vault  Operations Control will be re-enabled and configured by user in the target Autonomous AI Database. Transported data will remain unprotected after migration if Database Vault is not configured in the target database. If the input parameter is not provided or set to FALSE/false, the transport will fail when Database Vault protection is detected.

***DVREALM_USER*** - (OPTIONAL INPUT) Required only if Database Vault is enabled and configured in the source database. Specify a Database Vault realm owner or authorized user required to access objects protected by Database Vault during the backup process. If not provided and Database Vault is enabled, backup will fail with an error.

***DVREALM_PASSWORD*** - (RUNTIME INPUT) Required only if Database Vault is enabled and configured in the source. Password for the specified DVREALM_USER. If not provided and Database Vault is enabled, backup will fail with an error. Provide as CLI runtime input when prompted. This prompt appears only if DVREALM_USER is provided.

**Backup Utility Sample Inputs**
```
  [DEFAULT]
  ################################################################################
  ###                     Project and Tablespace inputs                        ###
  ################################################################################
  PROJECT_NAME=tts_project
  DATABASE_NAME=orclpdb1
  TABLESPACES=emp_tablespace, dept_tablespace
  SCHEMAS=user1, user2,user3
  
  
  ################################################################################
  ###                     Database connection inputs                           ###
  ################################################################################
  HOSTNAME=<host>
  LSNR_PORT=1521
  DB_SVC_NAME=orclpdb1
  ORAHOME=/opt/oracle/product/19c/dbhome_1
  DBUSER=<USER>
  DB_VERSION=19c
  
  
  ################################################################################
  ###                     Object Storage Service (OSS) inputs                  ###
  ################################################################################
  #    The following inputs are required only in case of OSS based transport   ###
  #    Please leave them empty if using FSS.                                   ###
  ################################################################################
  TTS_BACKUP_URL=https://objectstorage.us-ashburn-1.oraclecloud.com/n/<namespace>/b/<bucketname>
  TTS_BUNDLE_URL=https://objectstorage.us-ashburn-1.oraclecloud.com/n/<namespace>/b/<bucketname>
  OCI_INSTALLER_PATH=/home/oracle/opc_installer/oci_installer/oci_install.jar
  CONFIG_FILE=/home/oracle/OCI_CONFIG/config
  COMPARTMENT_OCID=ocid1.compartment.oc1..xxxxx
  OCI_PROXY_HOST=proxy.company.com
  OCI_PROXY_PORT=80
  
  
  ################################################################################
  ###                     Run type inputs                                      ###
  ################################################################################
  FINAL_BACKUP=TRUE/FALSE
  DRY_RUN=TRUE/FALSE
  
  
  ################################################################################
  ###                     Performance inputs                                   ###
  ################################################################################
  PARALLELISM=
  CLUSTER_MODE=TRUE/FALSE
  
  ################################################################################
  ###                     Miscellaneous inputs                                 ###
  ################################################################################
  EXCLUDE_TABLES=
  EXCLUDE_STATISTICS=TRUE/FALSE
  TRANSPORT_TABLES_PROTECTED_BY_REDACTION_POLICIES=FALSE
  TRANSPORT_TABLES_PROTECTED_BY_OLS_POLICIES=FALSE
  TRANSPORT_DB_PROTECTED_BY_DATABASE_VAULT=FALSE
  DVREALM_USER=
```

Run the TTS Backup Tool from the project directory as below. User will be prompted for database password and optional TDE wallet store password.

**Run Backup Utility**

```
  $ python3 tts-backup.py 
  Enter database password: Test
  Enter TDE wallet store password (optional) 
  Required only if any of the tablespaces are TDE encrypted (leave empty and press Enter if not applicable):
```

The tool will take backups of the tablespace datafiles and create a metadata bundle. Both backups and the bundle will be uploaded to the provided OCI Object Storage buckets or FSS Mount Targets. Backup Utility will output an URL to OCI Object Storage metadata bundle or FSS Mount Target path for metadata bundle. User should note the given URL/Path as that will be needed as migration input when creating Autonomous AI Database for the migration.

**TTS Backup Utility Version**

To check the version of the TTS Backup Utility being used, run the command below

```
  $ python3 tts-backup.py --version
```

### Create Dynamic Group and Policy

Transportable Tablespaces functionality will download metadata from OCI Object Storage metadata bucket using [OCI Resource Principal](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/resource-principal.html). Create Dynamic Group and Policy to allow access to the metadata bucket using the resource principal.

1.  Create a Dynamic Group **TTSDynamicGroup** with matching rule:\
    ALL {resource.type = \'autonomousdatabase\', [resource.compartment.id](http://resource.compartment.id) = \'your_Compartment_OCID\'}
2.  Create a Policy using the dynamic group with Policy Statement:\
    Allow dynamic-group **TTSDynamicGroup** to manage buckets in tenancy\
    Allow dynamic-group **TTSDynamicGroup** to manage objects in tenancy\
    \
    Prepend domain name to the dynamic group name if needed as below.\
    Allow dynamic-group \<*identity_domain_name\>*/**TTSDynamicGroup** to manage buckets in tenancy\
    Allow dynamic-group \<*identity_domain_name\>*/**TTSDynamicGroup** to manage objects in tenancy
    
### Create Autonomous AI Database with Migration inputs

Create an Autonomous AI Database from OCI Console using the steps below. 

1.  Go to OCI Console → Oracle Database → Autonomous AI Database
2.  Click on ***Create Autonomous Database***
3.  Provide all the necessary inputs.
4.  Select database version that is equal to or greater than the source database.
5.  Specify ***Storage (TB)*** in ***Configure the database*** section to match size of tablespace(s) being transported.
6.  Expand ***Migration section*** on the page.
7.  Specify OCI Object Storage URL or FSS Mount Target path to the metadata bundle as given by Backup Utility.
8.  Submit ***Create Autonomous Database.***

The operation will first create the database and then trigger migration operation. For non-incremental operation, migration will perform all the necessary steps and the created database will have the transported tablespaces. In case of incremental operation, this is the first step in the migration process. First backup pieces will be restored to the created database. User has to continue with incremental backup up to the final backup to complete the migration process.

### Incremental Migration

If user is performing an incremental migration operation, repeat Backup Tablespaces step at source database for each incremental using the same set of inputs. Do not alter the tablespace list during incremental backups. Use the Tablespace list provided during first backup. Backup Utility will output a new OCI Object Storage URL / FSS Mount Target path corresponding to that increment. Use the OCI Object Storage URL to update the Autonomous AI Database created with the first backup above. Set FINAL_BACKUP=TRUE in the input file before performing final backup.

### Modify Autonomous AI Database with Migration inputs

1.  Go to OCI Console → Oracle Database → Autonomous AI Database
2.  Select and click on the database created with the first backup.
3.  Verify ***Storage*** in ***Resource allocation*** section. Use ***Manage resource allocation*** tab to increase storage if needed.
4.  Expand ***Migration section*** on the page.
5.  Specify OCI Object Storage URL or FSS Mount Target path to the metadata bundle as given by Backup Utility for the increment or final backup.
6.  Click on **Save**.

The operation will trigger the transport tablespaces job on the database.

## Transport Tablespaces using OCI File Storage Service

Oracle Cloud Infrastructure (OCI) File Storage Service (FSS) can also be used to transport tablespaces from an on-premise or another Oracle Database Cloud Service to Autonomous AI Database. Autonomous AI Database created for migration using FSS must be configured with Private endpoint network access. Use the following steps to transport tablespaces using OCI FSS.

### Step-by-step guide

Transporting Tablespaces involves below high level steps.

1. Configure an OCI File System.
2. Backup tablespaces on source database using Oracle-provided Backup Utility.
3. Provision an Autonomous AI Database by providing migration inputs.
   
### Configure OCI File System

Create a File System by providing Export and Mount Target information. Refer to [How to Attach a File System to your Autonomous AI Database](https://blogs.oracle.com/datawarehousing/post/attach-file-system-autonomous-database) and use the guidelines for creating the file system. User has to mount the File System to the source database host(s) using the **Mount Commands** provided by the **File System** -> **Export**. Refer to [Mounting File Systems From UNIX-Style Instances](https://docs.oracle.com/en-us/iaas/Content/File/Tasks/mountingunixstyleos.htm) for detailed instructions.

### Backup Tablespaces on Source Database

#### Pre-requisites

- Create a Project Directory that will used as staging location on the host running the source database.
- Download [Transportable Tablespaces Backup Utility](https://github.com/oracle-devrel/oracle-autonomous-database-samples/tree/main/migration-tools/tts-backup-python) to the project directory.
- Provide inputs for backup in the tts-backup-env.txt file.

#### TTS Backup Tool inputs

Open tts-backup-env.txt file downloaded to the project directory and provide the following inputs in the file.

##### Project and Tablespace inputs

***PROJECT_NAME*** : (REQUIRED INPUT) Name for transport tablespace project. \
***DATABASE_NAME*** : (REQUIRED INPUT) Database Name containing the tablespaces. \
***TABLESPACES*** : (OPTIONAL INPUT) List of comma separated tablespaces to be transported.  Leave empty to transport all user tablespaces. \
***SCHEMAS*** : (OPTIONAL INPUT) List of comma separated schemas to be exported. Leave empty to export all non-common schemas.

##### Database connection inputs

***HOSTNAME*** : (REQUIRED INPUT) Host where database is running, used for connecting to the database. \
***LSNR_PORT*** : (REQUIRED INPUT) Listener port, used for connecting to the database. \
***DB_SVC_NAME*** : (REQUIRED INPUT) Database service name, used for connecting to the database.  \
***ORAHOME*** : (REQUIRED INPUT) Database home, \$ORACLE_HOME. \
***DBUSER*** : (REQUIRED INPUT) Username for connecting to the database. User should have sysdba privileges. \
***DBPASSWORD*** : (RUNTIME INPUT) Password for connection to the database. DO NOT provide in the file. Provide as CLI runtime input when prompted. \
***DB_VERSION*** : (REQUIRED INPUT) DB Version, supported values are 11g, 12c, 19c, 23ai.

##### File Storage Service (FSS) inputs
***TTS_FSS_CONFIG*** : (REQUIRED INPUT) FSS configuration should be given in the format FSS:\<FIle System Name\>:\<FQDN of Mount Target\>:\<Export Path\>. \
***TTS_FSS_MOUNT_DIR*** : (REQUIRED INPUT) Absolute path where file system was mounted on source database host(s).

##### TDE keys inputs

***TDE_WALLET_STORE_PASSWORD*** : (RUNTIME INPUT) Provide TDE wallet store password if any of the tablespaces being transported are encrypted. DO NOT provide in the file. Provide as CLI runtime input when prompted.

##### Run type inputs 

***FINAL_BACKUP*** : (REQUIRED INPUT) Accepted values TRUE/true or FALSE/false. Value should be TRUE for a non-incremental migration. For incremental migration, value should be FALSE for all incremental backups including the first backup. Set the value to TRUE for final backup of an incremental migration. Tablespaces being transported must be set to READ-ONLY when FINAL_BACKUP is set to TRUE. Tablespace and Schema metadata will be exported only when FINAL_BAKCUP is set to TRUE. 

***DRY_RUN*** : (OPTIONAL INPUT) Accepted values TRUE/true or FALSE/false. When set to TRUE, the backup script runs in validation mode only and does not perform the actual backup. Use DRY_RUN to detect potential problems with transport and fix them before running the actual backup. If the input parameter is not provided, value defaults to FALSE.

##### Performance inputs     

***PARALLELISM*** : (REQUIRED INPUT) Number of channels to be used for backup. 

***CLUSTER_MODE*** : (OPTIONAL INPUT)  Accepted values TRUE/true or FALSE/false. If set to TRUE, RMAN allocates backup channels across all open RAC instances (channels_per_host = parallelism / num_rac_instances). If the input parameter is not provided or set to FALSE, all the channels (as specified by parallelism) are allocated only on host where backup tool is running. If CLUSTER_MODE is TRUE, File System should be mounted to all source database host(s). If CLUSTER_MODE is FALSE, File System should be mounted on the host where backup utility is run. 

##### Miscellaneous Inputs

***EXCLUDE_TABLES*** : (OPTIONAL INPUT) List of comma separated tables to exclude. Validation checks are skipped for these tables and tables along with their dependent objects are excluded during Data Pump export of metadata. Leave empty to not exclude any tables. Note that table names are case-sensitive.

***EXCLUDE_STATISTICS*** : (OPTIONAL INPUT) Accepted values TRUE/true or FALSE/false. When set to TRUE, statistics (table, index, and related statistics) are excluded during tablespace metadata export. If the input parameter is not provided, value defaults to FALSE.

***TRANSPORT_TABLES_PROTECTED_BY_REDACTION_POLICIES*** - (OPTIONAL INPUT) Accepted values TRUE/true or FALSE/false. Explicit consent to transport tables protected by redaction policies. If redaction protected tables are detected in the source database and this parameter is set to TRUE/true, the backup process will proceed with the understanding that the corresponding redaction policies will be created user in the target Autonomous AI Database. Redacted data will be unprotected after migration if the policies are not created in the target database. If the input parameter is not provided or set to FALSE/false, backup validations will fail when redaction protected tables are found in the source database.

***TRANSPORT_TABLES_PROTECTED_BY_OLS_POLICIES*** - (OPTIONAL INPUT) Accepted values TRUE/true or FALSE/false. Explicit consent to transport tables that are protected by Oracle Label Security (OLS) policies. If OLS protected tables are detected and this parameter is set to TRUE/true, the backup process will proceed with the understanding that OLS policies will be created by user in the target Autonomous AI Database. Data protected by OLS will be unprotected after migration if the policies are not created in the target database. If the input parameter is not provided or set to FALSE/false, backup validations will fail when OLS protected tables are found in the source database.

***TRANSPORT_DB_PROTECTED_BY_DATABASE_VAULT*** - (OPTIONAL INPUT) Accepted values TRUE/true or FALSE/false. Explicit consent to transport tablespaces from a database protected by Oracle Database Vault. If Database Vault Operations Control is detected and this parameter is set to TRUE/true, the backup process will proceed with the understanding that Database Vault  Operations Control will be re-enabled and configured by user in the target Autonomous AI Database. Transported data will remain unprotected after migration if Database Vault is not configured in the target database. If the input parameter is not provided or set to FALSE/false, the transport will fail when Database Vault protection is detected.

***DVREALM_USER*** - (OPTIONAL INPUT) Required only if Database Vault is enabled and configured in the source database. Specify a Database Vault realm owner or authorized user required to access objects protected by Database Vault during the backup process. If not provided and Database Vault is enabled, backup will fail with an error.

***DVREALM_PASSWORD*** - (RUNTIME INPUT) Required only if Database Vault is enabled and configured in the source. Password for the specified DVREALM_USER. If not provided and Database Vault is enabled, backup will fail with an error. Provide as CLI runtime input when prompted. This prompt appears only if DVREALM_USER is provided.

**Backup Utility Sample Inputs**
```
  [DEFAULT]
  ################################################################################
  ###                     Project and Tablespace inputs                        ###
  ################################################################################
  PROJECT_NAME=tts_project
  DATABASE_NAME=orclpdb1
  TABLESPACES=emp_tablespace, dept_tablespace
  SCHEMAS=user1, user2,user3
  
  
  ################################################################################
  ###                     Database connection inputs                           ###
  ################################################################################
  HOSTNAME=<host>
  LSNR_PORT=1521
  DB_SVC_NAME=orclpdb1
  ORAHOME=/opt/oracle/product/19c/dbhome_1
  DBUSER=<USER>
  DB_VERSION=19c
  
  
  ################################################################################
  ###                     File Storage Service (FSS) inputs                    ###
  ################################################################################
  #    The following inputs are required only in case of FSS based transport   ###
  #    Please leave them empty if using Object storage.                        ###
  ################################################################################
  TTS_FSS_CONFIG=FSS:myFSS:myfss.vcn.com:/myFSS
  TTS_FSS_MOUNT_DIR=/u01/app/oracle/myFSS
  
  
  ################################################################################
  ###                     Run type inputs                                      ###
  ################################################################################
  FINAL_BACKUP=TRUE/FALSE
  DRY_RUN=TRUE/FALSE
  
  
  ################################################################################
  ###                     Performance inputs                                   ###
  ################################################################################
  PARALLELISM=
  CLUSTER_MODE=TRUE/FALSE
  
  ################################################################################
  ###                     Miscellaneous inputs                                 ###
  ################################################################################
  EXCLUDE_TABLES=
  EXCLUDE_STATISTICS=TRUE/FALSE
  TRANSPORT_TABLES_PROTECTED_BY_REDACTION_POLICIES=FALSE
  TRANSPORT_TABLES_PROTECTED_BY_OLS_POLICIES=FALSE
  TRANSPORT_DB_PROTECTED_BY_DATABASE_VAULT=FALSE
  DVREALM_USER=
```

Run the TTS Backup Tool from the project directory as below. User will be prompted for database password and optional TDE wallet store password.

**Run Backup Utility**

```
  $ python3 tts-backup.py 
  Enter database password: Test
  Enter TDE wallet store password (optional) 
  Required only if any of the tablespaces are TDE encrypted (leave empty and press Enter if not applicable):
```

The tool will take backups of the tablespace datafiles and create a metadata bundle. Both backups and the bundle will be uploaded to backup and metadata directories under the File System - Export path. Backup Utility will output an URL to FSS file path for the metadata bundle. User should note the given FSS file path as that will be needed as migration input when creating Autonomous AI Database for the migration.

**TTS Backup Utility Version**

To check the version of the TTS Backup Utility being used, run the command below

```
  $ python3 tts-backup.py --version
```

### Create Autonomous AI Database with Migration inputs

Create an Autonomous AI Database from OCI Console using the steps below. 

1.  Go to OCI Console → Oracle Database → Autonomous AI Database
2.  Click on ***Create Autonomous Database***
3.  Provide all the necessary inputs.
4.  Select database version that is equal to or greater than the source database.
5.  Specify ***Storage (TB)*** in ***Configure the database*** section to match size of tablespace(s) being transported.
6.  Specify ***Network Access*** as ***Private endpoint access*** only and provide the necessary inputs.
7.  Expand ***Migration section*** on the page.
8.  Specify FSS file path to the metadata bundle as given by Backup Utility.
9.  Submit ***Create Autonomous Database.***

The operation will first create the database and then trigger migration operation. For non-incremental operation, migration will perform all the necessary steps and the created database will have the transported tablespaces. In case of incremental operation, this is the first step in the migration process. First backup pieces will be restored to the created database. User has to continue with incremental backup up to the final backup to complete the migration process.

### Incremental Migration

If user is performing an incremental migration operation, repeat Backup Tablespaces step at source database for each incremental using the same set of inputs. Do not alter the tablespace list during incremental backups. Use the Tablespace list provided during first backup. Backup Utility will output a new OCI Object Storage URL / FSS Mount Target path corresponding to that increment. Use the FSS file path to update the Autonomous AI Database created with the first backup above. Set FINAL_BACKUP=TRUE in the input file before performing final backup.

### Modify Autonomous AI Database with Migration inputs

1.  Go to OCI Console → Oracle Database → Autonomous AI Database
2.  Select and click on the database created with the first backup.
3.  Verify ***Storage*** in ***Resource allocation*** section. Use ***Manage resource allocation*** tab to increase storage if needed.
4.  Expand ***Migration section*** on the page.
5.  Specify FSS file path to the metadata bundle as given by Backup Utility for the increment or final backup.
6.  Click on **Save**.

The operation will trigger the transport tablespaces job on the database.
