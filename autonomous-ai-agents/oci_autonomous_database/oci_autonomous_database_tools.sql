rem ============================================================================
rem LICENSE
rem   Copyright (c) 2025 Oracle and/or its affiliates.
rem   Licensed under the Universal Permissive License (UPL), Version 1.0
rem   https://oss.oracle.com/licenses/upl/
rem
rem NAME
rem   oci_autonomous_database_tools.sql
rem
rem DESCRIPTION
rem   Installer script for OCI Autonomous Database AI tools
rem   (Select AI Agent / Oracle Autonomous AI Database).
rem
rem   This script installs a consolidated PL/SQL package and registers
rem   AI Agent tools used to automate OCI Autonomous Database operations
rem   via Select AI Agent (Oracle Autonomous AI Database).
rem
rem RELEASE VERSION
rem   1.1
rem
rem RELEASE DATE
rem   5-Feb-2026
rem
rem MAJOR CHANGES IN THIS RELEASE
rem - Compatibility with web SQL developer  
rem
rem SCRIPT STRUCTURE
rem   1. Initialization:
rem        - Grants
rem        - Configuration setup
rem
rem   2. Package Deployment:
rem        - &&SCHEMA_NAME.oci_autonomous_database_agents
rem          (package specification and body)
rem
rem   3. AI Tool Setup:
rem        - Creation of all Autonomous Database agent tools
rem
rem INSTALL INSTRUCTIONS
rem   1. Connect as ADMIN or a user with required privileges
rem   2. Run the script using SQL Developer / Web SQL Developer
rem   3. Verify installation by checking tool registration
rem      and package compilation status.
rem
rem PARAMETERS
rem   SCHEMA_NAME (Required)
rem     Schema in which the package and tools will be created.
rem
rem   CONFIG_JSON (Optional)
rem     JSON string used to configure OCI access.
rem
rem NOTES
rem   - Optional CONFIG_JSON keys:
rem       * use_resource_principal (boolean)
rem       * credential_name (string)
rem       * compartment_name (string)
rem       * compartment_ocid (string)
rem
rem   - Configuration can also be updated post-install
rem     in the SELECTAI_AGENT_CONFIG table.
rem
rem   - This script is idempotent only if DROP logic
rem     is explicitly enabled.
rem
rem ============================================================================


SET SERVEROUTPUT ON
SET VERIFY OFF

VAR v_schema VARCHAR2(128)
EXEC :v_schema := '&SCHEMA_NAME';

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

VAR v_config VARCHAR2(256)
EXEC :v_config := '&CONFIG_JSON';

-------------------------------------------------------------------------------
-- Initializes the OCI Autonomous Database AI Agent.
-------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE initialize_autonomous_database_agent(
  p_install_schema_name IN VARCHAR2,
  p_config_json         IN CLOB
)
IS
  l_use_rp              BOOLEAN := NULL;
  l_credential_name     VARCHAR2(4000) := NULL;
  l_compartment_ocid    VARCHAR2(4000) := NULL;
  l_compartment_name    VARCHAR2(4000) := NULL;
  l_schema_name         VARCHAR2(128);
  c_adb_agent CONSTANT  VARCHAR2(64) := 'OCI_AUTONOMOUS_DATABASE';

  TYPE priv_list_t IS VARRAY(250) OF VARCHAR2(4000);
  l_priv_list CONSTANT priv_list_t := priv_list_t(
    'DBMS_CLOUD',
    'DBMS_CLOUD_ADMIN',
    'DBMS_CLOUD_AI_AGENT',
    'DBMS_CLOUD_OCI_DB_DATABASE',
    -- Types used by common responses / requests (best-effort)
    'DBMS_CLOUD_OCI_DATABASE_CREATE_AUTONOMOUS_DATABASE_BASE_T',
    'DBMS_CLOUD_OCI_DB_DATABASE_CREATE_AUTONOMOUS_DATABASE_RESPONSE_T',
    'DBMS_CLOUD_OCI_DB_DATABASE_DELETE_AUTONOMOUS_DATABASE_RESPONSE_T',
    'DBMS_CLOUD_OCI_DB_DATABASE_GET_AUTONOMOUS_DATABASE_RESPONSE_T',
    'DBMS_CLOUD_OCI_DATABASE_AUTONOMOUS_DATABASE_T',
    'DBMS_CLOUD_OCI_DB_DATABASE_STOP_AUTONOMOUS_DATABASE_RESPONSE_T',
    'DBMS_CLOUD_OCI_DB_DATABASE_START_AUTONOMOUS_DATABASE_RESPONSE_T',
    'DBMS_CLOUD_OCI_DB_DATABASE_RESTART_AUTONOMOUS_DATABASE_RESPONSE_T',
    'DBMS_CLOUD_OCI_DB_DATABASE_GET_MAINTENANCE_RUN_HISTORY_RESPONSE_T',
    'DBMS_CLOUD_OCI_DATABASE_UPDATE_AUTONOMOUS_DATABASE_DETAILS_T',
    'DBMS_CLOUD_OCI_DB_DATABASE_UPDATE_AUTONOMOUS_DATABASE_RESPONSE_T',
    'DBMS_CLOUD_OCI_DB_DATABASE_LIST_KEY_STORES_RESPONSE_T',
    'DBMS_CLOUD_OCI_DATABASE_KEY_STORE_SUMMARY_TBL',
    'DBMS_CLOUD_OCI_DATABASE_KEY_STORE_SUMMARY_T',
    'DBMS_CLOUD_OCI_DB_DATABASE_LIST_DB_HOMES_RESPONSE_T',
    'DBMS_CLOUD_OCI_DATABASE_DB_HOME_SUMMARY_TBL',
    'DBMS_CLOUD_OCI_DATABASE_DB_HOME_SUMMARY_T',
    'DBMS_CLOUD_OCI_DB_DATABASE_SHRINK_AUTONOMOUS_DATABASE_RESPONSE_T',
    'DBMS_CLOUD_OCI_DB_DATABASE_DELETE_KEY_STORE_RESPONSE_T',
    'DBMS_CLOUD_OCI_DB_DATABASE_LIST_APPLICATION_VIPS_RESPONSE_T',
    'DBMS_CLOUD_OCI_DB_DATABASE_LIST_AUTONOMOUS_CONTAINER_DATABASES_RESPONSE_T',
    'DBMS_CLOUD_OCI_DB_DATABASE_LIST_AUTONOMOUS_DATABASE_BACKUPS_RESPONSE_T',
    'DBMS_CLOUD_OCI_DATABASE_VARCHAR2_TBL',
    'DBMS_CLOUD_OCI_DATABASE_CUSTOMER_CONTACT_TBL',
    'DBMS_CLOUD_OCI_DATABASE_RESOURCE_POOL_SUMMARY_T',
    'DBMS_CLOUD_OCI_DATABASE_SCHEDULED_OPERATION_DETAILS_TBL',
    'DBMS_CLOUD_OCI_DATABASE_DATABASE_TOOL_TBL',
    'DBMS_CLOUD_OCI_DATABASE_LONG_TERM_BACK_UP_SCHEDULE_DETAILS_T'
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
    o_use_rp := NULL;
    o_credential_name := NULL;
    o_compartment_name := NULL;
    o_compartment_ocid := NULL;

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
  -- Helper: generic MERGE for a single config key/value (schema-qualified)
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

    EXECUTE IMMEDIATE l_sql USING p_key, p_val, p_agent;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Warning: failed to persist ' || p_key || ' config: ' || SQLERRM);
  END merge_config_key;

  ----------------------------------------------------------------------------
  -- Apply config and persist in SELECTAI_AGENT_CONFIG
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
    l_effective_use_rp := CASE WHEN p_use_rp IS NULL THEN TRUE ELSE p_use_rp END;

    IF p_credential_name IS NOT NULL THEN
      merge_config_key(p_schema, 'CREDENTIAL_NAME', p_credential_name, c_adb_agent);
    END IF;
    IF p_compartment_name IS NOT NULL THEN
      merge_config_key(p_schema, 'COMPARTMENT_NAME', p_compartment_name, c_adb_agent);
    END IF;
    IF p_compartment_ocid IS NOT NULL THEN
      merge_config_key(p_schema, 'COMPARTMENT_OCID', p_compartment_ocid, c_adb_agent);
    END IF;

    l_enable_rp_str := CASE WHEN l_effective_use_rp THEN 'YES' ELSE 'NO' END;
    merge_config_key(p_schema, 'ENABLE_RESOURCE_PRINCIPAL', l_enable_rp_str, c_adb_agent);

    IF l_effective_use_rp THEN
      BEGIN
        DBMS_CLOUD_ADMIN.ENABLE_RESOURCE_PRINCIPAL(USERNAME => p_schema);
        DBMS_OUTPUT.PUT_LINE('Resource principal enabled for ' || p_schema);
      EXCEPTION
        WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('Failed to enable resource principal for ' || p_schema || ' - ' || SQLERRM);
      END;
    ELSE
      DBMS_OUTPUT.PUT_LINE(
        'Resource principal NOT enabled per config. Using credential: '
        || NVL(p_credential_name, '<not provided>')
      );
    END IF;
  END apply_config;

BEGIN
  l_schema_name := DBMS_ASSERT.SIMPLE_SQL_NAME(p_install_schema_name);

  execute_grants(l_schema_name, l_priv_list);

  get_config(
    p_config_json       => p_config_json,
    o_use_rp            => l_use_rp,
    o_credential_name   => l_credential_name,
    o_compartment_name  => l_compartment_name,
    o_compartment_ocid  => l_compartment_ocid
  );

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

  apply_config(
    p_schema              => l_schema_name,
    p_use_rp              => l_use_rp,
    p_credential_name     => l_credential_name,
    p_compartment_name    => l_compartment_name,
    p_compartment_ocid    => l_compartment_ocid
  );

  DBMS_OUTPUT.PUT_LINE('initialize_autonomous_database_agent completed for schema ' || l_schema_name);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Fatal error in initialize_autonomous_database_agent: ' || SQLERRM);
    RAISE;
END initialize_autonomous_database_agent;
/

-------------------------------------------------------------------------------
-- Run initialization
-------------------------------------------------------------------------------
BEGIN

  initialize_autonomous_database_agent(
    p_install_schema_name => :v_schema,
    p_config_json         => :v_config
  );

END;
/

BEGIN
  EXECUTE IMMEDIATE
    'ALTER SESSION SET CURRENT_SCHEMA = ' || :v_schema;
END;
/

------------------------------------------------------------------------
-- Package specification
------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE oci_autonomous_database_agents
AS
  FUNCTION list_subscribed_regions RETURN CLOB;
  FUNCTION list_compartments RETURN CLOB;
  FUNCTION get_compartment_ocid_by_name(p_compartment_name IN VARCHAR2) RETURN CLOB;

  FUNCTION provision_adbs_tool(
    compartment_name        IN VARCHAR2,
    db_name                 IN VARCHAR2,
    display_name            IN VARCHAR2 DEFAULT NULL,
    workload_type           IN VARCHAR2,
    ecpu_count              IN NUMBER,
    storage_gb              IN NUMBER,
    region                  IN VARCHAR2,
    data_guard              IN VARCHAR2,
    credential_name         IN VARCHAR2 DEFAULT NULL,
    oci_vault_secret_id     IN VARCHAR2,
    is_auto_scaling_enabled IN NUMBER
  ) RETURN CLOB;

  FUNCTION list_autonomous_databases(
    region            IN VARCHAR2,
    compartment_name  IN VARCHAR2,
    credential_name   IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION drop_autonomous_database(
    db_ocid         IN VARCHAR2,
    region          IN VARCHAR2,
    credential_name IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION manage_autonomous_db_power(
    db_ocid         IN VARCHAR2,
    region          IN VARCHAR2,
    action          IN VARCHAR2,
    credential_name IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION update_autonomous_db_resources(
    db_ocid         IN VARCHAR2,
    region          IN VARCHAR2,
    cpu_count       IN NUMBER DEFAULT NULL,
    storage_tbs     IN NUMBER DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION get_autonomous_database_details(
    db_ocid           IN VARCHAR2,
    region            IN VARCHAR2,
    credential_name   IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION stop_autonomous_database(
    db_ocid           IN VARCHAR2,
    region            IN VARCHAR2,
    credential_name   IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION start_autonomous_database(
    db_ocid           IN VARCHAR2,
    region            IN VARCHAR2,
    credential_name   IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION restart_autonomous_database(
    db_ocid           IN VARCHAR2,
    region            IN VARCHAR2,
    credential_name   IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION get_maintenance_run_history_json(
    maintenance_run_history_id IN VARCHAR2,
    region                    IN VARCHAR2 DEFAULT NULL,
    credential_name           IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION update_autonomous_database(
    autonomous_database_id                IN VARCHAR2,
    region                                IN VARCHAR2                                   DEFAULT NULL,
    credential_name                       IN VARCHAR2                                   DEFAULT NULL,
    backup_retention_period_in_days       IN NUMBER                                     DEFAULT NULL,
    compute_model                         IN VARCHAR2                                   DEFAULT NULL,
    in_memory_percentage                  IN NUMBER                                     DEFAULT NULL,
    local_adg_auto_failover_max_data_loss_limit IN NUMBER                               DEFAULT NULL,
    cpu_core_count                        IN NUMBER                                     DEFAULT NULL,
    long_term_backup_schedule             IN dbms_cloud_oci_database_long_term_back_up_schedule_details_t DEFAULT NULL,
    compute_count                         IN NUMBER                                     DEFAULT NULL,
    ocpu_count                            IN NUMBER                                     DEFAULT NULL,
    data_storage_size_in_t_bs             IN NUMBER                                     DEFAULT NULL,
    data_storage_size_in_g_bs             IN NUMBER                                     DEFAULT NULL,
    display_name                          IN VARCHAR2                                   DEFAULT NULL,
    is_free_tier                          IN NUMBER                                     DEFAULT NULL,
    admin_password                        IN VARCHAR2                                   DEFAULT NULL,
    db_name                               IN VARCHAR2                                   DEFAULT NULL,
    freeform_tags                         IN json_element_t                             DEFAULT NULL,
    defined_tags                          IN json_element_t                             DEFAULT NULL,
    db_workload                           IN VARCHAR2                                   DEFAULT NULL,
    license_model                         IN VARCHAR2                                   DEFAULT NULL,
    is_access_control_enabled             IN NUMBER                                     DEFAULT NULL,
    whitelisted_ips                       IN dbms_cloud_oci_database_varchar2_tbl       DEFAULT NULL,
    are_primary_whitelisted_ips_used      IN NUMBER                                     DEFAULT NULL,
    standby_whitelisted_ips               IN dbms_cloud_oci_database_varchar2_tbl       DEFAULT NULL,
    is_auto_scaling_enabled               IN NUMBER                                     DEFAULT NULL,
    is_refreshable_clone                  IN NUMBER                                     DEFAULT NULL,
    refreshable_mode                      IN VARCHAR2                                   DEFAULT NULL,
    is_local_data_guard_enabled           IN NUMBER                                     DEFAULT NULL,
    is_data_guard_enabled                 IN NUMBER                                     DEFAULT NULL,
    peer_db_id                            IN VARCHAR2                                   DEFAULT NULL,
    db_version                            IN VARCHAR2                                   DEFAULT NULL,
    open_mode                             IN VARCHAR2                                   DEFAULT NULL,
    permission_level                      IN VARCHAR2                                   DEFAULT NULL,
    subnet_id                             IN VARCHAR2                                   DEFAULT NULL,
    private_endpoint_label                IN VARCHAR2                                   DEFAULT NULL,
    private_endpoint_ip                   IN VARCHAR2                                   DEFAULT NULL,
    nsg_ids                               IN dbms_cloud_oci_database_varchar2_tbl       DEFAULT NULL,
    customer_contacts                     IN dbms_cloud_oci_database_customer_contact_tbl DEFAULT NULL,
    is_mtls_connection_required           IN NUMBER                                     DEFAULT NULL,
    resource_pool_leader_id               IN VARCHAR2                                   DEFAULT NULL,
    resource_pool_summary                 IN dbms_cloud_oci_database_resource_pool_summary_t DEFAULT NULL,
    scheduled_operations                  IN dbms_cloud_oci_database_scheduled_operation_details_tbl DEFAULT NULL,
    is_auto_scaling_for_storage_enabled   IN NUMBER                                     DEFAULT NULL,
    max_cpu_core_count                    IN NUMBER                                     DEFAULT NULL,
    database_edition                      IN VARCHAR2                                   DEFAULT NULL,
    db_tools_details                      IN dbms_cloud_oci_database_database_tool_tbl  DEFAULT NULL,
    secret_id                             IN VARCHAR2                                   DEFAULT NULL,
    secret_version_number                 IN NUMBER                                     DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION list_key_stores(
    compartment_id   IN VARCHAR2,
    region           IN VARCHAR2 DEFAULT NULL,
    credential_name  IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION list_db_homes(
    compartment_id   IN VARCHAR2,
    region           IN VARCHAR2 DEFAULT NULL,
    credential_name  IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION shrink_autonomous_database(
    db_ocid          IN VARCHAR2,
    region           IN VARCHAR2 DEFAULT NULL,
    credential_name  IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION delete_key_store(
    key_store_id     IN VARCHAR2,
    region           IN VARCHAR2 DEFAULT NULL,
    credential_name  IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION list_autonomous_container_database(
    compartment_id   IN VARCHAR2,
    region           IN VARCHAR2 DEFAULT NULL,
    credential_name  IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION list_autonomous_database_backups(
    compartment_id          IN VARCHAR2,
    autonomous_database_id  IN VARCHAR2,
    region                  IN VARCHAR2 DEFAULT NULL,
    credential_name         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;
END oci_autonomous_database_agents;
/

------------------------------------------------------------------------
-- Package body
------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY oci_autonomous_database_agents
AS
  c_adb_agent CONSTANT VARCHAR2(64) := 'OCI_AUTONOMOUS_DATABASE';

  FUNCTION get_agent_config(
    schema_name   IN VARCHAR2,
    table_name    IN VARCHAR2,
    agent_name    IN VARCHAR2
  ) RETURN CLOB
  IS
    l_sql          VARCHAR2(4000);
    l_cursor       SYS_REFCURSOR;
    l_config_json  JSON_OBJECT_T := JSON_OBJECT_T();
    l_key          VARCHAR2(200);
    l_value        CLOB;
    l_result_json  JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    l_sql := 'SELECT "KEY", "VALUE" FROM ' || schema_name || '.' || table_name ||
             ' WHERE "AGENT" = :agent';
    OPEN l_cursor FOR l_sql USING agent_name;
    LOOP
      FETCH l_cursor INTO l_key, l_value;
      EXIT WHEN l_cursor%NOTFOUND;
      l_config_json.put(l_key, l_value);
    END LOOP;
    CLOSE l_cursor;

    l_result_json.put('status', 'success');
    l_result_json.put('config_params', l_config_json);
    RETURN l_result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      BEGIN
        IF l_cursor%ISOPEN THEN
          CLOSE l_cursor;
        END IF;
      EXCEPTION
        WHEN OTHERS THEN NULL;
      END;
      l_result_json := JSON_OBJECT_T();
      l_result_json.put('status', 'error');
      l_result_json.put('message', 'Error: ' || SQLERRM);
      RETURN l_result_json.to_clob();
  END get_agent_config;

  PROCEDURE resolve_credential(
    p_credential_name IN  VARCHAR2,
    o_credential_name OUT VARCHAR2
  ) IS
    l_current_user VARCHAR2(128) := SYS_CONTEXT('USERENV', 'CURRENT_USER');
    l_cfg_json      CLOB;
    l_cfg           JSON_OBJECT_T;
    l_params        JSON_OBJECT_T;
  BEGIN
    o_credential_name := p_credential_name;
    IF o_credential_name IS NOT NULL THEN
      RETURN;
    END IF;

    l_cfg_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', c_adb_agent);
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status') = 'success' THEN
      l_params := l_cfg.get_object('config_params');
      IF l_params.has('CREDENTIAL_NAME') THEN
        o_credential_name := l_params.get_string('CREDENTIAL_NAME');
      END IF;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      o_credential_name := p_credential_name;
  END resolve_credential;

  FUNCTION list_subscribed_regions RETURN CLOB
  IS
    l_result_json     JSON_OBJECT_T := JSON_OBJECT_T();
    l_regions         JSON_ARRAY_T  := JSON_ARRAY_T();
    l_credential_name VARCHAR2(256);
    tenancy_id        VARCHAR2(128);
    l_region          VARCHAR2(128);
    l_endpoint        VARCHAR2(1000);
    l_response        CLOB;
    l_data            JSON_ARRAY_T;
    l_obj             JSON_OBJECT_T;
  BEGIN
    resolve_credential(NULL, l_credential_name);
    IF l_credential_name IS NULL THEN
      l_result_json.put('status','error');
      l_result_json.put('message','Missing credential_name (set in SELECTAI_AGENT_CONFIG for OCI_AUTONOMOUS_DATABASE).');
      RETURN l_result_json.to_clob();
    END IF;

    SELECT
      lower(JSON_VALUE(cloud_identity, '$.TENANT_OCID')) AS tenant_ocid,
      JSON_VALUE(cloud_identity, '$.REGION') AS region
    INTO tenancy_id, l_region
    FROM v$pdbs;

   -- l_endpoint := 'https://identity.' || l_region || '.oci.oraclecloud.com/20160918/regionSubscriptions?tenancyId=' || tenancy_id;

    l_endpoint := 'https://identity.'|| l_region|| '.oraclecloud.com/20160918/'|| 'tenancies/'|| tenancy_id|| '/regionSubscriptions';

    l_response := DBMS_CLOUD.get_response_text(
      DBMS_CLOUD.send_request(
        credential_name => l_credential_name,
        uri             => l_endpoint,
        method          => DBMS_CLOUD.METHOD_GET
      )
    );

    l_data := JSON_ARRAY_T.parse(l_response);
    FOR i IN 0 .. l_data.get_size() - 1 LOOP
      l_obj := JSON_OBJECT_T(l_data.get(i));
      l_regions.append(
        JSON_OBJECT(
          'region_name' VALUE l_obj.get_string('regionName'),
          'region_key'  VALUE l_obj.get_string('regionKey'),
          'status'      VALUE l_obj.get_string('status'),
          'is_home_region' VALUE CASE WHEN l_obj.get_boolean('isHomeRegion') THEN 'Yes' ELSE 'No' END
        )
      );
    END LOOP;

    l_result_json.put('status','success');
    l_result_json.put('message','Successfully retrieved subscribed regions');
    l_result_json.put('total_regions', l_regions.get_size());
    l_result_json.put('regions', l_regions);
    RETURN l_result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result_json := JSON_OBJECT_T();
      l_result_json.put('status','error');
      l_result_json.put('message','Failed to retrieve subscribed regions: ' || SQLERRM);
      l_result_json.put('endpoint_used', l_endpoint);
      RETURN l_result_json.to_clob();
  END list_subscribed_regions;

  FUNCTION list_compartments RETURN CLOB
  IS
    l_result_json     JSON_OBJECT_T := JSON_OBJECT_T();
    l_compartments    JSON_ARRAY_T  := JSON_ARRAY_T();
    l_credential_name VARCHAR2(256);
    tenancy_id        VARCHAR2(128);
    l_region          VARCHAR2(128);
    l_endpoint        VARCHAR2(1000);
    l_response        CLOB;
    l_data            JSON_ARRAY_T;
    l_obj             JSON_OBJECT_T;
  BEGIN
    resolve_credential(NULL, l_credential_name);
    IF l_credential_name IS NULL THEN
      l_result_json.put('status','error');
      l_result_json.put('message','Missing credential_name (set in SELECTAI_AGENT_CONFIG for OCI_AUTONOMOUS_DATABASE).');
      RETURN l_result_json.to_clob();
    END IF;

    SELECT
      JSON_VALUE(cloud_identity, '$.TENANT_OCID') AS tenant_ocid,
      JSON_VALUE(cloud_identity, '$.REGION') AS region
    INTO tenancy_id, l_region
    FROM v$pdbs;

    l_endpoint :=
      'https://identity.' || l_region || '.oci.oraclecloud.com/20160918/compartments?compartmentId=' || tenancy_id;

    l_response := DBMS_CLOUD.get_response_text(
      DBMS_CLOUD.send_request(
        credential_name => l_credential_name,
        uri             => l_endpoint,
        method          => DBMS_CLOUD.METHOD_GET
      )
    );

    l_data := JSON_ARRAY_T.parse(l_response);
    FOR i IN 0 .. l_data.get_size() - 1 LOOP
      l_obj := JSON_OBJECT_T(l_data.get(i));
      l_compartments.append(
        JSON_OBJECT(
          'name' VALUE l_obj.get_string('name'),
          'id' VALUE l_obj.get_string('id'),
          'description' VALUE l_obj.get_string('description'),
          'lifecycle_state' VALUE l_obj.get_string('lifecycleState'),
          'time_created' VALUE l_obj.get_string('timeCreated')
        )
      );
    END LOOP;

    l_result_json.put('status','success');
    l_result_json.put('message','Successfully retrieved compartments');
    l_result_json.put('total_compartments', l_compartments.get_size());
    l_result_json.put('compartments', l_compartments);
    RETURN l_result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result_json := JSON_OBJECT_T();
      l_result_json.put('status','error');
      l_result_json.put('message','Failed to retrieve compartments: ' || SQLERRM);
      l_result_json.put('endpoint_used', l_endpoint);
      RETURN l_result_json.to_clob();
  END list_compartments;

  FUNCTION get_compartment_ocid_by_name(p_compartment_name IN VARCHAR2) RETURN CLOB
  IS
    l_comp_json_clob CLOB;
    l_root           JSON_OBJECT_T;
    l_arr            JSON_ARRAY_T;
    l_obj            JSON_OBJECT_T;
    l_result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    l_ocid           VARCHAR2(4000);
  BEGIN
    l_comp_json_clob := list_compartments();
    l_root := JSON_OBJECT_T.parse(l_comp_json_clob);
    IF l_root.get_string('status') <> 'success' THEN
      RETURN l_comp_json_clob;
    END IF;

    l_arr := l_root.get_array('compartments');
    FOR i IN 0 .. l_arr.get_size() - 1 LOOP
      l_obj := JSON_OBJECT_T(l_arr.get(i));
      IF l_obj.get_string('name') = p_compartment_name THEN
        l_ocid := l_obj.get_string('id');
        EXIT;
      END IF;
    END LOOP;

    IF l_ocid IS NOT NULL THEN
      l_result_json.put('status','success');
      l_result_json.put('compartment_name', p_compartment_name);
      l_result_json.put('compartment_ocid', l_ocid);
    ELSE
      l_result_json.put('status','error');
      l_result_json.put('message','Compartment "' || p_compartment_name || '" not found');
    END IF;
    RETURN l_result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result_json := JSON_OBJECT_T();
      l_result_json.put('status','error');
      l_result_json.put('message','Unexpected error: ' || SQLERRM);
      RETURN l_result_json.to_clob();
  END get_compartment_ocid_by_name;

  FUNCTION provision_adbs_tool(
    compartment_name        IN VARCHAR2,
    db_name                 IN VARCHAR2,
    display_name            IN VARCHAR2 DEFAULT NULL,
    workload_type           IN VARCHAR2,
    ecpu_count              IN NUMBER,
    storage_gb              IN NUMBER,
    region                  IN VARCHAR2,
    data_guard              IN VARCHAR2,
    credential_name         IN VARCHAR2 DEFAULT NULL,
    oci_vault_secret_id     IN VARCHAR2,
    is_auto_scaling_enabled IN NUMBER
  ) RETURN CLOB
  IS
    in_details     DBMS_CLOUD_OCI_DATABASE_CREATE_AUTONOMOUS_DATABASE_BASE_T :=
                   DBMS_CLOUD_OCI_DATABASE_CREATE_AUTONOMOUS_DATABASE_BASE_T();
    resp           DBMS_CLOUD_OCI_DB_DATABASE_CREATE_AUTONOMOUS_DATABASE_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    l_workload     VARCHAR2(20);
    l_compartment_id VARCHAR2(256);
    l_credential   VARCHAR2(256);
    l_comp_json    CLOB;
    l_comp_obj     JSON_OBJECT_T;
  BEGIN
    resolve_credential(credential_name, l_credential);

    l_comp_json := get_compartment_ocid_by_name(p_compartment_name => compartment_name);
    l_comp_obj := JSON_OBJECT_T.parse(l_comp_json);
    IF l_comp_obj.has('compartment_ocid') THEN
      l_compartment_id := l_comp_obj.get_string('compartment_ocid');
    END IF;

    IF l_compartment_id IS NULL THEN
      result_json.put('status','error');
      result_json.put('message','Failed to resolve compartment OCID for compartment_name=' || compartment_name);
      RETURN result_json.to_clob();
    END IF;

    CASE UPPER(workload_type)
      WHEN 'OLTP' THEN l_workload := 'OLTP';
      WHEN 'ADW'  THEN l_workload := 'DW';
      WHEN 'JSON' THEN l_workload := 'JSON';
      WHEN 'APEX' THEN l_workload := 'APEX';
      ELSE l_workload := 'OLTP';
    END CASE;

    in_details.compartment_id := l_compartment_id;
    in_details.db_name := UPPER(db_name);
    in_details.compute_model := 'ECPU';
    in_details.compute_count := ecpu_count;
    in_details.secret_id := oci_vault_secret_id;
    in_details.db_workload := l_workload;
    in_details.data_storage_size_in_g_bs := storage_gb;
    in_details.display_name := display_name;
    in_details.is_auto_scaling_enabled := is_auto_scaling_enabled;

    IF data_guard IS NOT NULL AND UPPER(data_guard) = 'ENABLED' THEN
      in_details.is_data_guard_enabled := 1;
      result_json.put('data_guard_enabled', 'ENABLED');
    ELSE
      in_details.is_data_guard_enabled := 0;
      result_json.put('data_guard_enabled', 'DISABLED');
    END IF;

    resp := DBMS_CLOUD_OCI_DB_DATABASE.CREATE_AUTONOMOUS_DATABASE(
      create_autonomous_database_details => in_details,
      credential_name => l_credential,
      region => region
    );

    result_json.put('status', 'success');
    result_json.put('message', 'Autonomous Database provisioning initiated successfully');
    result_json.put('status_code', resp.status_code);
    result_json.put('database_ocid', resp.response_body.id);
    result_json.put('database_name', db_name);
    result_json.put('workload_type', l_workload);
    result_json.put('ecpu_count', ecpu_count);
    result_json.put('storage_gb', storage_gb);
    result_json.put('region', region);
    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status', 'error');
      result_json.put('message', 'Failed to provision Autonomous Database: ' || SQLERRM);
      RETURN result_json.to_clob();
  END provision_adbs_tool;

  FUNCTION list_autonomous_databases(
    region            IN VARCHAR2,
    compartment_name  IN VARCHAR2,
    credential_name   IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_response     CLOB;
    l_endpoint     VARCHAR2(1000);
    l_result_json  JSON_OBJECT_T := JSON_OBJECT_T();
    l_db_array     JSON_ARRAY_T := JSON_ARRAY_T();
    l_dbs_data     JSON_ARRAY_T;
    l_db_obj       JSON_OBJECT_T;
    l_db_ocid      VARCHAR2(256);
    l_credential   VARCHAR2(256);
    l_compartment_id VARCHAR2(256);
    l_comp_json    CLOB;
    l_comp_obj     JSON_OBJECT_T;
  BEGIN
    resolve_credential(credential_name, l_credential);

    l_comp_json := get_compartment_ocid_by_name(p_compartment_name => compartment_name);
    l_comp_obj := JSON_OBJECT_T.parse(l_comp_json);
    IF l_comp_obj.has('compartment_ocid') THEN
      l_compartment_id := l_comp_obj.get_string('compartment_ocid');
    END IF;
    IF l_compartment_id IS NULL THEN
      l_result_json.put('status','error');
      l_result_json.put('message','Failed to resolve compartment OCID for compartment_name=' || compartment_name);
      RETURN l_result_json.to_clob();
    END IF;

    l_endpoint := 'https://database.' || region ||
                  '.oraclecloud.com/20160918/autonomousDatabases?compartmentId=' || l_compartment_id;

    l_response := DBMS_CLOUD.get_response_text(
      DBMS_CLOUD.send_request(
        credential_name => l_credential,
        uri             => l_endpoint,
        method          => DBMS_CLOUD.METHOD_GET
      )
    );

    l_dbs_data := JSON_ARRAY_T.parse(l_response);
    FOR i IN 0 .. l_dbs_data.get_size() - 1 LOOP
      l_db_obj := JSON_OBJECT_T(l_dbs_data.get(i));
      l_db_ocid := l_db_obj.get_string('id');
      l_db_array.append(
        JSON_OBJECT(
          'display_name' VALUE l_db_obj.get_string('displayName'),
          'db_ocid' VALUE l_db_ocid,
          'db_workload' VALUE l_db_obj.get_string('dbWorkload'),
          'lifecycle' VALUE l_db_obj.get_string('lifecycleState'),
          'computeModel' VALUE l_db_obj.get_string('computeModel'),
          'computeCount' VALUE l_db_obj.get_string('computeCount'),
          'dataStorageSizeInGBs' VALUE l_db_obj.get_string('dataStorageSizeInGBs'),
          'dataStorageSizeInTBs' VALUE l_db_obj.get_string('dataStorageSizeInTBs')
        )
      );
    END LOOP;

    l_result_json.put('status','success');
    l_result_json.put('message','Successfully retrieved Autonomous Databases');
    l_result_json.put('total_databases', l_db_array.get_size());
    l_result_json.put('databases', l_db_array);
    RETURN l_result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result_json := JSON_OBJECT_T();
      l_result_json.put('status','error');
      l_result_json.put('message','Failed to list Autonomous Databases: ' || SQLERRM);
      RETURN l_result_json.to_clob();
  END list_autonomous_databases;

  FUNCTION drop_autonomous_database(
    db_ocid         IN VARCHAR2,
    region          IN VARCHAR2,
    credential_name IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    resp        DBMS_CLOUD_OCI_DB_DATABASE_DELETE_AUTONOMOUS_DATABASE_RESPONSE_T;
    result_json JSON_OBJECT_T := JSON_OBJECT_T();
    l_credential VARCHAR2(256);
  BEGIN
    resolve_credential(credential_name, l_credential);
    resp := DBMS_CLOUD_OCI_DB_DATABASE.DELETE_AUTONOMOUS_DATABASE(
      autonomous_database_id => db_ocid,
      region                 => region,
      credential_name        => l_credential
    );

    result_json.put('status', 'success');
    result_json.put('message', 'Autonomous Database deletion initiated successfully');
    result_json.put('status_code', resp.status_code);
    result_json.put('database_ocid', db_ocid);
    result_json.put('region', region);
    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status', 'error');
      result_json.put('message', 'Failed to delete Autonomous Database: ' || SQLERRM);
      result_json.put('database_ocid', db_ocid);
      RETURN result_json.to_clob();
  END drop_autonomous_database;

  FUNCTION manage_autonomous_db_power(
    db_ocid         IN VARCHAR2,
    region          IN VARCHAR2,
    action          IN VARCHAR2,
    credential_name IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_endpoint  VARCHAR2(1000);
    l_response  CLOB;
    result_json JSON_OBJECT_T := JSON_OBJECT_T();
    l_credential VARCHAR2(256);
  BEGIN
    resolve_credential(credential_name, l_credential);
    IF UPPER(action) = 'START' THEN
      l_endpoint := 'https://database.' || region || '.oraclecloud.com/20160918/autonomousDatabases/' || db_ocid || '/actions/start';
    ELSIF UPPER(action) = 'STOP' THEN
      l_endpoint := 'https://database.' || region || '.oraclecloud.com/20160918/autonomousDatabases/' || db_ocid || '/actions/stop';
    ELSE
      result_json.put('status', 'error');
      result_json.put('message', 'Invalid action. Use START or STOP.');
      RETURN result_json.to_clob();
    END IF;

    l_response := DBMS_CLOUD.get_response_text(
      DBMS_CLOUD.send_request(
        credential_name => l_credential,
        uri             => l_endpoint,
        method          => DBMS_CLOUD.METHOD_POST,
        headers         => JSON_OBJECT('Content-Type' VALUE 'application/json')
      )
    );

    result_json.put('status', 'success');
    result_json.put('message', 'Database ' || LOWER(action) || ' request sent successfully');
    result_json.put('database_ocid', db_ocid);
    result_json.put('region', region);
    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status', 'error');
      result_json.put('message', 'Failed to ' || LOWER(action) || ' database: ' || SQLERRM);
      RETURN result_json.to_clob();
  END manage_autonomous_db_power;

  FUNCTION update_autonomous_db_resources(
    db_ocid         IN VARCHAR2,
    region          IN VARCHAR2,
    cpu_count       IN NUMBER DEFAULT NULL,
    storage_tbs     IN NUMBER DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_endpoint  VARCHAR2(1000);
    l_response  CLOB;
    l_body      VARCHAR2(4000);
    result_json JSON_OBJECT_T := JSON_OBJECT_T();
    l_credential VARCHAR2(256);
  BEGIN
    resolve_credential(credential_name, l_credential);
    l_endpoint := 'https://database.' || region || '.oraclecloud.com/20160918/autonomousDatabases/' || db_ocid;

    l_body := '{';
    IF cpu_count IS NOT NULL THEN
      l_body := l_body || '"cpuCoreCount": ' || TO_CHAR(cpu_count);
    END IF;
    IF storage_tbs IS NOT NULL THEN
      IF cpu_count IS NOT NULL THEN
        l_body := l_body || ', ';
      END IF;
      l_body := l_body || '"dataStorageSizeInTBs": ' || TO_CHAR(storage_tbs);
    END IF;
    l_body := l_body || '}';

    l_response := DBMS_CLOUD.get_response_text(
      DBMS_CLOUD.send_request(
        credential_name => l_credential,
        uri             => l_endpoint,
        method          => DBMS_CLOUD.METHOD_PUT,
        headers         => JSON_OBJECT('Content-Type' VALUE 'application/json'),
        body            => UTL_RAW.cast_to_raw(l_body)
      )
    );

    result_json.put('status', 'success');
    result_json.put('message', 'Database resource update request sent successfully');
    result_json.put('database_ocid', db_ocid);
    result_json.put('region', region);
    result_json.put('cpu_count', NVL(TO_CHAR(cpu_count), 'unchanged'));
    result_json.put('storage_tbs', NVL(TO_CHAR(storage_tbs), 'unchanged'));
    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status', 'error');
      result_json.put('message', 'Failed to update database resources: ' || SQLERRM);
      RETURN result_json.to_clob();
  END update_autonomous_db_resources;

  FUNCTION get_autonomous_database_details(
    db_ocid           IN VARCHAR2,
    region            IN VARCHAR2,
    credential_name   IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_resp        DBMS_CLOUD_OCI_DB_DATABASE_GET_AUTONOMOUS_DATABASE_RESPONSE_T;
    l_json        JSON_OBJECT_T := JSON_OBJECT_T();
    l_credential  VARCHAR2(256);
  BEGIN
    resolve_credential(credential_name, l_credential);
    l_resp := DBMS_CLOUD_OCI_DB_DATABASE.GET_AUTONOMOUS_DATABASE(
      autonomous_database_id => db_ocid,
      opc_request_id         => NULL,
      region                 => region,
      endpoint               => NULL,
      credential_name        => l_credential
    );

    l_json.put('status', 'success');
    l_json.put('status_code', l_resp.status_code);
    l_json.put('headers', l_resp.headers);
    IF l_resp.response_body IS NOT NULL THEN
      l_json.put('database_id', l_resp.response_body.id);
      l_json.put('display_name', l_resp.response_body.display_name);
      l_json.put('lifecycle_state', l_resp.response_body.lifecycle_state);
      l_json.put('db_workload', l_resp.response_body.db_workload);
    END IF;
    RETURN l_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_json := JSON_OBJECT_T();
      l_json.put('status','error');
      l_json.put('message', SQLERRM);
      RETURN l_json.to_clob();
  END get_autonomous_database_details;

  FUNCTION stop_autonomous_database(
    db_ocid           IN VARCHAR2,
    region            IN VARCHAR2,
    credential_name   IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_response    DBMS_CLOUD_OCI_DB_DATABASE_STOP_AUTONOMOUS_DATABASE_RESPONSE_T;
    l_result_json JSON_OBJECT_T := JSON_OBJECT_T();
    l_credential  VARCHAR2(256);
  BEGIN
    resolve_credential(credential_name, l_credential);
    l_response := DBMS_CLOUD_OCI_DB_DATABASE.STOP_AUTONOMOUS_DATABASE(
      autonomous_database_id => db_ocid,
      if_match               => NULL,
      region                 => region,
      endpoint               => NULL,
      credential_name        => l_credential
    );

    l_result_json.put('status', 'success');
    l_result_json.put('message', 'Stop initiated');
    l_result_json.put('status_code', l_response.status_code);
    l_result_json.put('headers', l_response.headers);
    RETURN l_result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result_json := JSON_OBJECT_T();
      l_result_json.put('status','error');
      l_result_json.put('message', SQLERRM);
      RETURN l_result_json.to_clob();
  END stop_autonomous_database;

  FUNCTION start_autonomous_database(
    db_ocid           IN VARCHAR2,
    region            IN VARCHAR2,
    credential_name   IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_response    DBMS_CLOUD_OCI_DB_DATABASE_START_AUTONOMOUS_DATABASE_RESPONSE_T;
    l_result_json JSON_OBJECT_T := JSON_OBJECT_T();
    l_credential  VARCHAR2(256);
  BEGIN
    resolve_credential(credential_name, l_credential);
    l_response := DBMS_CLOUD_OCI_DB_DATABASE.START_AUTONOMOUS_DATABASE(
      autonomous_database_id => db_ocid,
      if_match               => NULL,
      region                 => region,
      endpoint               => NULL,
      credential_name        => l_credential
    );

    l_result_json.put('status', 'success');
    l_result_json.put('message', 'Start initiated');
    l_result_json.put('status_code', l_response.status_code);
    l_result_json.put('headers', l_response.headers);
    RETURN l_result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result_json := JSON_OBJECT_T();
      l_result_json.put('status','error');
      l_result_json.put('message', SQLERRM);
      RETURN l_result_json.to_clob();
  END start_autonomous_database;

  FUNCTION restart_autonomous_database(
    db_ocid           IN VARCHAR2,
    region            IN VARCHAR2,
    credential_name   IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_response    DBMS_CLOUD_OCI_DB_DATABASE_RESTART_AUTONOMOUS_DATABASE_RESPONSE_T;
    l_result_json JSON_OBJECT_T := JSON_OBJECT_T();
    l_credential  VARCHAR2(256);
  BEGIN
    resolve_credential(credential_name, l_credential);
    l_response := DBMS_CLOUD_OCI_DB_DATABASE.RESTART_AUTONOMOUS_DATABASE(
      autonomous_database_id => db_ocid,
      if_match               => NULL,
      region                 => region,
      endpoint               => NULL,
      credential_name        => l_credential
    );

    l_result_json.put('status', 'success');
    l_result_json.put('message', 'Restart initiated');
    l_result_json.put('status_code', l_response.status_code);
    l_result_json.put('headers', l_response.headers);
    RETURN l_result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result_json := JSON_OBJECT_T();
      l_result_json.put('status','error');
      l_result_json.put('message', SQLERRM);
      RETURN l_result_json.to_clob();
  END restart_autonomous_database;

  FUNCTION get_maintenance_run_history_json(
    maintenance_run_history_id IN VARCHAR2,
    region                    IN VARCHAR2 DEFAULT NULL,
    credential_name           IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_response    DBMS_CLOUD_OCI_DB_DATABASE_GET_MAINTENANCE_RUN_HISTORY_RESPONSE_T;
    l_result_json JSON_OBJECT_T := JSON_OBJECT_T();
    l_credential  VARCHAR2(256);
  BEGIN
    resolve_credential(credential_name, l_credential);
    l_response := DBMS_CLOUD_OCI_DB_DATABASE.GET_MAINTENANCE_RUN_HISTORY(
      maintenance_run_history_id => maintenance_run_history_id,
      region                     => region,
      endpoint                   => NULL,
      credential_name            => l_credential
    );

    l_result_json.put('status', 'success');
    l_result_json.put('message', 'Maintenance run history retrieved');
    l_result_json.put('status_code', l_response.status_code);
    l_result_json.put('headers', l_response.headers);
    IF l_response.response_body IS NOT NULL THEN
      l_result_json.put('history_id', l_response.response_body.id);
    END IF;
    RETURN l_result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result_json := JSON_OBJECT_T();
      l_result_json.put('status','error');
      l_result_json.put('message', SQLERRM);
      RETURN l_result_json.to_clob();
  END get_maintenance_run_history_json;

  FUNCTION update_autonomous_database(
    autonomous_database_id                IN VARCHAR2,
    region                                IN VARCHAR2                                   DEFAULT NULL,
    credential_name                       IN VARCHAR2                                   DEFAULT NULL,
    backup_retention_period_in_days       IN NUMBER                                     DEFAULT NULL,
    compute_model                         IN VARCHAR2                                   DEFAULT NULL,
    in_memory_percentage                  IN NUMBER                                     DEFAULT NULL,
    local_adg_auto_failover_max_data_loss_limit IN NUMBER                               DEFAULT NULL,
    cpu_core_count                        IN NUMBER                                     DEFAULT NULL,
    long_term_backup_schedule             IN dbms_cloud_oci_database_long_term_back_up_schedule_details_t DEFAULT NULL,
    compute_count                         IN NUMBER                                     DEFAULT NULL,
    ocpu_count                            IN NUMBER                                     DEFAULT NULL,
    data_storage_size_in_t_bs             IN NUMBER                                     DEFAULT NULL,
    data_storage_size_in_g_bs             IN NUMBER                                     DEFAULT NULL,
    display_name                          IN VARCHAR2                                   DEFAULT NULL,
    is_free_tier                          IN NUMBER                                     DEFAULT NULL,
    admin_password                        IN VARCHAR2                                   DEFAULT NULL,
    db_name                               IN VARCHAR2                                   DEFAULT NULL,
    freeform_tags                         IN json_element_t                             DEFAULT NULL,
    defined_tags                          IN json_element_t                             DEFAULT NULL,
    db_workload                           IN VARCHAR2                                   DEFAULT NULL,
    license_model                         IN VARCHAR2                                   DEFAULT NULL,
    is_access_control_enabled             IN NUMBER                                     DEFAULT NULL,
    whitelisted_ips                       IN dbms_cloud_oci_database_varchar2_tbl       DEFAULT NULL,
    are_primary_whitelisted_ips_used      IN NUMBER                                     DEFAULT NULL,
    standby_whitelisted_ips               IN dbms_cloud_oci_database_varchar2_tbl       DEFAULT NULL,
    is_auto_scaling_enabled               IN NUMBER                                     DEFAULT NULL,
    is_refreshable_clone                  IN NUMBER                                     DEFAULT NULL,
    refreshable_mode                      IN VARCHAR2                                   DEFAULT NULL,
    is_local_data_guard_enabled           IN NUMBER                                     DEFAULT NULL,
    is_data_guard_enabled                 IN NUMBER                                     DEFAULT NULL,
    peer_db_id                            IN VARCHAR2                                   DEFAULT NULL,
    db_version                            IN VARCHAR2                                   DEFAULT NULL,
    open_mode                             IN VARCHAR2                                   DEFAULT NULL,
    permission_level                      IN VARCHAR2                                   DEFAULT NULL,
    subnet_id                             IN VARCHAR2                                   DEFAULT NULL,
    private_endpoint_label                IN VARCHAR2                                   DEFAULT NULL,
    private_endpoint_ip                   IN VARCHAR2                                   DEFAULT NULL,
    nsg_ids                               IN dbms_cloud_oci_database_varchar2_tbl       DEFAULT NULL,
    customer_contacts                     IN dbms_cloud_oci_database_customer_contact_tbl DEFAULT NULL,
    is_mtls_connection_required           IN NUMBER                                     DEFAULT NULL,
    resource_pool_leader_id               IN VARCHAR2                                   DEFAULT NULL,
    resource_pool_summary                 IN dbms_cloud_oci_database_resource_pool_summary_t DEFAULT NULL,
    scheduled_operations                  IN dbms_cloud_oci_database_scheduled_operation_details_tbl DEFAULT NULL,
    is_auto_scaling_for_storage_enabled   IN NUMBER                                     DEFAULT NULL,
    max_cpu_core_count                    IN NUMBER                                     DEFAULT NULL,
    database_edition                      IN VARCHAR2                                   DEFAULT NULL,
    db_tools_details                      IN dbms_cloud_oci_database_database_tool_tbl  DEFAULT NULL,
    secret_id                             IN VARCHAR2                                   DEFAULT NULL,
    secret_version_number                 IN NUMBER                                     DEFAULT NULL
  ) RETURN CLOB
  IS
    l_details   DBMS_CLOUD_OCI_DATABASE_UPDATE_AUTONOMOUS_DATABASE_DETAILS_T :=
      DBMS_CLOUD_OCI_DATABASE_UPDATE_AUTONOMOUS_DATABASE_DETAILS_T();
    l_response  DBMS_CLOUD_OCI_DB_DATABASE_UPDATE_AUTONOMOUS_DATABASE_RESPONSE_T;
    l_result    JSON_OBJECT_T := JSON_OBJECT_T();
    l_credential VARCHAR2(256);
  BEGIN
    resolve_credential(credential_name, l_credential);

    IF backup_retention_period_in_days IS NOT NULL THEN l_details.backup_retention_period_in_days := backup_retention_period_in_days; END IF;
    IF compute_model IS NOT NULL THEN l_details.compute_model := compute_model; END IF;
    IF in_memory_percentage IS NOT NULL THEN l_details.in_memory_percentage := in_memory_percentage; END IF;
    IF local_adg_auto_failover_max_data_loss_limit IS NOT NULL THEN l_details.local_adg_auto_failover_max_data_loss_limit := local_adg_auto_failover_max_data_loss_limit; END IF;
    IF cpu_core_count IS NOT NULL THEN l_details.cpu_core_count := cpu_core_count; END IF;
    IF long_term_backup_schedule IS NOT NULL THEN l_details.long_term_backup_schedule := long_term_backup_schedule; END IF;
    IF compute_count IS NOT NULL THEN l_details.compute_count := compute_count; END IF;
    IF ocpu_count IS NOT NULL THEN l_details.ocpu_count := ocpu_count; END IF;
    IF data_storage_size_in_t_bs IS NOT NULL THEN l_details.data_storage_size_in_t_bs := data_storage_size_in_t_bs; END IF;
    IF data_storage_size_in_g_bs IS NOT NULL THEN l_details.data_storage_size_in_g_bs := data_storage_size_in_g_bs; END IF;
    IF display_name IS NOT NULL THEN l_details.display_name := display_name; END IF;
    IF is_free_tier IS NOT NULL THEN l_details.is_free_tier := is_free_tier; END IF;
    IF admin_password IS NOT NULL THEN l_details.admin_password := admin_password; END IF;
    IF db_name IS NOT NULL THEN l_details.db_name := db_name; END IF;
    IF freeform_tags IS NOT NULL THEN l_details.freeform_tags := freeform_tags; END IF;
    IF defined_tags IS NOT NULL THEN l_details.defined_tags := defined_tags; END IF;
    IF db_workload IS NOT NULL THEN l_details.db_workload := db_workload; END IF;
    IF license_model IS NOT NULL THEN l_details.license_model := license_model; END IF;
    IF is_access_control_enabled IS NOT NULL THEN l_details.is_access_control_enabled := is_access_control_enabled; END IF;
    IF whitelisted_ips IS NOT NULL THEN l_details.whitelisted_ips := whitelisted_ips; END IF;
    IF are_primary_whitelisted_ips_used IS NOT NULL THEN l_details.are_primary_whitelisted_ips_used := are_primary_whitelisted_ips_used; END IF;
    IF standby_whitelisted_ips IS NOT NULL THEN l_details.standby_whitelisted_ips := standby_whitelisted_ips; END IF;
    IF is_auto_scaling_enabled IS NOT NULL THEN l_details.is_auto_scaling_enabled := is_auto_scaling_enabled; END IF;
    IF is_refreshable_clone IS NOT NULL THEN l_details.is_refreshable_clone := is_refreshable_clone; END IF;
    IF refreshable_mode IS NOT NULL THEN l_details.refreshable_mode := refreshable_mode; END IF;
    IF is_local_data_guard_enabled IS NOT NULL THEN l_details.is_local_data_guard_enabled := is_local_data_guard_enabled; END IF;
    IF is_data_guard_enabled IS NOT NULL THEN l_details.is_data_guard_enabled := is_data_guard_enabled; END IF;
    IF peer_db_id IS NOT NULL THEN l_details.peer_db_id := peer_db_id; END IF;
    IF db_version IS NOT NULL THEN l_details.db_version := db_version; END IF;
    IF open_mode IS NOT NULL THEN l_details.open_mode := open_mode; END IF;
    IF permission_level IS NOT NULL THEN l_details.permission_level := permission_level; END IF;
    IF subnet_id IS NOT NULL THEN l_details.subnet_id := subnet_id; END IF;
    IF private_endpoint_label IS NOT NULL THEN l_details.private_endpoint_label := private_endpoint_label; END IF;
    IF private_endpoint_ip IS NOT NULL THEN l_details.private_endpoint_ip := private_endpoint_ip; END IF;
    IF nsg_ids IS NOT NULL THEN l_details.nsg_ids := nsg_ids; END IF;
    IF customer_contacts IS NOT NULL THEN l_details.customer_contacts := customer_contacts; END IF;
    IF is_mtls_connection_required IS NOT NULL THEN l_details.is_mtls_connection_required := is_mtls_connection_required; END IF;
    IF resource_pool_leader_id IS NOT NULL THEN l_details.resource_pool_leader_id := resource_pool_leader_id; END IF;
    IF resource_pool_summary IS NOT NULL THEN l_details.resource_pool_summary := resource_pool_summary; END IF;
    IF scheduled_operations IS NOT NULL THEN l_details.scheduled_operations := scheduled_operations; END IF;
    IF is_auto_scaling_for_storage_enabled IS NOT NULL THEN l_details.is_auto_scaling_for_storage_enabled := is_auto_scaling_for_storage_enabled; END IF;
    IF max_cpu_core_count IS NOT NULL THEN l_details.max_cpu_core_count := max_cpu_core_count; END IF;
    IF database_edition IS NOT NULL THEN l_details.database_edition := database_edition; END IF;
    IF db_tools_details IS NOT NULL THEN l_details.db_tools_details := db_tools_details; END IF;
    IF secret_id IS NOT NULL THEN l_details.secret_id := secret_id; END IF;
    IF secret_version_number IS NOT NULL THEN l_details.secret_version_number := secret_version_number; END IF;

    l_response := DBMS_CLOUD_OCI_DB_DATABASE.UPDATE_AUTONOMOUS_DATABASE(
      autonomous_database_id             => autonomous_database_id,
      update_autonomous_database_details => l_details,
      if_match                           => NULL,
      opc_request_id                     => NULL,
      region                             => region,
      endpoint                           => NULL,
      credential_name                    => l_credential
    );

    l_result.put('status','success');
    l_result.put('message','Update initiated');
    l_result.put('status_code', l_response.status_code);
    l_result.put('headers', l_response.headers);
    IF l_response.response_body IS NOT NULL THEN
      l_result.put('database_id', l_response.response_body.id);
      l_result.put('display_name', l_response.response_body.display_name);
      l_result.put('lifecycle_state', l_response.response_body.lifecycle_state);
    END IF;
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status','error');
      l_result.put('message', SQLERRM);
      RETURN l_result.to_clob();
  END update_autonomous_database;

  FUNCTION list_key_stores(
    compartment_id   IN VARCHAR2,
    region           IN VARCHAR2 DEFAULT NULL,
    credential_name  IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_response     DBMS_CLOUD_OCI_DB_DATABASE_LIST_KEY_STORES_RESPONSE_T;
    l_result       JSON_OBJECT_T := JSON_OBJECT_T();
    l_keystores    JSON_ARRAY_T  := JSON_ARRAY_T();
    l_summary_tbl  DBMS_CLOUD_OCI_DATABASE_KEY_STORE_SUMMARY_TBL;
    l_summary      DBMS_CLOUD_OCI_DATABASE_KEY_STORE_SUMMARY_T;
    l_credential   VARCHAR2(256);
  BEGIN
    resolve_credential(credential_name, l_credential);
    l_response := DBMS_CLOUD_OCI_DB_DATABASE.LIST_KEY_STORES(
      compartment_id  => compartment_id,
      limit           => NULL,
      page            => NULL,
      opc_request_id  => NULL,
      region          => region,
      endpoint        => NULL,
      credential_name => l_credential
    );

    l_result.put('status','success');
    l_result.put('status_code', l_response.status_code);
    l_result.put('headers', l_response.headers);
    l_summary_tbl := l_response.response_body;
    FOR i IN 1 .. l_summary_tbl.COUNT LOOP
      l_summary := l_summary_tbl(i);
      l_keystores.append(
        JSON_OBJECT(
          'id' VALUE l_summary.id,
          'display_name' VALUE l_summary.display_name,
          'compartment_id' VALUE l_summary.compartment_id,
          'lifecycle_state' VALUE l_summary.lifecycle_state,
          'time_created' VALUE TO_CHAR(l_summary.time_created, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        )
      );
    END LOOP;
    l_result.put('keystores', l_keystores);
    l_result.put('next_page', l_response.headers.get_string('opc-next-page'));
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status','error');
      l_result.put('message', SQLERRM);
      RETURN l_result.to_clob();
  END list_key_stores;

  FUNCTION list_db_homes(
    compartment_id   IN VARCHAR2,
    region           IN VARCHAR2 DEFAULT NULL,
    credential_name  IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_response   DBMS_CLOUD_OCI_DB_DATABASE_LIST_DB_HOMES_RESPONSE_T;
    l_result     JSON_OBJECT_T := JSON_OBJECT_T();
    l_array      JSON_ARRAY_T  := JSON_ARRAY_T();
    l_summaries  DBMS_CLOUD_OCI_DATABASE_DB_HOME_SUMMARY_TBL;
    l_summary    DBMS_CLOUD_OCI_DATABASE_DB_HOME_SUMMARY_T;
    l_credential VARCHAR2(256);
  BEGIN
    resolve_credential(credential_name, l_credential);
    l_response := DBMS_CLOUD_OCI_DB_DATABASE.LIST_DB_HOMES(
      compartment_id  => compartment_id,
      db_system_id    => NULL,
      vm_cluster_id   => NULL,
      backup_id       => NULL,
      db_version      => NULL,
      limit           => NULL,
      page            => NULL,
      sort_by         => NULL,
      sort_order      => NULL,
      lifecycle_state => NULL,
      display_name    => NULL,
      region          => region,
      endpoint        => NULL,
      credential_name => l_credential
    );

    l_result.put('status','success');
    l_result.put('status_code', l_response.status_code);
    l_result.put('headers', l_response.headers);
    l_summaries := l_response.response_body;
    FOR i IN 1 .. l_summaries.COUNT LOOP
      l_summary := l_summaries(i);
      l_array.append(
        JSON_OBJECT(
          'id' VALUE l_summary.id,
          'display_name' VALUE l_summary.display_name,
          'db_version' VALUE l_summary.db_version,
          'lifecycle_state' VALUE l_summary.lifecycle_state
        )
      );
    END LOOP;
    l_result.put('db_homes', l_array);
    l_result.put('next_page', l_response.headers.get_string('opc-next-page'));
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status','error');
      l_result.put('message', SQLERRM);
      RETURN l_result.to_clob();
  END list_db_homes;

  FUNCTION shrink_autonomous_database(
    db_ocid          IN VARCHAR2,
    region           IN VARCHAR2 DEFAULT NULL,
    credential_name  IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_response   DBMS_CLOUD_OCI_DB_DATABASE_SHRINK_AUTONOMOUS_DATABASE_RESPONSE_T;
    l_result     JSON_OBJECT_T := JSON_OBJECT_T();
    l_credential VARCHAR2(256);
  BEGIN
    resolve_credential(credential_name, l_credential);
    l_response := DBMS_CLOUD_OCI_DB_DATABASE.SHRINK_AUTONOMOUS_DATABASE(
      autonomous_database_id => db_ocid,
      if_match               => NULL,
      region                 => region,
      endpoint               => NULL,
      credential_name        => l_credential
    );

    l_result.put('status','success');
    l_result.put('message','Shrink initiated');
    l_result.put('status_code', l_response.status_code);
    l_result.put('headers', l_response.headers);
    IF l_response.response_body IS NOT NULL THEN
      l_result.put('database_id', l_response.response_body.id);
      l_result.put('display_name', l_response.response_body.display_name);
      l_result.put('lifecycle_state', l_response.response_body.lifecycle_state);
    END IF;
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status','error');
      l_result.put('message', SQLERRM);
      RETURN l_result.to_clob();
  END shrink_autonomous_database;

  FUNCTION delete_key_store(
    key_store_id     IN VARCHAR2,
    region           IN VARCHAR2 DEFAULT NULL,
    credential_name  IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_response   DBMS_CLOUD_OCI_DB_DATABASE_DELETE_KEY_STORE_RESPONSE_T;
    l_result     JSON_OBJECT_T := JSON_OBJECT_T();
    l_credential VARCHAR2(256);
  BEGIN
    resolve_credential(credential_name, l_credential);
    l_response := DBMS_CLOUD_OCI_DB_DATABASE.DELETE_KEY_STORE(
      key_store_id    => key_store_id,
      if_match        => NULL,
      opc_request_id  => NULL,
      region          => region,
      endpoint        => NULL,
      credential_name => l_credential
    );

    l_result.put('status','success');
    l_result.put('message','Key store deletion initiated');
    l_result.put('status_code', l_response.status_code);
    l_result.put('headers', l_response.headers);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status','error');
      l_result.put('message', SQLERRM);
      RETURN l_result.to_clob();
  END delete_key_store;

  FUNCTION list_autonomous_container_database(
    compartment_id   IN VARCHAR2,
    region           IN VARCHAR2 DEFAULT NULL,
    credential_name  IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_response   DBMS_CLOUD_OCI_DB_DATABASE_LIST_AUTONOMOUS_CONTAINER_DATABASES_RESPONSE_T;
    l_result     JSON_OBJECT_T := JSON_OBJECT_T();
    l_array      JSON_ARRAY_T := JSON_ARRAY_T();
    l_item       JSON_OBJECT_T;
    l_credential VARCHAR2(256);
  BEGIN
    resolve_credential(credential_name, l_credential);
    l_response := DBMS_CLOUD_OCI_DB_DATABASE.LIST_AUTONOMOUS_CONTAINER_DATABASES(
      compartment_id  => compartment_id,
      region          => region,
      credential_name => l_credential
    );

    FOR i IN 1 .. l_response.response_body.COUNT LOOP
      l_item := JSON_OBJECT_T();
      l_item.put('id', l_response.response_body(i).id);
      l_item.put('display_name', l_response.response_body(i).display_name);
      l_item.put('db_unique_name', l_response.response_body(i).db_unique_name);
      l_item.put('db_name', l_response.response_body(i).db_name);
      l_item.put('lifecycle_state', l_response.response_body(i).lifecycle_state);
      l_item.put('time_created', TO_CHAR(l_response.response_body(i).time_created, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
      l_item.put('db_version', l_response.response_body(i).db_version);
      l_item.put('availability_domain', l_response.response_body(i).availability_domain);
      l_item.put('compute_model', l_response.response_body(i).compute_model);
      l_item.put('available_cpus', l_response.response_body(i).available_cpus);
      l_item.put('total_cpus', l_response.response_body(i).total_cpus);
      l_array.append(l_item);
    END LOOP;

    l_result.put('status','success');
    l_result.put('message','Autonomous Container Databases listed');
    l_result.put('autonomous_containers', l_array);
    l_result.put('status_code', l_response.status_code);
    l_result.put('headers', l_response.headers);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status','error');
      l_result.put('message', SQLERRM);
      RETURN l_result.to_clob();
  END list_autonomous_container_database;

  FUNCTION list_autonomous_database_backups(
    compartment_id          IN VARCHAR2,
    autonomous_database_id  IN VARCHAR2,
    region                  IN VARCHAR2 DEFAULT NULL,
    credential_name         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_response   DBMS_CLOUD_OCI_DB_DATABASE_LIST_AUTONOMOUS_DATABASE_BACKUPS_RESPONSE_T;
    l_result     JSON_OBJECT_T := JSON_OBJECT_T();
    l_array      JSON_ARRAY_T := JSON_ARRAY_T();
    l_item       JSON_OBJECT_T;
    l_dest_obj   JSON_OBJECT_T;
    l_credential VARCHAR2(256);
  BEGIN
    resolve_credential(credential_name, l_credential);
    l_response := DBMS_CLOUD_OCI_DB_DATABASE.LIST_AUTONOMOUS_DATABASE_BACKUPS(
      compartment_id         => compartment_id,
      autonomous_database_id => autonomous_database_id,
      region                 => region,
      credential_name        => l_credential
    );

    FOR i IN 1 .. l_response.response_body.COUNT LOOP
      l_item := JSON_OBJECT_T();
      l_item.put('id', l_response.response_body(i).id);
      l_item.put('display_name', l_response.response_body(i).display_name);
      l_item.put('lifecycle_state', l_response.response_body(i).lifecycle_state);
      l_item.put('db_version', l_response.response_body(i).db_version);
      l_item.put('size_in_t_bs', l_response.response_body(i).size_in_t_bs);
      l_item.put('database_size_in_t_bs', l_response.response_body(i).database_size_in_t_bs);
      l_item.put('retention_period_in_days', l_response.response_body(i).retention_period_in_days);
      l_item.put('time_started', TO_CHAR(l_response.response_body(i).time_started, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
      l_item.put('time_ended', TO_CHAR(l_response.response_body(i).time_ended, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
      l_item.put('time_available_till', TO_CHAR(l_response.response_body(i).time_available_till, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));

      l_dest_obj := JSON_OBJECT_T();
      IF l_response.response_body(i).backup_destination_details IS NOT NULL THEN
        l_dest_obj.put('id', l_response.response_body(i).backup_destination_details.id);
        l_dest_obj.put('type', l_response.response_body(i).backup_destination_details.l_type);
        l_dest_obj.put('vpc_user', l_response.response_body(i).backup_destination_details.vpc_user);
      END IF;
      l_item.put('backup_destination', l_dest_obj);

      l_array.append(l_item);
    END LOOP;

    l_result.put('status','success');
    l_result.put('message','Autonomous DB backups retrieved');
    l_result.put('backups', l_array);
    l_result.put('status_code', l_response.status_code);
    l_result.put('headers', l_response.headers);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status','error');
      l_result.put('message', SQLERRM);
      RETURN l_result.to_clob();
  END list_autonomous_database_backups;

END oci_autonomous_database_agents;
/

-------------------------------------------------------------------------------
-- This procedure installs or refreshes the OCI Autonomous Database AI Agent tools.
-------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE initialize_autonomous_database_tools
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
  drop_tool_if_exists(tool_name => 'LIST_SUBSCRIBED_REGIONS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_SUBSCRIBED_REGIONS_TOOL',
    attributes => '{
      "instruction": "Lists all Oracle Cloud regions subscribed by the current tenancy. Use to help the user pick a region.",
      "function": "oci_autonomous_database_agents.list_subscribed_regions"
    }',
    description => 'Tool for listing subscribed OCI regions'
  );

  drop_tool_if_exists(tool_name => 'LIST_COMPARTMENTS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_COMPARTMENTS_TOOL',
    attributes => '{
      "instruction": "Lists compartments in the tenancy. Use to help the user pick a compartment for Autonomous Database operations.",
      "function": "oci_autonomous_database_agents.list_compartments"
    }',
    description => 'Tool for listing compartments'
  );

  drop_tool_if_exists(tool_name => 'GET_COMPARTMENT_OCID_BY_NAME_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_COMPARTMENT_OCID_BY_NAME_TOOL',
    attributes => '{
      "instruction": "Given a compartment name, return its OCID (uses LIST_COMPARTMENTS_TOOL internally).",
      "function": "oci_autonomous_database_agents.get_compartment_ocid_by_name"
    }',
    description => 'Tool to get compartment OCID by name'
  );

  drop_tool_if_exists(tool_name => 'ADBS_PROVISIONING_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'ADBS_PROVISIONING_TOOL',
    attributes => '{
      "instruction": "Provisions an Oracle Autonomous Database. Use LIST_SUBSCRIBED_REGIONS_TOOL and LIST_COMPARTMENTS_TOOL to gather prerequisites, then confirm all choices before provisioning.",
      "function": "oci_autonomous_database_agents.provision_adbs_tool"
    }',
    description => 'Tool for provisioning Oracle Autonomous Databases'
  );

  drop_tool_if_exists(tool_name => 'LIST_AUTONOMOUS_DATABASES_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_AUTONOMOUS_DATABASES_TOOL',
    attributes => '{
      "instruction": "Lists Oracle Autonomous Databases in a given compartment and region.",
      "function": "oci_autonomous_database_agents.list_autonomous_databases"
    }',
    description => 'Tool for listing Oracle Autonomous Databases'
  );

  drop_tool_if_exists(tool_name => 'ADBS_UNPROVISION_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'ADBS_UNPROVISION_TOOL',
    attributes => '{
      "instruction": "Drops an Oracle Autonomous Database (confirm before calling).",
      "function": "oci_autonomous_database_agents.drop_autonomous_database"
    }',
    description => 'Tool for dropping Oracle Autonomous Databases'
  );

  drop_tool_if_exists(tool_name => 'MANAGE_AUTONOMOUS_DB_POWER_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'MANAGE_AUTONOMOUS_DB_POWER_TOOL',
    attributes => '{
      "instruction": "Starts or stops an Autonomous Database based on action START or STOP (confirm before calling).",
      "function": "oci_autonomous_database_agents.manage_autonomous_db_power"
    }',
    description => 'Tool for starting or stopping an Autonomous Database'
  );

  drop_tool_if_exists(tool_name => 'UPDATE_AUTONOMOUS_DB_RESOURCES_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'UPDATE_AUTONOMOUS_DB_RESOURCES_TOOL',
    attributes => '{
      "instruction": "Updates the CPU core count and/or storage size (TB) for an Autonomous Database (confirm before calling).",
      "function": "oci_autonomous_database_agents.update_autonomous_db_resources"
    }',
    description => 'Tool for updating CPU and storage for an Autonomous Database'
  );

  drop_tool_if_exists(tool_name => 'GET_AUTONOMOUS_DATABASE_DETAILS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_AUTONOMOUS_DATABASE_DETAILS_TOOL',
    attributes => '{
      "instruction": "Fetches metadata for a specific Autonomous Database by OCID.",
      "function": "oci_autonomous_database_agents.get_autonomous_database_details"
    }',
    description => 'Tool for getting Autonomous Database details'
  );

  drop_tool_if_exists(tool_name => 'STOP_AUTONOMOUS_DATABASE_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'STOP_AUTONOMOUS_DATABASE_TOOL',
    attributes => '{
      "instruction": "Stops the specified Autonomous Database (confirm before calling).",
      "function": "oci_autonomous_database_agents.stop_autonomous_database"
    }',
    description => 'Tool for stopping an Autonomous Database'
  );

  drop_tool_if_exists(tool_name => 'START_AUTONOMOUS_DATABASE_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'START_AUTONOMOUS_DATABASE_TOOL',
    attributes => '{
      "instruction": "Starts the specified Autonomous Database.",
      "function": "oci_autonomous_database_agents.start_autonomous_database"
    }',
    description => 'Tool for starting an Autonomous Database'
  );

  drop_tool_if_exists(tool_name => 'DATABASE_RESTART_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'DATABASE_RESTART_TOOL',
    attributes => '{
      "instruction": "Restarts the specified Autonomous Database (confirm before calling).",
      "function": "oci_autonomous_database_agents.restart_autonomous_database"
    }',
    description => 'Tool for restarting an Autonomous Database'
  );

  drop_tool_if_exists(tool_name => 'GET_MAINTENANCE_RUN_HISTORY_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_MAINTENANCE_RUN_HISTORY_TOOL',
    attributes => '{
      "instruction": "Retrieve details for a specific maintenance run history by maintenance_run_history_id.",
      "function": "oci_autonomous_database_agents.get_maintenance_run_history_json"
    }',
    description => 'Tool to fetch Autonomous Database maintenance run history'
  );

  drop_tool_if_exists(tool_name => 'UPDATE_AUTONOMOUS_DATABASE_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'UPDATE_AUTONOMOUS_DATABASE_TOOL',
    attributes => '{
      "instruction": "Update one or more attributes of an Autonomous Database. Only include parameters explicitly provided by the user; omit any omitted values.",
      "function": "oci_autonomous_database_agents.update_autonomous_database"
    }',
    description => 'Tool for updating Autonomous Database attributes'
  );

  drop_tool_if_exists(tool_name => 'LIST_KEY_STORES_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_KEY_STORES_TOOL',
    attributes => '{
      "instruction": "List key stores in a given compartment.",
      "function": "oci_autonomous_database_agents.list_key_stores"
    }',
    description => 'Tool for listing Autonomous Database key stores'
  );

  drop_tool_if_exists(tool_name => 'LIST_DB_HOMES_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_DB_HOMES_TOOL',
    attributes => '{
      "instruction": "List DB homes in a given compartment.",
      "function": "oci_autonomous_database_agents.list_db_homes"
    }',
    description => 'Tool for listing DB homes'
  );

  drop_tool_if_exists(tool_name => 'SHRINK_AUTONOMOUS_DATABASE_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'SHRINK_AUTONOMOUS_DATABASE_TOOL',
    attributes => '{
      "instruction": "Shrink an Autonomous Database''s storage (confirm before calling).",
      "function": "oci_autonomous_database_agents.shrink_autonomous_database"
    }',
    description => 'Tool for shrinking an Autonomous Database storage'
  );

  drop_tool_if_exists(tool_name => 'DELETE_KEY_STORE_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'DELETE_KEY_STORE_TOOL',
    attributes => '{
      "instruction": "Delete a key store by key_store_id (confirm before calling).",
      "function": "oci_autonomous_database_agents.delete_key_store"
    }',
    description => 'Tool for deleting a key store'
  );

  drop_tool_if_exists(tool_name => 'LIST_ACDS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_ACDS_TOOL',
    attributes => '{
      "instruction": "List Autonomous Container Databases in a compartment.",
      "function": "oci_autonomous_database_agents.list_autonomous_container_database"
    }',
    description => 'Tool to list Autonomous Container Databases'
  );

  drop_tool_if_exists(tool_name => 'LIST_ADB_BACKUPS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_ADB_BACKUPS_TOOL',
    attributes => '{
      "instruction": "List Autonomous Database backups for a given compartment and autonomous_database_id.",
      "function": "oci_autonomous_database_agents.list_autonomous_database_backups"
    }',
    description => 'Tool to list Autonomous Database backups'
  );

  DBMS_OUTPUT.PUT_LINE('initialize_autonomous_database_tools completed.');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error in initialize_autonomous_database_tools: ' || SQLERRM);
    RAISE;
END initialize_autonomous_database_tools;
/

BEGIN
  initialize_autonomous_database_tools;
END;
/

alter session set current_schema = ADMIN;
