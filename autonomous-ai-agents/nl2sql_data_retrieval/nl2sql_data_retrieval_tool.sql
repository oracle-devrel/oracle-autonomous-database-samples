rem ============================================================================
rem LICENSE
rem   Copyright (c) 2025 Oracle and/or its affiliates.
rem   Licensed under the Universal Permissive License (UPL), Version 1.0
rem   https://oss.oracle.com/licenses/upl/
rem
rem NAME
rem   nl2sql_data_retrieval_tools.sql
rem
rem DESCRIPTION
rem   Installer script for NL2SQL generic data retrieval tools.
rem   (Select AI Agent / Oracle AI Database).
rem
rem   This script installs a consolidated PL/SQL package and registers
rem   AI Agent tools used to refine the Select AI NL2SQL operations 
rem   via Select AI Agent (Oracle AI Database).
rem
rem RELEASE VERSION
rem   1.0
rem
rem RELEASE DATE
rem   30-Jan-2026
rem
rem MAJOR CHANGES IN THIS RELEASE
rem   - Initial release
rem
rem SCRIPT STRUCTURE
rem   1. Initialization:
rem        - Grants
rem        - Configuration setup
rem
rem   2. Package Deployment:
rem        - &&INSTALL_SCHEMA.nl2sql_data_retrieval_agents
rem          (package specification and body)
rem
rem   3. AI Tool Setup:
rem        - Creation of all NL2SQl data retrieval agent tools
rem
rem INSTALL INSTRUCTIONS
rem   1. Connect as ADMIN or a user with required privileges
rem   2. Run the script using SQL*Plus or SQLcl:
rem
rem      sqlplus admin@db @nl2sql_data_retrieval_tools.sql <INSTALL_SCHEMA>
rem
rem   3. Verify installation by checking tool registration
rem      and package compilation status.
rem
rem PARAMETERS
rem   INSTALL_SCHEMA (Required)
rem     Schema in which the package and tools will be created.
rem ----------------------------------------------------------------------------
rem GOOGLE CUSTOM SEARCH – SETUP INSTRUCTIONS
rem ----------------------------------------------------------------------------
rem The WEBSEARCH tool uses Google Custom Search Engine (CSE) APIs.
rem Google credentials MUST be stored securely in OCI Vault.
rem
rem Step 1: Create a Google Cloud Project
rem   - Go to https://console.cloud.google.com/
rem   - Create a new project or select an existing one
rem
rem Step 2: Enable Custom Search API
rem   - Navigate to: APIs & Services → Library
rem   - Search for "Custom Search API"
rem   - Click Enable
rem
rem Step 3: Create a Google API Key
rem   - Go to: APIs & Services → Credentials
rem   - Click "Create Credentials" → API Key
rem   - Copy the generated API Key
rem   - (Optional) Restrict the key to "Custom Search API"
rem
rem Step 4: Create a Custom Search Engine (CX ID)
rem   - Go to https://programmablesearchengine.google.com/
rem   - Click "Add" to create a new search engine
rem   - Set "Search the entire web" = ON
rem   - Save and note the Search Engine ID (cx)
rem
rem Step 5: Store secrets securely in OCI Vault (MANDATORY)
rem   - Create an OCI Vault in your compartment (if not already available)
rem   - Store the Google API Key as a Vault secret
rem   - Store the Google CX ID as a separate Vault secret
rem   - Note the Secret OCIDs for both secrets
rem
rem Step 6: Configure NL2SQL Data Retrieval Agent
rem   - Provide the Vault Secret OCIDs during installation:
rem       * vault_secret_id1 → Google API Key secret OCID
rem       * vault_secret_id2 → Google CX ID secret OCID
rem   - Provide the OCI region where the Vault exists
rem   - Provide the OCI credential name with access to read Vault secrets
rem
rem Notes:
rem   - Secrets are resolved at runtime using DBMS_CLOUD_OCI_SC_SECRETS
rem   - Do NOT store Google API keys or CX IDs directly in database tables
rem   - Rotating the secret in OCI Vault does not require code changes
rem
rem Reference API:
rem   https://www.googleapis.com/customsearch/v1
rem ----------------------------------------------------------------------------
rem
rem ============================================================================


SET SERVEROUTPUT ON
SET VERIFY OFF

-- ============================================================================
-- Installation Parameters
-- ============================================================================

-- First argument: Schema Name (Required)
ACCEPT SCHEMA_NAME CHAR PROMPT 'Enter schema name (required): '
DEFINE INSTALL_SCHEMA = '&SCHEMA_NAME'

-- Second argument: NL2SQL Data Retrieval Agent configuration (Required)
PROMPT
PROMPT Enter NL2SQL Data Retrieval Agent configuration in JSON format.
PROMPT These parameters are necessary to configure the websearch functionality.
PROMPT
PROMPT Optional parameters:
PROMPT   - credential_name              : OCI credential to access Vault
PROMPT   - vault_region                 : OCI region where Vault secrets exist
PROMPT   - api_key_vault_secret_ocid    : Vault secret OCID for Google API Key
PROMPT   - cxid_vault_secret_ocid       : Vault secret OCID for Google CX ID
PROMPT
PROMPT Provide input in below format
PROMPT Example:
PROMPT {
PROMPT   "credential_name":"OCI_CRED",
PROMPT   "vault_region":"eu-frankfurt-1",
PROMPT   "cxid_vault_secret_ocid":"ocid1.vaultsecret.oc1..aaaa",
PROMPT   "api_key_vault_secret_ocid":"ocid1.vaultsecret.oc1..bbbb"
PROMPT }
PROMPT
PROMPT

ACCEPT INSTALL_CONFIG_JSON CHAR PROMPT 'Enter INSTALL_CONFIG_JSON (optional and can be set later in SELECTAI_AGENT_CONFIG table): '
DEFINE INSTALL_CONFIG_JSON = '&INSTALL_CONFIG_JSON'


CREATE OR REPLACE PROCEDURE initialize_nl2sql_data_retrieval_agent(
  p_install_schema_name IN VARCHAR2,
  p_config_json         IN CLOB
)
IS
  l_use_rp              BOOLEAN := NULL;
  l_schema_name         VARCHAR2(128);
  c_nlb_agent CONSTANT  VARCHAR2(64) := 'NL2SQL_DATA_RETRIEVAL_AGENT';
  l_credential_name   VARCHAR2(100);
  l_oci_region        VARCHAR2(100);   
  l_vault_secret_id1  VARCHAR2(512);
  l_vault_secret_id2  VARCHAR2(512);
  l_ai_profile        VARCHAR2(100);

  TYPE priv_list_t IS VARRAY(200) OF VARCHAR2(4000);
  l_priv_list CONSTANT priv_list_t := priv_list_t(
    'DBMS_CLOUD',
    'DBMS_CLOUD_AI',
    'DBMS_CLOUD_AI_AGENT',
    'DBMS_CLOUD_OCI_SECRETS_SECRET_BUNDLE_T',
    'DBMS_CLOUD_OCI_SC_SECRETS_GET_SECRET_BUNDLE_RESPONSE_T',
    'DBMS_CLOUD_OCI_SECRETS_BASE64_SECRET_BUNDLE_CONTENT_DETAILS_T',
    'DBMS_CLOUD_OCI_SC_SECRETS'
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
    
    EXCEPTION
      WHEN OTHERS THEN
        RAISE;
    
  END execute_grants;
  
    ----------------------------------------------------------------------------
  -- get_config: returns parsed values via OUT params (no globals modified)
  ----------------------------------------------------------------------------
  PROCEDURE get_config(
    p_config_json           IN  CLOB,
    o_use_rp                OUT BOOLEAN,
    o_credential_name       OUT VARCHAR2,
    o_oci_region            OUT VARCHAR2,
    o_vault_secret_id1      OUT VARCHAR2,
    o_vault_secret_id2      OUT VARCHAR2,
    o_ai_profile            OUT VARCHAR2
  ) IS
    l_cfg JSON_OBJECT_T := NULL;
  BEGIN
    -- initialize outs to NULL for deterministic behavior
    o_use_rp := NULL;
    o_credential_name := NULL;
    o_oci_region := NULL;
    o_vault_secret_id1 := NULL;
    o_vault_secret_id2 := NULL;
    o_ai_profile := NULL;

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

        IF l_cfg.has('api_key_vault_secret_ocid') THEN
          o_vault_secret_id1 := l_cfg.get_string('api_key_vault_secret_ocid');
        END IF;

        IF l_cfg.has('cxid_vault_secret_ocid') THEN
          o_vault_secret_id2 := l_cfg.get_string('cxid_vault_secret_ocid');
        END IF;
        
        IF l_cfg.has('vault_region') THEN
          o_oci_region := l_cfg.get_string('vault_region');
        END IF;
        
        IF l_cfg.has('ai_profile') THEN
          o_ai_profile := l_cfg.get_string('ai_profile');
        END IF;

      EXCEPTION
        WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('Config JSON parse failed: ' || SQLERRM);
          -- leave outs as NULL so default logic applies upstream
          o_use_rp := NULL;
          o_credential_name := NULL;
          o_vault_secret_id1 := NULL;
          o_vault_secret_id2 := NULL;
          o_oci_region := NULL;
          o_ai_profile := NULL;
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
    p_oci_region            IN VARCHAR2,
    p_vault_secret_id1      IN VARCHAR2,
    p_vault_secret_id2      IN VARCHAR2,
    p_ai_profile            IN VARCHAR2
  ) IS
    l_effective_use_rp  BOOLEAN;
    l_enable_rp_str     VARCHAR2(3);
    c_vault_agent       VARCHAR2(100) := 'NL2SQL_DATA_RETRIEVAL_AGENT';
    l_credential_name   VARCHAR2(100);
    l_oci_region        VARCHAR2(100); 
    l_use_rp            VARCHAR2(100); 
    l_vault_secret_id1  VARCHAR2(512);
    l_vault_secret_id2  VARCHAR2(512);
    l_ai_profile        VARCHAR2(100);
    
  BEGIN
    -- Determine effective value for resource principal:
    -- If JSON supplied a value, use it. If not supplied, default to TRUE (YES).
    IF p_use_rp IS NULL THEN
      l_effective_use_rp := TRUE; -- default is YES when not provided
    ELSE
      l_effective_use_rp := p_use_rp;
    END IF;

    -- Persist credential_name
    IF p_credential_name IS NOT NULL THEN
      merge_config_key(p_schema, 'VALUT_OCI_CRED', p_credential_name, c_vault_agent);
    END IF;

    IF p_oci_region IS NOT NULL THEN
      merge_config_key(p_schema, 'VALUT_REGION', p_oci_region, c_vault_agent);
    END IF;

    IF p_vault_secret_id1 IS NOT NULL THEN
      merge_config_key(p_schema, 'API_KEY_VAULT_SECRET_OCID', p_vault_secret_id1, c_vault_agent);
    END IF;
    
    IF p_vault_secret_id2 IS NOT NULL THEN
      merge_config_key(p_schema, 'CXID_VAULT_SECRET_OCID', p_vault_secret_id2, c_vault_agent);
    END IF;
    
    IF p_ai_profile IS NOT NULL THEN
      merge_config_key(p_schema, 'AGENT_AI_PROFILE', p_ai_profile, c_vault_agent);
    END IF;
    
    -- Persist ENABLE_RESOURCE_PRINCIPAL as YES/NO based on effective value (default YES)
    IF l_effective_use_rp THEN
      l_enable_rp_str := 'YES';
    ELSE
      l_enable_rp_str := 'NO';
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
    o_oci_region        => l_oci_region,
    o_vault_secret_id1  => l_vault_secret_id1,
    o_vault_secret_id2  => l_vault_secret_id2,
    o_ai_profile        => l_ai_profile
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
    p_oci_region          => l_oci_region,
    p_vault_secret_id1    => l_vault_secret_id1,
    p_vault_secret_id2    => l_vault_secret_id2,
    p_ai_profile          => l_ai_profile
  );

  DBMS_OUTPUT.PUT_LINE('initialize_nl2sql_data_retrieval_agent completed for schema ' || l_schema_name);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Fatal error in initialize_nl2sql_data_retrieval_agent: ' || SQLERRM);
    RAISE;
  
END initialize_nl2sql_data_retrieval_agent;
/

-------------------------------------------------------------------------------
-- Run the setup for the NL2SQL data retrieval AI agent.
-------------------------------------------------------------------------------
BEGIN
  initialize_nl2sql_data_retrieval_agent(
    p_install_schema_name => '&&INSTALL_SCHEMA',
    p_config_json         => '&&INSTALL_CONFIG_JSON'
  );
END;
/


alter session set current_schema = &&INSTALL_SCHEMA;

------------------------------------------------------------------------
-- Package specification
------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE nl2sql_data_retrieval_functions
AS
  FUNCTION get_vault_secret (
      p_secret_id       IN VARCHAR2,
      p_region          IN VARCHAR2,
      p_credential_name IN VARCHAR2
    ) RETURN VARCHAR2;

  FUNCTION websearch_func(search_query IN CLOB) RETURN CLOB;
  
  FUNCTION get_url_content(url IN CLOB) RETURN CLOB;
  
  FUNCTION get_distinct_values_func(
    schema_name    IN VARCHAR2,
    table_name     IN VARCHAR2,
    column_name    IN VARCHAR2,
    match_pattern  IN VARCHAR2 DEFAULT NULL,
    match_type     IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;
  
    FUNCTION get_range_values_func(
      user_prompt   IN CLOB
    ) RETURN CLOB; 
  
  FUNCTION get_current_timestamp(
    p_format IN VARCHAR2 DEFAULT 'YYYY-MM-DD HH24:MI:SS.FF'
  ) RETURN CLOB;
  
  FUNCTION runsql_func(
        user_prompt   IN CLOB
  ) RETURN CLOB;
  
  FUNCTION generate_chart_func(
    chart_prompt IN CLOB
  ) RETURN CLOB;

END nl2sql_data_retrieval_functions;
/

------------------------------------------------------------------------
-- Package body
------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY nl2sql_data_retrieval_functions
AS

    FUNCTION get_vault_secret (
      p_secret_id       IN VARCHAR2,
      p_region          IN VARCHAR2,
      p_credential_name IN VARCHAR2
    ) RETURN VARCHAR2
    IS
      l_response        DBMS_CLOUD_OCI_SECRETS_SECRET_BUNDLE_T;
      l_get_secret_resp DBMS_CLOUD_OCI_SC_SECRETS_GET_SECRET_BUNDLE_RESPONSE_T;
      l_base64_secret   VARCHAR2(32767);
      l_raw_secret      RAW(32767);
      l_decoded_secret  VARCHAR2(32767);
      
    BEGIN
      -- Fetch secret bundle from OCI Vault
      l_get_secret_resp :=
        DBMS_CLOUD_OCI_SC_SECRETS.GET_SECRET_BUNDLE(
          secret_id       => p_secret_id,
          region          => p_region,
          credential_name => p_credential_name
        );
    
      -- Extract response body
      l_response := l_get_secret_resp.response_body;
    
      -- Extract Base64 secret content
      l_base64_secret :=
        TREAT(
          l_response.secret_bundle_content
          AS DBMS_CLOUD_OCI_SECRETS_BASE64_SECRET_BUNDLE_CONTENT_DETAILS_T
        ).content;
    
      -- Decode Base64
      l_raw_secret :=
        UTL_ENCODE.BASE64_DECODE(
          UTL_RAW.CAST_TO_RAW(l_base64_secret)
        );
    
      l_decoded_secret :=
        UTL_RAW.CAST_TO_VARCHAR2(l_raw_secret);
      
      dbms_output.put_line('Secret fetched from vault is '||l_decoded_secret);
      
      RETURN l_decoded_secret;
    
    EXCEPTION
      WHEN OTHERS THEN
        -- Avoid leaking secret data
        RAISE_APPLICATION_ERROR(
          -20001,
          'Failed to retrieve or decode OCI Vault secret: ' || SQLERRM
        );
        
    END get_vault_secret;
    
    

    FUNCTION websearch_func (
        search_query IN CLOB
    ) RETURN CLOB
    AS
        l_resp             DBMS_CLOUD_TYPES.RESP;
    
        -- Config values from SELECTAI_AGENT_CONFIG
        l_secretid_key     VARCHAR2(4000);
        l_secretid_cx      VARCHAR2(4000);
        l_region           VARCHAR2(4000);
        l_oci_cred         VARCHAR2(4000);
    
        -- Decoded secrets from OCI Vault
        l_google_api_key   VARCHAR2(4000);
        l_google_cx_id     VARCHAR2(4000);
    
        l_obj              JSON_OBJECT_T;
        l_arr              JSON_ARRAY_T;
        l_ret_obj          JSON_OBJECT_T;
        l_ret_arr          JSON_ARRAY_T := NEW JSON_ARRAY_T;
    
        MAX_SEARCH_RESULTS CONSTANT PLS_INTEGER := 10;
        l_result           CLOB;
    BEGIN
        ------------------------------------------------------------------
        -- Read Vault configuration from SELECTAI_AGENT_CONFIG
        ------------------------------------------------------------------
        SELECT value
        INTO l_secretid_key
        FROM selectai_agent_config
        WHERE agent = 'NL2SQL_DATA_RETRIEVAL_AGENT'
          AND key   = 'API_KEY_VAULT_SECRET_OCID';
        
        SELECT value
        INTO l_secretid_cx
        FROM selectai_agent_config
        WHERE agent = 'NL2SQL_DATA_RETRIEVAL_AGENT'
          AND key   = 'CXID_VAULT_SECRET_OCID';
        
        SELECT value
        INTO l_region
        FROM selectai_agent_config
        WHERE agent = 'NL2SQL_DATA_RETRIEVAL_AGENT'
          AND key   = 'VALUT_REGION';
        
        SELECT value
        INTO l_oci_cred
        FROM selectai_agent_config
        WHERE agent = 'NL2SQL_DATA_RETRIEVAL_AGENT'
          AND key   = 'VALUT_OCI_CRED';
    
    
        ------------------------------------------------------------------
        -- Resolve actual secrets from OCI Vault
        ------------------------------------------------------------------
        l_google_api_key :=
            get_vault_secret(
                p_secret_id       => l_secretid_key,
                p_region          => l_region,
                p_credential_name => l_oci_cred
            );
    
        l_google_cx_id :=
            get_vault_secret(
                p_secret_id       => l_secretid_cx,
                p_region          => l_region,
                p_credential_name => l_oci_cred
            );
    
        ------------------------------------------------------------------
        -- Call Google Custom Search API
        ------------------------------------------------------------------
        l_resp := DBMS_CLOUD.SEND_REQUEST(
            credential_name => NULL,
            method          => 'GET',
            uri             => 'https://www.googleapis.com/customsearch/v1'
                   || '?key=' || l_google_api_key
                   || '&'||'cx='  || l_google_cx_id
                   || '&'||'num=' || MAX_SEARCH_RESULTS
                   || '&'||'q='   || UTL_URL.ESCAPE(search_query)
        );
    
        ------------------------------------------------------------------
        -- Parse response
        ------------------------------------------------------------------
        l_arr :=
            JSON_OBJECT_T(
                DBMS_CLOUD.GET_RESPONSE_TEXT(l_resp)
            ).GET_ARRAY('items');
    
        FOR i IN 0 .. l_arr.GET_SIZE - 1 LOOP
            l_ret_obj := NEW JSON_OBJECT_T;
            l_obj := TREAT(l_arr.get(i) AS JSON_OBJECT_T);
    
            l_ret_obj.put('title',   l_obj.get_string('title'));
            l_ret_obj.put('link',    l_obj.get_string('link'));
            l_ret_obj.put('snippet', l_obj.get_string('snippet'));
    
            l_ret_arr.append(l_ret_obj);
        END LOOP;
    
        l_result := l_ret_arr.to_clob;
        RETURN l_result;
    
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(
                -20002,
                'Websearch configuration not found in SELECTAI_AGENT_CONFIG'
            );
        WHEN OTHERS THEN
            RAISE_APPLICATION_ERROR(
                -20003,
                'Websearch failed: ' || SQLERRM
            );
    END websearch_func;

  ----------------------------------------------------------------------
  -- get_url_content: uses explicit credential if provided, else config
  ----------------------------------------------------------------------
    FUNCTION get_url_content (
        url IN CLOB
    ) RETURN CLOB
    AS
        l_resp   DBMS_CLOUD_TYPES.RESP;
        l_result CLOB;
    BEGIN
        l_resp := DBMS_CLOUD.SEND_REQUEST(
                    credential_name => NULL,
                    method          => 'GET',
                    uri             => url
                 );
    
        l_result := DBMS_LOB.SUBSTR(DBMS_VECTOR_CHAIN.UTL_TO_TEXT(DBMS_CLOUD.GET_RESPONSE_RAW(l_resp)), 32767, 1);
        
        RETURN l_result;
        
    END get_url_content;
    
    FUNCTION get_distinct_values_func (
        schema_name    IN VARCHAR2,
        table_name     IN VARCHAR2,
        column_name    IN VARCHAR2,
        match_pattern  IN VARCHAR2 DEFAULT NULL,
        match_type     IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB IS
        l_sql         VARCHAR2(4000);
        l_result      CLOB;
        l_data_type   VARCHAR2(128);
        max_length    PLS_INTEGER := 32767;
        l_match_type  VARCHAR2(10);
        l_threshold   NUMBER := 50; -- fuzzy similarity threshold (0–100)
    BEGIN
        -- Fetch column data type
        l_sql := 'SELECT data_type FROM all_tab_columns
                   WHERE owner = :1
                     AND table_name = :2
                     AND column_name = :3';
        EXECUTE IMMEDIATE l_sql INTO l_data_type
            USING schema_name, table_name, column_name;
    
        -- Normalize match_type input
        IF TRIM(match_pattern) IS NOT NULL AND 
           NVL(LOWER(TRIM(match_type)), 'NULL') NOT IN ('fuzzy', 'regex', 'exact') THEN
            l_match_type := 'fuzzy';
        ELSE
            l_match_type := LOWER(TRIM(match_type));
        END IF;
    
        -- Main matching logic
        IF match_pattern IS NOT NULL AND LENGTH(TRIM(match_pattern)) > 0 THEN
            l_sql := 'SELECT JSON_ARRAYAGG(col RETURNING CLOB) FROM (' ||
                     'SELECT DISTINCT ' || DBMS_ASSERT.enquote_name(column_name) || ' AS col ' ||
                     'FROM ' || DBMS_ASSERT.sql_object_name(schema_name || '.' || table_name);
    
            CASE l_match_type
                WHEN 'fuzzy' THEN
                    l_sql := l_sql ||
                            ' WHERE FUZZY_MATCH(JARO_WINKLER, ' || DBMS_ASSERT.enquote_name(column_name) || ', :pattern) >= :threshold)';
                    EXECUTE IMMEDIATE l_sql INTO l_result USING match_pattern, l_threshold;
    
                WHEN 'exact' THEN
                    l_sql := l_sql ||
                            ' WHERE ' || DBMS_ASSERT.enquote_name(column_name) || ' = :pattern)';
                    EXECUTE IMMEDIATE l_sql INTO l_result USING match_pattern;
    
                WHEN 'regex' THEN
                    l_sql := l_sql ||
                            ' WHERE REGEXP_LIKE(' || DBMS_ASSERT.enquote_name(column_name) || ', :pattern, ''i''))';
                    EXECUTE IMMEDIATE l_sql INTO l_result USING match_pattern;
    
                ELSE
                    raise_application_error(-20000, INITCAP(l_match_type) || ' match type is not supported.');
    
            END CASE;
        END IF;
    
        -- Fallback: return all distinct values
        IF l_result IS NULL THEN
            l_sql :=
              'SELECT JSON_ARRAYAGG(col RETURNING CLOB) FROM (' ||
              'SELECT DISTINCT ' || DBMS_ASSERT.enquote_name(column_name) || ' AS col ' ||
              'FROM ' || DBMS_ASSERT.sql_object_name(schema_name || '.' || table_name) || ')';
            EXECUTE IMMEDIATE l_sql INTO l_result;
        END IF;
    
        -- Truncate long results
        IF l_result IS NOT NULL AND DBMS_LOB.getlength(l_result) > max_length THEN
            l_result := SUBSTR(l_result, 1, max_length - 1)
                     || ',"notice":"Results truncated to '
                     || TO_CHAR(max_length) || ' characters."}';
        END IF;
    
        RETURN l_result;
    
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN '{"error": "Column not found."}';
        WHEN OTHERS THEN
            RETURN '{"error": "' || REPLACE(SQLERRM, '"', '''') || '"}';
    END get_distinct_values_func;
    
    
    
    FUNCTION get_current_timestamp(
      p_format IN VARCHAR2 DEFAULT 'YYYY-MM-DD HH24:MI:SS.FF'
    ) RETURN CLOB
    IS
      l_timestamp TIMESTAMP := SYSTIMESTAMP;
      l_clob      CLOB;
    BEGIN
      l_clob := TO_CLOB(TO_CHAR(l_timestamp, p_format));
      RETURN l_clob;
    END;
    
    

    FUNCTION get_range_values_func(
      user_prompt   IN CLOB
    ) RETURN CLOB 
    IS
      l_sql CLOB;
      l_wrapped_sql CLOB;
      l_sql_result   CLOB;    
      l_json_result CLOB;
      l_obj         JSON_OBJECT_T:=new JSON_OBJECT_T();
      MAX_ROWS      CONSTANT PLS_INTEGER := 1000;
      SORRY_MESSAGE CONSTANT VARCHAR2(4000) := 'Sorry, unfortunately a valid SELECT statement could not be generated ';
      l_ai_profile   VARCHAR2(4000);
    BEGIN
      ------------------------------------------------------------------
      -- Fetch AI profile from SELECTAI_AGENT_CONFIG
      ------------------------------------------------------------------
      SELECT value
      INTO l_ai_profile
      FROM selectai_agent_config
      WHERE agent = 'NL2SQL_DATA_RETRIEVAL_AGENT'
        AND key   = 'AGENT_AI_PROFILE';
        
        BEGIN
            l_sql := DBMS_CLOUD_AI.generate(prompt       => user_prompt,
                                            profile_name => l_ai_profile,
                                            action       => 'showsql');
        EXCEPTION
            WHEN OTHERS THEN
                RETURN 'Error Encountered: ' || SQLERRM;
        END;
        -- Check if SQL generation failed
        -- If failed, we directly give the generated sql back to LLM
        -- We want the LLM invoke the tool again with a better user prompt based on the sorry message
        IF INSTR(l_sql, SORRY_MESSAGE) = 1 THEN
            RETURN l_sql;
        END IF;
      -- Execute the SQL
    
        l_wrapped_sql := 'SELECT JSON_ARRAYAGG(JSON_OBJECT(* RETURNING CLOB) RETURNING CLOB) result ' ||
                        'FROM ( select * from (' || l_sql || ' ) FETCH FIRST ' || TO_CHAR(MAX_ROWS) || ' ROWS ONLY)';
        -- Execute the SQL
        EXECUTE IMMEDIATE l_wrapped_sql
            INTO l_sql_result;
        
        l_obj.put('sql_query',l_sql);
        
         IF l_sql_result is NULL THEN 
          l_obj.put('sql_result','No data found.');
        ELSE
          l_obj.put('sql_result',JSON_ARRAY_T.PARSE(l_sql_result));
        END IF;
        
        RETURN l_obj.to_clob();
     
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RETURN '{"error":"AI profile not configured in SELECTAI_AGENT_CONFIG"}';
      WHEN OTHERS THEN
        RETURN 'Run SQL exception encountered: ' || SQLERRM ;
    END get_range_values_func;
    
    
    
    FUNCTION runsql_func(
        user_prompt   IN CLOB
    ) RETURN CLOB 
    IS
      l_sql CLOB;
      l_wrapped_sql CLOB;
      l_sql_result   CLOB;    
      l_json_result CLOB;
      l_obj         JSON_OBJECT_T:=new JSON_OBJECT_T();
      MAX_ROWS      CONSTANT PLS_INTEGER := 1000;
      SORRY_MESSAGE CONSTANT VARCHAR2(4000) := 'Sorry, unfortunately a valid SELECT statement could not be generated ';
      l_ai_profile   VARCHAR2(4000);
    BEGIN
      ------------------------------------------------------------------
      -- Fetch AI profile from SELECTAI_AGENT_CONFIG
      ------------------------------------------------------------------
      SELECT value
      INTO l_ai_profile
      FROM selectai_agent_config
      WHERE agent = 'NL2SQL_DATA_RETRIEVAL_AGENT'
        AND key   = 'AGENT_AI_PROFILE';
        
    BEGIN
        l_sql := DBMS_CLOUD_AI.generate(prompt       => user_prompt,
                                        profile_name => l_ai_profile,
                                        action       => 'showsql');
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 'Error Encountered: ' || SQLERRM;
    END;
    -- Check if SQL generation failed
    -- If failed, we directly give the generated sql back to LLM
    -- We want the LLM invoke the tool again with a better user prompt based on the sorry message
    IF INSTR(l_sql, SORRY_MESSAGE) = 1 THEN
        RETURN l_sql;
    END IF;
  -- Execute the SQL

    l_wrapped_sql := 'SELECT JSON_ARRAYAGG(JSON_OBJECT(* RETURNING CLOB) RETURNING CLOB) result ' ||
                    'FROM ( select * from (' || l_sql || ' ) FETCH FIRST ' || TO_CHAR(MAX_ROWS) || ' ROWS ONLY)';
    -- Execute the SQL
    EXECUTE IMMEDIATE l_wrapped_sql
        INTO l_sql_result;
    
    l_obj.put('sql_query',l_sql);
    
     IF l_sql_result is NULL THEN 
      l_obj.put('sql_result','No data found.');
    ELSE
      l_obj.put('sql_result',JSON_ARRAY_T.PARSE(l_sql_result));
    END IF;
    
    RETURN l_obj.to_clob();

 
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RETURN '{"error":"AI profile not configured in SELECTAI_AGENT_CONFIG"}';
      WHEN OTHERS THEN
        RETURN 'Run SQL exception encountered: ' || SQLERRM ;
        
    END runsql_func;
    
    
    
    ------------------------------------------------------------------------------------
    -- generate_chart_func - to generate the charts
    ------------------------------------------------------------------------------------
    FUNCTION generate_chart_func(
      chart_prompt IN CLOB
    ) RETURN CLOB
    IS
      l_full_prompt  CLOB;
      l_result       CLOB;
      l_ai_profile   VARCHAR2(4000);
    BEGIN
      ------------------------------------------------------------------
      -- Fetch AI profile from SELECTAI_AGENT_CONFIG
      ------------------------------------------------------------------
      SELECT value
      INTO l_ai_profile
      FROM selectai_agent_config
      WHERE agent = 'NL2SQL_DATA_RETRIEVAL_AGENT'
        AND key   = 'AGENT_AI_PROFILE';
    
      ------------------------------------------------------------------
      -- Build prompt
      ------------------------------------------------------------------
      l_full_prompt :=
           'You are a helpful assistant that generates Chart.js configurations in valid JSON format based on user prompts.' || CHR(10) ||
           '' || CHR(10) ||
           'Rules:' || CHR(10) ||
           '- Output ONLY a single valid JSON object or array of JSON objects. No markdown, no code blocks, no explanations.' || CHR(10) ||
           '- JSON must be syntactically valid. No comments. No text outside braces. No trailing commas.' || CHR(10) ||
           '- Use only these Chart.js types: "bar", "line", "pie", "doughnut", "radar", "scatter", "bubble", "polarArea".' || CHR(10) ||
           '- Ensure "labels" and "datasets" arrays are properly formatted.' || CHR(10) ||
           '- For "backgroundColor" and "borderColor", use ONLY colors from this palette and repeat as needed:' || CHR(10) ||
           '  ["#007bff", "#6c757d", "#28a745", "#ffc107", "#dc3545",' || CHR(10) ||
           '   "#20c997", "#6610f2", "#e83e8c", "#fd7e14", "#17a2b8",' || CHR(10) ||
           '   "#8bc34a", "#673ab7", "#03a9f4", "#ff9800", "#ff5722",' || CHR(10) ||
           '   "#4caf50", "#795548", "#607d8b", "#c2185b", "#343a40"]' || CHR(10) ||
           '- Do NOT output this palette again in the JSON. Just use these colors as values.' || CHR(10) ||
           '- Example of correct output:' || CHR(10) ||
           '{' || CHR(10) ||
           '  "type": "bar",' || CHR(10) ||
           '  "data": {' || CHR(10) ||
           '    "labels": ["A", "B", "C", "D", "E"],' || CHR(10) ||
           '    "datasets": [{' || CHR(10) ||
           '      "label": "Dataset 1",' || CHR(10) ||
           '      "data": [10, 20, 30, 40, 50],' || CHR(10) ||
           '      "backgroundColor": ["#007bff", "#6c757d", "#28a745", "#ffc107", "#dc3545"],' || CHR(10) ||
           '      "borderColor": ["#007bff", "#6c757d", "#28a745", "#ffc107", "#dc3545"],' || CHR(10) ||
           '      "borderWidth": 1' || CHR(10) ||
           '    }]' || CHR(10) ||
           '  },' || CHR(10) ||
           '  "options": {' || CHR(10) ||
           '    "responsive": true,' || CHR(10) ||
           '    "plugins": {' || CHR(10) ||
           '      "title": {"display": true, "text": "Sample Chart"}' || CHR(10) ||
           '    }' || CHR(10) ||
           '  }' || CHR(10) ||
           '}' || CHR(10) ||
           chart_prompt;
    
      ------------------------------------------------------------------
      -- Invoke Select AI using configured profile
      ------------------------------------------------------------------
      l_result :=
        DBMS_CLOUD_AI.generate(
          prompt       => l_full_prompt,
          profile_name => l_ai_profile,
          action       => 'chat'
        );
    
      RETURN l_result;
    
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RETURN '{"error":"AI profile not configured in SELECTAI_AGENT_CONFIG"}';
      WHEN OTHERS THEN
        RETURN '{"error":"' || REPLACE(SQLERRM, '"', '\\"') || '"}';
    END generate_chart_func;

END nl2sql_data_retrieval_functions;
/


------------------------------------------------------------------------------------------
-- This procedure installs or refreshes the NL2SQL data retrieval Agent tools in the
-- current schema. It drops any existing tool definitions and recreates them
-- pointing to the latest implementations in &&INSTALL_SCHEMA.nl2sql_data_retrieval_agents.
------------------------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE initialize_nl2sql_data_retrieval_tools
IS
  PROCEDURE drop_tool_if_exists (tool_name IN VARCHAR2) IS
    l_tool_count NUMBER;
    l_sql        CLOB;
  BEGIN
    l_sql := 'SELECT COUNT(*) FROM USER_AI_AGENT_TOOLS WHERE TOOL_NAME = :1';
    EXECUTE IMMEDIATE l_sql INTO l_tool_count USING tool_name;
    IF l_tool_count > 0 THEN
      DBMS_CLOUD_AI_AGENT.DROP_TOOL(tool_name);
    END IF;
  END drop_tool_if_exists;
BEGIN

  -- Web search tool (used by tasks in this repo)
  drop_tool_if_exists(tool_name => 'WEBSEARCH');

  DBMS_CLOUD_AI_AGENT.create_tool(
    tool_name  => 'WEBSEARCH',
    attributes => '{
      "instruction": "This tool performs a web search for the given query string and returns a list of relevant results, including title, link, and short snippet of link content. If need more information from specified url link, then invoke GET_URL_CONTENT_ORCL tool",
      "function": "nl2sql_data_retrieval_functions.websearch_func"
    }'
  );

  drop_tool_if_exists(tool_name => 'GET_URL_CONTENT');
  
  DBMS_CLOUD_AI_AGENT.create_tool(
    tool_name  => 'GET_URL_CONTENT',
    attributes => '{
      "instruction": "This tool fetches and returns the plain text content from the specified URL. ",
      "function": "nl2sql_data_retrieval_functions.get_url_content"
    }'
  );

   drop_tool_if_exists(tool_name => 'DISTINCT_VALUES_CHECK');
   
   DBMS_CLOUD_AI_AGENT.create_tool(
    tool_name  => 'DISTINCT_VALUES_CHECK',
    attributes => '{"instruction": "This tool returns distinct values from a specified column in a given table. ' ||
                    'If match_pattern is specified, then match_type must also be specified.' ||
                    'If both match_pattern and match_type are provided, the tool will filter distinct values using the specified matching technique.' ||
                    'If no matching values are found for the match_pattern, or if match_pattern was not specified, then the tool will return distinct values from the column.",
                    "function": "nl2sql_data_retrieval_functions.get_distinct_values_func",
                    "tool_inputs": [{"name": "match_type",
                                     "mandatory": false,
                                     "description": "Type of filtering technique to use: ' ||
                                                    '1.fuzzy - uses FUZZY MATCH  string comparison in Oracle 23ai; ' ||
                                                    '2.exact - uses ''='' operator for exact matches; ' ||
                                                    '3.regex - uses REGEXP_LIKE for regular expression matching of the pattern."},
                                    {"name": "match_pattern",
                                    "mandatory": false,
                                    "description": "Pattern or keyword to filter values. If provided, matching_type must also be specified."}
                                    ]}'
  );
  
   drop_tool_if_exists(tool_name => 'SQL_TOOL');
   
   DBMS_CLOUD_AI_AGENT.create_tool(
    tool_name  => 'SQL_TOOL',
    attributes => '{"instruction": "This tool can access the data in database. It will take user question as user_prompt and generate a sql query, and then it will execute the sql query to get the result' ||
                                    ' If the result is 0 rows. It''s possible that there is an predicates issue. Please use RANGE_VALUES_CHECK for Numeric, DATE, or TIMESTAMP types or DISTINCT_VALUES_CHECK tool for other datatype columns to get all the distinct values and reinvoke the tool with a refined the user question", 
                    "function": "nl2sql_data_retrieval_functions.runsql_func"}'
    );

   drop_tool_if_exists(tool_name => 'RANGE_VALUES_CHECK');
  
   DBMS_CLOUD_AI_AGENT.create_tool(
    tool_name  => 'RANGE_VALUES_CHECK',
    attributes => '{
      "instruction": "This tool returns the minimum and maximum (range) values of a column in the given table. Only Numeric, DATE, or TIMESTAMP types columns are supported.",
      "function": "nl2sql_data_retrieval_functions.get_range_values_func"
    }'
   );
   
   drop_tool_if_exists(tool_name => 'GENERATE_CHART');

   DBMS_CLOUD_AI_AGENT.create_tool(
    tool_name  => 'GENERATE_CHART',
    attributes => '{"instruction": "Use this tool when you need to generate a chart, graph, or visualization based on data. Provide a detailed prompt describing the chart type, data, labels, titles, and any other details. The tool will return formatted HTML for embedding the chart in the response.", 
                    "function": "nl2sql_data_retrieval_functions.generate_chart_func"}'
   );

  DBMS_OUTPUT.PUT_LINE('initialize_nl2sql_data_retrieval_tools completed.');
  
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error in initialize_nl2sql_data_retrieval_tools: ' || SQLERRM);
    RAISE;
    
END initialize_nl2sql_data_retrieval_tools;
/

-------------------------------------------------------------------------------
-- Call the procedure to (re)create all OCI NLB AI Agent tools
-------------------------------------------------------------------------------
BEGIN
  initialize_nl2sql_data_retrieval_tools;
END;
/

alter session set current_schema = ADMIN;




