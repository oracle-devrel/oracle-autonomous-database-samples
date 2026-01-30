rem ============================================================================
rem LICENSE
rem   Copyright (c) 2025 Oracle and/or its affiliates.
rem   Licensed under the Universal Permissive License (UPL), Version 1.0
rem   https://oss.oracle.com/licenses/upl/
rem
rem NAME
rem   oci_network_load_balancer_tools.sql
rem
rem DESCRIPTION
rem   Installer script for OCI Network Load Balancer AI tools
rem   (Select AI Agent / Oracle AI Database).
rem
rem   This script installs a consolidated PL/SQL package and registers
rem   AI Agent tools used to automate OCI Network Load Balancer operations
rem   via Select AI Agent (Oracle AI Database).
rem
rem RELEASE VERSION
rem   1.0
rem
rem RELEASE DATE
rem   26-Jan-2026
rem
rem MAJOR CHANGES IN THIS RELEASE
rem   - Initial release
rem   - Added Network Load Balancer AI agent tool registrations
rem
rem SCRIPT STRUCTURE
rem   1. Initialization:
rem        - Grants
rem        - Configuration setup
rem
rem   2. Package Deployment:
rem        - &&INSTALL_SCHEMA.oci_network_load_balancer_agents
rem          (package specification and body)
rem
rem   3. AI Tool Setup:
rem        - Creation of all Network Load Balancer agent tools
rem
rem INSTALL INSTRUCTIONS
rem   1. Connect as ADMIN or a user with required privileges
rem   2. Run the script using SQL*Plus or SQLcl:
rem
rem      sqlplus admin@db @oci_network_load_balancer_tools.sql <INSTALL_SCHEMA> [CONFIG_JSON]
rem
rem   3. Verify installation by checking tool registration
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
-- Initializes the OCI Network Load Balancer AI Agent. This procedure:
--   • Grants required DBMS_CLOUD_OCI NLB type privileges.
--   • Creates the SELECTAI_AGENT_CONFIG table.
--   • Parses the JSON config and persists credential, compartment, and RP flag.
-------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE initialize_network_load_balancer_agent(
  p_install_schema_name IN VARCHAR2,
  p_config_json         IN CLOB
)
IS
  l_use_rp              BOOLEAN := NULL;
  l_credential_name     VARCHAR2(4000) := NULL;
  l_compartment_ocid    VARCHAR2(4000) := NULL;
  l_compartment_name    VARCHAR2(4000) := NULL;
  l_schema_name         VARCHAR2(128);
  c_nlb_agent CONSTANT  VARCHAR2(64) := 'OCI_NETWORK_LOAD_BALANCER';

  TYPE priv_list_t IS VARRAY(200) OF VARCHAR2(4000);
  l_priv_list CONSTANT priv_list_t := priv_list_t(
    'DBMS_CLOUD',
    'DBMS_CLOUD_ADMIN',
    'DBMS_CLOUD_AI_AGENT',
    'DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER',
    -- Response types used by wrappers
    'DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_GET_LISTENER_RESPONSE_T',
    'DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_LIST_LISTENERS_RESPONSE_T',
    'DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_DELETE_LISTENER_RESPONSE_T',
    'DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_DELETE_NETWORK_LOAD_BALANCER_RESPONSE_T',
    'DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_CREATE_NETWORK_LOAD_BALANCER_RESPONSE_T',
    'DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_CREATE_LISTENER_RESPONSE_T',
    'DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_CHANGE_NETWORK_LOAD_BALANCER_COMPARTMENT_RESPONSE_T',
    'DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_LIST_BACKEND_SETS_RESPONSE_T',
    'DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_LIST_BACKENDS_RESPONSE_T',
    'DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_LIST_NETWORK_LOAD_BALANCER_HEALTHS_RESPONSE_T',
    'DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_LIST_NETWORK_LOAD_BALANCERS_POLICIES_RESPONSE_T',
    'DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_LIST_NETWORK_LOAD_BALANCERS_PROTOCOLS_RESPONSE_T',
    'DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_LIST_NETWORK_LOAD_BALANCERS_RESPONSE_T',
    'DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_UPDATE_NETWORK_LOAD_BALANCER_RESPONSE_T',
    'DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_UPDATE_LISTENER_RESPONSE_T',
    'DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_CREATE_BACKEND_SET_RESPONSE_T',
    -- Model/detail types used by wrappers
    'DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_CREATE_NETWORK_LOAD_BALANCER_DETAILS_T',
    'DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_RESERVED_IP_TBL',
    'DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_RESERVED_IP_T',
    'DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_VARCHAR2_TBL',
    'DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_LISTENER_SUMMARY_TBL',
    'DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_NETWORK_LOAD_BALANCER_SUMMARY_T',
    'DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_UPDATE_NETWORK_LOAD_BALANCER_DETAILS_T',
    'DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_CREATE_LISTENER_DETAILS_T',
    'DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_UPDATE_LISTENER_DETAILS_T',
    'DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_CHANGE_NETWORK_LOAD_BALANCER_COMPARTMENT_DETAILS_T',
    'DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_HEALTH_CHECKER_DETAILS_T',
    'DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_CREATE_BACKEND_SET_DETAILS_T',
    'DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_BACKEND_DETAILS_TBL'
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
    l_effective_use_rp := CASE WHEN p_use_rp IS NULL THEN TRUE ELSE p_use_rp END;

    IF p_credential_name IS NOT NULL THEN
      merge_config_key(p_schema, 'CREDENTIAL_NAME', p_credential_name, c_nlb_agent);
    END IF;

    IF p_compartment_name IS NOT NULL THEN
      merge_config_key(p_schema, 'COMPARTMENT_NAME', p_compartment_name, c_nlb_agent);
    END IF;

    IF p_compartment_ocid IS NOT NULL THEN
      merge_config_key(p_schema, 'COMPARTMENT_OCID', p_compartment_ocid, c_nlb_agent);
    END IF;

    l_enable_rp_str := CASE WHEN l_effective_use_rp THEN 'YES' ELSE 'NO' END;
    merge_config_key(p_schema, 'ENABLE_RESOURCE_PRINCIPAL', l_enable_rp_str, c_nlb_agent);

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

  DBMS_OUTPUT.PUT_LINE('initialize_network_load_balancer_agent completed for schema ' || l_schema_name);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Fatal error in initialize_network_load_balancer_agent: ' || SQLERRM);
    RAISE;
END initialize_network_load_balancer_agent;
/

-------------------------------------------------------------------------------
-- Run the setup for the Network Load Balancer AI agent.
-------------------------------------------------------------------------------
BEGIN
  initialize_network_load_balancer_agent(
    p_install_schema_name => '&&INSTALL_SCHEMA',
    p_config_json         => '&&INSTALL_CONFIG_JSON'
  );
END;
/

alter session set current_schema = &&INSTALL_SCHEMA;

------------------------------------------------------------------------
-- Package specification
------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE oci_network_load_balancer_agents
AS
  FUNCTION list_subscribed_regions RETURN CLOB;
  FUNCTION list_compartments RETURN CLOB;

  FUNCTION get_listener (
    p_network_load_balancer_id IN VARCHAR2,
    p_listener_name            IN VARCHAR2,
    p_region                   IN VARCHAR2,
    p_credential_name          IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION list_listeners (
    p_network_load_balancer_id IN VARCHAR2,
    p_region                   IN VARCHAR2,
    p_credential_name          IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION delete_listener (
    p_network_load_balancer_id IN VARCHAR2,
    p_listener_name            IN VARCHAR2,
    p_region                   IN VARCHAR2,
    p_credential_name          IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION delete_network_load_balancer (
    p_network_load_balancer_id IN VARCHAR2,
    p_region                   IN VARCHAR2,
    p_credential_name          IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION create_network_load_balancer (
    p_compartment_name                  IN VARCHAR2,
    p_display_name                      IN VARCHAR2,
    p_is_preserve_source_destination    IN NUMBER,
    p_reserved_ips_json                 IN CLOB,
    p_is_private                        IN NUMBER,
    p_subnet_id                         IN VARCHAR2,
    p_network_security_group_ids_json   IN CLOB,
    p_nlb_ip_version                    IN VARCHAR2,
    p_listener_name                     IN VARCHAR2,
    p_listener_backend_set_name         IN VARCHAR2,
    p_listener_port                     IN NUMBER,
    p_listener_protocol                 IN VARCHAR2,
    p_backend_set_name                  IN VARCHAR2,
    p_backend_policy                    IN VARCHAR2,
    p_health_protocol                   IN VARCHAR2,
    p_health_port                       IN NUMBER,
    p_freeform_tags                     IN CLOB,
    p_defined_tags                      IN CLOB,
    p_region                            IN VARCHAR2,
    p_credential_name                   IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION create_listener (
    p_network_load_balancer_id   IN VARCHAR2,
    p_name                       IN VARCHAR2,
    p_default_backend_set_name   IN VARCHAR2,
    p_port                       IN NUMBER,
    p_protocol                   IN VARCHAR2,
    p_ip_version                 IN VARCHAR2,
    p_region                     IN VARCHAR2,
    p_credential_name            IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION change_nlb_compartment (
    p_network_load_balancer_id IN VARCHAR2,
    p_new_compartment_id       IN VARCHAR2,
    p_region                   IN VARCHAR2,
    p_credential_name          IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION list_backend_sets (
    p_network_load_balancer_id IN VARCHAR2,
    p_region                   IN VARCHAR2,
    p_credential_name          IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION list_backends (
    p_network_load_balancer_id IN VARCHAR2,
    p_backend_set_name         IN VARCHAR2,
    p_region                   IN VARCHAR2,
    p_credential_name          IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION list_nlb_healths (
    p_compartment_id  IN VARCHAR2,
    p_region          IN VARCHAR2,
    p_credential_name IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION list_nlb_policies (
    p_region          IN VARCHAR2,
    p_credential_name IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION list_nlb_protocols (
    p_region          IN VARCHAR2,
    p_credential_name IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION list_network_load_balancers (
    p_compartment_id  IN VARCHAR2,
    p_region          IN VARCHAR2,
    p_credential_name IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION update_network_load_balancer (
    p_network_load_balancer_id         IN VARCHAR2,
    p_display_name                     IN VARCHAR2,
    p_is_preserve_source_destination   IN NUMBER,
    p_nlb_ip_version                   IN VARCHAR2,
    p_freeform_tags                    IN CLOB,
    p_defined_tags                     IN CLOB,
    p_region                           IN VARCHAR2,
    p_credential_name                  IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION update_listener (
    p_network_load_balancer_id   IN VARCHAR2,
    p_listener_name              IN VARCHAR2,
    p_default_backend_set_name   IN VARCHAR2,
    p_port                       IN NUMBER,
    p_protocol                   IN VARCHAR2,
    p_ip_version                 IN VARCHAR2,
    p_region                     IN VARCHAR2,
    p_credential_name            IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION create_backend_set (
    p_network_load_balancer_id  IN VARCHAR2,
    p_name                      IN VARCHAR2,
    p_policy                    IN VARCHAR2,
    p_protocol                  IN VARCHAR2,
    p_port                      IN NUMBER,
    p_region                    IN VARCHAR2,
    p_credential_name           IN VARCHAR2
  ) RETURN CLOB;

END oci_network_load_balancer_agents;
/

------------------------------------------------------------------------
-- Package body
------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY oci_network_load_balancer_agents
AS
  c_nlb_agent CONSTANT VARCHAR2(64) := 'OCI_NETWORK_LOAD_BALANCER';

  -- Helper function to get configuration parameters for the current user
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

  ----------------------------------------------------------------------
  -- resolve_credential: uses explicit credential if provided, else config
  ----------------------------------------------------------------------
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

    l_cfg_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', c_nlb_agent);
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

  ----------------------------------------------------------------------
  -- list_subscribed_regions: REST call to Identity regionSubscriptions
  ----------------------------------------------------------------------
  FUNCTION list_subscribed_regions RETURN CLOB
  IS
    l_result_json  JSON_OBJECT_T := JSON_OBJECT_T();
    l_regions      JSON_ARRAY_T  := JSON_ARRAY_T();
    l_current_user VARCHAR2(128) := SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json      CLOB;
    l_cfg           JSON_OBJECT_T;
    l_params        JSON_OBJECT_T;
    l_credential_name VARCHAR2(256);
    tenancy_id      VARCHAR2(128);
    l_region        VARCHAR2(128);
    l_endpoint      VARCHAR2(1000);
    l_response      CLOB;
    l_data          JSON_ARRAY_T;
    l_obj           JSON_OBJECT_T;
  BEGIN
    resolve_credential(NULL, l_credential_name);
    IF l_credential_name IS NULL THEN
      l_result_json.put('status','error');
      l_result_json.put('message','Missing credential_name (set in SELECTAI_AGENT_CONFIG for OCI_NETWORK_LOAD_BALANCER).');
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
          'status'      VALUE l_obj.get_string('status')
        )
      );
    END LOOP;

    l_result_json.put('status','success');
    l_result_json.put('message','Successfully retrieved subscribed regions');
    l_result_json.put('regions', l_regions);
    RETURN l_result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result_json := JSON_OBJECT_T();
      l_result_json.put('status','error');
      l_result_json.put('message','Failed to retrieve subscribed regions: ' || SQLERRM);
      RETURN l_result_json.to_clob();
  END list_subscribed_regions;

  ----------------------------------------------------------------------
  -- list_compartments: REST call to Identity compartments
  ----------------------------------------------------------------------
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
      l_result_json.put('message','Missing credential_name (set in SELECTAI_AGENT_CONFIG for OCI_NETWORK_LOAD_BALANCER).');
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
          'id'   VALUE l_obj.get_string('id'),
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
      RETURN l_result_json.to_clob();
  END list_compartments;

  ----------------------------------------------------------------------
  -- get_compartment_ocid_by_name: utility used by create_nlb
  ----------------------------------------------------------------------
  FUNCTION get_compartment_ocid_by_name(
    p_compartment_name IN VARCHAR2,
    p_credential_name  IN VARCHAR2 DEFAULT NULL
  ) RETURN VARCHAR2
  IS
    l_comp_json_clob CLOB;
    l_root           JSON_OBJECT_T;
    l_arr            JSON_ARRAY_T;
    l_obj            JSON_OBJECT_T;
    l_id             VARCHAR2(4000);
  BEGIN
    -- Currently list_compartments uses config credential only; honor override by temporarily resolving
    IF p_credential_name IS NOT NULL THEN
      -- Fall back: if caller provides credential override, list_compartments still uses config.
      NULL;
    END IF;

    l_comp_json_clob := list_compartments();
    l_root := JSON_OBJECT_T.parse(l_comp_json_clob);
    IF l_root.get_string('status') <> 'success' THEN
      RETURN NULL;
    END IF;
    l_arr := l_root.get_array('compartments');
    FOR i IN 0 .. l_arr.get_size() - 1 LOOP
      l_obj := JSON_OBJECT_T(l_arr.get(i));
      IF l_obj.get_string('name') = p_compartment_name THEN
        l_id := l_obj.get_string('id');
        EXIT;
      END IF;
    END LOOP;
    RETURN l_id;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN NULL;
  END get_compartment_ocid_by_name;

  ----------------------------------------------------------------------
  -- NLB wrappers (adapted from /Users/rposina/Downloads/network_load_balancer.sql)
  ----------------------------------------------------------------------
  FUNCTION get_listener (
    p_network_load_balancer_id IN VARCHAR2,
    p_listener_name            IN VARCHAR2,
    p_region                   IN VARCHAR2,
    p_credential_name          IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_resp            DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_GET_LISTENER_RESPONSE_T;
    l_result          JSON_OBJECT_T := JSON_OBJECT_T();
    l_credential      VARCHAR2(256);
  BEGIN
    resolve_credential(p_credential_name, l_credential);

    l_resp := DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER.GET_LISTENER(
      network_load_balancer_id => p_network_load_balancer_id,
      listener_name            => p_listener_name,
      opc_request_id           => NULL,
      if_none_match            => NULL,
      region                   => p_region,
      endpoint                 => NULL,
      credential_name          => l_credential
    );

    l_result.put('status',      'success');
    l_result.put('message',     'Listener retrieved successfully');
    l_result.put('status_code', l_resp.status_code);
    l_result.put('headers',     l_resp.headers);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status',  'error');
      l_result.put('message', 'Failed to get listener: ' || SQLERRM);
      l_result.put('nlb_id',   p_network_load_balancer_id);
      RETURN l_result.to_clob();
  END get_listener;

  FUNCTION list_listeners (
    p_network_load_balancer_id IN VARCHAR2,
    p_region                   IN VARCHAR2,
    p_credential_name          IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_resp        DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_LIST_LISTENERS_RESPONSE_T;
    l_result      JSON_OBJECT_T := JSON_OBJECT_T();
    l_items       DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_LISTENER_SUMMARY_TBL;
    l_payload     CLOB := '';
    l_credential  VARCHAR2(256);
  BEGIN
    resolve_credential(p_credential_name, l_credential);

    l_resp := DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER.LIST_LISTENERS(
      network_load_balancer_id => p_network_load_balancer_id,
      region                   => p_region,
      credential_name          => l_credential
    );

    l_items := l_resp.response_body.items;
    l_payload := '[';
    FOR i IN 1 .. l_items.COUNT LOOP
      IF i > 1 THEN
        l_payload := l_payload || ',';
      END IF;

      l_payload := l_payload || '{"name":"' || l_items(i).name ||
                                 '","port":' || l_items(i).port ||
                                 ',"protocol":"' || l_items(i).protocol ||
                                 '","ipVersion":"' || l_items(i).ip_version || '"}';
    END LOOP;
    l_payload := l_payload || ']';

    l_result.put('status',      'success');
    l_result.put('message',     'Listeners listed successfully');
    l_result.put('status_code', l_resp.status_code);
    l_result.put('listeners',   JSON_ELEMENT_T.parse(l_payload));
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status',  'error');
      l_result.put('message', 'Failed to list listeners: ' || SQLERRM);
      l_result.put('nlb_id',  p_network_load_balancer_id);
      RETURN l_result.to_clob();
  END list_listeners;

  FUNCTION delete_listener (
    p_network_load_balancer_id IN VARCHAR2,
    p_listener_name            IN VARCHAR2,
    p_region                   IN VARCHAR2,
    p_credential_name          IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_resp       DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_DELETE_LISTENER_RESPONSE_T;
    l_result     JSON_OBJECT_T := JSON_OBJECT_T();
    l_credential VARCHAR2(256);
  BEGIN
    resolve_credential(p_credential_name, l_credential);

    l_resp := DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER.DELETE_LISTENER(
      network_load_balancer_id => p_network_load_balancer_id,
      listener_name            => p_listener_name,
      opc_request_id           => NULL,
      if_match                 => NULL,
      region                   => p_region,
      endpoint                 => NULL,
      credential_name          => l_credential
    );

    l_result.put('status',      'success');
    l_result.put('message',     'Listener deleted successfully');
    l_result.put('status_code', l_resp.status_code);
    l_result.put('headers',     l_resp.headers);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status',  'error');
      l_result.put('message', 'Failed to delete listener: ' || SQLERRM);
      l_result.put('nlb_id',  p_network_load_balancer_id);
      l_result.put('listener', p_listener_name);
      RETURN l_result.to_clob();
  END delete_listener;

  FUNCTION delete_network_load_balancer (
    p_network_load_balancer_id IN VARCHAR2,
    p_region                   IN VARCHAR2,
    p_credential_name          IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_resp       DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_DELETE_NETWORK_LOAD_BALANCER_RESPONSE_T;
    l_result     JSON_OBJECT_T := JSON_OBJECT_T();
    l_credential VARCHAR2(256);
  BEGIN
    resolve_credential(p_credential_name, l_credential);

    l_resp := DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER.DELETE_NETWORK_LOAD_BALANCER(
      network_load_balancer_id => p_network_load_balancer_id,
      if_match                 => NULL,
      opc_request_id           => NULL,
      region                   => p_region,
      endpoint                 => NULL,
      credential_name          => l_credential
    );

    l_result.put('status',      'success');
    l_result.put('message',     'Network Load Balancer deleted successfully');
    l_result.put('status_code', l_resp.status_code);
    l_result.put('headers',     l_resp.headers);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status',  'error');
      l_result.put('message', 'Failed to delete network load balancer: ' || SQLERRM);
      l_result.put('nlb_id',  p_network_load_balancer_id);
      RETURN l_result.to_clob();
  END delete_network_load_balancer;

  FUNCTION create_network_load_balancer (
    p_compartment_name                  IN VARCHAR2,
    p_display_name                      IN VARCHAR2,
    p_is_preserve_source_destination    IN NUMBER,
    p_reserved_ips_json                 IN CLOB,
    p_is_private                        IN NUMBER,
    p_subnet_id                         IN VARCHAR2,
    p_network_security_group_ids_json   IN CLOB,
    p_nlb_ip_version                    IN VARCHAR2,
    p_listener_name                     IN VARCHAR2,
    p_listener_backend_set_name         IN VARCHAR2,
    p_listener_port                     IN NUMBER,
    p_listener_protocol                 IN VARCHAR2,
    p_backend_set_name                  IN VARCHAR2,
    p_backend_policy                    IN VARCHAR2,
    p_health_protocol                   IN VARCHAR2,
    p_health_port                       IN NUMBER,
    p_freeform_tags                     IN CLOB,
    p_defined_tags                      IN CLOB,
    p_region                            IN VARCHAR2,
    p_credential_name                   IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_listeners_json     JSON_OBJECT_T := JSON_OBJECT_T();
    l_listener_obj       JSON_OBJECT_T := JSON_OBJECT_T();
    l_backend_sets_json  JSON_OBJECT_T := JSON_OBJECT_T();
    l_backend_set_obj    JSON_OBJECT_T := JSON_OBJECT_T();
    l_health_checker     JSON_OBJECT_T := JSON_OBJECT_T();

    l_listeners          JSON_ELEMENT_T;
    l_backend_sets       JSON_ELEMENT_T;
    l_freeform_tags      JSON_ELEMENT_T := CASE WHEN p_freeform_tags IS NOT NULL THEN JSON_OBJECT_T.parse(p_freeform_tags) ELSE NULL END;
    l_defined_tags       JSON_ELEMENT_T := CASE WHEN p_defined_tags IS NOT NULL THEN JSON_OBJECT_T.parse(p_defined_tags) ELSE NULL END;

    l_result             JSON_OBJECT_T := JSON_OBJECT_T();
    l_resp               DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_CREATE_NETWORK_LOAD_BALANCER_RESPONSE_T;
    l_details            DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_CREATE_NETWORK_LOAD_BALANCER_DETAILS_T;

    l_reserved_ips       DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_RESERVED_IP_TBL := DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_RESERVED_IP_TBL();
    l_nsg_ids            DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_VARCHAR2_TBL := DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_VARCHAR2_TBL();
    l_compartment_id     VARCHAR2(256);
    l_credential         VARCHAR2(256);
  BEGIN
    resolve_credential(p_credential_name, l_credential);

    l_compartment_id := get_compartment_ocid_by_name(p_compartment_name => p_compartment_name);
    IF l_compartment_id IS NULL THEN
      l_result.put('status','error');
      l_result.put('message','Failed to resolve compartment OCID for compartment_name=' || p_compartment_name);
      RETURN l_result.to_clob();
    END IF;

    IF p_reserved_ips_json IS NOT NULL THEN
      DECLARE
        l_json_arr JSON_ARRAY_T := JSON_ARRAY_T.parse(p_reserved_ips_json);
        l_obj      JSON_OBJECT_T;
      BEGIN
        FOR i IN 0 .. l_json_arr.get_size - 1 LOOP
          l_obj := JSON_OBJECT_T(l_json_arr.get(i));
          l_reserved_ips.EXTEND;
          l_reserved_ips(l_reserved_ips.COUNT) := DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_RESERVED_IP_T(
            id => l_obj.get_string('id')
          );
        END LOOP;
      END;
    END IF;

    IF p_network_security_group_ids_json IS NOT NULL THEN
      DECLARE
        l_json_arr JSON_ARRAY_T := JSON_ARRAY_T.parse(p_network_security_group_ids_json);
      BEGIN
        FOR i IN 0 .. l_json_arr.get_size - 1 LOOP
          l_nsg_ids.EXTEND;
          l_nsg_ids(l_nsg_ids.COUNT) := l_json_arr.get_string(i);
        END LOOP;
      END;
    END IF;

    l_listener_obj.put('name', p_listener_name);
    l_listener_obj.put('defaultBackendSetName', p_listener_backend_set_name);
    l_listener_obj.put('port', p_listener_port);
    l_listener_obj.put('protocol', p_listener_protocol);
    l_listeners_json.put(p_listener_name, l_listener_obj);
    l_listeners := l_listeners_json;

    l_health_checker.put('protocol', p_health_protocol);
    l_health_checker.put('port', p_health_port);
    l_backend_set_obj.put('policy', p_backend_policy);
    l_backend_set_obj.put('backends', JSON_ARRAY_T());
    l_backend_set_obj.put('healthChecker', l_health_checker);
    l_backend_sets_json.put(p_backend_set_name, l_backend_set_obj);
    l_backend_sets := l_backend_sets_json;

    l_details := DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_CREATE_NETWORK_LOAD_BALANCER_DETAILS_T(
      compartment_id                  => l_compartment_id,
      display_name                    => p_display_name,
      is_preserve_source_destination => p_is_preserve_source_destination,
      reserved_ips                    => l_reserved_ips,
      is_private                      => p_is_private,
      subnet_id                       => p_subnet_id,
      network_security_group_ids      => l_nsg_ids,
      nlb_ip_version                  => p_nlb_ip_version,
      listeners                       => l_listeners,
      backend_sets                    => l_backend_sets,
      freeform_tags                   => l_freeform_tags,
      defined_tags                    => l_defined_tags
    );

    l_resp := DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER.CREATE_NETWORK_LOAD_BALANCER(
      create_network_load_balancer_details => l_details,
      opc_retry_token                      => NULL,
      opc_request_id                       => NULL,
      region                               => p_region,
      endpoint                             => NULL,
      credential_name                      => l_credential
    );

    l_result.put('status', 'success');
    l_result.put('message', 'Network Load Balancer created successfully');
    l_result.put('status_code', l_resp.status_code);
    l_result.put('headers', l_resp.headers);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status',  'error');
      l_result.put('message', 'Failed to create NLB: ' || SQLERRM);
      RETURN l_result.to_clob();
  END create_network_load_balancer;

  FUNCTION create_listener (
    p_network_load_balancer_id   IN VARCHAR2,
    p_name                       IN VARCHAR2,
    p_default_backend_set_name   IN VARCHAR2,
    p_port                       IN NUMBER,
    p_protocol                   IN VARCHAR2,
    p_ip_version                 IN VARCHAR2,
    p_region                     IN VARCHAR2,
    p_credential_name            IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_details     DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_CREATE_LISTENER_DETAILS_T;
    l_resp        DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_CREATE_LISTENER_RESPONSE_T;
    l_result      JSON_OBJECT_T := JSON_OBJECT_T();
    l_credential  VARCHAR2(256);
  BEGIN
    resolve_credential(p_credential_name, l_credential);

    l_details := NEW DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_CREATE_LISTENER_DETAILS_T(
      p_name,
      p_default_backend_set_name,
      p_port,
      p_protocol,
      p_ip_version
    );

    l_resp := DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER.CREATE_LISTENER(
      network_load_balancer_id => p_network_load_balancer_id,
      create_listener_details  => l_details,
      opc_request_id           => NULL,
      opc_retry_token          => NULL,
      if_match                 => NULL,
      region                   => p_region,
      endpoint                 => NULL,
      credential_name          => l_credential
    );

    l_result.put('status',      'success');
    l_result.put('message',     'Listener created successfully');
    l_result.put('status_code', l_resp.status_code);
    l_result.put('headers',     l_resp.headers);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status',  'error');
      l_result.put('message', 'Failed to create listener: ' || SQLERRM);
      RETURN l_result.to_clob();
  END create_listener;

  FUNCTION change_nlb_compartment (
    p_network_load_balancer_id IN VARCHAR2,
    p_new_compartment_id       IN VARCHAR2,
    p_region                   IN VARCHAR2,
    p_credential_name          IN VARCHAR2
  ) RETURN CLOB
  IS
    l_change_details DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_CHANGE_NETWORK_LOAD_BALANCER_COMPARTMENT_DETAILS_T;
    l_resp           DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_CHANGE_NETWORK_LOAD_BALANCER_COMPARTMENT_RESPONSE_T;
    l_result         JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    l_change_details := DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_CHANGE_NETWORK_LOAD_BALANCER_COMPARTMENT_DETAILS_T(
      compartment_id => p_new_compartment_id
    );

    l_resp := DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER.CHANGE_NETWORK_LOAD_BALANCER_COMPARTMENT(
      network_load_balancer_id                         => p_network_load_balancer_id,
      change_network_load_balancer_compartment_details => l_change_details,
      opc_request_id                                   => NULL,
      opc_retry_token                                  => NULL,
      if_match                                         => NULL,
      region                                           => p_region,
      endpoint                                         => NULL,
      credential_name                                  => p_credential_name
    );

    l_result.put('status',      'success');
    l_result.put('message',     'Network Load Balancer moved successfully');
    l_result.put('status_code', l_resp.status_code);
    l_result.put('headers',     l_resp.headers);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status',    'error');
      l_result.put('message',   'Failed to change compartment: ' || SQLERRM);
      l_result.put('nlb_id',    p_network_load_balancer_id);
      RETURN l_result.to_clob();
  END change_nlb_compartment;

  FUNCTION list_backend_sets (
    p_network_load_balancer_id IN VARCHAR2,
    p_region                   IN VARCHAR2,
    p_credential_name          IN VARCHAR2
  ) RETURN CLOB
  IS
    l_resp         DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_LIST_BACKEND_SETS_RESPONSE_T;
    l_result       JSON_OBJECT_T := JSON_OBJECT_T();
    l_backend_sets JSON_ARRAY_T  := JSON_ARRAY_T();
    l_entry        JSON_OBJECT_T;
  BEGIN
    l_resp := DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER.LIST_BACKEND_SETS(
      network_load_balancer_id => p_network_load_balancer_id,
      opc_request_id           => NULL,
      if_none_match            => NULL,
      limit                    => NULL,
      page                     => NULL,
      sort_order               => NULL,
      sort_by                  => NULL,
      region                   => p_region,
      endpoint                 => NULL,
      credential_name          => p_credential_name
    );

    FOR i IN 1 .. l_resp.response_body.items.COUNT LOOP
      l_entry := JSON_OBJECT_T();
      l_entry.put('name',   l_resp.response_body.items(i).name);
      l_entry.put('policy', l_resp.response_body.items(i).policy);
      l_backend_sets.append(l_entry);
    END LOOP;

    l_result.put('status',        'success');
    l_result.put('message',       'Backend sets listed successfully');
    l_result.put('status_code',   l_resp.status_code);
    l_result.put('headers',       l_resp.headers);
    l_result.put('backend_sets',  l_backend_sets);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status',  'error');
      l_result.put('message', 'Failed to list backend sets: ' || SQLERRM);
      l_result.put('nlb_id',  p_network_load_balancer_id);
      RETURN l_result.to_clob();
  END list_backend_sets;

  FUNCTION list_backends (
    p_network_load_balancer_id IN VARCHAR2,
    p_backend_set_name         IN VARCHAR2,
    p_region                   IN VARCHAR2,
    p_credential_name          IN VARCHAR2
  ) RETURN CLOB
  IS
    l_resp   DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_LIST_BACKENDS_RESPONSE_T;
    l_result JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    l_resp := DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER.LIST_BACKENDS(
      network_load_balancer_id => p_network_load_balancer_id,
      backend_set_name         => p_backend_set_name,
      opc_request_id           => NULL,
      if_none_match            => NULL,
      limit                    => NULL,
      page                     => NULL,
      sort_order               => NULL,
      sort_by                  => NULL,
      region                   => p_region,
      endpoint                 => NULL,
      credential_name          => p_credential_name
    );

    l_result.put('status',       'success');
    l_result.put('message',      'Backend list retrieved successfully');
    l_result.put('status_code',  l_resp.status_code);
    l_result.put('headers',      l_resp.headers);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status',  'error');
      l_result.put('message', 'Failed to list backends: ' || SQLERRM);
      l_result.put('nlb_id',  p_network_load_balancer_id);
      RETURN l_result.to_clob();
  END list_backends;

  FUNCTION list_nlb_healths (
    p_compartment_id  IN VARCHAR2,
    p_region          IN VARCHAR2,
    p_credential_name IN VARCHAR2
  ) RETURN CLOB
  IS
    l_resp         DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_LIST_NETWORK_LOAD_BALANCER_HEALTHS_RESPONSE_T;
    l_result       JSON_OBJECT_T := JSON_OBJECT_T();
    l_health_array JSON_ARRAY_T  := JSON_ARRAY_T();
    l_item_obj     JSON_OBJECT_T;
  BEGIN
    l_resp := DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER.LIST_NETWORK_LOAD_BALANCER_HEALTHS(
      compartment_id   => p_compartment_id,
      sort_order       => NULL,
      sort_by          => NULL,
      opc_request_id   => NULL,
      limit            => NULL,
      page             => NULL,
      region           => p_region,
      endpoint         => NULL,
      credential_name  => p_credential_name
    );

    FOR i IN 1 .. l_resp.response_body.items.COUNT LOOP
      l_item_obj := JSON_OBJECT_T();
      l_item_obj.put('network_load_balancer_id', l_resp.response_body.items(i).network_load_balancer_id);
      l_item_obj.put('status',                   l_resp.response_body.items(i).status);
      l_health_array.append(l_item_obj);
    END LOOP;

    l_result.put('status',           'success');
    l_result.put('message',          'NLB health list retrieved successfully');
    l_result.put('status_code',      l_resp.status_code);
    l_result.put('headers',          l_resp.headers);
    l_result.put('health_summaries', l_health_array);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status',  'error');
      l_result.put('message', 'Failed to list NLB health summaries: ' || SQLERRM);
      l_result.put('compartment_id', p_compartment_id);
      RETURN l_result.to_clob();
  END list_nlb_healths;

  FUNCTION list_nlb_policies (
    p_region          IN VARCHAR2,
    p_credential_name IN VARCHAR2
  ) RETURN CLOB
  IS
    l_resp   DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_LIST_NETWORK_LOAD_BALANCERS_POLICIES_RESPONSE_T;
    l_result JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    l_resp := DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER.LIST_NETWORK_LOAD_BALANCERS_POLICIES(
      opc_request_id   => NULL,
      limit            => NULL,
      page             => NULL,
      sort_order       => NULL,
      sort_by          => NULL,
      region           => p_region,
      endpoint         => NULL,
      credential_name  => p_credential_name
    );

    l_result.put('status',       'success');
    l_result.put('message',      'Network Load Balancer policies listed successfully');
    l_result.put('status_code',  l_resp.status_code);
    l_result.put('headers',      l_resp.headers);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status',  'error');
      l_result.put('message', 'Failed to list NLB policies: ' || SQLERRM);
      RETURN l_result.to_clob();
  END list_nlb_policies;

  FUNCTION list_nlb_protocols (
    p_region          IN VARCHAR2,
    p_credential_name IN VARCHAR2
  ) RETURN CLOB
  IS
    l_resp   DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_LIST_NETWORK_LOAD_BALANCERS_PROTOCOLS_RESPONSE_T;
    l_result JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    l_resp := DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER.LIST_NETWORK_LOAD_BALANCERS_PROTOCOLS(
      opc_request_id   => NULL,
      limit            => NULL,
      page             => NULL,
      sort_order       => NULL,
      sort_by          => NULL,
      region           => p_region,
      endpoint         => NULL,
      credential_name  => p_credential_name
    );

    l_result.put('status',       'success');
    l_result.put('message',      'Network Load Balancer protocols listed (deprecated endpoint)');
    l_result.put('status_code',  l_resp.status_code);
    l_result.put('headers',      l_resp.headers);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status',  'error');
      l_result.put('message', 'Failed to list NLB protocols: ' || SQLERRM);
      RETURN l_result.to_clob();
  END list_nlb_protocols;

  FUNCTION list_network_load_balancers (
    p_compartment_id  IN VARCHAR2,
    p_region          IN VARCHAR2,
    p_credential_name IN VARCHAR2
  ) RETURN CLOB
  IS
    l_resp      DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_LIST_NETWORK_LOAD_BALANCERS_RESPONSE_T;
    l_result    JSON_OBJECT_T := JSON_OBJECT_T();
    l_array     JSON_ARRAY_T := JSON_ARRAY_T();
    l_item      DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_NETWORK_LOAD_BALANCER_SUMMARY_T;
  BEGIN
    l_resp := DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER.LIST_NETWORK_LOAD_BALANCERS(
      compartment_id   => p_compartment_id,
      lifecycle_state  => NULL,
      display_name     => NULL,
      limit            => NULL,
      page             => NULL,
      sort_order       => NULL,
      sort_by          => NULL,
      opc_request_id   => NULL,
      region           => p_region,
      endpoint         => NULL,
      credential_name  => p_credential_name
    );

    IF l_resp.response_body.items IS NOT NULL THEN
      FOR i IN 1 .. l_resp.response_body.items.COUNT LOOP
        l_item := l_resp.response_body.items(i);
        l_array.append(
          JSON_OBJECT(
            'name' VALUE l_item.display_name,
            'id' VALUE l_item.id,
            'lifecycle_state' VALUE l_item.lifecycle_state
          )
        );
      END LOOP;
    END IF;

    l_result.put('status',      'success');
    l_result.put('message',     'Network Load Balancers listed successfully');
    l_result.put('status_code', l_resp.status_code);
    l_result.put('nlbs',        l_array);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status',  'error');
      l_result.put('message', 'Failed to list NLBs: ' || SQLERRM);
      l_result.put('compartment_id', p_compartment_id);
      RETURN l_result.to_clob();
  END list_network_load_balancers;

  FUNCTION update_network_load_balancer (
    p_network_load_balancer_id         IN VARCHAR2,
    p_display_name                     IN VARCHAR2,
    p_is_preserve_source_destination   IN NUMBER,
    p_nlb_ip_version                   IN VARCHAR2,
    p_freeform_tags                    IN CLOB,
    p_defined_tags                     IN CLOB,
    p_region                           IN VARCHAR2,
    p_credential_name                  IN VARCHAR2
  ) RETURN CLOB
  IS
    l_resp           DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_UPDATE_NETWORK_LOAD_BALANCER_RESPONSE_T;
    l_result         JSON_OBJECT_T := JSON_OBJECT_T();
    l_update_details DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_UPDATE_NETWORK_LOAD_BALANCER_DETAILS_T;
  BEGIN
    l_update_details := DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_UPDATE_NETWORK_LOAD_BALANCER_DETAILS_T(
      display_name                    => p_display_name,
      is_preserve_source_destination => p_is_preserve_source_destination,
      nlb_ip_version                  => p_nlb_ip_version,
      freeform_tags                   => CASE WHEN p_freeform_tags IS NOT NULL THEN JSON_ELEMENT_T.parse(p_freeform_tags) ELSE NULL END,
      defined_tags                    => CASE WHEN p_defined_tags IS NOT NULL THEN JSON_ELEMENT_T.parse(p_defined_tags) ELSE NULL END
    );

    l_resp := DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER.UPDATE_NETWORK_LOAD_BALANCER(
      network_load_balancer_id             => p_network_load_balancer_id,
      update_network_load_balancer_details => l_update_details,
      if_match                             => NULL,
      opc_request_id                       => NULL,
      region                               => p_region,
      endpoint                             => NULL,
      credential_name                      => p_credential_name
    );

    l_result.put('status',      'success');
    l_result.put('message',     'Network Load Balancer updated successfully');
    l_result.put('status_code', l_resp.status_code);
    l_result.put('headers',     l_resp.headers);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status', 'error');
      l_result.put('message', 'Failed to update network load balancer: ' || SQLERRM);
      l_result.put('network_load_balancer_id', p_network_load_balancer_id);
      RETURN l_result.to_clob();
  END update_network_load_balancer;

  FUNCTION update_listener (
    p_network_load_balancer_id   IN VARCHAR2,
    p_listener_name              IN VARCHAR2,
    p_default_backend_set_name   IN VARCHAR2,
    p_port                       IN NUMBER,
    p_protocol                   IN VARCHAR2,
    p_ip_version                 IN VARCHAR2,
    p_region                     IN VARCHAR2,
    p_credential_name            IN VARCHAR2
  ) RETURN CLOB
  IS
    l_resp            DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_UPDATE_LISTENER_RESPONSE_T;
    l_result          JSON_OBJECT_T := JSON_OBJECT_T();
    l_update_listener DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_UPDATE_LISTENER_DETAILS_T;
  BEGIN
    l_update_listener := DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_UPDATE_LISTENER_DETAILS_T(
      default_backend_set_name => p_default_backend_set_name,
      port                     => p_port,
      protocol                 => p_protocol,
      ip_version               => p_ip_version
    );

    l_resp := DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER.UPDATE_LISTENER(
      network_load_balancer_id => p_network_load_balancer_id,
      update_listener_details  => l_update_listener,
      listener_name            => p_listener_name,
      opc_request_id           => NULL,
      opc_retry_token          => NULL,
      if_match                 => NULL,
      region                   => p_region,
      endpoint                 => NULL,
      credential_name          => p_credential_name
    );

    l_result.put('status',      'success');
    l_result.put('message',     'Listener updated successfully');
    l_result.put('status_code', l_resp.status_code);
    l_result.put('headers',     l_resp.headers);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status', 'error');
      l_result.put('message', 'Failed to update listener: ' || SQLERRM);
      l_result.put('network_load_balancer_id', p_network_load_balancer_id);
      l_result.put('listener_name', p_listener_name);
      RETURN l_result.to_clob();
  END update_listener;

  FUNCTION create_backend_set (
    p_network_load_balancer_id  IN VARCHAR2,
    p_name                      IN VARCHAR2,
    p_policy                    IN VARCHAR2,
    p_protocol                  IN VARCHAR2,
    p_port                      IN NUMBER,
    p_region                    IN VARCHAR2,
    p_credential_name           IN VARCHAR2
  ) RETURN CLOB
  IS
    l_health_checker  DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_HEALTH_CHECKER_DETAILS_T;
    l_backend_set     DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_CREATE_BACKEND_SET_DETAILS_T;
    l_response        DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER_CREATE_BACKEND_SET_RESPONSE_T;
    l_result          JSON_OBJECT_T := JSON_OBJECT_T();
    l_backends        DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_BACKEND_DETAILS_TBL :=
                        DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_BACKEND_DETAILS_TBL();
  BEGIN
    l_health_checker := DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_HEALTH_CHECKER_DETAILS_T(
      protocol             => p_protocol,
      port                 => p_port,
      retries              => NULL,
      timeout_in_millis    => NULL,
      interval_in_millis   => NULL,
      url_path             => NULL,
      response_body_regex  => NULL,
      return_code          => NULL,
      request_data         => NULL,
      response_data        => NULL
    );

    l_backend_set := DBMS_CLOUD_OCI_NETWORK_LOAD_BALANCER_CREATE_BACKEND_SET_DETAILS_T(
      name               => p_name,
      policy             => p_policy,
      is_preserve_source => NULL,
      ip_version         => NULL,
      backends           => l_backends,
      health_checker     => l_health_checker
    );

    l_response := DBMS_CLOUD_OCI_NLB_NETWORK_LOAD_BALANCER.CREATE_BACKEND_SET(
      network_load_balancer_id   => p_network_load_balancer_id,
      create_backend_set_details => l_backend_set,
      opc_request_id             => NULL,
      opc_retry_token            => NULL,
      if_match                   => NULL,
      region                     => p_region,
      endpoint                   => NULL,
      credential_name            => p_credential_name
    );

    l_result.put('status',      'success');
    l_result.put('message',     'Backend set created successfully');
    l_result.put('status_code', l_response.status_code);
    l_result.put('headers',     l_response.headers);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result := JSON_OBJECT_T();
      l_result.put('status',  'error');
      l_result.put('message', 'Failed to create backend set: ' || SQLERRM);
      RETURN l_result.to_clob();
  END create_backend_set;

END oci_network_load_balancer_agents;
/

-------------------------------------------------------------------------------
-- This procedure installs or refreshes the OCI NLB AI Agent tools in the
-- current schema. It drops any existing tool definitions and recreates them
-- pointing to the latest implementations in &&INSTALL_SCHEMA.oci_network_load_balancer_agents.
-------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE initialize_network_load_balancer_tools
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
  -- Shared discovery tools (used by tasks in this repo)
  drop_tool_if_exists(tool_name => 'LIST_SUBSCRIBED_REGIONS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_SUBSCRIBED_REGIONS_TOOL',
    attributes => '{
      "instruction": "Lists subscribed OCI regions for the tenancy. Use to help the user choose a region.",
      "function": "oci_network_load_balancer_agents.list_subscribed_regions"
    }',
    description => 'Tool for listing subscribed OCI regions'
  );

  drop_tool_if_exists(tool_name => 'LIST_COMPARTMENTS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_COMPARTMENTS_TOOL',
    attributes => '{
      "instruction": "Lists compartments in the tenancy. Use to help the user choose a compartment for NLB operations.",
      "function": "oci_network_load_balancer_agents.list_compartments"
    }',
    description => 'Tool for listing compartments in the tenancy'
  );

  -- NLB tools
  drop_tool_if_exists(tool_name => 'GET_LISTENER_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_LISTENER_TOOL',
    attributes => '{
      "instruction": "Retrieve a specific listener from an OCI Network Load Balancer.",
      "function": "oci_network_load_balancer_agents.get_listener"
    }',
    description => 'Tool for fetching an OCI NLB listener'
  );

  drop_tool_if_exists(tool_name => 'LIST_LISTENERS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_LISTENERS_TOOL',
    attributes => '{
      "instruction": "List all listeners associated with a specified OCI Network Load Balancer.",
      "function": "oci_network_load_balancer_agents.list_listeners"
    }',
    description => 'Tool for listing OCI NLB listeners'
  );

  drop_tool_if_exists(tool_name => 'DELETE_LISTENER_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'DELETE_LISTENER_TOOL',
    attributes => '{
      "instruction": "Delete a listener from a specified OCI Network Load Balancer (confirm before calling).",
      "function": "oci_network_load_balancer_agents.delete_listener"
    }',
    description => 'Tool for deleting an OCI NLB listener'
  );

  drop_tool_if_exists(tool_name => 'DELETE_NETWORK_LOAD_BALANCER_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'DELETE_NETWORK_LOAD_BALANCER_TOOL',
    attributes => '{
      "instruction": "Delete an OCI Network Load Balancer resource by its OCID (confirm before calling).",
      "function": "oci_network_load_balancer_agents.delete_network_load_balancer"
    }',
    description => 'Tool for deleting an OCI Network Load Balancer'
  );

  drop_tool_if_exists(tool_name => 'CREATE_NETWORK_LOAD_BALANCER_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'CREATE_NETWORK_LOAD_BALANCER_TOOL',
    attributes => '{
      "instruction": "Create a new OCI Network Load Balancer. Collect required inputs step-by-step and explain parameters with examples when asked.",
      "function": "oci_network_load_balancer_agents.create_network_load_balancer"
    }',
    description => 'Tool for creating an OCI Network Load Balancer'
  );

  drop_tool_if_exists(tool_name => 'CREATE_LISTENER_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'CREATE_LISTENER_TOOL',
    attributes => '{
      "instruction": "Create a listener for an existing OCI Network Load Balancer.",
      "function": "oci_network_load_balancer_agents.create_listener"
    }',
    description => 'Tool for creating a listener on an OCI Network Load Balancer'
  );

  drop_tool_if_exists(tool_name => 'CHANGE_NLB_COMPARTMENT_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'CHANGE_NLB_COMPARTMENT_TOOL',
    attributes => '{
      "instruction": "Move an OCI Network Load Balancer to a different compartment.",
      "function": "oci_network_load_balancer_agents.change_nlb_compartment"
    }',
    description => 'Tool for changing the compartment of an OCI Network Load Balancer'
  );

  drop_tool_if_exists(tool_name => 'LIST_BACKEND_SETS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_BACKEND_SETS_TOOL',
    attributes => '{
      "instruction": "List backend sets configured on an OCI Network Load Balancer.",
      "function": "oci_network_load_balancer_agents.list_backend_sets"
    }',
    description => 'Tool for listing backend sets of an OCI Network Load Balancer'
  );

  drop_tool_if_exists(tool_name => 'LIST_BACKENDS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_BACKENDS_TOOL',
    attributes => '{
      "instruction": "List backend servers within a specified backend set on an OCI Network Load Balancer.",
      "function": "oci_network_load_balancer_agents.list_backends"
    }',
    description => 'Tool for listing backends in a backend set of an OCI Network Load Balancer'
  );

  drop_tool_if_exists(tool_name => 'LIST_NLB_HEALTHS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_NLB_HEALTHS_TOOL',
    attributes => '{
      "instruction": "List health summary status for all network load balancers in a compartment.",
      "function": "oci_network_load_balancer_agents.list_nlb_healths"
    }',
    description => 'Tool for listing health summaries of network load balancers in a compartment'
  );

  drop_tool_if_exists(tool_name => 'LIST_NLB_POLICIES_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_NLB_POLICIES_TOOL',
    attributes => '{
      "instruction": "List available load balancer policies for OCI Network Load Balancers.",
      "function": "oci_network_load_balancer_agents.list_nlb_policies"
    }',
    description => 'Tool for listing NLB policies'
  );

  drop_tool_if_exists(tool_name => 'LIST_NLB_PROTOCOLS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_NLB_PROTOCOLS_TOOL',
    attributes => '{
      "instruction": "List supported protocols for OCI Network Load Balancers (deprecated endpoint).",
      "function": "oci_network_load_balancer_agents.list_nlb_protocols"
    }',
    description => 'Tool for listing NLB protocols (deprecated)'
  );

  drop_tool_if_exists(tool_name => 'LIST_NETWORK_LOAD_BALANCERS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_NETWORK_LOAD_BALANCERS_TOOL',
    attributes => '{
      "instruction": "List all network load balancers in a compartment.",
      "function": "oci_network_load_balancer_agents.list_network_load_balancers"
    }',
    description => 'Tool for listing network load balancers in a compartment'
  );

  drop_tool_if_exists(tool_name => 'UPDATE_NETWORK_LOAD_BALANCER_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'UPDATE_NETWORK_LOAD_BALANCER_TOOL',
    attributes => '{
      "instruction": "Update a network load balancer (display name, tags, preserve flag, IP version).",
      "function": "oci_network_load_balancer_agents.update_network_load_balancer"
    }',
    description => 'Tool for updating a network load balancer'
  );

  drop_tool_if_exists(tool_name => 'UPDATE_LISTENER_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'UPDATE_LISTENER_TOOL',
    attributes => '{
      "instruction": "Update a listener on a network load balancer.",
      "function": "oci_network_load_balancer_agents.update_listener"
    }',
    description => 'Tool for updating a listener'
  );

  drop_tool_if_exists(tool_name => 'CREATE_BACKEND_SET_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'CREATE_BACKEND_SET_TOOL',
    attributes => '{
      "instruction": "Create a backend set on a network load balancer.",
      "function": "oci_network_load_balancer_agents.create_backend_set"
    }',
    description => 'Tool for creating a backend set'
  );

  DBMS_OUTPUT.PUT_LINE('initialize_network_load_balancer_tools completed.');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error in initialize_network_load_balancer_tools: ' || SQLERRM);
    RAISE;
END initialize_network_load_balancer_tools;
/

-------------------------------------------------------------------------------
-- Call the procedure to (re)create all OCI NLB AI Agent tools
-------------------------------------------------------------------------------
BEGIN
  initialize_network_load_balancer_tools;
END;
/

alter session set current_schema = ADMIN;
