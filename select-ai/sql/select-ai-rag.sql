-- Copyright (c) 2025 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

/* Run this script as the Autonomous Database database user that will be accessing your AI provider */

-- config.sql contains the endpoints, resource groups and other settings required to connect to your Azure OpenAI deployment
@./config.sql

-- Make sure credentials have been defined to enable access to the LLM and the object store files
@credential-create.sql ALL

--
-- Customer support site
--
-- This script will create a vector index using Select AI based on web site files that were uploaded to Azure Blob Storage
-- It's a support site that helps customers get answers to issues with Oracle MovieStream - a fictitious movie streaming service

-- Review the file list that comprise the support web site
SELECT object_name, bytes 
FROM dbms_cloud.list_objects(
    credential_name => '&STORAGE_CREDENTIAL_NAME',
    location_uri => '&STORAGE_URL/support-site'
);

-- Start with the AI profile for our support site that uses Azure OpenAI and a vector index
-- The Vector index will be used for RAG
-- Note: there are many more attributes you can set to fine tune your results:
-- See: https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/select-ai-retrieval-augmented-generation.html
DECLARE 
  l_attributes VARCHAR2(32000);
BEGIN
  -- recreate the profile in case it already exists
  dbms_cloud_ai.drop_profile (
      profile_name => 'SUPPORT_SITE',
      force => true
  );

  -- create an AI profile that will use the SUPPORT vector that's created in the next step. 
  -- Start by defining the attributes for the provider and the vector
  l_attributes := 
    '{"provider": "&AI_PROVIDER",        
      "credential_name": "&AI_CREDENTIAL_NAME",              
      "vector_index_name": "SUPPORT"';
  
  -- Azure has different attributes than the other providers.
  IF upper('&AI_PROVIDER') = 'AZURE' THEN
    l_attributes := l_attributes || 
              ',
              "azure_resource_name": "&AZURE_OPENAI_RESOURCE_NAME",                    
              "azure_deployment_name": "&AZURE_OPENAI_DEPLOYMENT_NAME",
              "azure_embedding_deployment_name":"&AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME"';
  END IF;
  -- Finish the attribute definition
  l_attributes := l_attributes || '}';

  -- now, create the profile
  dbms_cloud_ai.create_profile (
      profile_name => 'SUPPORT_SITE',
      attributes => l_attributes      
  );
END;
/

-- Create your vector index
BEGIN
  -- Recreate the vector index in case it already exists
  dbms_cloud_ai.drop_vector_index (
    index_name => 'SUPPORT',
    force => true
  );

  -- Create a vector index that points to the azure storage location. This will create a pipeline that loads the index and keeps
  -- it up to date

  dbms_cloud_ai.create_vector_index(
    index_name  => 'SUPPORT',
    attributes  => '{"vector_db_provider": "oracle",
                    "object_storage_credential_name": "&STORAGE_CREDENTIAL_NAME",
                    "location": "&STORAGE_URL/support-site/",
                    "profile_name": "SUPPORT_SITE",
                    "vector_table_name":"support_site_vector",
                    "vector_distance_metric": "cosine"
                  }'
  );
END;
/

-- A pipeline was created and you can see it here. The pipeline runs periodically to update the vectors. 
-- Check out the status table to see progress/details
SELECT pipeline_id, pipeline_name, status, last_execution, status_table 
FROM user_cloud_pipelines;

SELECT * 
FROM user_cloud_pipeline_attributes;

SELECT * 
FROM user_cloud_pipeline_history;

-- Review the generated table that has the chunks and vector embedding
SELECT * FROM support_site_vector;

-- Let's ask support questions using Select AI and this new profile
begin
  dbms_cloud_ai.set_profile(
        profile_name => 'SUPPORT_SITE'
    );
end;
/

-- Ask your questions!
SELECT AI NARRATE George Clooney lips are moving but I can not hear him;

-- Or use the PLSQL API
SELECT
  dbms_cloud_ai.generate (
    profile_name => 'SUPPORT_SITE',
    action => 'narrate',
    prompt => 'George Clooney lips are moving but I can not hear him'
  ) as support_question;
