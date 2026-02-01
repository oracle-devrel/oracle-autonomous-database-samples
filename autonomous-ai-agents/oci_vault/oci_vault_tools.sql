rem ============================================================================
rem LICENSE
rem   Copyright (c) 2025 Oracle and/or its affiliates.
rem   Licensed under the Universal Permissive License (UPL), Version 1.0
rem   https://oss.oracle.com/licenses/upl/
rem
rem NAME
rem   oci_vault_tools.sql
rem
rem DESCRIPTION
rem   Installer script for OCI Vault AI tools
rem   (Select AI Agent / Oracle Autonomous AI Database).
rem
rem   This script installs a consolidated PL/SQL package and registers
rem   AI Agent tools used to automate OCI Vault operations
rem   via Select AI Agent (Oracle Autonomous AI Database).
rem
rem RELEASE VERSION
rem   1.1
rem
rem RELEASE DATE
rem   30-Jan-2026
rem
rem MAJOR CHANGES IN THIS RELEASE
rem   - Initial release
rem   - Added OCI Vault AI agent tool registrations
rem
rem SCRIPT STRUCTURE
rem   1. Initialization:
rem        - Grants
rem        - Configuration setup
rem
rem   2. Package Deployment:
rem        - &&INSTALL_SCHEMA.oci_vault_agents
rem          (package specification and body)
rem
rem   3. AI Tool Setup:
rem        - Creation of all OCI Vault agent tools
rem
rem INSTALL INSTRUCTIONS
rem   1. Connect as ADMIN or a user with required privileges
rem
rem   2. Run the script using SQL*Plus or SQLcl:
rem
rem      sqlplus admin@db @oci_vault_agent_install.sql <INSTALL_SCHEMA> [CONFIG_JSON]
rem
rem   3. Minimal install (uses defaults):
rem
rem      sqlplus admin@db @oci_vault_tools.sql <INSTALL_SCHEMA>
rem
rem   4. Verify installation by checking tool registration
rem      and package compilation status.
rem
rem PARAMETERS
rem   INSTALL_SCHEMA (Required)
rem     Schema in which the package and tools will be created.
rem
rem   CONFIG_JSON (Optional)
rem     JSON string used to configure OCI access.
rem
rem NOTES
rem   - Optional CONFIG_JSON keys:
rem       * credential_name (string)
rem       * compartment_name (string)
rem
rem   - Configuration can also be updated post-install
rem     in the SELECTAI_AGENT_CONFIG table.
rem
rem   - This script is idempotent only if DROP logic
rem     is explicitly enabled.
rem
rem
rem ============================================================================


SET SERVEROUTPUT ON
SET VERIFY OFF

-- First argument: Schema Name (Required)
ACCEPT SCHEMA_NAME CHAR PROMPT 'Enter schema name: '
DEFINE INSTALL_SCHEMA = '&SCHEMA_NAME'

-- Second argument: JSON config (Optional)
PROMPT
PROMPT Enter the OCI Agent configuration values in JSON format.
PROMPT The OCI credential is required to connect to OCI resources.
PROMPT The compartment name is also required.
PROMPT
PROMPT Example:
PROMPT {"credential_name":"MY_CRED","compartment_name":"MY_COMP"}
PROMPT
PROMPT Press ENTER to skip this step.
PROMPT If not provided now, the configuration can be added later in the SELECTAI_AGENT_CONFIG table.
PROMPT

ACCEPT INSTALL_CONFIG_JSON CHAR PROMPT 'Enter INSTALL_CONFIG_JSON (optional): '
DEFINE INSTALL_CONFIG_JSON = '&INSTALL_CONFIG_JSON'

-------------------------------------------------------------------------------
-- Initializes the OCI Vault AI Agent. This procedure:
--   • Grants all required DBMS_CLOUD_OCI Vault type privileges.
--   • Creates the SELECTAI_AGENT_CONFIG table.
--   • Parses the JSON config and persists credential, compartment.
-- Ensures the Vault agent is fully ready for tool execution.
-------------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE initialize_vault_agent(
  p_install_schema_name IN VARCHAR2,
  p_config_json         IN CLOB
)
IS
  -- local vars
  l_use_rp              BOOLEAN := NULL;
  l_credential_name     VARCHAR2(4000) := NULL;
  l_compartment_ocid    VARCHAR2(4000) := NULL;
  l_compartment_name    VARCHAR2(4000) := NULL;
  l_schema_name         VARCHAR2(128);
  c_vault_agent CONSTANT VARCHAR2(64) := 'OCI_VAULT';

  TYPE priv_list_t IS VARRAY(100) OF VARCHAR2(4000);
  l_priv_list CONSTANT priv_list_t := priv_list_t(
    'DBMS_CLOUD_ADMIN',
    'DBMS_CLOUD_OCI_VT_VAULTS',
    'DBMS_CLOUD_OCI_VT_VAULTS_CREATE_SECRET_RESPONSE_T',
    'DBMS_CLOUD_OCI_VAULT_SECRET_T',
    'DBMS_CLOUD_OCI_VAULT_CREATE_SECRET_DETAILS_T',
    'DBMS_CLOUD_OCI_VAULT_BASE64_SECRET_CONTENT_DETAILS_T',
    'DBMS_CLOUD_OCI_VAULT_SECRET_RULE_TBL',
    'DBMS_CLOUD_OCI_VT_VAULTS_GET_SECRET_RESPONSE_T',
    'DBMS_CLOUD_OCI_VT_VAULTS_LIST_SECRETS_RESPONSE_T',
    'DBMS_CLOUD_OCI_VAULT_SECRET_SUMMARY_TBL',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_GET_NAMESPACE_RESPONSE_T',
    'DBMS_CLOUD_OCI_VT_VAULTS_LIST_SECRET_VERSIONS_RESPONSE_T',
    'DBMS_CLOUD_OCI_VAULT_SECRET_VERSION_SUMMARY_TBL',
    'DBMS_CLOUD_OCI_VT_VAULTS_GET_SECRET_VERSION_RESPONSE_T',
    'DBMS_CLOUD_OCI_VAULT_SECRET_VERSION_T',
    'DBMS_CLOUD_OCI_VT_VAULTS_UPDATE_SECRET_RESPONSE_T',
    'DBMS_CLOUD_OCI_VAULT_UPDATE_SECRET_DETAILS_T',
    'DBMS_CLOUD_OCI_VT_VAULTS_SCHEDULE_SECRET_DELETION_RESPONSE_T',
    'DBMS_CLOUD_OCI_VAULT_SCHEDULE_SECRET_DELETION_DETAILS_T',
    'DBMS_CLOUD_OCI_VT_VAULTS_CANCEL_SECRET_DELETION_RESPONSE_T',
    'DBMS_CLOUD_OCI_VT_VAULTS_CHANGE_SECRET_COMPARTMENT_RESPONSE_T',
    'DBMS_CLOUD_OCI_VAULT_CHANGE_SECRET_COMPARTMENT_DETAILS_T',
    'DBMS_CLOUD_OCI_VT_VAULTS_SCHEDULE_SECRET_VERSION_DELETION_RESPONSE_T',
    'DBMS_CLOUD_OCI_VAULT_SCHEDULE_SECRET_VERSION_DELETION_DETAILS_T',
    'DBMS_CLOUD_OCI_VT_VAULTS_CANCEL_SECRET_VERSION_DELETION_RESPONSE_T'
  );

  ----------------------------------------------------------------------------
  -- Helper: grant execute on list of objects
  ----------------------------------------------------------------------------
  PROCEDURE execute_grants(p_schema IN VARCHAR2, p_objects IN priv_list_t) IS
  BEGIN
    EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.V_$PDBS TO ' || p_schema;
    FOR i IN 1 .. p_objects.COUNT LOOP
      BEGIN
        EXECUTE IMMEDIATE 'GRANT EXECUTE ON ' || p_objects(i) || ' TO ' || p_schema;
      EXCEPTION
        WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('Warning: failed to grant ' || p_objects(i) ||
                               ' to ' || p_schema || ' - ' || SQLERRM);
      END;
    END LOOP;
  END execute_grants;

  ----------------------------------------------------------------------------
  -- get_config: returns parsed values via OUT params (no globals modified)
  ----------------------------------------------------------------------------
  PROCEDURE get_config(
    p_config_json       IN  CLOB,
    o_use_rp            OUT BOOLEAN,
    o_credential_name   OUT VARCHAR2,
    o_compartment_name  OUT VARCHAR2,
    o_compartment_ocid  OUT VARCHAR2
  ) IS
    l_cfg JSON_OBJECT_T := NULL;
  BEGIN
    -- initialize outs to NULL for deterministic behavior
    o_use_rp := NULL;
    o_credential_name := NULL;
    o_compartment_name := NULL;
    o_compartment_ocid := NULL;

    -- only parse if JSON is not null or empty
    IF p_config_json IS NOT NULL AND TRIM(p_config_json) IS NOT NULL THEN
      BEGIN
        l_cfg := JSON_OBJECT_T.parse(p_config_json);

        IF l_cfg.has('use_resource_principal') THEN
          o_use_rp := l_cfg.get_boolean('use_resource_principal');
        END IF;

        IF l_cfg.has('credential_name') THEN
          o_credential_name := l_cfg.get_string('credential_name');
        END IF;

        IF l_cfg.has('compartment_name') THEN
          o_compartment_name := l_cfg.get_string('compartment_name');
        END IF;

        IF l_cfg.has('compartment_ocid') THEN
          o_compartment_ocid := l_cfg.get_string('compartment_ocid');
        END IF;

      EXCEPTION
        WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('Config JSON parse failed: ' || SQLERRM);
          -- leave outs as NULL so default logic applies upstream
          o_use_rp := NULL;
          o_credential_name := NULL;
          o_compartment_name := NULL;
          o_compartment_ocid := NULL;
      END;
    ELSE
      DBMS_OUTPUT.PUT_LINE('No config JSON provided, using defaults.');
    END IF;
  END get_config;

  ----------------------------------------------------------------------------
  -- Helper: generic MERGE for a single config key/value
  ----------------------------------------------------------------------------
  PROCEDURE merge_config_key(
    p_schema IN VARCHAR2,
    p_key    IN VARCHAR2,
    p_val    IN CLOB,
    p_agent  IN VARCHAR2
  ) IS
    l_sql CLOB;
  BEGIN
    l_sql :=
      'MERGE INTO ' || p_schema || '.SELECTAI_AGENT_CONFIG c
         USING (SELECT :k AS "KEY", :v AS "VALUE", :a AS "AGENT" FROM DUAL) src
           ON (c."KEY" = src."KEY" AND c."AGENT" = src."AGENT")
       WHEN MATCHED THEN
         UPDATE SET c."VALUE" = src."VALUE"
       WHEN NOT MATCHED THEN
         INSERT ("KEY", "VALUE", "AGENT") VALUES (src."KEY", src."VALUE", src."AGENT")';

    EXECUTE IMMEDIATE l_sql
      USING p_key, p_val, p_agent;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Warning: failed to persist ' || p_key || ' config: ' || SQLERRM);
  END merge_config_key;

  ----------------------------------------------------------------------------
  -- Combined helper: Apply config and insert into config table
  ----------------------------------------------------------------------------
  PROCEDURE apply_config(
    p_schema                IN VARCHAR2,
    p_use_rp                IN BOOLEAN,
    p_credential_name       IN VARCHAR2,
    p_compartment_name      IN VARCHAR2,
    p_compartment_ocid      IN VARCHAR2
  ) IS
    l_effective_use_rp  BOOLEAN;
    l_enable_rp_str     VARCHAR2(3);
  BEGIN
    -- Determine effective value for resource principal:
    -- If JSON supplied a value, use it. If not supplied, default to TRUE (YES).
    IF p_use_rp IS NULL THEN
      l_effective_use_rp := TRUE; -- default is YES when not provided
    ELSE
      l_effective_use_rp := p_use_rp;
    END IF;

    -- Persist credential_name, compartment_ocid, compartment_name if present
    IF p_credential_name IS NOT NULL THEN
      merge_config_key(p_schema, 'CREDENTIAL_NAME', p_credential_name, c_vault_agent);
    END IF;

    IF p_compartment_ocid IS NOT NULL THEN
      merge_config_key(p_schema, 'COMPARTMENT_OCID', p_compartment_ocid, c_vault_agent);
    END IF;

    IF p_compartment_name IS NOT NULL THEN
      merge_config_key(p_schema, 'COMPARTMENT_NAME', p_compartment_name, c_vault_agent);
    END IF;

    -- Persist ENABLE_RESOURCE_PRINCIPAL as YES/NO based on effective value (default YES)
    IF l_effective_use_rp THEN
      l_enable_rp_str := 'YES';
    ELSE
      l_enable_rp_str := 'NO';
    END IF;

    merge_config_key(p_schema, 'ENABLE_RESOURCE_PRINCIPAL', l_enable_rp_str, c_vault_agent);

    -- Now enable or skip enabling resource principal at DB level based on effective flag
    IF l_effective_use_rp THEN
      BEGIN
        DBMS_CLOUD_ADMIN.ENABLE_RESOURCE_PRINCIPAL(USERNAME => p_schema);
        DBMS_OUTPUT.PUT_LINE('Resource principal enabled for ' || p_schema);
      EXCEPTION
        WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('Failed to enable resource principal for ' || p_schema || ' - ' || SQLERRM);
          -- continue; user may prefer to use a credential instead
      END;
    ELSE
      DBMS_OUTPUT.PUT_LINE(
        'Resource principal NOT enabled per config. Using credential: '
        || NVL(p_credential_name, '<not provided>')
      );
    END IF;
  END apply_config;

BEGIN
  -- Validate schema name to avoid SQL injection when used in identifiers
  l_schema_name := DBMS_ASSERT.SIMPLE_SQL_NAME(p_install_schema_name);

  -- Grant required execute privileges using helper
  execute_grants(l_schema_name, l_priv_list);

  -- Parse optional config JSON into local variables
  get_config(
    p_config_json       => p_config_json,
    o_use_rp            => l_use_rp,
    o_credential_name   => l_credential_name,
    o_compartment_name  => l_compartment_name,
    o_compartment_ocid  => l_compartment_ocid
  );

  -- Create generic agent config table
  BEGIN
    EXECUTE IMMEDIATE
      'CREATE TABLE ' || l_schema_name || '.SELECTAI_AGENT_CONFIG (
         "ID"     NUMBER GENERATED BY DEFAULT AS IDENTITY,
         "KEY"    VARCHAR2(200) NOT NULL,
         "VALUE"  CLOB,
         "AGENT"  VARCHAR2(128) NOT NULL,
         CONSTRAINT SELECTAI_AGENT_CONFIG_PK PRIMARY KEY ("ID"),
         CONSTRAINT SELECTAI_AGENT_CONFIG_UK UNIQUE ("KEY","AGENT")
       )';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -955 THEN
        NULL; -- already exists
      ELSE
        RAISE;
      END IF;
  END;

  -- Apply config and insert into config table
  apply_config(
    p_schema              => l_schema_name,
    p_use_rp              => l_use_rp,
    p_credential_name     => l_credential_name,
    p_compartment_name    => l_compartment_name,
    p_compartment_ocid    => l_compartment_ocid
  );

  DBMS_OUTPUT.PUT_LINE('initialize_vault_agent completed for schema ' || l_schema_name);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Fatal error in initialize_vault_agent: ' || SQLERRM);
    RAISE;
END initialize_vault_agent;
/
-------------------------------------------------------------------------------
-- Call initialize_vault_agent procedure
-------------------------------------------------------------------------------
BEGIN
  initialize_vault_agent(
    p_install_schema_name => '&&INSTALL_SCHEMA',
    p_config_json         => '&&INSTALL_CONFIG_JSON'
  );
END;
/


alter session set current_schema = &&INSTALL_SCHEMA;

------------------------------------------------------------------------
-- Package specification
------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE oci_vault_agents
AS
  /*
    Package: oci_vault_agents
    Purpose: collection of PL/SQL helper functions for OCI Vault operations
    NOTE: functions return CLOB JSON describing result, status_code, and headers
  */
   FUNCTION get_namespace(
    region           IN VARCHAR2
  ) RETURN CLOB;
  
  PROCEDURE resolve_metadata(
    region          IN  VARCHAR2,
    namespace       OUT VARCHAR2,
    compartment_id  OUT VARCHAR2
  );
  
  FUNCTION get_compartment_ocid_by_name(
    compartment_name IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION create_secret (
      secret_name         IN VARCHAR2,
      plain_text          IN VARCHAR2,
      description         IN VARCHAR2,
      vault_id            IN VARCHAR2,
      key_id              IN VARCHAR2,
      region              IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION get_secret (
      secret_id       IN VARCHAR2,
      region          IN VARCHAR2
  ) RETURN CLOB;

  -- Additional functions consolidated into the package
  FUNCTION list_secrets (
      region           IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION list_secret_versions (
      secret_id IN VARCHAR2,
      region    IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION get_secret_version (
      secret_id             IN VARCHAR2,
      secret_version_number IN NUMBER,
      region                IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION update_secret (
      secret_id              IN VARCHAR2,
      description            IN VARCHAR2 DEFAULT NULL,
      current_version_number IN NUMBER   DEFAULT NULL,
      plain_text             IN VARCHAR2 DEFAULT NULL,
      defined_tags           IN JSON_ELEMENT_T DEFAULT NULL,
      freeform_tags          IN JSON_ELEMENT_T DEFAULT NULL,
      secret_rules           IN DBMS_CLOUD_OCI_VAULT_SECRET_RULE_TBL DEFAULT NULL,
      region                 IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION schedule_secret_deletion (
      secret_id        IN VARCHAR2,
      time_of_deletion IN TIMESTAMP WITH TIME ZONE,
      region           IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION schedule_secret_version_deletion (
      secret_id              IN VARCHAR2,
      secret_version_number  IN NUMBER,
      time_of_deletion       IN TIMESTAMP WITH TIME ZONE,
      region                 IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION cancel_secret_deletion (
      secret_id IN VARCHAR2,
      region    IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION cancel_secret_version_deletion (
      secret_id             IN VARCHAR2,
      secret_version_number IN NUMBER,
      region                IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION change_secret_compartment (
      secret_id         IN VARCHAR2,
      region            IN VARCHAR2
  ) RETURN CLOB;
  
  FUNCTION list_compartments(credential_name VARCHAR2)
  RETURN CLOB;
  
  FUNCTION get_agent_config(
    schema_name   IN VARCHAR2,
    table_name    IN VARCHAR2,
    agent_name    IN VARCHAR2
  ) RETURN CLOB;

END oci_vault_agents;
/

------------------------------------------------------------------------
-- Package body
------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY oci_vault_agents
AS
  -- Helper function to get configuration parameters
  FUNCTION get_agent_config(
    schema_name   IN VARCHAR2,
    table_name    IN VARCHAR2,
    agent_name    IN VARCHAR2
  ) RETURN CLOB
  IS
      l_sql          VARCHAR2(4000);
      l_cursor       SYS_REFCURSOR;
      l_config_json  JSON_OBJECT_T := JSON_OBJECT_T();
      l_row          VARCHAR2(4000);
      l_key          VARCHAR2(200);
      l_value        CLOB;
      l_result_json  JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
      -- Build dynamic SQL to fetch the config key and value from the specified schema and table
      l_sql := 'SELECT "KEY", "VALUE" FROM ' || schema_name || '.' || table_name ||
               ' WHERE "AGENT" = :agent';

      -- Open a cursor for the dynamic SQL
      OPEN l_cursor FOR l_sql USING agent_name;

      -- Loop through the result set and populate the JSON object
      LOOP
          FETCH l_cursor INTO l_key, l_value;
          EXIT WHEN l_cursor%NOTFOUND;

          -- Add each config key-value pair to the JSON object
          l_config_json.put(l_key, l_value);
      END LOOP;

      -- Close the cursor
      CLOSE l_cursor;

      -- Return the JSON object as CLOB
      l_result_json.put('status', 'success');
      l_result_json.put('config_params', l_config_json);

      RETURN l_result_json.to_clob();
  EXCEPTION
      WHEN OTHERS THEN
          l_result_json := JSON_OBJECT_T();
          l_result_json.put('status', 'error');
          l_result_json.put('message', 'Error: ' || SQLERRM);
          RETURN l_result_json.to_clob();
  END get_agent_config;

    -- Helper: gets the list of compartments
  FUNCTION list_compartments(credential_name VARCHAR2)
  RETURN CLOB
  IS
      l_response        CLOB;
      l_endpoint        VARCHAR2(1000);
      l_result_json     JSON_OBJECT_T := JSON_OBJECT_T();
      l_compartments    JSON_ARRAY_T := JSON_ARRAY_T();
      l_comp_data       JSON_ARRAY_T;
      l_comp_obj        JSON_OBJECT_T;
      l_name            VARCHAR2(200);
      l_ocid            VARCHAR2(200);
      l_description     VARCHAR2(500);
      l_lifecycle_state VARCHAR2(50);
      l_time_created    VARCHAR2(100);
      tenancy_id        VARCHAR2(128);
      l_region          VARCHAR2(128);

  BEGIN

      SELECT
        JSON_VALUE(cloud_identity, '$.TENANT_OCID') AS tenant_ocid,
        JSON_VALUE(cloud_identity, '$.REGION') AS region
      into tenancy_id,l_region
      FROM v$pdbs;

      -- Construct endpoint to list compartments in tenancy
      l_endpoint := 'https://identity.'||l_region||'.oci.oraclecloud.com/20160918/compartments?compartmentId='
                    || tenancy_id ;

      BEGIN
          -- Call OCI REST API
          l_response := DBMS_CLOUD.get_response_text(
              DBMS_CLOUD.send_request(
                  credential_name => credential_name,
                  uri             => l_endpoint,
                  method          => DBMS_CLOUD.METHOD_GET
              )
          );

          -- Parse response JSON as array
          l_comp_data := JSON_ARRAY_T.parse(l_response);

          IF l_comp_data.get_size() > 0 THEN
              FOR i IN 0 .. l_comp_data.get_size() - 1 LOOP
                  l_comp_obj := JSON_OBJECT_T(l_comp_data.get(i));
                  l_name := l_comp_obj.get_string('name');
                  l_ocid := l_comp_obj.get_string('id');
                  l_description := l_comp_obj.get_string('description');
                  l_lifecycle_state := l_comp_obj.get_string('lifecycleState');
                  l_time_created := l_comp_obj.get_string('timeCreated');
                  
                  l_compartments.append(
                      JSON_OBJECT(
                          'name' VALUE l_name,
                          'id' VALUE l_ocid,
                          'description' VALUE l_description,
                          'lifecycle_state' VALUE l_lifecycle_state,
                          'time_created' VALUE l_time_created
                      )
                  );

              END LOOP;

              l_result_json.put('status', 'success');
              l_result_json.put('message', 'Successfully retrieved compartments');
              l_result_json.put('total_compartments', l_compartments.get_size());
              l_result_json.put('compartments', l_compartments);
          ELSE
              l_result_json.put('status', 'error');
              l_result_json.put('message', 'No compartments found in response');
          END IF;

      EXCEPTION
          WHEN OTHERS THEN
              l_result_json.put('status', 'error');
              l_result_json.put('message', 'Failed to retrieve compartments: ' || SQLERRM);
              l_result_json.put('endpoint_used', l_endpoint);
      END;

      RETURN l_result_json.to_clob();
  END list_compartments;

  -- Helper: gets the compartment ocid with the given compatment name
  FUNCTION get_compartment_ocid_by_name(
    compartment_name IN VARCHAR2
  ) RETURN CLOB
  IS
    l_comp_json_clob    CLOB;
    l_result_json       JSON_OBJECT_T := JSON_OBJECT_T();
    l_compartments      JSON_ARRAY_T;
    l_compartment_str   VARCHAR2(32767);
    l_comp_obj          JSON_OBJECT_T;
    l_ocid              VARCHAR2(200);
    found               BOOLEAN := FALSE;
    l_compartment_name  VARCHAR2(256);
    credential_name     VARCHAR2(256);
    l_current_user      VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json          CLOB;
    l_cfg               JSON_OBJECT_T;
    l_params            JSON_OBJECT_T;
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_VAULT');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params      := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    -- Call existing list_compartments function
    l_comp_json_clob := list_compartments(credential_name);

    -- Parse returned JSON object
    l_result_json := JSON_OBJECT_T.parse(l_comp_json_clob);

    IF l_result_json.get('status').to_string() = '"success"' THEN
        -- Get compartments array (array of JSON strings)
        l_compartments := l_result_json.get_array('compartments');

        FOR i IN 0 .. l_compartments.get_size() - 1 LOOP
            -- Each element is a JSON string, parse it to JSON object
            l_compartment_str := l_compartments.get_string(i);
            l_comp_obj := JSON_OBJECT_T.parse(l_compartment_str);

            IF l_comp_obj.get_string('name') = compartment_name THEN
                l_ocid := l_comp_obj.get_string('id');
                found := TRUE;
                EXIT;
            END IF;
        END LOOP;

        IF found THEN
            l_result_json := JSON_OBJECT_T();
            l_result_json.put('status', 'success');
            l_result_json.put('compartment_name', compartment_name);
            l_result_json.put('compartment_ocid', l_ocid);
        ELSE
            l_result_json := JSON_OBJECT_T();
            l_result_json.put('status', 'error');
            l_result_json.put('message', 'Compartment "' || compartment_name || '" not found');
        END IF;

    ELSE
        -- Forward error from list_compartments
        RETURN l_comp_json_clob;
    END IF;

    RETURN l_result_json.to_clob();

  EXCEPTION
    WHEN OTHERS THEN
        l_result_json := JSON_OBJECT_T();
        l_result_json.put('status', 'error');
        l_result_json.put('message', 'Unexpected error: ' || SQLERRM);
        RETURN l_result_json.to_clob();
  END get_compartment_ocid_by_name;

  ----------------------------------------------------------------------
  -- get_namespace: Retrieve namespace metadata
  ----------------------------------------------------------------------
  FUNCTION get_namespace(
    region           IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp           DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_GET_NAMESPACE_RESPONSE_T;
    result_json      JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user   VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json       CLOB;
    l_cfg            JSON_OBJECT_T;
    l_params         JSON_OBJECT_T;
    credential_name  VARCHAR2(256);
    compartment_name VARCHAR2(256);
    compartment_id   VARCHAR2(256);
    l_json           CLOB;
    l_obj            JSON_OBJECT_T;
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_VAULT');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params         := l_cfg.get_object('config_params');
      credential_name  := l_params.get_string('CREDENTIAL_NAME');
      compartment_name := l_params.get_string('COMPARTMENT_NAME');
    END IF;

    l_json := get_compartment_ocid_by_name(compartment_name => compartment_name);
    l_obj := JSON_OBJECT_T.parse(l_json);
    IF l_obj.has('compartment_ocid') THEN
      compartment_id := l_obj.get_string('compartment_ocid');
    END IF;

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.GET_NAMESPACE(
      opc_client_request_id => NULL,
      compartment_id        => compartment_id,
      region                => region,
      endpoint              => NULL,
      credential_name       => credential_name
    );

    result_json.put('namespace', TRIM(BOTH CHR(34) FROM l_resp.response_body));
    result_json.put('region',    region);
    result_json.put('compartment_id', compartment_id);
    result_json.put('status_code', l_resp.status_code);
    IF l_resp.headers IS NOT NULL AND l_resp.headers.has('opc-request-id') THEN
      result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION WHEN OTHERS THEN
    result_json := JSON_OBJECT_T(); result_json.put('status','error'); result_json.put('message', SQLERRM);
    result_json.put('region', region); RETURN result_json.to_clob();
  END get_namespace;

  -- Helper: resolve metadata (namespace and compartment_id) using local get_namespace
  PROCEDURE resolve_metadata(
    region          IN  VARCHAR2,
    namespace       OUT VARCHAR2,
    compartment_id  OUT VARCHAR2
  )
  IS
    l_json     CLOB;
    l_obj      JSON_OBJECT_T;
    l_ns       VARCHAR2(256);
    l_com_id   VARCHAR2(256);
  BEGIN
    l_json := get_namespace(region => region);
    l_obj := JSON_OBJECT_T.parse(l_json);
    IF l_obj.has('namespace') THEN
      l_ns := l_obj.get_string('namespace');
    END IF;
    IF l_obj.has('compartment_id') THEN
      l_com_id := l_obj.get_string('compartment_id');
    END IF;
    namespace := l_ns;
    compartment_id := l_com_id;
  EXCEPTION
    WHEN OTHERS THEN
    NULL;
  END resolve_metadata;

  ----------------------------------------------------------------------
  -- create_secret
  ----------------------------------------------------------------------
  FUNCTION create_secret (
      secret_name         IN VARCHAR2,
      plain_text          IN VARCHAR2,
      description         IN VARCHAR2,
      vault_id            IN VARCHAR2,
      key_id              IN VARCHAR2,
      region              IN VARCHAR2
  ) RETURN CLOB
  AS
      l_response      DBMS_CLOUD_OCI_VT_VAULTS_CREATE_SECRET_RESPONSE_T;
      l_details       DBMS_CLOUD_OCI_VAULT_CREATE_SECRET_DETAILS_T;
      l_content       DBMS_CLOUD_OCI_VAULT_BASE64_SECRET_CONTENT_DETAILS_T;
      l_encoded       VARCHAR2(32767);
      l_output        CLOB;
      credential_name VARCHAR2(256);
      l_json          JSON_OBJECT_T := JSON_OBJECT_T();
      l_secret_obj    JSON_OBJECT_T := JSON_OBJECT_T();
      l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
      l_config_json  CLOB;
      l_config_obj   JSON_OBJECT_T;
      l_config_params JSON_OBJECT_T;
      namespace             VARCHAR2(256);
      compartment_id        VARCHAR2(256);
  BEGIN
      -- Resolve compartment OCID (uses persisted config or provided name)
      l_config_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_VAULT');
      l_config_obj := JSON_OBJECT_T.parse(l_config_json);
      
      IF l_config_obj.get_string('status') = 'success' THEN
          l_config_params := l_config_obj.get_object('config_params');
          credential_name := l_config_params.get_string('CREDENTIAL_NAME');
      ELSE
          DBMS_OUTPUT.PUT_LINE('Error: ' || l_config_obj.get_string('message'));
      END IF;

      resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

      -- Encode plain text as Base64
      l_encoded := UTL_RAW.cast_to_varchar2(
                    UTL_ENCODE.base64_encode(
                      UTL_RAW.cast_to_raw(plain_text)
                    )
                  );

      -- Build secret content details
      l_content := DBMS_CLOUD_OCI_VAULT_BASE64_SECRET_CONTENT_DETAILS_T(
                    content_type => 'BASE64',
                    name         => secret_name,
                    stage        => 'CURRENT',
                    content      => l_encoded
                  );

      -- Build the secret creation details
      l_details := DBMS_CLOUD_OCI_VAULT_CREATE_SECRET_DETAILS_T(
                    compartment_id => compartment_id,
                    defined_tags   => NULL,
                    description    => description,
                    freeform_tags  => NULL,
                    key_id         => key_id,
                    metadata       => NULL,
                    secret_content => l_content,
                    secret_name    => secret_name,
                    secret_rules   => NULL,
                    vault_id       => vault_id
                  );

      -- Call the CREATE_SECRET API
      l_response := DBMS_CLOUD_OCI_VT_VAULTS.CREATE_SECRET(
          create_secret_details => l_details,
          opc_request_id        => NULL,
          opc_retry_token       => NULL,
          region                => region,
          endpoint              => NULL,
          credential_name       => credential_name
      );

      -- Build the JSON response
      l_json.put('status_code', l_response.status_code);

      IF l_response.headers IS NOT NULL THEN
          l_json.put('headers', l_response.headers.to_clob);
      END IF;

      IF l_response.response_body IS NOT NULL THEN
          l_secret_obj.put('id',               l_response.response_body.id);
          l_secret_obj.put('name',             l_response.response_body.secret_name);
          l_secret_obj.put('compartment_id',   l_response.response_body.compartment_id);
          l_secret_obj.put('vault_id',         l_response.response_body.vault_id);
          l_secret_obj.put('lifecycle_state',  l_response.response_body.lifecycle_state);
          l_secret_obj.put('description',      l_response.response_body.description);

          IF l_response.response_body.time_created IS NOT NULL THEN
              l_secret_obj.put('time_created',
                TO_CHAR(l_response.response_body.time_created, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
              );
          END IF;

          l_json.put('secret', l_secret_obj);
      END IF;

      l_output := l_json.to_clob;
      RETURN l_output;
  EXCEPTION
    WHEN OTHERS THEN
      -- return an error JSON to caller
      l_json := JSON_OBJECT_T();
      l_json.put('error', SQLERRM);
      RETURN l_json.to_clob;
  END create_secret;

  ----------------------------------------------------------------------
  -- get_secret
  ----------------------------------------------------------------------
  FUNCTION get_secret (
      secret_id       IN VARCHAR2,
      region          IN VARCHAR2
  ) RETURN CLOB
  AS
      l_response   DBMS_CLOUD_OCI_VT_VAULTS_GET_SECRET_RESPONSE_T;
      l_secret     DBMS_CLOUD_OCI_VAULT_SECRET_T;
      l_output     CLOB;
      l_json       JSON_OBJECT_T := JSON_OBJECT_T();
      l_secret_obj JSON_OBJECT_T := JSON_OBJECT_T();
      credential_name VARCHAR2(256);
      l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
      l_config_json  CLOB;
      l_config_obj   JSON_OBJECT_T;
      l_config_params JSON_OBJECT_T;
  BEGIN
      l_config_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_VAULT');
      l_config_obj := JSON_OBJECT_T.parse(l_config_json);
      
      IF l_config_obj.get_string('status') = 'success' THEN
          l_config_params := l_config_obj.get_object('config_params');

          credential_name := l_config_params.get_string('CREDENTIAL_NAME');
      ELSE
          DBMS_OUTPUT.PUT_LINE('Error: ' || l_config_obj.get_string('message'));
      END IF;

      -- Call the OCI Vault GET_SECRET API
      l_response := DBMS_CLOUD_OCI_VT_VAULTS.GET_SECRET(
          secret_id       => secret_id,
          opc_request_id  => NULL,
          region          => region,
          endpoint        => NULL,
          credential_name => credential_name
      );

      -- Add status code
      l_json.put('status_code', l_response.status_code);

      -- Add headers if present
      IF l_response.headers IS NOT NULL THEN
          l_json.put('headers', l_response.headers.to_clob);
      END IF;

      -- Add secret details if present
      IF l_response.response_body IS NOT NULL THEN
          l_secret := l_response.response_body;

          l_secret_obj.put('id', l_secret.id);
          l_secret_obj.put('name', l_secret.secret_name);
          l_secret_obj.put('compartment_id', l_secret.compartment_id);
          l_secret_obj.put('vault_id', l_secret.vault_id);
          l_secret_obj.put('description', l_secret.description);
          l_secret_obj.put('lifecycle_state', l_secret.lifecycle_state);

          IF l_secret.time_created IS NOT NULL THEN
              l_secret_obj.put(
                  'time_created',
                  TO_CHAR(l_secret.time_created, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
              );
          END IF;

          IF l_secret.time_of_deletion IS NOT NULL THEN
              l_secret_obj.put(
                  'time_of_deletion',
                  TO_CHAR(l_secret.time_of_deletion, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
              );
          END IF;

          IF l_secret.time_of_current_version_expiry IS NOT NULL THEN
              l_secret_obj.put(
                  'time_of_current_version_expiry',
                  TO_CHAR(l_secret.time_of_current_version_expiry, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
              );
          END IF;

          l_json.put('secret', l_secret_obj);
      END IF;

      l_output := l_json.to_clob;
      RETURN l_output;
  EXCEPTION
    WHEN OTHERS THEN
      l_json := JSON_OBJECT_T();
      l_json.put('error', SQLERRM);
      RETURN l_json.to_clob;
  END get_secret;

  ----------------------------------------------------------------------
  -- list_secrets (package version)
  ----------------------------------------------------------------------
  FUNCTION list_secrets (
      region             IN VARCHAR2
  ) RETURN CLOB
  AS
      l_response      DBMS_CLOUD_OCI_VT_VAULTS_LIST_SECRETS_RESPONSE_T;
      l_secret_tbl    DBMS_CLOUD_OCI_VAULT_SECRET_SUMMARY_TBL;
      l_output        CLOB;
      l_json          JSON_OBJECT_T := JSON_OBJECT_T();
      l_secrets_arr   JSON_ARRAY_T := JSON_ARRAY_T();
      l_secret_obj    JSON_OBJECT_T := JSON_OBJECT_T();
      l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
      l_config_json   CLOB;
      l_cfg           JSON_OBJECT_T;
      l_params        JSON_OBJECT_T;
      credential_name VARCHAR2(256);
      namespace       VARCHAR2(256);
      compartment_id  VARCHAR2(256);
  BEGIN
      l_config_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_VAULT');
      l_cfg := JSON_OBJECT_T.parse(l_config_json);
      IF l_cfg.get_string('status') = 'success' THEN
          l_params := l_cfg.get_object('config_params');
          credential_name := l_params.get_string('CREDENTIAL_NAME');
      END IF;

      resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

      l_response := DBMS_CLOUD_OCI_VT_VAULTS.LIST_SECRETS(
          compartment_id   => compartment_id,
          name             => NULL,
          limit            => NULL,
          page             => NULL,
          opc_request_id   => NULL,
          sort_by          => NULL,
          sort_order       => NULL,
          vault_id         => NULL,
          lifecycle_state  => NULL,
          region           => region,
          endpoint         => NULL,
          credential_name  => credential_name
      );

      l_json.put('status_code', l_response.status_code);

      IF l_response.headers IS NOT NULL THEN
          l_json.put('headers', l_response.headers.to_clob);
      END IF;

      IF l_response.response_body IS NOT NULL THEN
          l_secret_tbl := l_response.response_body;

          FOR i IN 1 .. l_secret_tbl.COUNT LOOP
              l_secret_obj := JSON_OBJECT_T();
              l_secret_obj.put('id',              l_secret_tbl(i).id);
              l_secret_obj.put('name',            l_secret_tbl(i).secret_name);
              l_secret_obj.put('compartment_id',  l_secret_tbl(i).compartment_id);
              l_secret_obj.put('vault_id',        l_secret_tbl(i).vault_id);
              l_secret_obj.put('description',     l_secret_tbl(i).description);
              l_secret_obj.put('lifecycle_state', l_secret_tbl(i).lifecycle_state);
              IF l_secret_tbl(i).time_created IS NOT NULL THEN
                  l_secret_obj.put('time_created',
                    TO_CHAR(l_secret_tbl(i).time_created, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
              END IF;
              l_secrets_arr.append(l_secret_obj);
          END LOOP;

          l_json.put('secrets', l_secrets_arr);
      END IF;

      l_output := l_json.to_clob;
      RETURN l_output;
  EXCEPTION
      WHEN OTHERS THEN
          l_json := JSON_OBJECT_T();
          l_json.put('error', SQLERRM);
          RETURN l_json.to_clob;
  END list_secrets;

  ----------------------------------------------------------------------
  -- list_secret_versions
  ----------------------------------------------------------------------
  FUNCTION list_secret_versions (
      secret_id       IN VARCHAR2,
      region          IN VARCHAR2
  ) RETURN CLOB
  AS
      l_response     DBMS_CLOUD_OCI_VT_VAULTS_LIST_SECRET_VERSIONS_RESPONSE_T;
      l_versions     DBMS_CLOUD_OCI_VAULT_SECRET_VERSION_SUMMARY_TBL;
      l_output       CLOB;
      l_json         JSON_OBJECT_T := JSON_OBJECT_T();
      l_versions_arr JSON_ARRAY_T := JSON_ARRAY_T();
      l_version_obj  JSON_OBJECT_T;
      l_stages_arr   JSON_ARRAY_T;
      l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
      l_config_json   CLOB;
      l_cfg           JSON_OBJECT_T;
      l_params        JSON_OBJECT_T;
      credential_name VARCHAR2(256);
  BEGIN
      l_config_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_VAULT');
      l_cfg := JSON_OBJECT_T.parse(l_config_json);
      IF l_cfg.get_string('status') = 'success' THEN
          l_params := l_cfg.get_object('config_params');
          credential_name := l_params.get_string('CREDENTIAL_NAME');
      END IF;

      l_response := DBMS_CLOUD_OCI_VT_VAULTS.LIST_SECRET_VERSIONS(
          secret_id       => secret_id,
          limit           => NULL,
          page            => NULL,
          opc_request_id  => NULL,
          sort_by         => NULL,
          sort_order      => NULL,
          region          => region,
          endpoint        => NULL,
          credential_name => credential_name
      );

      l_json.put('status_code', l_response.status_code);

      IF l_response.headers IS NOT NULL THEN
          l_json.put('headers', l_response.headers.to_clob);
      END IF;

      IF l_response.response_body IS NOT NULL THEN
          l_versions := l_response.response_body;

          FOR i IN 1 .. l_versions.COUNT LOOP
              l_version_obj := JSON_OBJECT_T();

              l_version_obj.put('version_number', l_versions(i).version_number);
              l_version_obj.put('content_type', l_versions(i).content_type);
              l_version_obj.put('name', l_versions(i).name);
              l_version_obj.put('secret_id', l_versions(i).secret_id);

              IF l_versions(i).stages IS NOT NULL THEN
                  l_stages_arr := JSON_ARRAY_T();
                  FOR j IN 1 .. l_versions(i).stages.COUNT LOOP
                      l_stages_arr.append(l_versions(i).stages(j));
                  END LOOP;
                  l_version_obj.put('stages', l_stages_arr);
              END IF;

              IF l_versions(i).time_created IS NOT NULL THEN
                  l_version_obj.put('time_created',
                    TO_CHAR(l_versions(i).time_created, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
              END IF;

              IF l_versions(i).time_of_deletion IS NOT NULL THEN
                  l_version_obj.put('time_of_deletion',
                    TO_CHAR(l_versions(i).time_of_deletion, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
              END IF;

              IF l_versions(i).time_of_expiry IS NOT NULL THEN
                  l_version_obj.put('time_of_expiry',
                    TO_CHAR(l_versions(i).time_of_expiry, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
              END IF;

              l_versions_arr.append(l_version_obj);
          END LOOP;

          l_json.put('versions', l_versions_arr);
      END IF;

      l_output := l_json.to_clob;
      RETURN l_output;
  EXCEPTION
      WHEN OTHERS THEN
          l_json := JSON_OBJECT_T();
          l_json.put('error', SQLERRM);
          RETURN l_json.to_clob;
  END list_secret_versions;

  ----------------------------------------------------------------------
  -- get_secret_version
  ----------------------------------------------------------------------
  FUNCTION get_secret_version (
      secret_id             IN VARCHAR2,
      secret_version_number IN NUMBER,
      region                IN VARCHAR2
  ) RETURN CLOB
  AS
      l_response   DBMS_CLOUD_OCI_VT_VAULTS_GET_SECRET_VERSION_RESPONSE_T;
      l_version    DBMS_CLOUD_OCI_VAULT_SECRET_VERSION_T;
      l_output     CLOB;
      l_json       JSON_OBJECT_T := JSON_OBJECT_T();
      l_version_obj JSON_OBJECT_T := JSON_OBJECT_T();
      l_stages_arr JSON_ARRAY_T := JSON_ARRAY_T();
      l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
      l_config_json   CLOB;
      l_cfg           JSON_OBJECT_T;
      l_params        JSON_OBJECT_T;
      credential_name VARCHAR2(256);
  BEGIN
      l_config_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_VAULT');
      l_cfg := JSON_OBJECT_T.parse(l_config_json);
      IF l_cfg.get_string('status') = 'success' THEN
          l_params := l_cfg.get_object('config_params');
          credential_name := l_params.get_string('CREDENTIAL_NAME');
      END IF;

      l_response := DBMS_CLOUD_OCI_VT_VAULTS.GET_SECRET_VERSION(
          secret_id             => secret_id,
          secret_version_number => secret_version_number,
          opc_request_id        => NULL,
          region                => region,
          endpoint              => NULL,
          credential_name       => credential_name
      );

      l_json.put('status_code', l_response.status_code);

      IF l_response.headers IS NOT NULL THEN
          l_json.put('headers', l_response.headers.to_clob);
      END IF;

      IF l_response.response_body IS NOT NULL THEN
          l_version := l_response.response_body;

          l_version_obj.put('secret_id', l_version.secret_id);
          l_version_obj.put('version_number', l_version.version_number);
          l_version_obj.put('content_type', l_version.content_type);
          l_version_obj.put('name', l_version.name);

          IF l_version.stages IS NOT NULL THEN
              FOR i IN 1 .. l_version.stages.COUNT LOOP
                  l_stages_arr.append(l_version.stages(i));
              END LOOP;
              l_version_obj.put('stages', l_stages_arr);
          END IF;

          IF l_version.time_created IS NOT NULL THEN
              l_version_obj.put('time_created',
                TO_CHAR(l_version.time_created, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
          END IF;

          IF l_version.time_of_deletion IS NOT NULL THEN
              l_version_obj.put('time_of_deletion',
                TO_CHAR(l_version.time_of_deletion, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
          END IF;

          IF l_version.time_of_current_version_expiry IS NOT NULL THEN
              l_version_obj.put('time_of_current_version_expiry',
                TO_CHAR(l_version.time_of_current_version_expiry, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
          END IF;

          l_json.put('secret_version', l_version_obj);
      END IF;

      l_output := l_json.to_clob;
      RETURN l_output;
  EXCEPTION
      WHEN OTHERS THEN
          l_json := JSON_OBJECT_T();
          l_json.put('error', SQLERRM);
          RETURN l_json.to_clob;
  END get_secret_version;

  ----------------------------------------------------------------------
  -- update_secret
  ----------------------------------------------------------------------
  FUNCTION update_secret (
      secret_id              IN VARCHAR2,
      description            IN VARCHAR2 DEFAULT NULL,
      current_version_number IN NUMBER   DEFAULT NULL,
      plain_text             IN VARCHAR2 DEFAULT NULL,
      defined_tags           IN JSON_ELEMENT_T DEFAULT NULL,
      freeform_tags          IN JSON_ELEMENT_T DEFAULT NULL,
      secret_rules           IN DBMS_CLOUD_OCI_VAULT_SECRET_RULE_TBL DEFAULT NULL,
      region                 IN VARCHAR2
  ) RETURN CLOB
  AS
      l_response    DBMS_CLOUD_OCI_VT_VAULTS_UPDATE_SECRET_RESPONSE_T;
      l_details     DBMS_CLOUD_OCI_VAULT_UPDATE_SECRET_DETAILS_T;
      l_content     DBMS_CLOUD_OCI_VAULT_BASE64_SECRET_CONTENT_DETAILS_T;
      l_get_resp    DBMS_CLOUD_OCI_VT_VAULTS_GET_SECRET_RESPONSE_T;
      l_secret_name VARCHAR2(512);
      l_encoded     VARCHAR2(32767);
      l_output      CLOB;
      l_json        JSON_OBJECT_T := JSON_OBJECT_T();
      l_secret_obj  JSON_OBJECT_T := JSON_OBJECT_T();
      l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
      l_config_json   CLOB;
      l_cfg           JSON_OBJECT_T;
      l_params        JSON_OBJECT_T;
      credential_name VARCHAR2(256);
  BEGIN
      IF current_version_number IS NOT NULL AND (plain_text IS NOT NULL OR secret_rules IS NOT NULL) THEN
          RAISE_APPLICATION_ERROR(-20001,
            'Cannot update current_version_number together with secret_content or secret_rules in one call.');
      END IF;

      l_config_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_VAULT');
      l_cfg := JSON_OBJECT_T.parse(l_config_json);
      IF l_cfg.get_string('status') = 'success' THEN
          l_params := l_cfg.get_object('config_params');
          credential_name := l_params.get_string('CREDENTIAL_NAME');
      END IF;

      l_get_resp := DBMS_CLOUD_OCI_VT_VAULTS.GET_SECRET(
          secret_id       => secret_id,
          opc_request_id  => NULL,
          region          => region,
          endpoint        => NULL,
          credential_name => credential_name
      );

      IF l_get_resp.response_body IS NOT NULL THEN
          l_secret_name := l_get_resp.response_body.secret_name;
      ELSE
          RAISE_APPLICATION_ERROR(-20002, 'Could not fetch secret_name for secret_id: ' || secret_id);
      END IF;

      IF plain_text IS NOT NULL THEN
          l_encoded := UTL_RAW.cast_to_varchar2(
                         UTL_ENCODE.base64_encode(
                           UTL_RAW.cast_to_raw(plain_text)
                         )
                       );

          l_content := DBMS_CLOUD_OCI_VAULT_BASE64_SECRET_CONTENT_DETAILS_T(
              content_type => 'BASE64',
              name         => l_secret_name || '_' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISS'),
              stage        => 'CURRENT',
              content      => l_encoded
          );
      END IF;

      l_details := DBMS_CLOUD_OCI_VAULT_UPDATE_SECRET_DETAILS_T(
          current_version_number => current_version_number,
          defined_tags           => defined_tags,
          description            => description,
          freeform_tags          => freeform_tags,
          metadata               => NULL,
          secret_content         => l_content,
          secret_rules           => secret_rules
      );

      l_response := DBMS_CLOUD_OCI_VT_VAULTS.UPDATE_SECRET(
          secret_id             => secret_id,
          update_secret_details => l_details,
          if_match              => NULL,
          opc_request_id        => NULL,
          region                => region,
          endpoint              => NULL,
          credential_name       => credential_name
      );

      l_json.put('status_code', l_response.status_code);

      IF l_response.headers IS NOT NULL THEN
          l_json.put('headers', l_response.headers.to_clob);
      END IF;

      IF l_response.response_body IS NOT NULL THEN
          l_secret_obj.put('id',               l_response.response_body.id);
          l_secret_obj.put('name',             l_response.response_body.secret_name);
          l_secret_obj.put('compartment_id',   l_response.response_body.compartment_id);
          l_secret_obj.put('vault_id',         l_response.response_body.vault_id);
          l_secret_obj.put('lifecycle_state',  l_response.response_body.lifecycle_state);
          l_secret_obj.put('description',      l_response.response_body.description);

          IF l_response.response_body.time_created IS NOT NULL THEN
              l_secret_obj.put(
                  'time_created',
                  TO_CHAR(l_response.response_body.time_created, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
              );
          END IF;

          l_json.put('secret', l_secret_obj);
      END IF;

      l_output := l_json.to_clob;
      RETURN l_output;
  EXCEPTION
      WHEN OTHERS THEN
          l_json := JSON_OBJECT_T();
          l_json.put('error', SQLERRM);
          RETURN l_json.to_clob;
  END update_secret;

  ----------------------------------------------------------------------
  -- schedule_secret_deletion
  ----------------------------------------------------------------------
  FUNCTION schedule_secret_deletion (
      secret_id        IN VARCHAR2,
      time_of_deletion IN TIMESTAMP WITH TIME ZONE,
      region           IN VARCHAR2
  ) RETURN CLOB
  AS
      l_response DBMS_CLOUD_OCI_VT_VAULTS_SCHEDULE_SECRET_DELETION_RESPONSE_T;
      l_details  DBMS_CLOUD_OCI_VAULT_SCHEDULE_SECRET_DELETION_DETAILS_T;
      l_json     JSON_OBJECT_T := JSON_OBJECT_T();
      l_output   CLOB;
      l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
      l_config_json   CLOB;
      l_cfg           JSON_OBJECT_T;
      l_params        JSON_OBJECT_T;
      credential_name VARCHAR2(256);
  BEGIN
      l_config_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_VAULT');
      l_cfg := JSON_OBJECT_T.parse(l_config_json);
      IF l_cfg.get_string('status') = 'success' THEN
          l_params := l_cfg.get_object('config_params');
          credential_name := l_params.get_string('CREDENTIAL_NAME');
      END IF;

      l_details := DBMS_CLOUD_OCI_VAULT_SCHEDULE_SECRET_DELETION_DETAILS_T(
                     time_of_deletion => time_of_deletion
                   );

      l_response := DBMS_CLOUD_OCI_VT_VAULTS.SCHEDULE_SECRET_DELETION(
          secret_id                         => secret_id,
          schedule_secret_deletion_details  => l_details,
          if_match                          => NULL,
          opc_request_id                    => NULL,
          region                            => region,
          endpoint                          => NULL,
          credential_name                   => credential_name
      );

      l_json.put('status_code', l_response.status_code);

      IF l_response.headers IS NOT NULL THEN
          l_json.put('headers', l_response.headers.to_clob);
      END IF;

      l_json.put('message', 'Secret deletion has been scheduled.');

      l_output := l_json.to_clob;
      RETURN l_output;
  EXCEPTION
      WHEN OTHERS THEN
          l_json := JSON_OBJECT_T();
          l_json.put('error', SQLERRM);
          RETURN l_json.to_clob;
  END schedule_secret_deletion;

  ----------------------------------------------------------------------
  -- schedule_secret_version_deletion
  ----------------------------------------------------------------------
  FUNCTION schedule_secret_version_deletion (
      secret_id              IN VARCHAR2,
      secret_version_number  IN NUMBER,
      time_of_deletion       IN TIMESTAMP WITH TIME ZONE,
      region                 IN VARCHAR2
  ) RETURN CLOB
  AS
      l_response DBMS_CLOUD_OCI_VT_VAULTS_SCHEDULE_SECRET_VERSION_DELETION_RESPONSE_T;
      l_details  DBMS_CLOUD_OCI_VAULT_SCHEDULE_SECRET_VERSION_DELETION_DETAILS_T;
      l_json     JSON_OBJECT_T := JSON_OBJECT_T();
      l_output   CLOB;
      l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
      l_config_json   CLOB;
      l_cfg           JSON_OBJECT_T;
      l_params        JSON_OBJECT_T;
      credential_name VARCHAR2(256);
  BEGIN
      l_config_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_VAULT');
      l_cfg := JSON_OBJECT_T.parse(l_config_json);
      IF l_cfg.get_string('status') = 'success' THEN
          l_params := l_cfg.get_object('config_params');
          credential_name := l_params.get_string('CREDENTIAL_NAME');
      END IF;

      l_details := DBMS_CLOUD_OCI_VAULT_SCHEDULE_SECRET_VERSION_DELETION_DETAILS_T(
                     time_of_deletion => time_of_deletion
                   );

      l_response := DBMS_CLOUD_OCI_VT_VAULTS.SCHEDULE_SECRET_VERSION_DELETION(
          secret_id                                => secret_id,
          secret_version_number                    => secret_version_number,
          schedule_secret_version_deletion_details => l_details,
          if_match                                 => NULL,
          opc_request_id                           => NULL,
          region                                   => region,
          endpoint                                 => NULL,
          credential_name                          => credential_name
      );

      l_json.put('status_code', l_response.status_code);

      IF l_response.headers IS NOT NULL THEN
          l_json.put('headers', l_response.headers.to_clob);
      END IF;

      l_json.put('message', 'Secret version deletion has been scheduled.');

      l_output := l_json.to_clob;
      RETURN l_output;
  EXCEPTION
      WHEN OTHERS THEN
          l_json := JSON_OBJECT_T();
          l_json.put('error', SQLERRM);
          RETURN l_json.to_clob;
  END schedule_secret_version_deletion;

  ----------------------------------------------------------------------
  -- cancel_secret_deletion
  ----------------------------------------------------------------------
  FUNCTION cancel_secret_deletion (
      secret_id       IN VARCHAR2,
      region          IN VARCHAR2
  ) RETURN CLOB
  AS
      l_response   DBMS_CLOUD_OCI_VT_VAULTS_CANCEL_SECRET_DELETION_RESPONSE_T;
      l_json       JSON_OBJECT_T := JSON_OBJECT_T();
      l_output     CLOB;
      l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
      l_config_json   CLOB;
      l_cfg           JSON_OBJECT_T;
      l_params        JSON_OBJECT_T;
      credential_name VARCHAR2(256);
  BEGIN
      l_config_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_VAULT');
      l_cfg := JSON_OBJECT_T.parse(l_config_json);
      IF l_cfg.get_string('status') = 'success' THEN
          l_params := l_cfg.get_object('config_params');
          credential_name := l_params.get_string('CREDENTIAL_NAME');
      END IF;

      l_response := DBMS_CLOUD_OCI_VT_VAULTS.CANCEL_SECRET_DELETION(
          secret_id       => secret_id,
          if_match        => NULL,
          opc_request_id  => NULL,
          region          => region,
          endpoint        => NULL,
          credential_name => credential_name
      );

      l_json.put('status_code', l_response.status_code);
      IF l_response.headers IS NOT NULL THEN
          l_json.put('headers', l_response.headers.to_clob);
      END IF;
      l_json.put('message', 'Scheduled deletion has been cancelled for the secret.');
      l_output := l_json.to_clob;
      RETURN l_output;
  EXCEPTION
      WHEN OTHERS THEN
          l_json := JSON_OBJECT_T();
          l_json.put('error', SQLERRM);
          RETURN l_json.to_clob;
  END cancel_secret_deletion;

  ----------------------------------------------------------------------
  -- cancel_secret_version_deletion
  ----------------------------------------------------------------------
  FUNCTION cancel_secret_version_deletion (
      secret_id             IN VARCHAR2,
      secret_version_number IN NUMBER,
      region                IN VARCHAR2
  ) RETURN CLOB
  AS
      l_response   DBMS_CLOUD_OCI_VT_VAULTS_CANCEL_SECRET_VERSION_DELETION_RESPONSE_T;
      l_json       JSON_OBJECT_T := JSON_OBJECT_T();
      l_output     CLOB;
      l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
      l_config_json   CLOB;
      l_cfg           JSON_OBJECT_T;
      l_params        JSON_OBJECT_T;
      credential_name VARCHAR2(256);
  BEGIN
      l_config_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_VAULT');
      l_cfg := JSON_OBJECT_T.parse(l_config_json);
      IF l_cfg.get_string('status') = 'success' THEN
          l_params := l_cfg.get_object('config_params');
          credential_name := l_params.get_string('CREDENTIAL_NAME');
      END IF;

      l_response := DBMS_CLOUD_OCI_VT_VAULTS.CANCEL_SECRET_VERSION_DELETION(
          secret_id             => secret_id,
          secret_version_number => secret_version_number,
          if_match              => NULL,
          opc_request_id        => NULL,
          region                => region,
          endpoint              => NULL,
          credential_name       => credential_name
      );

      l_json.put('status_code', l_response.status_code);
      IF l_response.headers IS NOT NULL THEN
          l_json.put('headers', l_response.headers.to_clob);
      END IF;
      l_json.put('message', 'Scheduled deletion has been cancelled for the secret version.');
      l_output := l_json.to_clob;
      RETURN l_output;
  EXCEPTION
      WHEN OTHERS THEN
          l_json := JSON_OBJECT_T();
          l_json.put('error', SQLERRM);
          RETURN l_json.to_clob;
  END cancel_secret_version_deletion;

  ----------------------------------------------------------------------
  -- change_secret_compartment
  ----------------------------------------------------------------------
  FUNCTION change_secret_compartment (
      secret_id         IN VARCHAR2,
      region            IN VARCHAR2
  ) RETURN CLOB
  AS
      l_response     DBMS_CLOUD_OCI_VT_VAULTS_CHANGE_SECRET_COMPARTMENT_RESPONSE_T;
      l_details      DBMS_CLOUD_OCI_VAULT_CHANGE_SECRET_COMPARTMENT_DETAILS_T;
      l_output       CLOB;
      l_json         JSON_OBJECT_T := JSON_OBJECT_T();
      l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
      l_config_json   CLOB;
      l_cfg           JSON_OBJECT_T;
      l_params        JSON_OBJECT_T;
      credential_name VARCHAR2(256);
      namespace       VARCHAR2(256);
      compartment_id  VARCHAR2(256);
  BEGIN
      l_config_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_VAULT');
      l_cfg := JSON_OBJECT_T.parse(l_config_json);
      IF l_cfg.get_string('status') = 'success' THEN
          l_params := l_cfg.get_object('config_params');
          credential_name := l_params.get_string('CREDENTIAL_NAME');
      END IF;
     
     resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

      l_details := DBMS_CLOUD_OCI_VAULT_CHANGE_SECRET_COMPARTMENT_DETAILS_T(
                     compartment_id => compartment_id
                   );

      l_response := DBMS_CLOUD_OCI_VT_VAULTS.CHANGE_SECRET_COMPARTMENT(
          secret_id                         => secret_id,
          change_secret_compartment_details => l_details,
          if_match                          => NULL,
          opc_request_id                    => NULL,
          opc_retry_token                   => NULL,
          region                            => region,
          endpoint                          => NULL,
          credential_name                   => credential_name
      );

      l_json.put('status_code', l_response.status_code);
      IF l_response.headers IS NOT NULL THEN
          l_json.put('headers', l_response.headers.to_clob);
      END IF;
      l_json.put('message', 'Secret has been moved to the new compartment.');
      l_output := l_json.to_clob;
      RETURN l_output;
  EXCEPTION
      WHEN OTHERS THEN
          l_json := JSON_OBJECT_T();
          l_json.put('error', SQLERRM);
          RETURN l_json.to_clob;
  END change_secret_compartment;

END oci_vault_agents;
/


-------------------------------------------------------------------------------
-- This procedure installs or refreshes the OCI Vault AI Agent tools in the
-- current schema. It drops any existing tool definitions and recreates them
-- pointing to the latest implementations in &&INSTALL_SCHEMA.oci_vault_agents.
-------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE initialize_vault_tools
IS
    PROCEDURE drop_tool_if_exists (tool_name IN VARCHAR2) IS
      l_tool_count NUMBER;
      l_sql        CLOB;
    BEGIN
      l_sql := 'SELECT COUNT(*) FROM USER_AI_AGENT_TOOLS WHERE TOOL_NAME = :1';
      execute immediate l_sql into l_tool_count using tool_name;
      IF l_tool_count > 0 THEN
        DBMS_CLOUD_AI_AGENT.DROP_TOOL(tool_name);
      END IF;
    END drop_tool_if_exists;
BEGIN
    ------------------------------------------------------------------------
    -- AI TOOL: LIST_SECRETS_TOOL
    -- maps to oci_vault_agents.list_secrets
    ------------------------------------------------------------------------
    drop_tool_if_exists(tool_name => 'LIST_SECRETS_TOOL');
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name => 'LIST_SECRETS_TOOL',
        attributes => '{
            "instruction": "Enumerate all secrets visible to this agent within the configured compartment of the specified region. Use to inventory secrets, review basic metadata (name/OCID, vault, lifecycle state, timestamps), and support governance. This tool never returns secret payloads.",
            "function": "oci_vault_agents.list_secrets"
            }',
        description => 'Tool for listing all secrets in a given OCI Vault compartment'
    );

    ------------------------------------------------------------------------
    -- AI TOOL: LIST_SECRET_VERSIONS_TOOL
    -- maps to oci_vault_agents.list_secret_versions
    ------------------------------------------------------------------------
    drop_tool_if_exists(tool_name => 'LIST_SECRET_VERSIONS_TOOL');
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name => 'LIST_SECRET_VERSIONS_TOOL',
        attributes => '{
            "instruction": "List every version of a secret to understand its rotation history and stage assignments. Use for auditing and troubleshooting rotations. This tool returns version metadata only, not secret contents.",
            "function": "oci_vault_agents.list_secret_versions"
            }',
        description => 'Tool for listing all versions of an OCI Vault secret'
    );

    ------------------------------------------------------------------------
    -- AI TOOL: GET_SECRET_VERSION_TOOL
    -- maps to oci_vault_agents.get_secret_version
    ------------------------------------------------------------------------
    drop_tool_if_exists(tool_name => 'GET_SECRET_VERSION_TOOL');
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name => 'GET_SECRET_VERSION_TOOL',
        attributes => '{
            "instruction": "Retrieve metadata for a specific version of a secret, including stage and timing information, to verify the state of that version. Does not return the secret value.",
            "function": "oci_vault_agents.get_secret_version"
            }',
        description => 'Tool for fetching a specific version of an OCI Vault secret'
    );

    ------------------------------------------------------------------------
    -- AI TOOL: UPDATE_SECRET_TOOL
    -- maps to oci_vault_agents.update_secret
    ------------------------------------------------------------------------
    drop_tool_if_exists(tool_name => 'UPDATE_SECRET_TOOL');
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name => 'UPDATE_SECRET_TOOL',
        attributes => '{
            "instruction": "Update secret metadata or roll a new version. Use to rotate the secret by supplying new content or to adjust description, tags, or rules. When content is provided, a new CURRENT version is created in OCI Vault.",
            "function": "oci_vault_agents.update_secret"
            }',
        description => 'Tool for updating an OCI Vault secret'
    );

    ------------------------------------------------------------------------
    -- AI TOOL: SCHEDULE_SECRET_DELETION_TOOL
    -- maps to oci_vault_agents.schedule_secret_deletion
    ------------------------------------------------------------------------
    drop_tool_if_exists(tool_name => 'SCHEDULE_SECRET_DELETION_TOOL');
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name => 'SCHEDULE_SECRET_DELETION_TOOL',
        attributes => '{
            "instruction": "Schedule a delayed deletion of a secret. Use when decommissioning; the secret remains recoverable until the scheduled time and can be canceled before it executes.",
            "function": "oci_vault_agents.schedule_secret_deletion"
            }',
        description => 'Tool for scheduling deletion of an OCI Vault secret'
    );

    ------------------------------------------------------------------------
    -- AI TOOL: SCHEDULE_SECRET_VERSION_DELETION_TOOL
    -- maps to oci_vault_agents.schedule_secret_version_deletion
    ------------------------------------------------------------------------
    drop_tool_if_exists(tool_name => 'SCHEDULE_SECRET_VERSION_DELETION_TOOL');
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name => 'SCHEDULE_SECRET_VERSION_DELETION_TOOL',
        attributes => '{
            "instruction": "Schedule deletion of a specific secret version without removing the secret itself. Useful for pruning superseded versions while retaining the active one.",
            "function": "oci_vault_agents.schedule_secret_version_deletion"
            }',
        description => 'Tool for scheduling deletion of a specific OCI Vault secret version'
    );

    ------------------------------------------------------------------------
    -- AI TOOL: CANCEL_SECRET_DELETION_TOOL
    -- maps to oci_vault_agents.cancel_secret_deletion
    ------------------------------------------------------------------------
    drop_tool_if_exists(tool_name => 'CANCEL_SECRET_DELETION_TOOL');
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name => 'CANCEL_SECRET_DELETION_TOOL',
        attributes => '{
            "instruction": "Cancel a previously scheduled deletion of a secret and keep it active.",
            "function": "oci_vault_agents.cancel_secret_deletion"
            }',
        description => 'Tool for cancelling a scheduled deletion of an OCI Vault secret'
    );

    ------------------------------------------------------------------------
    -- AI TOOL: CANCEL_SECRET_VERSION_DELETION_TOOL
    -- maps to oci_vault_agents.cancel_secret_version_deletion
    ------------------------------------------------------------------------
    drop_tool_if_exists(tool_name => 'CANCEL_SECRET_VERSION_DELETION_TOOL');
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name => 'CANCEL_SECRET_VERSION_DELETION_TOOL',
        attributes => '{
            "instruction": "Cancel a previously scheduled deletion for a specific secret version.",
            "function": "oci_vault_agents.cancel_secret_version_deletion"
            }',
        description => 'Tool for cancelling scheduled deletion of a specific secret version'
    );

    ------------------------------------------------------------------------
    -- AI TOOL: CHANGE_SECRET_COMPARTMENT_TOOL
    -- maps to oci_vault_agents.change_secret_compartment
    ------------------------------------------------------------------------
    drop_tool_if_exists(tool_name => 'CHANGE_SECRET_COMPARTMENT_TOOL');
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name => 'CHANGE_SECRET_COMPARTMENT_TOOL',
        attributes => '{
            "instruction": "Move a secret to a different compartment to align with tenancy structure, permissions, or cost ownership. The secret remains the same resource with updated compartment context.",
            "function": "oci_vault_agents.change_secret_compartment"
            }',
        description => 'Tool for changing the compartment of an OCI Vault secret'
    );

    ------------------------------------------------------------------------
    -- AI TOOL: CREATE_SECRET_TOOL
    -- maps to oci_vault_agents.create_secret
    ------------------------------------------------------------------------
    drop_tool_if_exists(tool_name => 'CREATE_SECRET_TOOL');
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name => 'CREATE_SECRET_TOOL',
        attributes => '{
            "instruction": "Create a new secret in OCI Vault using the specified vault and key, establishing its initial CURRENT version with the provided plaintext. Use for onboarding new credentials or initializing managed secrets.",
            "function": "oci_vault_agents.create_secret"
            }',
        description => 'Tool for creating a secret in OCI Vault (Select AI Agent / Oracle Autonomous AI Database)'
    );

    ------------------------------------------------------------------------
    -- AI TOOL: GET_SECRET_TOOL
    -- maps to oci_vault_agents.get_secret
    ------------------------------------------------------------------------
    drop_tool_if_exists(tool_name => 'GET_SECRET_TOOL');
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name => 'GET_SECRET_TOOL',
        attributes => '{
            "instruction": "Retrieve existing secret metadata to inspect its state, associations, and timing details. Use for monitoring and diagnostics; this tool does not expose secret material.",
            "function": "oci_vault_agents.get_secret"
            }',
        description => 'Tool for fetching an OCI Vault secret (Select AI Agent / Oracle Autonomous AI Database)'
    );

    DBMS_OUTPUT.PUT_LINE('create_vault_tools completed.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error in create_vault_tools: ' || SQLERRM);
        RAISE;
END initialize_vault_tools;
/
-------------------------------------------------------------------------------
-- Call the procedure to (re)create all OCI Vault AI Agent tools
-------------------------------------------------------------------------------
BEGIN
    initialize_vault_tools;
END;
/

alter session set current_schema = ADMIN;
