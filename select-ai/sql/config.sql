-- Copyright (c) 2025 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

--
-- Configuration information for Autonomous Database
--
-- Connect string
-- you can get the ADB connection info by running /multicloud/{oci|azure|gcloud}-cli/show-adb-info.sh
define CONN='jdbc:oracle:thin:@(description=...)'
-- user name and password used for the sample data
define USER_NAME='moviestream'
-- # The password is for the sample user. It must be between 12 and 30 characters long and must include at least one uppercase letter, one lowercase letter, and one numeric character
-- example: watchS0meMovies#
define USER_PASSWORD=''

--
-- GENAI
-- Select AI LLM providers are pluggable. ADB will use the one specified below.
--
-- The AI provider: oci, azure or google
define AI_PROVIDER='oci'
-- The Select AI profile name that encapsulates the AI provider info + tables for NL2SQL
define AI_PROFILE_NAME='genai'
-- This is a database credential that captures the secret key or other connection info
define AI_CREDENTIAL_NAME='AI_CRED'

-- The endpoint should be the servername only. This is not required for OCI GenAI. 
-- Examples:
-- myopenai.openai.azure.com
-- us-east4-aiplatform.googleapis.com
define AI_ENDPOINT=''
-- API key for AI service. This is not required for OCI GenAI.
define AI_KEY=''

-- For Azure:
-- Azure OpenAI resource name
define AZURE_OPENAI_RESOURCE_NAME='your-openai-resource-name'
-- Azure OpenAI deployment name
define AZURE_OPENAI_DEPLOYMENT_NAME='your-openai-deployment-name'
-- Azure OpenAI Embedding deployment name. This is used for creating embeddings for RAG
define AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME='your-openai-emedding-deployment-name'

--
-- Data Lake Storage
--
-- valid values for storage provider: oci, azure, google
-- you can get the storage info by running /multicloud/{oci|azure|gcloud}-cli/show-data-lake-storage-info.sh
define STORAGE_PROVIDER='oci'
-- The url is a pointer to the bucket that will be used for import/export to object storage
-- Examples:
-- google: https://storage.googleapis.com/adb-sample
-- azure : https://devadbstorageacct.blob.core.windows.net/adb-sample
-- oci   : https://adwc4pm.objectstorage.us-ashburn-1.oci.customer-oci.com/n/adwc4pm/b/adb-sample/o
define STORAGE_URL=''

-- A database credential encapsulates the authentication details to the object store. Specify a name for the credential below
define STORAGE_CREDENTIAL_NAME='storage_cred'

--Azure storage properties
define AZURE_STORAGE_ACCOUNT_NAME=''
define AZURE_STORAGE_KEY=''
-- Google storage properties
define GOOGLE_STORAGE_ACCESS_KEY=''
define GOOGLE_STORAGE_SECRET=''

--
-- OCI API credentials
--
-- One credential is used to access all services. You can get most of these settings from your ~/.oci/config file
define OCI_USER_OCID=''
define OCI_TENANCY_OCID=''
define OCI_FINGERPRINT=''
-- The private key requires a "-" continuation character at the end of the line. 
-- Do not include the private key's BEGIN and END lines
define OCI_PRIVATE_KEY='example1-
example2-
example3'