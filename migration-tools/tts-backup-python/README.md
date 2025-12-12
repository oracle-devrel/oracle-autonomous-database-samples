# Transportable Tablespaces Using Backup

Transportable Tablespaces can be used to move tablespaces from customer
on-premise or another database cloud service into ADB-S. Tablespaces can
be transported when creating a new database in ADB-S or as modify
operation on an existing database.

## Step-by-step guide

Transporting Tablespaces involves the following steps.

1.  Create Object Storage Buckets

2.  Create Dynamic Group and Policy

3.  Backup Tablespaces on Source Database

4.  Create or Modify database in ADB-S by specifying intent to transport
    tablespaces using a tag

### Create Object Storage Buckets

Transportable Tablespaces needs two object storage buckets - one for
backups and another for metadata. Create the buckets in your Oracle
Storage Cloud Service account. Note the URLs of the buckets as they are
needed as inputs for the operation. Use [Oracle Cloud Infrastructure Object Storage Native URI Format](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/file-uri-formats.html) for the URL.

Example:
[https://objectstorage.region.oraclecloud.com/n/\<namespace-string\>/b/\<bucket-name\>](https://objectstorage.region.oraclecloud.com/n/namespace-string/b/bucket/o/filename)

To make Object Storage URI work, please [generate an API signing key](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm)].
Download the private key .pem file and the API signing key config file with below contents to source database host.

    [DEFAULT]

    user=ocid1.user.oc1..xxxxx

    fingerprint=f6:d6:e5:xxxxx

    tenancy=ocid1.tenancy.oc1..xxxxx

    region=us-ashburn-1

    key_file=<path to the downloaded private key file>

Note - User should have read and write access to the object storage buckets.

## Create Dynamic Group and Policy

Transportable Tablespaces functionality will download metadata from metadata bucket using [OCI Resource Principal](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/resource-principal.html)].

### Create Dynamic Group and Policy to allow access to the metadata bucket using the resource principal.

1.  Create a Dynamic Group **TTSDynamicGroup** with matching rule:\
    ALL {resource.type = \'autonomousdatabase\', [resource.compartment.id](http://resource.compartment.id) = \'your_Compartment_OCID\'}

2.  Create a Policy using the dynamic group with Policy Statement:\
    Allow dynamic-group **TTSDynamicGroup** to manage buckets in tenancy\
    Allow dynamic-group **TTSDynamicGroup** to manage objects in tenancy\
    \
    Prepend domain name to the dynamic group name if needed as below.\
    Allow dynamic-group \<*identity_domain_name\>*/**TTSDynamicGroup** to manage buckets in tenancy\
    Allow dynamic-group \<*identity_domain_name\>*/**TTSDynamicGroup** to manage objects in tenancy

### Backup Tablespaces on Source Database

#### Pre-requisites

- Create a Project Directory that will used as staging location on the host running the source database.
- Download [Oracle Database Backup Cloud Module](https://www.oracle.com/database/technologies/oracle-cloud-backup-downloads.html) to the Project Directory. Unzip the downloaded opc_installer.zip in the project directory.
- Download [tts-backup-python.zip](file:////confluence/download/attachments/11465427748/tts-backup-python.zip%3fversion=33&modificationDate=1764740426000&api=v2) to the project directory. Unzip the tts-backup-python.zip in the project directory.
- Provide inputs for backup in the **tts-backup-env.txt** file.
- [tts-backup-python.zip for VodaFone](file:////confluence/download/attachments/11465427748/tts-backup-python.zip%3fversion=33&modificationDate=1764740426000&api=v2)

#### TTS Backup Tool inputs

Open tts-backup-env.txt file downloaded to the project directory and provide the following inputs in the file.

##### Project and Tablespace inputs

***PROJECT_NAME** ***: Name for transport tablespace project. (REQUIRED INPUT) \
***DATABASE_NAME*** : Database Name containing the tablespaces.  (REQUIRED INPUT) \
***TABLESPACES*** : List of comma separated transportable tablespaces.  (OPTIONAL INPUT) if empty all user tablespaces are added.\
***SCHEMAS*** : List of comma separated transportable schemas. (OPTIONAL INPUT) if empty all required users are added. None of the schemas should be a common user.

##### Database connection inputs

***HOSTNAME*** : (REQUIRED INPUT) Host where database is running, used for connecting to the database.\
***LSNR_PORT*** : (REQUIRED INPUT) Listener port, used for connecting to the database.  \
***DB_SVC_NAME*** : (REQUIRED INPUT) Database service name, used for connecting to the database.  \
***ORAHOME*** : (REQUIRED INPUT) Database home, \$ORACLE_HOME.\
***DBUSER*** : (REQUIRED INPUT) Username for connecting to the database.  User should have sysdba privileges. \
***DBPASSWORD*** : (REQUIRED INPUT) Password for connection to the database. (Provide as CLI argument or Runtime input)\
***DB_VERSION*** : (REQUIRED INPUT) DB Version, supported values are 11g, 12c, 19c, 23ai.

##### Object Storage Service (OSS) inputs ( Required if using OSS for transport. Leave them empty if using FSS. )

***TTS_BACKUP_URL*** : (REQUIRED INPUT) Object storage bucket uri for backup files.      \
***TTS_BUNDLE_URL*** : (REQUIRED INPUT) Object storage bucket uri for transportable tablespace bundle.\
***OCI_INSTALLER_PATH :*** (REQUIRED INPUT) Path to oci_install.jar\
***CONFIG_FILE :*** **(REQUIRED INPUT) Path to dowloaded API keys config file. Make sure to update the key_file parameter with the file path to your private key in the config file.\
***COMPARTMENT_OCID :*** **(REQUIRED INPUT) Compartment OCID of bucket  (TTS_BACKUP_URL) that stores backup files. \
***OCI_PROXY_HOST :** ***(OPTIONAL INPUT) HTTP proxy server.\
***OCI_PROXY_HOST :** ***(OPTIONAL INPUT)  HTTP proxy server connection port.

##### File Storage Service (FSS) inputs ( Required if using FSS for transport. Leave them empty if using OSS. )

***TTS_FSS_CONFIG*** : (REQUIRED INPUT) FSS configuration should given in the format FSS:\<FIle System Name\>:\<FQDN of Mount Target\>:\<Export Path\>\
***TTS_FSS_MOUNT_DIR*** : (REQUIRED INPUT) Absolute path where file system was mounted on source database host\
\
Refer to [<https://blogs.oracle.com/datawarehousing/post/attach-file-system-autonomous-database>] for details on how File System should be configured for use by ADB-S.

##### TDE keys inputs

***TDE_WALLET_STORE_PASSWORD*** : (REQUIRED only if any of the tablespaces are TDE Encrypted). Required to export TDE KEYS. (Provide as CLI argument or Runtime input)

##### Final backup inputs 

***FINAL_BACKUP*** : (REQUIRED INPUT) Final backup will be done only if FINAL_BACKUP=yes or YES. Accepted values YES, yes, NO, no. Used to indicate incremental operation. Specify YES for non-incremental operation. Specify NO for incremental backups. Last operation should be run with YES for schema to be exported.

##### Performance inputs     

***PARALLELISM*** : (OPTIONAL INPUT) Number of channels to be used for backup, parallelism = cpu_count \* instances.\
***CPU_COUNT*** : (OPTIONAL INPUT) Number of cpus to be used from an instance (used if parallelism is not given).

Leave these a blank unless really needed.

### Create or Modify ADB-S database with TTS tag

#### Create ADB-S database to transport tablespaces

Use the below steps to transport tablespaces while creating an ADB-S database.

	1.  Go to OCI Console → Oracle Database → Autonomous Database
	2.  Click on ***Create Autonomous Database***
	3.  Provide all the necessary inputs.
	4.  Select database version that is equal to or greater than the source database.
	5.  Specify ***Storage (TB)*** in ***Configure the database*** section to match size of tablespace(s) being transported.
	6.  Click on ***Show advanced options*** at the bottom of the page.  Click on ***Tags*** tab in the section.
	7.  Select ***Tag namespace*** **as ***None (add a free-form tag)***, ***Tag key*** as ***ADB\$TTS_BUNDLE_URL***, 
	    **Tag value** as metadata bundle url given by the TTS backup tool.
	8.  Click on ***Add Tag.***
	9.  Submit ***Create Autonomous Database.***

The operation will first create the database and then trigger transport tablespaces job.

#### Modify ADB-S database to transport tablespaces

Use the below steps to transport tablespaces to an existing database.

	1.  Go to OCI Console → Oracle Database → Autonomous Database
	2.  Select and click on the database for transporting tablespaces
	3.  Verify ***Storage*** in ***Resource allocation*** section. Use ***Manage resource allocation*** tab to increase storage if needed.
	4.  If this is the first time specifying **ADB\$TTS_BUNDLE_URL** tag on the database:
    		a.  Go to ***More Actions* *→* *Tags** ****menu item on the Autonomous Database Details page.*
    		b.  Select ***Tag namespace*** **as ***None (add a free-form tag)***, ***Tag key*** as ***ADB\$TTS_BUNDLE_URL***, \
		    **Tag value** as metadata bundle url given by the TTS backup tool.
    		c.  Click on ***Add Tag.***
    		d.  Submit ***Add Tags***.
	5.  If **ADB\$TTS_BUNDLE_URL** tag was already specified during create or a previous update of the database:
    		a.  Click on the **Tags** tab on the Autonomous Database Details page.
    		b.  Click on **Free-Form tags** tab and edit the **ADB\$TTS_BUNDLE_URL** tag. 
    		c.  Specify the new URL and submit **Save** action.

The operation will trigger the transport tablespaces job on the database.

#### To transport tablespaces using incremental database backups

Create a database or update an existing database by specifying **ADB\$TTS_BUNDLE_URL** of level 0 backup.\
For each incremental and final backup, edit the tag using the URL corresponding to that backup as mentioned in **Step 5** above. \
Before taking the final backup, alter all tablespaces being transported as read-only. Specify FINAL_BACKUP as YES in tts-backup-env.txt.\
Datafiles with incremental changes are restored to ADB-S from level 0 to final step. Metadata is imported on final step.

#### To transport tablespaces using non-incremental database backups

Non-incremental is a one time operation where datafiles are restored and metadata is imported to ADB-S.\
Alter all tabalespaces being transported as read-only. Specify FINAL_BACKUP as YES in tts-backup-env.txt.\
Create a database or update an existing database by specifying **ADB\$TTS_BUNDLE_URL** of one time backup.

