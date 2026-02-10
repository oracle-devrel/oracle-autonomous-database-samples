# Oracle Autonomous Database: Sample SQL Scripts
Numerous SQL scripts are available to help you get started using Autonomous Database.

Prerequisites:
* Create an Autonomous Database
    * [On OCI](../../multicloud/oci-cli/README.md) 
    * [On Azure](../../multicloud/azure-cli/README.md)
    * [On Google Cloud](../../multicloud/gcloud-cli/README.md)
* Azure and Google Cloud support private endpoints only; a VM must be deployed on the same VCN as Autonomous Database (or on a network that can access your Autonomous Database). OCI supports both public and private endpoints; ADB is deployed using public endpoints in our sample which means you can use your computer to access the database.
* Use these great VS Code extensions that help you develop and debug your database apps:
    * SQL Developer for VS Code ([Learn More](https://www.oracle.com/database/sqldeveloper/vscode/) | [Marketplace](https://marketplace.visualstudio.com/items?itemName=Oracle.sql-developer))
    * Oracle Developer Tools for VS Code  ([Learn More](https://docs.oracle.com/en/database/oracle/developer-tools-for-vscode/getting-started/gettingstarted.html) | [Marketplace](https://marketplace.visualstudio.com/items?itemName=Oracle.oracledevtools)) 

## Connect to Autonomous Database
There are [numerous client tools](../../azure-cli/README.md#whats-next) that you can use to start working with Autonomous Database. This includes the built-in SQL Worksheet that's part of the Database Tools (and available from the linked OCI Console) or a tool like VS Code and one an Oracle Database extension.

## Sample scripts
Try out these scripts to learn how to get started using Autonomous Database. Simply update the [`config.sql`](#configuration-file) script prior to running the samples:

|Script|Description|
|----|---|
|[credential-create.sql](credential-create.sql)|Autonomous Database credentials contain the secret keys used to connect to services - like Azure OpenAI. This script creates those credentials. It's called by multiple scripts listed below |
|[data-create-sample-schema.sql](data-create-sample-schema.sql)|Create a sample user and install sample data|
|[data-import-from-datalake.sql](data-create-synthetic-data.sql)|Import sample data from Azure Data Lake. Sample data was uploaded using the [`create-all-resources.sh`](../../azure-cli/create-all-resources.sh)and [`create-data-lake-storage.sh`](../../azure-cli/create-data-lake-storage.sh) scripts. You can run [`show-data-lake-storage-info.sh`](../../azure-cli/show-data-lake-storage-info.sh) to get connection information to the storage container.|
|[data-export-to-datalake.sql](data-export-to-datalake.sql)|Export data from a table to your data lake storage|
|[select-ai-admin-enable.sql](select-ai-admin-enable.sql)|Autonomous Database is secure by default. In order to access external services, you will need to enable connectivity. This script enables connectivity to your Azure OpenAI resource.|
|[select-ai-create-profile.sql](select-ai-create-profile.sql)|A Select AI profile is used to connect to your AI provider. It includes information about your provider plus tables and view that you want to be targets for natural language queries|
|[select-ai-create-synthetic-data.sql](select-ai-create-synthetic-data.sql)|Use AI to generate sample data sets. You will create tables and then populate them based on rules that you specify.|
|[select-ai-nl2sql.sql](select-ai-nl2sql.sql)|Use natural language to query your data|
|[select-ai-sql-function.sql](select-ai-sql-function.sql)|Use Select AI SQL functions to apply AI to your data. These examples summarize a support chat and make product recommendations based on info in your database|
|[select-ai-transform-and-summarize.sql](select-ai-transform-and-summarize.sql)|This builds on the previous sample. This will use Select AI SQL functions to transform data, parsing unstructured text into structured fields. For example, derive an address from free-form text. Or, derive key phrases and sentiment and return the result in structured format. This is useful for then storing the data in a way that can be queried using SQL|
|[select-ai-rag.sql](select-ai-rag.sql)|Select AI makes it easy to create AI vector management pipelines and then ask questions using AI and your organization's knowledge base|
|[json-duality.sql](json-duality.sql)|Autonomous Database allows you to work with JSON in many different ways. JSON Collections stored your documents in tables. No changes are made to those documents. JSON Duality Views present relational data as JSON - allowing you to query and update that data using the JSON APIs (like MongoDB API) or SQL. Check out both approaches.|

### Configuration file
Many of the SQL scripts rely on information found in your [config.sql](config.sql) file. Update the config file prior to running any of the scripts. 

>**IMPORTANT:** This file will contain sensitive data that should be protected. Set the file's permissions so that only the file's owner can view its contents:
```bash
chmod 600 config.sql
```

|Setting|Description|Example|
|----|----|----|
|CONN|JDBC Connection. Run the script <code>/multicloud/{oci-cli, azure-cli}/show-adb-info.sh</code> to easily get the connection details.|jdbc:oracle:thin:@(description= (retry_count=20)(retry_delay=3)(address=(protocol=tcps)(port=1521)(host=your-host.oraclecloud.com))(connect_data=(service_name=my_quickstart_medium.adb.oraclecloud.com))(security=(ssl_server_dn_match=no)))
|USER_NAME|Database user that will contain sample data|'moviestream'|
|USER_PASSWORD|Password for the sample database user|'watchS0meMovies#'
|**Select AI and GenAI** |[See Select AI documentation](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/sql-generation-ai-autonomous.html)
|AI_PROVIDER|ADB can use different LLMs. Specify the AI provider that will be used by Select AI (oci, azure or google)|'oci'|
|AI_PROFILE_NAME|The Select AI profile name that encapsulates the AI provider info + tables for NL2SQL. Enter a name using valid Oracle Database object naming rules.|'genai'|
|AI_CREDENTIAL_NAME|This is a database credential that captures the secret key or other connection info. Enter a name using valid Oracle Database object naming rules.|'ai_cred'|
|AI_ENDPOINT|The AI provider's endpoint. The endpoint should be the servername only. For example, myopenai.openai.azure.com. This is not required for OCI GenAI.|'ai_cred'|
|AI_KEY|The API key for AI service. This is not required for OCI GenAI.|'3Cu9ABGBCwkyYI...'|
|**Azure OpenAI settings**|
|AZURE_OPENAI_RESOURCE_NAME|Name of the Azure OpenAI resource|'dev-adb-azure-openai'|
|AZURE_OPENAI_DEPLOYMENT_NAME|Your Azure OpenAI deployment name. This is used for NL2SQL and AI SQLfunctions|'gpt-4o'|
|AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME|The Azure OpenAI deployment that uses an embedding model. This is used for creating vector embeddings.|'text-embedding-ada-002'|
|AI_KEY|Azure OpenAI secret key|'3Cu9AB...H53'|
|AI_CREDENTIAL_NAME|The database credential that will be used to connect to Azure OpenAI|'azure_cred4o'|
|**Data Lake/Object Storage**|
|STORAGE_PROVIDER|Name of your storage provider. Valid values are oci, azure or google.|'oci'|
|STORAGE_CREDENTIAL_NAME|The name of the Autonomous Database credential that's used to connect to your object storage service|'storage_cred'|
|STORAGE_URL|The URL that points to your bucket or container. Run the script <code>/multicloud/{oci-cli, azure-cli}/show-data-lake-storage-info.sh</code> to easily get the storage details.|'https://abc.objectstorage.us-ashburn-1.oci.customer-oci.com/n/adwc4pm/b/adb-sample/o'
|STORAGE_ACCOUNT_NAME|Name of your Azure Data Lake Storage Gen 2 account. Run the script <code>/multicloud/{oci-cli, azure-cli}/show-data-lake-storage-info.sh</code> to easily get the storage details.|'mysamplestorage'|
|STORAGE_KEY|The secret key used to connecto Azure Data Lake Storage. Run the script <code>/multicloud/{oci-cli, azure-cli}/show-data-lake-storage-info.sh</code> to easily get the storage details.|'dJVNxq1YTT...jp/g=='
|**OCI API user credentials**|[See Managing Native Credentials documentation](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/autonomous-manage-credentials.html#GUID-863FAF80-AEDB-4128-89E7-3B93FED550E)|
|OCI_USER_OCID|Your OCI user's identifier|'ocid1.user.oc1..aaaa...'|
|OCI_TENANCY_OCID|Your tenancy's identifier|'ocid1.tenancy.oc1..aaaaaaa...'|
|OCI_FINGERPRINT|Your signing key's fingerprint|'ocid1.tenancy.oc1..aaaaaaa...'|
|OCI_PRIVATE_KEY|Your private key. Do not include <code>-----BEGIN RSA PRIVATE KEY-----</code> and <code>-----END RSA PRIVATE KEY-----</code>. Add "-" as a new line character at the end of each line (except the last)|'MIIEpAIBA....-'|


You can find the Azure OpenAI settings in the Azure OpenAI Studio:
![Azure OpenAI settings](images/azure-openai.png)


<hr>
Copyright (c) 2026 Oracle and/or its affiliates.<br>
Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/
