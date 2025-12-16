# Transportable Tablespaces Using Backup

Transportable Tablespaces feature can be used to migrate Oracle database tablespaces from customer on-premise or another Oracle Database Cloud Service into Oracle Autonomous AI Database Cloud Service. User tablespaces along with the necessary schemas can be migrated using the Transportable Tablespaces mechanism. Customers can migrate both bigfile and smallfile tabalespaces. Tablespaces be can encrypted or unencrypted.  Migration can be done in full or incremental modes. Customers can use Oracle Cloud Infrastructure (OCI) Object Storage or File Storage Service (FSS) as intermediary for the migration. Source database can be of version 11g or higher. Tablespaces can be migrated to Oracle Autonomous AI Database version 19c or 23ai.

## Step-by-step guide

Transporting Tablespaces involves below high level steps.

1.  Create OCI Object Storage Buckets or FSS Mount Targets for backup
2.  Backup tablespaces on source database using Oracle-provided Backup Utility.
3.  Create Dynamic Group and Policy to allow Resource Principal access if using OCI Object Storage
4.  Provision an Autonomous AI Database by providing migration inputs.

### Create Object Storage Buckets

Transportable Tablespaces needs two OCI object storage buckets - one for backups and another for metadata. Create the buckets in your Oracle Storage Cloud Service account. Note the URLs of the buckets as they are needed as inputs for the operation. Use [Oracle Cloud Infrastructure Object Storage Native URI Format](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/file-uri-formats.html) for the URL.

Example:
[https://objectstorage.region.oraclecloud.com/n/\<namespace-string\>/b/\<bucket-name\>](https://objectstorage.region.oraclecloud.com/n/namespace-string/b/bucket/o/filename)

To make Object Storage URI work, please [generate an API signing key](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm). Download the private key .pem file and the API signing key config file with below contents to source database host.
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
- Download [Oracle Database Backup Cloud Module](https://www.oracle.com/database/technologies/oracle-cloud-backup-downloads.html) to the Project Directory. Unzip the downloaded opc_installer.zip in the project directory.
- Download Transportable Tablespaces Backup Utility files to the project directory.
- Provide inputs for backup in the **tts-backup-env.txt** file.

#### TTS Backup Tool inputs

Open tts-backup-env.txt file downloaded to the project directory and provide the following inputs in the file.

##### Project and Tablespace inputs

***PROJECT_NAME***: Name for transport tablespace project. (REQUIRED INPUT) \
***DATABASE_NAME*** : Database Name containing the tablespaces.  (REQUIRED INPUT) \
***TABLESPACES*** : List of comma separated transportable tablespaces.  (OPTIONAL INPUT) if empty all user tablespaces are added.\
***SCHEMAS*** : List of comma separated transportable schemas. (OPTIONAL INPUT) if empty all required users are added. None of the schemas should be a common user.

##### Database connection inputs

***HOSTNAME*** : (REQUIRED INPUT) Host where database is running, used for connecting to the database.\
***LSNR_PORT*** : (REQUIRED INPUT) Listener port, used for connecting to the database.  \
***DB_SVC_NAME*** : (REQUIRED INPUT) Database service name, used for connecting to the database.  \
***ORAHOME*** : (REQUIRED INPUT) Database home, \$ORACLE_HOME.\
***DBUSER*** : (REQUIRED INPUT) Username for connecting to the database.  User should have sysdba privileges. \
***DBPASSWORD*** : (RUNTIME INPUT) Password for connection to the database. DO NOT provide in the file. Provide as CLI runtime input when prompted.\
***DB_VERSION*** : (REQUIRED INPUT) DB Version, supported values are 11g, 12c, 19c, 23ai.

##### Object Storage Service (OSS) inputs ( Required if using OCI Object Storage for migration. Leave them empty if using FSS. )

***TTS_BACKUP_URL*** : (REQUIRED INPUT) Object storage bucket uri for backup files.      \
***TTS_BUNDLE_URL*** : (REQUIRED INPUT) Object storage bucket uri for transportable tablespace bundle.\
***OCI_INSTALLER_PATH*** : (REQUIRED INPUT) Path to oci_install.jar\
***CONFIG_FILE*** : (REQUIRED INPUT) Path to dowloaded API keys config file. Make sure to update the key_file parameter with the file path to your private key in the config file.\
***COMPARTMENT_OCID*** :(REQUIRED INPUT) Compartment OCID of bucket  (TTS_BACKUP_URL) that stores backup files. \
***OCI_PROXY_HOST*** : (OPTIONAL INPUT) HTTP proxy server.\
***OCI_PROXY_HOST*** : (OPTIONAL INPUT)  HTTP proxy server connection port.

##### File Storage Service (FSS) inputs ( Required if using FSS for migration. Leave them empty if using OSS. )

***TTS_FSS_CONFIG*** : (REQUIRED INPUT) FSS configuration should given in the format FSS:\<File System Name\>:\<FQDN of Mount Target\>:\<Export Path\>\
***TTS_FSS_MOUNT_DIR*** : (REQUIRED INPUT) Absolute path where file system was mounted on source database host\ 
\
Refer to the blog [How to Attach a File system to your Autonomous Database](<https://blogs.oracle.com/datawarehousing/post/attach-file-system-autonomous-database>) for details on how file system should be configured for use by ADB-S.

##### TDE keys inputs

***TDE_WALLET_STORE_PASSWORD*** : (RUNTIME INPUT, REQUIRED only if any of the tablespaces are TDE Encrypted). DO NOT provide in the file.  Provide as CLI runtime input when prompted.

##### Final backup inputs 

***FINAL_BACKUP*** : (REQUIRED INPUT) Accepted values TRUE/true or FALSE/false. Value should be TRUE for a non-incremental migration. For incremental migration, 
value should be FALSE for all incremental backups including the first backup. Set the value to TRUE for final backup of an incremental migration. Tablespaces 
being transported must be set to READ-ONLY when FINAL_BACKUP is set to TRUE. Tablespace and Schema metadata will be exported only when FINAL_BAKCUP is set to TRUE.

##### Performance inputs     

***PARALLELISM*** : (OPTIONAL INPUT) Number of channels to be used for backup, parallelism = cpu_count \* instances.\
***CPU_COUNT*** : (OPTIONAL INPUT) Number of cpus to be used from an instance (used if parallelism is not given).

Leave these a blank unless really needed.

**Backup Utility Sample Inputs**

Here is an example of [backup utility sample inputs] (https://https://github.com/oracle-devrel/oracle-autonomous-database-samples/tree/main/migration-tools/tts-backup-python/tts_backup_utility_sample_inputs.txt

Run the TTS Backup Tool from the project directory as below. User will be prompted for database password and optional TDE wallet store password.

**Run Backup Utility**
```
    $ python3 tts-backup.py 
    Enter value for required variable DBPASSWORD: Test
    Enter value for optional variable TDE_WALLET_STORE_PASSWORD 
    Required only if any of the tablespaces are TDE encrypted (leave empty and press Enter if not applicable):

```
The tool will take backups of the tablespace datafiles and create a metadata bundle. Both backups and the bundle will be uploaded to the provided OCI Object Storage buckets or FSS Mount Targets. Backup Utility will output an URL to OCI Object Storage metadata bundle or FSS Mount Target path for metadata bundle. User should note the given URL/Path as that will be needed as migration input when creating Autonomous AI Database for the migration.

### Create Dynamic Group and Policy (for OCI Object Storage backups)

Transportable Tablespaces functionality will download metadata from OCI Object Storage metadata bucket using [OCI Resource Principal](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/resource-principal.html). Create Dynamic Group and Policy to allow access to the metadata bucket using the resource principal. This step is not required if using FSS for backups.

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

If user is performing an incremental migration operation, repeat **Backup Tablespaces** step at source database for each incremental using the same set of inputs. Backup Utility will output a new OCI Object Storage URL / FSS Mount Target path corresponding to that increment. Use the URL/Path to update the Autonomous AI Database created with the first backup above. Set FINAL_BACKUP=TRUE in the input file before performing final backup.

#### Modify Autonomous AI Database with Migration inputs

1.  Go to OCI Console → Oracle Database → Autonomous AI Database
2.  Select and click on the database created with the first backup.
3.  Verify ***Storage*** in ***Resource allocation*** section. Use ***Manage resource allocation*** tab to increase storage if needed.
4.  Expand ***Migration section*** on the page.
5.  Specify OCI Object Storage URL or FSS Mount Target path to the metadata bundle as given by Backup Utility for the increment or final backup.
6.  Click on **Save**.

The operation will trigger the transport tablespaces job on the database.
