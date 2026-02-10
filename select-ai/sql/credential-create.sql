ARGUMENT 1 DEFAULT 'ALL'

define user_param=&1
undefine 1

prompt "Creating credential: &user_param"

-- Get the config information
@config.sql

-- This procedure will recreate credentials. You can specify a credential type (storage, OpenAI)

DECLARE
    l_exists number := 0;
    l_type varchar2(20) := nvl(upper('&user_param'),'ALL');
    l_username varchar2(400);
    l_password varchar2(400);
BEGIN
    -- AI provider. Note, they will have different syntax based on the provider
    if l_type in ('AI','ALL') then
        -- Create your credential. Replace it if already exists
        select COUNT(*)
        into l_exists
        from user_credentials    
        where upper(credential_name)=upper('&AI_CREDENTIAL_NAME');

        -- credential exists, so drop it
        IF l_exists = 1 THEN
            dbms_cloud.drop_credential (
                credential_name => '&AI_CREDENTIAL_NAME'
            );
        END IF;

        -- Check for OCI. 
        IF UPPER('&AI_PROVIDER') = 'OCI' THEN
            dbms_cloud.create_credential(                                               
                credential_name => '&AI_CREDENTIAL_NAME',                                          
                user_ocid       => '&OCI_USER_OCID',    
                tenancy_ocid    => '&OCI_TENANCY_OCID',
                fingerprint     => '&OCI_FINGERPRINT',
                private_key     => '&OCI_PRIVATE_KEY'
            );
        ELSE
            -- All other AI providers
            dbms_cloud.create_credential (                                                 
                credential_name => '&AI_CREDENTIAL_NAME',                                            
                username => UPPER('&AI_PROVIDER'),                                                 
                password => '&AI_KEY'
            );
        END IF; -- OCI vs other AI services
    END IF; -- AI Credential

    -- Create Storage credential
    if l_type in ('STORAGE','ALL') then
        -- Create your credential. Replace it if already exists
        select COUNT(*)
        into l_exists
        from user_credentials    
        where upper(credential_name)=upper('&STORAGE_CREDENTIAL_NAME');

        -- drop existing credential
        IF l_exists = 1 THEN
            dbms_cloud.drop_credential (
                credential_name => '&STORAGE_CREDENTIAL_NAME'
            );
        END IF;

        -- Check for OCI
        IF UPPER('&STORAGE_PROVIDER') = 'OCI' THEN
            dbms_cloud.create_credential(                                               
                credential_name => '&STORAGE_CREDENTIAL_NAME',                                          
                user_ocid       => '&OCI_USER_OCID',    
                tenancy_ocid    => '&OCI_TENANCY_OCID',
                fingerprint     => '&OCI_FINGERPRINT',
                private_key     => '&OCI_PRIVATE_KEY'
            );
        ELSE
            -- Google and Azure use different settings for username and password
            l_username := CASE WHEN UPPER('&STORAGE_PROVIDER') = 'AZURE' THEN '&AZURE_STORAGE_ACCOUNT_NAME' ELSE '&GOOGLE_STORAGE_ACCESS_KEY' END;
            l_password := CASE WHEN UPPER('&STORAGE_PROVIDER') = 'AZURE' THEN '&AZURE_STORAGE_KEY' ELSE '&GOOGLE_STORAGE_SECRET' END;

            dbms_cloud.create_credential(
                credential_name => '&STORAGE_CREDENTIAL_NAME',
                username => l_username,
                password => l_password
            );
        END IF; -- OCI vs other AI services
    END IF; -- Storage   
END;
/

-- Review the credentials
COLUMN credential_name FORMAT A40
COLUMN username FORMAT A40

select 
    credential_name, 
    username 
from user_credentials;
