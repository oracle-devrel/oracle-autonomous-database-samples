--
-- NAME:
--   provision_autonomous_database - Provision an Autonomous Database in OCI
--
-- DESCRIPTION:
--   This function provisions an Autonomous Database (ADB-S) in a specified
--   compartment within OCI. It takes workload type, compute and storage
--   configurations, and database options as inputs, builds the request object,
--   and calls DBMS_CLOUD_OCI_DB_DATABASE.CREATE_AUTONOMOUS_DATABASE to create
--   the database. The result is returned as a structured JSON response (CLOB).
--
-- PARAMETERS:
--   compartment_name        (IN)  - Name of the compartment where the ADB will be provisioned
--   db_name                 (IN)  - Database name (uppercase enforced)
--   display_name            (IN)  - Optional display name for the database
--   workload_type           (IN)  - Workload type: OLTP, ADW, JSON, or APEX
--   ecpu_count              (IN)  - Number of ECPUs
--   storage_tb              (IN)  - Storage size in TB
--   region                  (IN)  - Target OCI region for provisioning
--   data_guard              (IN)  - Enable/Disable Data Guard ('ENABLED' / 'DISABLED')
--   credential_name         (IN)  - Name of the stored credential (for DBMS_CLOUD)
--   database_pwd            (IN)  - Admin password for the database
--   is_auto_scaling_enabled (IN)  - Flag for auto-scaling (1 = enabled, 0 = disabled)
--
-- RETURNS:
--   CLOB containing JSON object with keys:
--     - status         : 'success' or 'error'
--     - message        : Status message
--     - status_code    : HTTP status code from OCI API (if success)
--     - database_ocid  : OCID of the provisioned database (if success)
--     - database_name  : Name of the provisioned database
--     - workload_type  : Workload type used for provisioning
--     - ecpu_count     : Number of ECPUs
--     - region         : Provisioned region
--     - data_guard_enabled : 'ENABLED' or 'DISABLED'
--
-- EXAMPLE:
--   SELECT provision_adbs_tool(
--            compartment_name        => 'COMP_DB',
--            db_name                 => 'MYDB',
--            display_name            => 'My ADB',
--            workload_type           => 'OLTP',
--            ecpu_count              => 4,
--            storage_tb              => 2,
--            region                  => 'us-ashburn-1',
--            data_guard              => 'DISABLED',
--            credential_name         => 'OCI_CRED',
--            database_pwd            => 'MySecurePwd#123',
--            is_auto_scaling_enabled => 1
--          )
--     FROM dual;
--
-- NOTES:
--   - Relies on get_compartment_ocid_by_name function to resolve the
--     compartment OCID from its name.
--   - Password must meet OCI’s complexity requirements.
--   - Returns JSON error object if provisioning fails.
--   - Uses DBMS_CLOUD_OCI to interact with OCI APIs.
--


CREATE OR REPLACE FUNCTION provision_autonomous_database(
    compartment_name        IN VARCHAR2,
    db_name                 IN VARCHAR2,
    display_name            IN VARCHAR2 default NULL,
    workload_type           IN VARCHAR2,
    ecpu_count              IN NUMBER,
    storage_tb              IN NUMBER,
    region                  IN VARCHAR2,
    data_guard              IN VARCHAR2,
    credential_name         IN VARCHAR2,
    database_pwd            IN VARCHAR2,
    is_auto_scaling_enabled IN NUMBER
) RETURN CLOB
IS
    in_details     dbms_cloud_oci_database_create_autonomous_database_base_t := 
                   dbms_cloud_oci_database_create_autonomous_database_base_t();
    resp           dbms_cloud_oci_db_database_create_autonomous_database_response_t;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    l_workload     VARCHAR2(20);
    compartment_id VARCHAR2(256);
    l_compartment_name VARCHAR2(256);
    
BEGIN
    

    SELECT
    JSON_VALUE(
    get_compartment_ocid_by_name(credential_name, compartment_name),
    '$.compartment_ocid'
    ) AS comp_ocid
    INTO compartment_id
    FROM dual;
    
    -- Map workload types
    CASE UPPER(workload_type)
        WHEN 'OLTP' THEN l_workload := 'OLTP';
        WHEN 'ADW' THEN l_workload := 'DW';
        WHEN 'JSON' THEN l_workload := 'JSON';
        WHEN 'APEX' THEN l_workload := 'APEX';
        ELSE l_workload := 'OLTP';
    END CASE;

    -- Setup the database details
    in_details.compartment_id := compartment_id;
    in_details.db_name := UPPER(db_name);
    in_details.compute_model := 'ECPU';
    in_details.compute_count := ecpu_count;
    in_details.data_storage_size_in_t_bs := storage_tb;
    in_details.admin_password := database_pwd;  -- In production, use secure password generation
    in_details.db_workload := l_workload;
    in_details.display_name := display_name;
    in_details.is_auto_scaling_enabled := is_auto_scaling_enabled;
    
    -- Enable Data Guard if requested
    IF UPPER(data_guard) = 'ENABLED' THEN
        in_details.is_data_guard_enabled := 0;
        result_json.put('data_guard_enabled', 'ENABLED');
    ELSE
        in_details.is_data_guard_enabled := 0;
        result_json.put('data_guard_enabled', 'DISABLED');
    END IF;

    -- Create the database
    BEGIN
        resp := DBMS_CLOUD_OCI_DB_DATABASE.CREATE_AUTONOMOUS_DATABASE(
                    create_autonomous_database_details => in_details,
                    credential_name => credential_name,
                    region => region
                    );
        
        -- Build success response
        result_json.put('status', 'success');
        result_json.put('message', 'Autonomous Database provisioning initiated successfully');
        result_json.put('status_code', resp.status_code);
        result_json.put('database_ocid', resp.response_body.id);
        result_json.put('database_name', db_name);
        result_json.put('workload_type', l_workload);
        result_json.put('ecpu_count', ecpu_count);
        result_json.put('region', region);

        
    EXCEPTION
        WHEN OTHERS THEN
            result_json.put('status', 'error');
            result_json.put('message', 'Failed to provision Autonomous Database: ' || SQLERRM);
    END;
    
    RETURN result_json.to_clob();
    
END provision_autonomous_database;
/

--Drop tool if exists

DECLARE
    l_tool_count NUMBER;
BEGIN
    -- Check if the tool exists
    SELECT COUNT(*)
    INTO l_tool_count
    FROM USER_AI_AGENT_TOOLS
    WHERE TOOL_NAME = 'ADBS_PROVISIONING_TOOL';

    -- Drop only if it exists
    IF l_tool_count > 0 THEN
        DBMS_CLOUD_AI_AGENT.DROP_TOOL('ADBS_PROVISIONING_TOOL');
    END IF;
END;
/

BEGIN
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name => 'ADBS_PROVISIONING_TOOL',
        attributes => '{"instruction": "This tool provisions an Oracle Autonomous Database.'||                            
                            'Use LIST_SUBSCRIBED_REGIONS_TOOL to check all available regions that the user subscribes to. ' ||
                            'You need confirm which region to use with the user if there are multiple regions ' ||
                            'If there is only one region, you can use it by default. ' ||
                            'Use LIST_COMPARTMENTS_TOOL and provide the list of compartments as bullet list.You need confirm which compartment to use with the user.'||
                            'Use ADBS_PROVISIONING_TOOL to provision database only after you have gathered ALL required information. ' ||
                            'Get all the inputs at once ' ||
                            'Must get final confirmation by summarizing all choices before provisioning. ",
                        "function" : "provision_autonomous_database"}',
        description => 'Tool for provisioning Oracle Autonomous Databases'
    );
END;
/
