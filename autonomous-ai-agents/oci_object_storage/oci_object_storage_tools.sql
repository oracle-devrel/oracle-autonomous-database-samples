rem ============================================================================
rem LICENSE
rem   Copyright (c) 2025 Oracle and/or its affiliates.
rem   Licensed under the Universal Permissive License (UPL), Version 1.0
rem   https://oss.oracle.com/licenses/upl/
rem
rem NAME
rem   oci_object_storage_tools.sql
rem
rem DESCRIPTION
rem   Installer script for OCI Object Storage AI tools
rem   (Select AI Agent / Oracle AI Database).
rem
rem   This script installs a consolidated PL/SQL package and registers
rem   AI Agent tools used to automate OCI Object Storage operations
rem   via Select AI Agent (Oracle AI Database).
rem
rem RELEASE VERSION
rem   1.1
rem
rem RELEASE DATE
rem   6-Feb-2026
rem
rem MAJOR CHANGES IN THIS RELEASE
rem   - Run Compatibility with Web SQL Developer
rem
rem SCRIPT STRUCTURE
rem   1. Initialization:
rem        - Grants
rem        - Configuration setup
rem
rem   2. Package Deployment:
rem        - &&SCHEMA_NAME.oci_object_storage_agents
rem          (package specification and body)
rem
rem   3. AI Tool Setup:
rem        - Creation of all Object Storage agent tools
rem
rem INSTALL INSTRUCTIONS
rem   1. Connect as ADMIN or a user with required privileges
rem
rem   2. Run the script using SQL*Plus or SQLcl:
rem
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
rem       * credential_name (string)
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
-- Initializes the OCI Object Storage AI Agent. This procedure:
--   • Grants all required DBMS_CLOUD_OCI Object Storage type privileges.
--   • Creates the SELECTAI_AGENT_CONFIG table.
--   • Parses the JSON config and persists credential, compartment.
-- Ensures the Object Storage agent is fully ready for tool execution.
-------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE initialize_object_storage_agent(
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
  c_obs_agent CONSTANT VARCHAR2(64) := 'OCI_OBJECT_STORAGE';

  TYPE priv_list_t IS VARRAY(300) OF VARCHAR2(4000);
  l_priv_list CONSTANT priv_list_t := priv_list_t(
    'DBMS_CLOUD',
    'DBMS_CLOUD_ADMIN',
    'DBMS_CLOUD_AI_AGENT',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_OBJECTS_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_OBJECT_VERSIONS_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_LIST_OBJECTS_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_BUCKET_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_BUCKET_SUMMARY_TBL',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_OBJECT_SUMMARY_TBL',
    -- Head/Get/Put object likely types (best-effort)
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_GET_OBJECT_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_PUT_OBJECT_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_HEAD_OBJECT_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_HEAD_BUCKET_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_COMMIT_MULTIPART_UPLOAD_PART_DETAILS_T',
    -- Buckets
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_GET_BUCKET_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_BUCKETS_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_CREATE_BUCKET_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_DELETE_BUCKET_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_UPDATE_BUCKET_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_UPDATE_BUCKET_DETAILS_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_MAKE_BUCKET_WRITABLE_RESPONSE_T',
    -- Namespace and metadata
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_GET_NAMESPACE_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_UPDATE_NAMESPACE_METADATA_RESPONSE_T',
    -- Lifecycle policy
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_PUT_OBJECT_LIFECYCLE_POLICY_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_OBJECT_LIFECYCLE_RULE_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_OBJECT_LIFECYCLE_RULE_TBL',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_PUT_OBJECT_LIFECYCLE_POLICY_DETAILS_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_OBJECT_NAME_FILTER_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_VARCHAR2_TBL',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_DELETE_OBJECT_LIFECYCLE_POLICY_RESPONSE_T',
    -- Multipart upload
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_CREATE_MULTIPART_UPLOAD_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_UPLOAD_PART_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_MULTIPART_UPLOADS_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_MULTIPART_UPLOAD_PARTS_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_MULTIPART_UPLOAD_PART_SUMMARY_TBL',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_COMMIT_MULTIPART_UPLOAD_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_ABORT_MULTIPART_UPLOAD_RESPONSE_T',
    -- PARs
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_CREATE_PREAUTHENTICATED_REQUEST_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_GET_PREAUTHENTICATED_REQUEST_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_PREAUTHENTICATED_REQUESTS_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_DELETE_PREAUTHENTICATED_REQUEST_RESPONSE_T',
    -- Replication
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_CREATE_REPLICATION_POLICY_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_GET_REPLICATION_POLICY_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_REPLICATION_POLICIES_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_DELETE_REPLICATION_POLICY_RESPONSE_T',
    -- Retention
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_CREATE_RETENTION_RULE_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_GET_RETENTION_RULE_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_RETENTION_RULES_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_UPDATE_RETENTION_RULE_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_DELETE_RETENTION_RULE_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_RETENTION_RULE_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_RETENTION_RULE_COLLECTION_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_DURATION_T',
    -- Work requests
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_GET_WORK_REQUEST_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_WORK_REQUESTS_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_WORK_REQUEST_ERRORS_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_WORK_REQUEST_LOGS_RESPONSE_T',
    -- Rename
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_RENAME_OBJECT_DETAILS_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_RENAME_OBJECT_RESPONSE_T',
    -- Reencrypt
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_REENCRYPT_BUCKET_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_REENCRYPT_OBJECT_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_REENCRYPT_OBJECT_DETAILS_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_SSE_CUSTOMER_KEY_DETAILS_T',
    -- Restore
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_RESTORE_OBJECTS_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_RESTORE_OBJECTS_DETAILS_T',
    -- Replication sources/policies details
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_REPLICATION_SOURCES_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_REPLICATION_SOURCE_TBL',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_REPLICATION_POLICY_SUMMARY_TBL',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_REPLICATION_POLICY_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_UPDATE_NAMESPACE_METADATA_DETAILS_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_UPDATE_RETENTION_RULE_DETAILS_T',
    -- Additional types for remaining imported functions
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_CREATE_BUCKET_DETAILS_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_COPY_OBJECT_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_COPY_OBJECT_DETAILS_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_DELETE_OBJECT_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_CREATE_MULTIPART_UPLOAD_DETAILS_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_COMMIT_MULTIPART_UPLOAD_PART_DETAILS_TBL',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_COMMIT_MULTIPART_UPLOAD_DETAILS_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_NUMBER_TBL',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_VARCHAR2_TBL',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_CREATE_PREAUTHENTICATED_REQUEST_DETAILS_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_CREATE_REPLICATION_POLICY_DETAILS_T',
    'DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_CANCEL_WORK_REQUEST_RESPONSE_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_CREATE_RETENTION_RULE_DETAILS_T',
    'DBMS_CLOUD_OCI_OBJECT_STORAGE_PREAUTHENTICATED_REQUEST_SUMMARY_T'
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
      EXCEPTION WHEN OTHERS THEN
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
    IF p_use_rp IS NULL THEN
      l_effective_use_rp := TRUE; -- default YES
    ELSE
      l_effective_use_rp := p_use_rp;
    END IF;

    IF p_credential_name IS NOT NULL THEN
      merge_config_key(p_schema, 'CREDENTIAL_NAME', p_credential_name, c_obs_agent);
    END IF;

    IF p_compartment_name IS NOT NULL THEN
      merge_config_key(p_schema, 'COMPARTMENT_NAME', p_compartment_name, c_obs_agent);
    END IF;

    l_enable_rp_str := CASE WHEN l_effective_use_rp THEN 'YES' ELSE 'NO' END;
    merge_config_key(p_schema, 'ENABLE_RESOURCE_PRINCIPAL', l_enable_rp_str, c_obs_agent);

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

  -- Grants
  execute_grants(l_schema_name, l_priv_list);

  -- Parse config JSON
  get_config(
    p_config_json       => p_config_json,
    o_use_rp            => l_use_rp,
    o_credential_name   => l_credential_name,
    o_compartment_name  => l_compartment_name,
    o_compartment_ocid  => l_compartment_ocid
  );

    -- Config table (idempotent) in target schema
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

  -- Persist config (into <schema>.SELECTAI_AGENT_CONFIG)
  apply_config(
    p_schema              => l_schema_name,
    p_use_rp              => l_use_rp,
    p_credential_name     => l_credential_name,
    p_compartment_name    => l_compartment_name,
    p_compartment_ocid    => l_compartment_ocid
  );

  DBMS_OUTPUT.PUT_LINE('initialize_object_storage_agent completed for schema ' || l_schema_name);

EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Fatal error in initialize_object_storage_agent: ' || SQLERRM);
    RAISE;
END initialize_object_storage_agent;
/

-------------------------------------------------------------------------------
-- Run the setup for the Object Storage AI agent.
-- This call applies all grants, creates the config table in the target schema,
-- and stores the runtime settings from the JSON config.
-------------------------------------------------------------------------------
BEGIN

  dbms_output.put_line('Schema entered is'||:v_schema);

  initialize_object_storage_agent(
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

/*
================================================================================
Package: OCI_OBJECT_STORAGE_AGENTS
================================================================================
Purpose
-------
This package provides a comprehensive set of PL/SQL helper functions that
expose Oracle Cloud Infrastructure (OCI) Object Storage operations as
AI-agent–callable tools for Oracle Autonomous Database Select AI / AI Agents.

The package abstracts low-level OCI REST and SDK calls and offers a clean,
JSON-based interface that can be safely consumed by:
  - Select AI Agents
  - Oracle APEX applications
  - Automation scripts
  - Conversational AI workflows

Key Capabilities
----------------
• Automatic resolution of:
  - Object Storage namespace
  - Compartment OCID
  - Credentials
  using centrally managed configuration (SELECTAI_AGENT_CONFIG)

• Read-only operations:
  - List buckets, objects, versions, multipart uploads
  - Retrieve metadata (HEAD / GET)
  - Inspect lifecycle, retention, replication, and work requests

• Write & management operations:
  - Create, update, delete buckets and objects
  - Upload objects (single & multipart)
  - Manage lifecycle policies, retention rules, replication
  - Create and manage Pre-Authenticated Requests (PAR)
  - Restore, rename, copy, re-encrypt objects and buckets

• All functions:
  - Return JSON (CLOB) responses
  - Are stateless and idempotent where possible
  - Are safe for AI-agent execution

Configuration Model
-------------------
This package relies on a configuration table (SELECTAI_AGENT_CONFIG) to store:
  - OCI credential name
  - Default compartment name / OCID
  - Other reusable parameters

End users only need to configure once; all tools reuse it automatically.

Who Is This For?
----------------
• DBAs automating OCI Object Storage from SQL
• Developers building APEX + AI integrations
• Platform teams creating reusable AI agents
• End users interacting with Object Storage via natural language

================================================================================
*/

------------------------------------------------------------------------
-- Package specification
------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE oci_object_storage_agents
AS
  /*
    Package: oci_object_storage_agents
    Purpose: collection of PL/SQL helper functions for OCI Object Storage operations
  */

  FUNCTION list_objects(
    region            IN VARCHAR2,
    bucket_name       IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION get_object(
    region            IN VARCHAR2,
    bucket_name       IN VARCHAR2,
    object_name       IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION list_buckets(
    region            IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION put_object(
    region         IN VARCHAR2,
    bucket_name    IN VARCHAR2,
    object_name    IN VARCHAR2,
    content        IN CLOB,
    content_type   IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION get_bucket(
    bucket_name       IN VARCHAR2,
    region            IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION head_bucket(
    bucket_name       IN VARCHAR2,
    region            IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION head_object(
    region            IN VARCHAR2,
    bucket_name       IN VARCHAR2,
    object_name       IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION list_object_versions(
    region            IN VARCHAR2,
    bucket_name       IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION list_multipart_uploads(
    region            IN VARCHAR2,
    bucket_name       IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION list_multipart_upload_parts(
    region            IN VARCHAR2,
    bucket_name       IN VARCHAR2,
    object_name       IN VARCHAR2,
    upload_id         IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION update_bucket(
    bucket_name            IN VARCHAR2,
    display_name           IN VARCHAR2,
    region                 IN VARCHAR2,
    versioning             IN VARCHAR2,
    public_access_type     IN VARCHAR2,
    object_events_enabled  IN NUMBER
  ) RETURN CLOB;

  FUNCTION make_bucket_writable(
    region       IN VARCHAR2,
    bucket_name  IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION put_object_lifecycle_policy(
    region        IN VARCHAR2,
    bucket_name   IN VARCHAR2,
    action        IN VARCHAR2,
    time_amount   IN NUMBER,
    time_unit     IN VARCHAR2,
    rule_name     IN VARCHAR2 DEFAULT 'demo-rule'
  ) RETURN CLOB;

  FUNCTION list_retention_rules(
    region       IN VARCHAR2,
    bucket_name  IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION get_retention_rule(
    region            IN VARCHAR2,
    bucket_name       IN VARCHAR2,
    retention_rule_id IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION list_preauthenticated_requests(
    region       IN VARCHAR2,
    bucket_name  IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION list_replication_policies(
    region       IN VARCHAR2,
    bucket_name  IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION get_replication_policy(
    region          IN VARCHAR2,
    bucket_name     IN VARCHAR2,
    replication_id  IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION list_replication_sources(
    region       IN VARCHAR2,
    bucket_name  IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION reencrypt_bucket(
    region       IN VARCHAR2,
    bucket_name  IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION reencrypt_object(
    region        IN VARCHAR2,
    bucket_name   IN VARCHAR2,
    object_name   IN VARCHAR2,
    kms_key_id    IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION rename_object(
    region        IN VARCHAR2,
    bucket_name   IN VARCHAR2,
    source_object IN VARCHAR2,
    new_object    IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION restore_objects(
    region        IN VARCHAR2,
    bucket_name   IN VARCHAR2,
    object_name   IN VARCHAR2,
    hours         IN NUMBER DEFAULT 24,
    version_id    IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION upload_part(
    region           IN VARCHAR2,
    bucket_name      IN VARCHAR2,
    object_name      IN VARCHAR2,
    upload_id        IN VARCHAR2,
    upload_part_num  IN NUMBER,
    upload_part_body IN BLOB,
    content_length   IN NUMBER
  ) RETURN CLOB;

  FUNCTION update_namespace_metadata(
    region           IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION update_retention_rule(
    region           IN VARCHAR2,
    bucket_name      IN VARCHAR2,
    rule_id          IN VARCHAR2,
    new_display_name IN VARCHAR2,
    duration_amount  IN NUMBER,
    time_unit        IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION list_work_requests(
    region           IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION list_work_request_errors(
    work_request_id IN VARCHAR2,
    region          IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION list_work_request_logs(
    work_request_id IN VARCHAR2,
    region          IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION get_work_request(
    work_request_id IN VARCHAR2,
    region          IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION create_bucket(
    bucket_name       IN VARCHAR2,
    region            IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION delete_bucket(
    bucket_name       IN VARCHAR2,
    region            IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION delete_object(
    region            IN VARCHAR2,
    bucket_name       IN VARCHAR2,
    object_name       IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION copy_object(
    region                  IN VARCHAR2,
    bucket_name             IN VARCHAR2,
    source_object_name      IN VARCHAR2,
    destination_region      IN VARCHAR2,
    destination_bucket_name IN VARCHAR2,
    destination_object_name IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION create_multipart_upload(
    region         IN VARCHAR2,
    bucket_name    IN VARCHAR2,
    object_name    IN VARCHAR2,
    content_type   IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION commit_multipart_upload(
    region          IN VARCHAR2,
    bucket_name     IN VARCHAR2,
    object_name     IN VARCHAR2,
    upload_id       IN VARCHAR2,
    part_num_arr    IN DBMS_CLOUD_OCI_OBJECT_STORAGE_NUMBER_TBL,
    etag_arr        IN DBMS_CLOUD_OCI_OBJECT_STORAGE_VARCHAR2_TBL
  ) RETURN CLOB;

  FUNCTION abort_multipart_upload(
    region          IN VARCHAR2,
    bucket_name     IN VARCHAR2,
    object_name     IN VARCHAR2,
    upload_id       IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION create_preauthenticated_request(
    region           IN VARCHAR2,
    bucket_name      IN VARCHAR2,
    name             IN VARCHAR2,
    object_name      IN VARCHAR2,
    access_type      IN VARCHAR2,
    listing_action   IN VARCHAR2 DEFAULT 'Deny',
    time_expires     IN TIMESTAMP WITH TIME ZONE
  ) RETURN CLOB;

  FUNCTION get_preauthenticated_request(
    region           IN VARCHAR2,
    bucket_name      IN VARCHAR2,
    par_id           IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION delete_preauthenticated_request(
    region           IN VARCHAR2,
    bucket_name      IN VARCHAR2,
    par_id           IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION create_replication_policy(
    region                    IN VARCHAR2,
    bucket_name               IN VARCHAR2,
    destination_region_name   IN VARCHAR2,
    destination_bucket_name   IN VARCHAR2,
    policy_name               IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION delete_replication_policy(
    region          IN VARCHAR2,
    bucket_name     IN VARCHAR2,
    replication_id  IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION create_retention_rule(
    region           IN VARCHAR2,
    bucket_name      IN VARCHAR2,
    display_name     IN VARCHAR2,
    duration_amount  IN NUMBER,
    time_unit        IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION delete_retention_rule(
    region            IN VARCHAR2,
    bucket_name       IN VARCHAR2,
    retention_rule_id IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION delete_object_lifecycle_policy(
    region       IN VARCHAR2,
    bucket_name  IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION cancel_work_request(
    work_request_id IN VARCHAR2,
    region          IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION get_namespace(
    region           IN VARCHAR2
  ) RETURN CLOB;


END oci_object_storage_agents;
/
------------------------------------------------------------------------
-- Package body
------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY oci_object_storage_agents
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
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
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
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
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
  -- list_objects: List all objects in a bucket (uses namespace lookup API)
  ----------------------------------------------------------------------
  FUNCTION list_objects(
    region            IN VARCHAR2,
    bucket_name       IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp                DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_OBJECTS_RESPONSE_T;
    l_objs                DBMS_CLOUD_OCI_OBJECT_STORAGE_LIST_OBJECTS_T;
    l_items               DBMS_CLOUD_OCI_OBJECT_STORAGE_OBJECT_SUMMARY_TBL;
    result_json           JSON_OBJECT_T := JSON_OBJECT_T();
    objects_arr           JSON_ARRAY_T := JSON_ARRAY_T();
    l_current_user        VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
    l_cfg_json            CLOB;
    l_cfg                 JSON_OBJECT_T;
    l_params              JSON_OBJECT_T;
    credential_name       VARCHAR2(256);
    namespace             VARCHAR2(256);
    compartment_id        VARCHAR2(256);
  BEGIN
    -- Load credential from config
    l_cfg_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status') = 'success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    -- Call LIST_OBJECTS API
    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.LIST_OBJECTS(
      namespace_name  => namespace,
      bucket_name     => bucket_name,
      region          => region,
      credential_name => credential_name
    );

    l_objs  := l_resp.response_body;
    l_items := l_objs.objects;

    FOR i IN 1 .. l_items.COUNT LOOP
      DECLARE
        l_obj_json JSON_OBJECT_T := JSON_OBJECT_T();
      BEGIN
        l_obj_json.put('name',         l_items(i).name);
        l_obj_json.put('size',         l_items(i).l_size);
        l_obj_json.put('etag',         l_items(i).etag);
        l_obj_json.put('storage_tier', l_items(i).storage_tier);
        IF l_items(i).time_created IS NOT NULL THEN
          l_obj_json.put('time_created', TO_CHAR(l_items(i).time_created, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
        END IF;
        objects_arr.append(l_obj_json);
      END;
    END LOOP;

    result_json.put('namespace',     namespace);
    result_json.put('bucket',        bucket_name);
    result_json.put('region',        region);
    result_json.put('object_count',  l_items.COUNT);
    result_json.put('objects',       objects_arr);
    result_json.put('status_code',   l_resp.status_code);

    RETURN result_json.to_clob();

  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status', 'error');
      result_json.put('message', SQLERRM);
      result_json.put('bucket', bucket_name);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END list_objects;

  ----------------------------------------------------------------------
  -- list_buckets: List all buckets in a compartment
  ----------------------------------------------------------------------
  FUNCTION list_buckets(
    region            IN VARCHAR2
  ) RETURN CLOB
  AS
    resp              DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_BUCKETS_RESPONSE_T;
    body              DBMS_CLOUD_OCI_OBJECT_STORAGE_BUCKET_SUMMARY_TBL;
    result_json       JSON_OBJECT_T := JSON_OBJECT_T();
    buckets_arr       JSON_ARRAY_T := JSON_ARRAY_T();
    l_current_user    VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
    l_cfg_json        CLOB;
    l_cfg             JSON_OBJECT_T;
    l_params          JSON_OBJECT_T;
    credential_name   VARCHAR2(256);
    compartment_id    VARCHAR2(128);
    namespace         VARCHAR2(256);
  BEGIN
    -- Load credential and optional default compartment OCID from config
    l_cfg_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status') = 'success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    -- Call LIST_BUCKETS API
    resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.LIST_BUCKETS(
      namespace_name  => namespace,
      compartment_id  => compartment_id,
      region          => region,
      credential_name => credential_name
    );

    body := resp.response_body;

    -- Build JSON result
    result_json.put('status', 'success');
    result_json.put('region', region);
    result_json.put('total_buckets', body.COUNT);

    FOR i IN 1 .. body.COUNT LOOP
      buckets_arr.append(
        JSON_OBJECT(
          'name'         VALUE body(i).name,
          'compartment'  VALUE body(i).compartment_id,
          'time_created' VALUE TO_CHAR(body(i).time_created, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        )
      );
    END LOOP;

    result_json.put('buckets', buckets_arr);

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status', 'error');
      result_json.put('message', SQLERRM);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END list_buckets;

  ----------------------------------------------------------------------
  -- get_bucket: Retrieve bucket metadata (summary)
  ----------------------------------------------------------------------
  FUNCTION get_bucket(
    bucket_name       IN VARCHAR2,
    region            IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp          DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_GET_BUCKET_RESPONSE_T;
    l_bucket        DBMS_CLOUD_OCI_OBJECT_STORAGE_BUCKET_T;
    l_json          JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
    l_cfg_json      CLOB;
    l_cfg           JSON_OBJECT_T;
    l_params        JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    -- Load credential from config
    l_cfg_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status') = 'success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    -- Call GET_BUCKET with selected fields
    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.GET_BUCKET(
      namespace_name  => namespace,
      bucket_name     => bucket_name,
      fields          => DBMS_CLOUD_OCI_OBJECT_STORAGE_VARCHAR2_TBL(
                           'approximateCount',
                           'approximateSize',
                           'autoTiering'
                         ),
      region          => region,
      credential_name => credential_name
    );

    l_bucket := l_resp.response_body;

    -- Populate JSON summary
    l_json.put('namespace',                 l_bucket.namespace);
    l_json.put('name',                      l_bucket.name);
    l_json.put('compartment_id',            l_bucket.compartment_id);
    l_json.put('created_by',                l_bucket.created_by);
    IF l_bucket.time_created IS NOT NULL THEN
      l_json.put('time_created',            TO_CHAR(l_bucket.time_created,'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
    END IF;
    l_json.put('etag',                      l_bucket.etag);
    l_json.put('public_access_type',        l_bucket.public_access_type);
    l_json.put('storage_tier',              l_bucket.storage_tier);
    l_json.put('object_events_enabled',     l_bucket.object_events_enabled);
    l_json.put('kms_key_id',                l_bucket.kms_key_id);
    l_json.put('object_lifecycle_policy_etag', l_bucket.object_lifecycle_policy_etag);
    l_json.put('approximate_count',         l_bucket.approximate_count);
    l_json.put('approximate_size',          l_bucket.approximate_size);
    l_json.put('replication_enabled',       l_bucket.replication_enabled);
    l_json.put('is_read_only',              l_bucket.is_read_only);
    l_json.put('id',                        l_bucket.id);
    l_json.put('versioning',                l_bucket.versioning);
    l_json.put('auto_tiering',              l_bucket.auto_tiering);

    -- HTTP status code
    l_json.put('status_code',               l_resp.status_code);

    RETURN l_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_json := JSON_OBJECT_T();
      l_json.put('status', 'error');
      l_json.put('message', SQLERRM);
      l_json.put('bucket_name', bucket_name);
      l_json.put('region', region);
      RETURN l_json.to_clob();
  END get_bucket;

  ----------------------------------------------------------------------
  -- head_bucket: Retrieve bucket metadata headers (HEAD_BUCKET)
  ----------------------------------------------------------------------
  FUNCTION head_bucket(
    bucket_name       IN VARCHAR2,
    region            IN VARCHAR2
  ) RETURN CLOB
  AS
    l_response     DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_HEAD_BUCKET_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    -- Load credential from config
    l_cfg_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status') = 'success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    -- Call HEAD_BUCKET API
    l_response := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.HEAD_BUCKET(
      namespace_name        => namespace,
      bucket_name           => bucket_name,
      if_match              => NULL,
      if_none_match         => NULL,
      opc_client_request_id => NULL,
      region                => region,
      endpoint              => NULL,
      credential_name       => credential_name
    );

    -- Construct JSON response
    IF l_response.headers IS NOT NULL THEN
      result_json.put('headers', l_response.headers);
    END IF;
    result_json.put('status_code', l_response.status_code);

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status', 'error');
      result_json.put('message', 'Failed to HEAD bucket: ' || SQLERRM);
      result_json.put('bucket_name', bucket_name);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END head_bucket;

  ----------------------------------------------------------------------
  -- head_object: Retrieve object metadata headers (HEAD_OBJECT)
  ----------------------------------------------------------------------
  FUNCTION head_object(
    region            IN VARCHAR2,
    bucket_name       IN VARCHAR2,
    object_name       IN VARCHAR2
  ) RETURN CLOB
  AS
    l_response     DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_HEAD_OBJECT_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    -- Load credential from config
    l_cfg_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status') = 'success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    -- Call HEAD_OBJECT API
    l_response := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.HEAD_OBJECT(
      namespace_name   => namespace,
      bucket_name      => bucket_name,
      object_name      => object_name,
      region           => region,
      credential_name  => credential_name
    );

    -- Construct JSON response
    IF l_response.headers IS NOT NULL THEN
      result_json.put('headers', l_response.headers);
    END IF;
    result_json.put('status_code', l_response.status_code);

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status', 'error');
      result_json.put('message', 'Failed to HEAD object: ' || SQLERRM);
      result_json.put('bucket_name', bucket_name);
      result_json.put('object_name', object_name);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END head_object;

  ----------------------------------------------------------------------
  -- list_object_versions: List all versions of objects in a bucket
  ----------------------------------------------------------------------
  FUNCTION list_object_versions(
    region            IN VARCHAR2,
    bucket_name       IN VARCHAR2
  ) RETURN CLOB
  AS
    l_response     DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_OBJECT_VERSIONS_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    versions_arr   JSON_ARRAY_T := JSON_ARRAY_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    -- Load credential from config
    l_cfg_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status') = 'success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    -- Call LIST_OBJECT_VERSIONS API
    l_response := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.LIST_OBJECT_VERSIONS(
      namespace_name  => namespace,
      bucket_name     => bucket_name,
      region          => region,
      credential_name => credential_name
    );

    -- Convert versions to JSON array
    IF l_response.response_body IS NOT NULL AND l_response.response_body.items IS NOT NULL THEN
      FOR i IN 1 .. l_response.response_body.items.COUNT LOOP
        DECLARE
          l_item JSON_OBJECT_T := JSON_OBJECT_T();
        BEGIN
          l_item.put('name',             l_response.response_body.items(i).name);
          l_item.put('size',             l_response.response_body.items(i).l_size);
          l_item.put('etag',             l_response.response_body.items(i).etag);
          l_item.put('md5',              l_response.response_body.items(i).md5);
          l_item.put('version_id',       l_response.response_body.items(i).version_id);
          l_item.put('is_delete_marker', l_response.response_body.items(i).is_delete_marker);
          l_item.put('archival_state',   l_response.response_body.items(i).archival_state);
          l_item.put('storage_tier',     l_response.response_body.items(i).storage_tier);
          IF l_response.response_body.items(i).time_created IS NOT NULL THEN
            l_item.put('time_created',  TO_CHAR(l_response.response_body.items(i).time_created, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
          END IF;
          IF l_response.response_body.items(i).time_modified IS NOT NULL THEN
            l_item.put('time_modified', TO_CHAR(l_response.response_body.items(i).time_modified, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
          END IF;
          versions_arr.append(l_item);
        END;
      END LOOP;
    END IF;

    -- Compose final JSON
    result_json.put('status_code', l_response.status_code);
    result_json.put('object_versions', versions_arr);

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status', 'error');
      result_json.put('message', SQLERRM);
      result_json.put('bucket_name', bucket_name);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END list_object_versions;

  ----------------------------------------------------------------------
  -- list_multipart_uploads: List all multipart uploads in a bucket
  ----------------------------------------------------------------------
  FUNCTION list_multipart_uploads(
    region            IN VARCHAR2,
    bucket_name       IN VARCHAR2
  ) RETURN CLOB
  AS
    l_response     DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_MULTIPART_UPLOADS_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    uploads_arr    JSON_ARRAY_T := JSON_ARRAY_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    -- Load credential from config
    l_cfg_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status') = 'success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    -- Call LIST_MULTIPART_UPLOADS API
    l_response := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.LIST_MULTIPART_UPLOADS(
      namespace_name  => namespace,
      bucket_name     => bucket_name,
      region          => region,
      credential_name => credential_name
    );

    -- Convert results
    IF l_response.response_body IS NOT NULL THEN
      FOR i IN 1 .. l_response.response_body.COUNT LOOP
        DECLARE
          l_item JSON_OBJECT_T := JSON_OBJECT_T();
        BEGIN
          l_item.put('object',       l_response.response_body(i).object);
          l_item.put('upload_id',    l_response.response_body(i).upload_id);
          l_item.put('storage_tier', l_response.response_body(i).storage_tier);
          IF l_response.response_body(i).time_created IS NOT NULL THEN
            l_item.put('time_created', TO_CHAR(l_response.response_body(i).time_created, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
          END IF;
          uploads_arr.append(l_item);
        END;
      END LOOP;
    END IF;

    -- Compose final JSON
    result_json.put('status_code', l_response.status_code);
    result_json.put('multipart_uploads', uploads_arr);
    IF l_response.headers IS NOT NULL THEN
      result_json.put('headers', l_response.headers);
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status', 'error');
      result_json.put('message', SQLERRM);
      result_json.put('bucket_name', bucket_name);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END list_multipart_uploads;

  ----------------------------------------------------------------------
  -- list_multipart_upload_parts: List all parts of a multipart upload
  ----------------------------------------------------------------------
  FUNCTION list_multipart_upload_parts(
    region            IN VARCHAR2,
    bucket_name       IN VARCHAR2,
    object_name       IN VARCHAR2,
    upload_id         IN VARCHAR2
  ) RETURN CLOB
  AS
    l_response     DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_MULTIPART_UPLOAD_PARTS_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    parts_arr      JSON_ARRAY_T := JSON_ARRAY_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    -- Load credential from config
    l_cfg_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status') = 'success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    -- Call LIST_MULTIPART_UPLOAD_PARTS API
    l_response := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.LIST_MULTIPART_UPLOAD_PARTS(
      namespace_name  => namespace,
      bucket_name     => bucket_name,
      object_name     => object_name,
      upload_id       => upload_id,
      region          => region,
      credential_name => credential_name
    );

    -- Convert parts to JSON array
    IF l_response.response_body IS NOT NULL THEN
      FOR i IN 1 .. l_response.response_body.COUNT LOOP
        DECLARE
          l_item JSON_OBJECT_T := JSON_OBJECT_T();
        BEGIN
          l_item.put('part_number', l_response.response_body(i).part_number);
          l_item.put('etag',        l_response.response_body(i).etag);
          l_item.put('md5',         l_response.response_body(i).md5);
          l_item.put('size',        l_response.response_body(i).l_size);
          parts_arr.append(l_item);
        END;
      END LOOP;
    END IF;

    -- Compose final JSON
    result_json.put('status_code', l_response.status_code);
    result_json.put('multipart_upload_parts', parts_arr);

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status', 'error');
      result_json.put('message', SQLERRM);
      result_json.put('bucket_name', bucket_name);
      result_json.put('object_name', object_name);
      result_json.put('upload_id', upload_id);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END list_multipart_upload_parts;

  ----------------------------------------------------------------------
  -- update_bucket: Update bucket properties (uses config + GET_NAMESPACE)
  ----------------------------------------------------------------------
  FUNCTION update_bucket(
    bucket_name            IN VARCHAR2,
    display_name           IN VARCHAR2,
    region                 IN VARCHAR2,
    versioning             IN VARCHAR2,
    public_access_type     IN VARCHAR2,
    object_events_enabled  IN NUMBER
  ) RETURN CLOB
  AS
    l_details       DBMS_CLOUD_OCI_OBJECT_STORAGE_UPDATE_BUCKET_DETAILS_T;
    l_response      DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_UPDATE_BUCKET_RESPONSE_T;
    result_json     JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
    l_cfg_json      CLOB;
    l_cfg           JSON_OBJECT_T;
    l_params        JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    compartment_id  VARCHAR2(256);
    namespace       VARCHAR2(256);
  BEGIN
    -- Load config (credential, compartment OCID)
    l_cfg_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status') = 'success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
      compartment_id  := l_params.get_string('COMPARTMENT_OCID');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    -- Build update details
    l_details := DBMS_CLOUD_OCI_OBJECT_STORAGE_UPDATE_BUCKET_DETAILS_T(
      namespace             => namespace,
      compartment_id        => compartment_id,
      name                  => display_name,
      metadata              => NULL,
      public_access_type    => public_access_type,
      object_events_enabled => object_events_enabled,
      freeform_tags         => NULL,
      defined_tags          => NULL,
      kms_key_id            => NULL,
      versioning            => versioning,
      auto_tiering          => NULL
    );

    -- Call UPDATE_BUCKET
    l_response := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.UPDATE_BUCKET(
      namespace_name        => namespace,
      bucket_name           => bucket_name,
      update_bucket_details => l_details,
      region                => region,
      credential_name       => credential_name
    );

    -- Compose result
    result_json.put('namespace',             namespace);
    result_json.put('bucket_name',           bucket_name);
    result_json.put('display_name',          display_name);
    result_json.put('compartment_id',        compartment_id);
    result_json.put('region',                region);
    result_json.put('versioning',            versioning);
    result_json.put('public_access_type',    public_access_type);
    result_json.put('object_events_enabled', object_events_enabled);
    result_json.put('status_code',           l_response.status_code);
    IF l_response.headers IS NOT NULL THEN
      result_json.put('headers', l_response.headers);
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status', 'error');
      result_json.put('message', SQLERRM);
      result_json.put('bucket_name', bucket_name);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END update_bucket;

  ----------------------------------------------------------------------
  -- make_bucket_writable: Make a bucket writable
  ----------------------------------------------------------------------
  FUNCTION make_bucket_writable(
    region       IN VARCHAR2,
    bucket_name  IN VARCHAR2
  ) RETURN CLOB
  AS
    l_response     DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_MAKE_BUCKET_WRITABLE_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    -- Load credential from config
    l_cfg_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status') = 'success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    -- Call MAKE_BUCKET_WRITABLE API
    l_response := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.MAKE_BUCKET_WRITABLE(
      namespace_name  => namespace,
      bucket_name     => bucket_name,
      region          => region,
      credential_name => credential_name
    );

    -- Build JSON response
    result_json.put('namespace',    namespace);
    result_json.put('bucket_name',  bucket_name);
    result_json.put('region',       region);
    result_json.put('status_code',  l_response.status_code);

    IF l_response.headers IS NOT NULL THEN
      IF l_response.headers.has('opc-request-id') THEN
        result_json.put('opc_request_id', l_response.headers.get_string('opc-request-id'));
      END IF;
      IF l_response.headers.has('etag') THEN
        result_json.put('etag', l_response.headers.get_string('etag'));
      END IF;
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status', 'error');
      result_json.put('message', 'Failed to make bucket writable: ' || SQLERRM);
      result_json.put('bucket_name', bucket_name);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END make_bucket_writable;

  ----------------------------------------------------------------------
  -- put_object_lifecycle_policy: Apply lifecycle policy to a bucket
  ----------------------------------------------------------------------
  FUNCTION put_object_lifecycle_policy(
    region        IN VARCHAR2,
    bucket_name   IN VARCHAR2,
    action        IN VARCHAR2,
    time_amount   IN NUMBER,
    time_unit     IN VARCHAR2,
    rule_name     IN VARCHAR2 DEFAULT 'demo-rule'
  ) RETURN CLOB
  AS
    l_resp        DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_PUT_OBJECT_LIFECYCLE_POLICY_RESPONSE_T;
    l_filter      DBMS_CLOUD_OCI_OBJECT_STORAGE_OBJECT_NAME_FILTER_T;
    l_rule        DBMS_CLOUD_OCI_OBJECT_STORAGE_OBJECT_LIFECYCLE_RULE_T;
    l_rule_list   DBMS_CLOUD_OCI_OBJECT_STORAGE_OBJECT_LIFECYCLE_RULE_TBL;
    l_policy      DBMS_CLOUD_OCI_OBJECT_STORAGE_PUT_OBJECT_LIFECYCLE_POLICY_DETAILS_T;
    result_json   JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    -- Load credential from config
    l_cfg_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status') = 'success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    -- Construct object name filter with empty include/exclude lists
    l_filter := DBMS_CLOUD_OCI_OBJECT_STORAGE_OBJECT_NAME_FILTER_T(
      DBMS_CLOUD_OCI_OBJECT_STORAGE_VARCHAR2_TBL(),
      DBMS_CLOUD_OCI_OBJECT_STORAGE_VARCHAR2_TBL(),
      DBMS_CLOUD_OCI_OBJECT_STORAGE_VARCHAR2_TBL()
    );

    -- Construct lifecycle rule
    l_rule := DBMS_CLOUD_OCI_OBJECT_STORAGE_OBJECT_LIFECYCLE_RULE_T(
      name               => NVL(rule_name, 'demo-rule'),
      target             => 'objects',
      action             => action,
      time_amount        => time_amount,
      time_unit         => time_unit,
      is_enabled         => 1,
      object_name_filter => l_filter
    );

    -- Build rule list and policy
    l_rule_list := DBMS_CLOUD_OCI_OBJECT_STORAGE_OBJECT_LIFECYCLE_RULE_TBL(l_rule);
    l_policy    := DBMS_CLOUD_OCI_OBJECT_STORAGE_PUT_OBJECT_LIFECYCLE_POLICY_DETAILS_T(l_rule_list);

    -- Call API
    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.PUT_OBJECT_LIFECYCLE_POLICY(
      namespace_name                    => namespace,
      bucket_name                       => bucket_name,
      put_object_lifecycle_policy_details => l_policy,
      region                            => region,
      credential_name                   => credential_name
    );

    -- Result
    result_json.put('bucket_name', bucket_name);
    result_json.put('region',      region);
    result_json.put('status_code', l_resp.status_code);

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status', 'error');
      result_json.put('message', SQLERRM);
      result_json.put('bucket_name', bucket_name);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END put_object_lifecycle_policy;

  ----------------------------------------------------------------------
  -- list_retention_rules: List retention rules for a bucket
  ----------------------------------------------------------------------
  FUNCTION list_retention_rules(
    region       IN VARCHAR2,
    bucket_name  IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp         DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_RETENTION_RULES_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    rules_arr      JSON_ARRAY_T := JSON_ARRAY_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    -- Load credential from config
    l_cfg_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status') = 'success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    -- Call LIST_RETENTION_RULES API
    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.LIST_RETENTION_RULES(
      namespace_name  => namespace,
      bucket_name     => bucket_name,
      region          => region,
      credential_name => credential_name
    );

    -- Metadata
    result_json.put('namespace', namespace);
    result_json.put('bucket',    bucket_name);
    result_json.put('region',    region);
    result_json.put('status_code', l_resp.status_code);

    -- Optional headers
    IF l_resp.headers IS NOT NULL THEN
      IF l_resp.headers.has('opc-request-id') THEN
        result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
      END IF;
      IF l_resp.headers.has('etag') THEN
        result_json.put('etag', l_resp.headers.get_string('etag'));
      END IF;
    END IF;

    -- Rules
    IF l_resp.response_body IS NOT NULL AND l_resp.response_body.items IS NOT NULL THEN
      FOR i IN 1 .. l_resp.response_body.items.COUNT LOOP
        DECLARE
          l_rule_json JSON_OBJECT_T := JSON_OBJECT_T();
          l_dur_json  JSON_OBJECT_T := NULL;
        BEGIN
          l_rule_json.put('id',           l_resp.response_body.items(i).id);
          l_rule_json.put('display_name', l_resp.response_body.items(i).display_name);
          l_rule_json.put('etag',         l_resp.response_body.items(i).etag);

          IF l_resp.response_body.items(i).duration IS NOT NULL THEN
            l_dur_json := JSON_OBJECT_T();
            l_dur_json.put('time_amount', l_resp.response_body.items(i).duration.time_amount);
            l_dur_json.put('time_unit',   l_resp.response_body.items(i).duration.time_unit);
            l_rule_json.put('duration', l_dur_json);
          END IF;

          IF l_resp.response_body.items(i).time_rule_locked IS NOT NULL THEN
            l_rule_json.put('time_rule_locked',
              TO_CHAR(l_resp.response_body.items(i).time_rule_locked, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
          END IF;

          IF l_resp.response_body.items(i).time_created IS NOT NULL THEN
            l_rule_json.put('time_created',
              TO_CHAR(l_resp.response_body.items(i).time_created, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
          END IF;

          IF l_resp.response_body.items(i).time_modified IS NOT NULL THEN
            l_rule_json.put('time_modified',
              TO_CHAR(l_resp.response_body.items(i).time_modified, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
          END IF;

          rules_arr.append(l_rule_json);
        END;
      END LOOP;
    END IF;

    result_json.put('retention_rules', rules_arr);

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status', 'error');
      result_json.put('message', SQLERRM);
      result_json.put('bucket', bucket_name);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END list_retention_rules;

  ----------------------------------------------------------------------
  -- get_retention_rule: Retrieve retention rule details
  ----------------------------------------------------------------------
  FUNCTION get_retention_rule(
    region            IN VARCHAR2,
    bucket_name       IN VARCHAR2,
    retention_rule_id IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp         DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_GET_RETENTION_RULE_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    rule_json      JSON_OBJECT_T := JSON_OBJECT_T();
    dur_json       JSON_OBJECT_T;
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    -- Load credential
    l_cfg_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status') = 'success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    -- Call GET_RETENTION_RULE
    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.GET_RETENTION_RULE(
      namespace_name    => namespace,
      bucket_name       => bucket_name,
      retention_rule_id => retention_rule_id,
      region            => region,
      credential_name   => credential_name
    );

    -- Input echo + status
    result_json.put('namespace',         namespace);
    result_json.put('bucket',            bucket_name);
    result_json.put('retention_rule_id', retention_rule_id);
    result_json.put('region',            region);
    result_json.put('status_code',       l_resp.status_code);

    -- Headers (optional)
    IF l_resp.headers IS NOT NULL THEN
      IF l_resp.headers.has('opc-request-id') THEN
        result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
      END IF;
      IF l_resp.headers.has('etag') THEN
        result_json.put('etag', l_resp.headers.get_string('etag'));
      END IF;
    END IF;

    -- Rule body
    IF l_resp.response_body IS NOT NULL THEN
      rule_json.put('id',           l_resp.response_body.id);
      rule_json.put('display_name', l_resp.response_body.display_name);
      rule_json.put('etag',         l_resp.response_body.etag);

      IF l_resp.response_body.duration IS NOT NULL THEN
        dur_json := JSON_OBJECT_T();
        dur_json.put('time_amount', l_resp.response_body.duration.time_amount);
        dur_json.put('time_unit',   l_resp.response_body.duration.time_unit);
        rule_json.put('duration', dur_json);
      END IF;

      IF l_resp.response_body.time_rule_locked IS NOT NULL THEN
        rule_json.put('time_rule_locked',
          TO_CHAR(l_resp.response_body.time_rule_locked, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
      END IF;

      IF l_resp.response_body.time_created IS NOT NULL THEN
        rule_json.put('time_created',
          TO_CHAR(l_resp.response_body.time_created, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
      END IF;

      IF l_resp.response_body.time_modified IS NOT NULL THEN
        rule_json.put('time_modified',
          TO_CHAR(l_resp.response_body.time_modified, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
      END IF;

      result_json.put('retention_rule', rule_json);
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status', 'error');
      result_json.put('message', SQLERRM);
      result_json.put('bucket', bucket_name);
      result_json.put('retention_rule_id', retention_rule_id);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END get_retention_rule;

  ----------------------------------------------------------------------
  -- get_object: Retrieve object metadata (headers/summary, not payload)
  ----------------------------------------------------------------------
  FUNCTION get_object(
    region            IN VARCHAR2,
    bucket_name       IN VARCHAR2,
    object_name       IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp          DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_GET_OBJECT_RESPONSE_T;
    l_json          JSON_OBJECT_T := JSON_OBJECT_T();
    l_headers       JSON_OBJECT_T;
    l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
    l_cfg_json      CLOB;
    l_cfg           JSON_OBJECT_T;
    l_params        JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    -- Load credential from config
    l_cfg_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status') = 'success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    -- Call OCI GET_OBJECT API (metadata only)
    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.GET_OBJECT(
      namespace_name  => namespace,
      bucket_name     => bucket_name,
      object_name     => object_name,
      region          => region,
      credential_name => credential_name
    );

    l_headers := l_resp.headers;

    -- Build JSON summary
    l_json.put('namespace', namespace);
    l_json.put('bucket_name', bucket_name);
    l_json.put('object_name', object_name);
    l_json.put('region', region);
    l_json.put('status_code', l_resp.status_code);

    IF l_headers IS NOT NULL THEN
      IF l_headers.has('etag') THEN
        l_json.put('etag', l_headers.get_string('etag'));
      END IF;
      IF l_headers.has('last-modified') THEN
        l_json.put('last_modified', l_headers.get_string('last-modified'));
      END IF;
      IF l_headers.has('content-length') THEN
        l_json.put('content_length', l_headers.get_string('content-length'));
      END IF;
      IF l_headers.has('content-type') THEN
        l_json.put('content_type', l_headers.get_string('content-type'));
      END IF;
    END IF;

    RETURN l_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_json := JSON_OBJECT_T();
      l_json.put('status', 'error');
      l_json.put('message', SQLERRM);
      l_json.put('bucket_name', bucket_name);
      l_json.put('object_name', object_name);
      l_json.put('region', region);
      RETURN l_json.to_clob();
  END get_object;

  ----------------------------------------------------------------------
  -- put_object: Upload content (CLOB) as an object to a bucket
  ----------------------------------------------------------------------
  FUNCTION put_object(
    region         IN VARCHAR2,
    bucket_name    IN VARCHAR2,
    object_name    IN VARCHAR2,
    content        IN CLOB,
    content_type   IN VARCHAR2
  ) RETURN CLOB
  AS
    l_blob         BLOB;
    l_response     DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_PUT_OBJECT_RESPONSE_T;
    l_json         JSON_OBJECT_T := JSON_OBJECT_T();
    l_headers      JSON_OBJECT_T;
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    -- Load credential from config
    l_cfg_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status') = 'success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    -- Convert CLOB content to BLOB (UTF-8)
    l_blob := TO_BLOB(UTL_I18N.STRING_TO_RAW(content, 'AL32UTF8'));

    -- Upload object
    l_response := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.PUT_OBJECT(
      namespace_name  => namespace,
      bucket_name     => bucket_name,
      object_name     => object_name,
      put_object_body => l_blob,
      content_type    => content_type,
      region          => region,
      credential_name => credential_name
    );

    -- Build response JSON
    l_json.put('namespace',     namespace);
    l_json.put('bucket',        bucket_name);
    l_json.put('object_name',   object_name);
    l_json.put('region',        region);
    l_json.put('status_code',   l_response.status_code);

    IF l_response.headers IS NOT NULL THEN
      l_headers := l_response.headers;
      IF l_headers.has('opc-request-id') THEN
        l_json.put('opc_request_id', l_headers.get_string('opc-request-id'));
      END IF;
      IF l_headers.has('etag') THEN
        l_json.put('etag', l_headers.get_string('etag'));
      END IF;
    END IF;

    RETURN l_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_json := JSON_OBJECT_T();
      l_json.put('status', 'error');
      l_json.put('message', SQLERRM);
      l_json.put('bucket', bucket_name);
      l_json.put('object_name', object_name);
      l_json.put('region', region);
      RETURN l_json.to_clob();
  END put_object;

  ----------------------------------------------------------------------
  -- list_preauthenticated_requests: List PARs for a bucket
  ----------------------------------------------------------------------
  FUNCTION list_preauthenticated_requests(
    region       IN VARCHAR2,
    bucket_name  IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp         DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_PREAUTHENTICATED_REQUESTS_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    pars_arr       JSON_ARRAY_T := JSON_ARRAY_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV', 'CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    -- Load credential
    l_cfg_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status') = 'success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    -- Call API
    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.LIST_PREAUTHENTICATED_REQUESTS(
      namespace_name  => namespace,
      bucket_name     => bucket_name,
      region          => region,
      credential_name => credential_name
    );

    -- Compose result
    result_json.put('namespace', namespace);
    result_json.put('bucket',    bucket_name);
    result_json.put('region',    region);
    result_json.put('status_code', l_resp.status_code);

    IF l_resp.headers IS NOT NULL THEN
      IF l_resp.headers.has('opc-request-id') THEN
        result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
      END IF;
      IF l_resp.headers.has('etag') THEN
        result_json.put('etag', l_resp.headers.get_string('etag'));
      END IF;
    END IF;

    IF l_resp.response_body IS NOT NULL THEN
      FOR i IN 1 .. l_resp.response_body.COUNT LOOP
        DECLARE
          l_item JSON_OBJECT_T := JSON_OBJECT_T();
        BEGIN
          l_item.put('id',                    l_resp.response_body(i).id);
          l_item.put('name',                  l_resp.response_body(i).name);
          l_item.put('access_type',           l_resp.response_body(i).access_type);
          l_item.put('object_name',           l_resp.response_body(i).object_name);
          l_item.put('bucket_listing_action', l_resp.response_body(i).bucket_listing_action);
          IF l_resp.response_body(i).time_created IS NOT NULL THEN
            l_item.put('time_created',
              TO_CHAR(l_resp.response_body(i).time_created, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
          END IF;
          IF l_resp.response_body(i).time_expires IS NOT NULL THEN
            l_item.put('time_expires',
              TO_CHAR(l_resp.response_body(i).time_expires, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
          END IF;
          pars_arr.append(l_item);
        END;
      END LOOP;
    END IF;

    result_json.put('preauthenticated_requests', pars_arr);
    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status','error');
      result_json.put('message', SQLERRM);
      result_json.put('bucket', bucket_name);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END list_preauthenticated_requests;

  ----------------------------------------------------------------------
  -- list_replication_policies: List replication policies for a bucket
  ----------------------------------------------------------------------
  FUNCTION list_replication_policies(
    region       IN VARCHAR2,
    bucket_name  IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp         DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_REPLICATION_POLICIES_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    policies_arr   JSON_ARRAY_T := JSON_ARRAY_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user, 'SELECTAI_AGENT_CONFIG', 'OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.LIST_REPLICATION_POLICIES(
      namespace_name=>namespace, bucket_name=>bucket_name, region=>region, credential_name=>credential_name
    );

    result_json.put('namespace', namespace);
    result_json.put('bucket',    bucket_name);
    result_json.put('region',    region);
    result_json.put('status_code', l_resp.status_code);

    IF l_resp.headers IS NOT NULL AND l_resp.headers.has('opc-request-id') THEN
      result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
    END IF;

    IF l_resp.response_body IS NOT NULL THEN
      FOR i IN 1 .. l_resp.response_body.COUNT LOOP
        DECLARE
          l_item JSON_OBJECT_T := JSON_OBJECT_T();
        BEGIN
          l_item.put('id',                        l_resp.response_body(i).id);
          l_item.put('name',                      l_resp.response_body(i).name);
          l_item.put('destination_region_name',   l_resp.response_body(i).destination_region_name);
          l_item.put('destination_bucket_name',   l_resp.response_body(i).destination_bucket_name);
          IF l_resp.response_body(i).time_created IS NOT NULL THEN
            l_item.put('time_created', TO_CHAR(l_resp.response_body(i).time_created, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
          END IF;
          l_item.put('status',                    l_resp.response_body(i).status);
          policies_arr.append(l_item);
        END;
      END LOOP;
    END IF;

    result_json.put('replication_policies', policies_arr);
    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status','error');
      result_json.put('message', SQLERRM);
      result_json.put('bucket', bucket_name);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END list_replication_policies;

  ----------------------------------------------------------------------
  -- get_replication_policy: Retrieve replication policy details
  ----------------------------------------------------------------------
  FUNCTION get_replication_policy(
    region          IN VARCHAR2,
    bucket_name     IN VARCHAR2,
    replication_id  IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp         DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_GET_REPLICATION_POLICY_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    -- Load credential
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    -- Namespace
    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    -- Call API
    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.GET_REPLICATION_POLICY(
      namespace_name=>namespace,
      bucket_name   =>bucket_name,
      replication_id=>replication_id,
      region        =>region,
      credential_name=>credential_name
    );

    result_json.put('namespace', namespace);
    result_json.put('bucket', bucket_name);
    result_json.put('replication_id', replication_id);
    result_json.put('region', region);
    result_json.put('status_code', l_resp.status_code);

    IF l_resp.response_body IS NOT NULL THEN
      result_json.put('id',                     l_resp.response_body.id);
      result_json.put('name',                   l_resp.response_body.name);
      result_json.put('destination_bucket_name',l_resp.response_body.destination_bucket_name);
      result_json.put('destination_region_name',l_resp.response_body.destination_region_name);
      result_json.put('status',                 l_resp.response_body.status);
      result_json.put('status_message',         l_resp.response_body.status_message);
      IF l_resp.response_body.time_created IS NOT NULL THEN
        result_json.put('time_created', TO_CHAR(l_resp.response_body.time_created, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
      END IF;
      IF l_resp.response_body.time_last_sync IS NOT NULL THEN
        result_json.put('time_last_sync', TO_CHAR(l_resp.response_body.time_last_sync, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
      END IF;
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status','error');
      result_json.put('message', SQLERRM);
      result_json.put('bucket', bucket_name);
      result_json.put('replication_id', replication_id);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END get_replication_policy;

  ----------------------------------------------------------------------
  -- list_replication_sources: List replication sources for a bucket
  ----------------------------------------------------------------------
  FUNCTION list_replication_sources(
    region       IN VARCHAR2,
    bucket_name  IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp         DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_REPLICATION_SOURCES_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    sources_arr    JSON_ARRAY_T := JSON_ARRAY_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.LIST_REPLICATION_SOURCES(
      namespace_name=>namespace,
      bucket_name   =>bucket_name,
      region        =>region,
      credential_name=>credential_name
    );

    IF l_resp.response_body IS NOT NULL THEN
      FOR i IN 1 .. l_resp.response_body.COUNT LOOP
        DECLARE
          l_item JSON_OBJECT_T := JSON_OBJECT_T();
        BEGIN
          l_item.put('policy_name',        l_resp.response_body(i).policy_name);
          l_item.put('source_region_name', l_resp.response_body(i).source_region_name);
          l_item.put('source_bucket_name', l_resp.response_body(i).source_bucket_name);
          sources_arr.append(l_item);
        END;
      END LOOP;
    END IF;

    result_json.put('replication_sources', sources_arr);
    result_json.put('status_code', l_resp.status_code);
    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status','error');
      result_json.put('message', SQLERRM);
      result_json.put('bucket', bucket_name);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END list_replication_sources;

  ----------------------------------------------------------------------
  -- reencrypt_bucket: Trigger re-encryption of a bucket
  ----------------------------------------------------------------------
  FUNCTION reencrypt_bucket(
    region       IN VARCHAR2,
    bucket_name  IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp         DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_REENCRYPT_BUCKET_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.REENCRYPT_BUCKET(
      namespace_name=>namespace,
      bucket_name   =>bucket_name,
      region        =>region,
      credential_name=>credential_name
    );

    result_json.put('namespace', namespace);
    result_json.put('bucket', bucket_name);
    result_json.put('region', region);
    result_json.put('status_code', l_resp.status_code);

    IF l_resp.headers IS NOT NULL THEN
      IF l_resp.headers.has('opc-request-id') THEN
        result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
      END IF;
      IF l_resp.headers.has('etag') THEN
        result_json.put('etag', l_resp.headers.get_string('etag'));
      END IF;
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status','error');
      result_json.put('message', SQLERRM);
      result_json.put('bucket', bucket_name);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END reencrypt_bucket;

  ----------------------------------------------------------------------
  -- reencrypt_object: Trigger re-encryption of an object
  ----------------------------------------------------------------------
  FUNCTION reencrypt_object(
    region        IN VARCHAR2,
    bucket_name   IN VARCHAR2,
    object_name   IN VARCHAR2,
    kms_key_id    IN VARCHAR2
  ) RETURN CLOB
  AS
    l_details      DBMS_CLOUD_OCI_OBJECT_STORAGE_REENCRYPT_OBJECT_DETAILS_T;
    l_resp         DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_REENCRYPT_OBJECT_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
    l_dummy_key     DBMS_CLOUD_OCI_OBJECT_STORAGE_SSE_CUSTOMER_KEY_DETAILS_T := NULL;
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_details := DBMS_CLOUD_OCI_OBJECT_STORAGE_REENCRYPT_OBJECT_DETAILS_T(
      kms_key_id, l_dummy_key, l_dummy_key
    );

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.REENCRYPT_OBJECT(
      namespace_name           => namespace,
      bucket_name              => bucket_name,
      object_name              => object_name,
      reencrypt_object_details => l_details,
      version_id               => NULL,
      opc_client_request_id    => NULL,
      region                   => region,
      endpoint                 => NULL,
      credential_name          => credential_name
    );

    result_json.put('namespace', namespace);
    result_json.put('bucket', bucket_name);
    result_json.put('object_name', object_name);
    result_json.put('kms_key_id', kms_key_id);
    result_json.put('region', region);
    result_json.put('status_code', l_resp.status_code);

    IF l_resp.headers IS NOT NULL THEN
      IF l_resp.headers.has('opc-request-id') THEN
        result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
      END IF;
      IF l_resp.headers.has('etag') THEN
        result_json.put('etag', l_resp.headers.get_string('etag'));
      END IF;
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status','error');
      result_json.put('message', SQLERRM);
      result_json.put('bucket', bucket_name);
      result_json.put('object_name', object_name);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END reencrypt_object;

  ----------------------------------------------------------------------
  -- rename_object: Rename an object in a bucket
  ----------------------------------------------------------------------
  FUNCTION rename_object(
    region        IN VARCHAR2,
    bucket_name   IN VARCHAR2,
    source_object IN VARCHAR2,
    new_object    IN VARCHAR2
  ) RETURN CLOB
  AS
    l_details      DBMS_CLOUD_OCI_OBJECT_STORAGE_RENAME_OBJECT_DETAILS_T;
    l_resp         DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_RENAME_OBJECT_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_details := DBMS_CLOUD_OCI_OBJECT_STORAGE_RENAME_OBJECT_DETAILS_T(
      source_name => source_object,
      new_name    => new_object,
      src_obj_if_match_e_tag   => NULL,
      new_obj_if_match_e_tag   => NULL,
      new_obj_if_none_match_e_tag => NULL
    );

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.RENAME_OBJECT(
      namespace_name        => namespace,
      bucket_name           => bucket_name,
      rename_object_details => l_details,
      opc_client_request_id => NULL,
      region                => region,
      endpoint              => NULL,
      credential_name       => credential_name
    );

    result_json.put('namespace', namespace);
    result_json.put('bucket', bucket_name);
    result_json.put('source_object', source_object);
    result_json.put('new_object', new_object);
    result_json.put('region', region);
    result_json.put('status_code', l_resp.status_code);

    IF l_resp.headers IS NOT NULL THEN
      IF l_resp.headers.has('opc-request-id') THEN
        result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
      END IF;
      IF l_resp.headers.has('etag') THEN
        result_json.put('etag', l_resp.headers.get_string('etag'));
      END IF;
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status','error');
      result_json.put('message', SQLERRM);
      result_json.put('bucket', bucket_name);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END rename_object;

  ----------------------------------------------------------------------
  -- restore_objects: Restore an object (optionally by version) for N hours
  ----------------------------------------------------------------------
  FUNCTION restore_objects(
    region        IN VARCHAR2,
    bucket_name   IN VARCHAR2,
    object_name   IN VARCHAR2,
    hours         IN NUMBER DEFAULT 24,
    version_id    IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  AS
    l_details      DBMS_CLOUD_OCI_OBJECT_STORAGE_RESTORE_OBJECTS_DETAILS_T;
    l_resp         DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_RESTORE_OBJECTS_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_details := DBMS_CLOUD_OCI_OBJECT_STORAGE_RESTORE_OBJECTS_DETAILS_T(
      object_name => object_name,
      hours       => hours,
      version_id  => version_id
    );

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.RESTORE_OBJECTS(
      namespace_name          => namespace,
      bucket_name             => bucket_name,
      restore_objects_details => l_details,
      region                  => region,
      credential_name         => credential_name
    );

    result_json.put('namespace', namespace);
    result_json.put('bucket_name', bucket_name);
    result_json.put('object_name', object_name);
    result_json.put('hours', hours);
    result_json.put('version_id', version_id);
    result_json.put('region', region);
    result_json.put('status_code', l_resp.status_code);

    IF l_resp.headers IS NOT NULL AND l_resp.headers.has('opc-request-id') THEN
      result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status','error');
      result_json.put('message', SQLERRM);
      result_json.put('bucket_name', bucket_name);
      result_json.put('object_name', object_name);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END restore_objects;

  ----------------------------------------------------------------------
  -- upload_part: Upload a single multipart upload part
  ----------------------------------------------------------------------
  FUNCTION upload_part(
    region           IN VARCHAR2,
    bucket_name      IN VARCHAR2,
    object_name      IN VARCHAR2,
    upload_id        IN VARCHAR2,
    upload_part_num  IN NUMBER,
    upload_part_body IN BLOB,
    content_length   IN NUMBER
  ) RETURN CLOB
  AS
    l_resp         DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_UPLOAD_PART_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.UPLOAD_PART(
      namespace_name              => namespace,
      bucket_name                 => bucket_name,
      object_name                 => object_name,
      upload_id                   => upload_id,
      upload_part_num             => upload_part_num,
      content_length              => content_length,
      upload_part_body            => upload_part_body,
      opc_client_request_id       => NULL,
      if_match                    => NULL,
      if_none_match               => NULL,
      expect                      => NULL,
      content_md5                 => NULL,
      opc_sse_customer_algorithm  => NULL,
      opc_sse_customer_key        => NULL,
      opc_sse_customer_key_sha256 => NULL,
      opc_sse_kms_key_id          => NULL,
      region                      => region,
      endpoint                    => NULL,
      credential_name             => credential_name
    );

    result_json.put('status_code', l_resp.status_code);
    IF l_resp.headers IS NOT NULL THEN
      result_json.put('headers', l_resp.headers);
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status','error');
      result_json.put('message', SQLERRM);
      result_json.put('bucket_name', bucket_name);
      result_json.put('object_name', object_name);
      result_json.put('upload_id', upload_id);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END upload_part;

  ----------------------------------------------------------------------
  -- update_namespace_metadata: Set default S3/Swift compartments for namespace
  ----------------------------------------------------------------------
  FUNCTION update_namespace_metadata(
    region           IN VARCHAR2
  ) RETURN CLOB
  AS
    result_json     JSON_OBJECT_T := JSON_OBJECT_T();
    l_details       DBMS_CLOUD_OCI_OBJECT_STORAGE_UPDATE_NAMESPACE_METADATA_DETAILS_T;
    l_resp          DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_UPDATE_NAMESPACE_METADATA_RESPONSE_T;
    l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json      CLOB;
    l_cfg           JSON_OBJECT_T;
    l_params        JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    -- Load config
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
      compartment_id  := l_params.get_string('COMPARTMENT_OCID');
    END IF;

    -- Resolve namespace
    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    -- Prepare details (use COMPARTMENT_OCID from config)
    l_details := DBMS_CLOUD_OCI_OBJECT_STORAGE_UPDATE_NAMESPACE_METADATA_DETAILS_T(
      default_s3_compartment_id    => compartment_id,
      default_swift_compartment_id => compartment_id
    );

    -- Call API
    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.UPDATE_NAMESPACE_METADATA(
      namespace_name                    => namespace,
      update_namespace_metadata_details => l_details,
      region                            => region,
      credential_name                   => credential_name
    );

    -- Build JSON
    result_json.put('namespace', namespace);
    result_json.put('compartment_id', compartment_id);
    IF l_resp.response_body IS NOT NULL THEN
      result_json.put('default_s3_compartment_id',    l_resp.response_body.default_s3_compartment_id);
      result_json.put('default_swift_compartment_id', l_resp.response_body.default_swift_compartment_id);
    END IF;
    result_json.put('status_code', l_resp.status_code);
    IF l_resp.headers IS NOT NULL AND l_resp.headers.has('opc-request-id') THEN
      result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status','error');
      result_json.put('message', SQLERRM);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END update_namespace_metadata;

  ----------------------------------------------------------------------
  -- update_retention_rule: Update retention rule on a bucket
  ----------------------------------------------------------------------
  FUNCTION update_retention_rule(
    region           IN VARCHAR2,
    bucket_name      IN VARCHAR2,
    rule_id          IN VARCHAR2,
    new_display_name IN VARCHAR2,
    duration_amount  IN NUMBER,
    time_unit        IN VARCHAR2
  ) RETURN CLOB
  AS
    l_duration     DBMS_CLOUD_OCI_OBJECT_STORAGE_DURATION_T;
    l_details      DBMS_CLOUD_OCI_OBJECT_STORAGE_UPDATE_RETENTION_RULE_DETAILS_T;
    l_resp         DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_UPDATE_RETENTION_RULE_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace       VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_duration := DBMS_CLOUD_OCI_OBJECT_STORAGE_DURATION_T(
      time_amount => duration_amount,
      time_unit   => time_unit
    );

    l_details := DBMS_CLOUD_OCI_OBJECT_STORAGE_UPDATE_RETENTION_RULE_DETAILS_T(
      display_name     => new_display_name,
      duration         => l_duration,
      time_rule_locked => NULL
    );

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.UPDATE_RETENTION_RULE(
      namespace_name                => namespace,
      bucket_name                   => bucket_name,
      retention_rule_id             => rule_id,
      update_retention_rule_details => l_details,
      region                        => region,
      credential_name               => credential_name
    );

    result_json.put('namespace', namespace);
    result_json.put('bucket', bucket_name);
    result_json.put('rule_id', rule_id);
    result_json.put('new_display_name', new_display_name);
    result_json.put('duration_amount', duration_amount);
    result_json.put('time_unit', time_unit);
    result_json.put('region', region);
    result_json.put('status_code', l_resp.status_code);

    IF l_resp.headers IS NOT NULL THEN
      IF l_resp.headers.has('opc-request-id') THEN
        result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
      END IF;
      IF l_resp.headers.has('etag') THEN
        result_json.put('etag', l_resp.headers.get_string('etag'));
      END IF;
    END IF;

    IF l_resp.response_body IS NOT NULL THEN
      result_json.put('id', l_resp.response_body.id);
      IF l_resp.response_body.time_modified IS NOT NULL THEN
        result_json.put('time_modified', TO_CHAR(l_resp.response_body.time_modified, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
      END IF;
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status','error');
      result_json.put('message', SQLERRM);
      result_json.put('bucket', bucket_name);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END update_retention_rule;

  ----------------------------------------------------------------------
  -- list_work_requests: List work requests in a compartment
  ----------------------------------------------------------------------
  FUNCTION list_work_requests(
    region           IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp         DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_WORK_REQUESTS_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    items_arr      JSON_ARRAY_T := JSON_ARRAY_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
      compartment_id  := l_params.get_string('COMPARTMENT_OCID');
    END IF;

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.LIST_WORK_REQUESTS(
      compartment_id  => compartment_id,
      region          => region,
      credential_name => credential_name
    );

    IF l_resp.response_body IS NOT NULL THEN
      FOR i IN 1 .. l_resp.response_body.COUNT LOOP
        DECLARE
          l_item JSON_OBJECT_T := JSON_OBJECT_T();
        BEGIN
          l_item.put('id',               l_resp.response_body(i).id);
          l_item.put('status',           l_resp.response_body(i).status);
          l_item.put('operation_type',   l_resp.response_body(i).operation_type);
          l_item.put('percent_complete', l_resp.response_body(i).percent_complete);
          IF l_resp.response_body(i).time_accepted IS NOT NULL THEN
            l_item.put('time_accepted',  TO_CHAR(l_resp.response_body(i).time_accepted,'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
          END IF;
          IF l_resp.response_body(i).time_started IS NOT NULL THEN
            l_item.put('time_started',   TO_CHAR(l_resp.response_body(i).time_started,'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
          END IF;
          IF l_resp.response_body(i).time_finished IS NOT NULL THEN
            l_item.put('time_finished',  TO_CHAR(l_resp.response_body(i).time_finished,'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
          END IF;
          items_arr.append(l_item);
        END;
      END LOOP;
    END IF;

    result_json.put('status_code', l_resp.status_code);
    result_json.put('items', items_arr);
    IF l_resp.headers IS NOT NULL AND l_resp.headers.has('opc-request-id') THEN
      result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status','error');
      result_json.put('message', SQLERRM);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END list_work_requests;

  ----------------------------------------------------------------------
  -- list_work_request_errors: List errors for a work request
  ----------------------------------------------------------------------
  FUNCTION list_work_request_errors(
    work_request_id IN VARCHAR2,
    region          IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp      DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_WORK_REQUEST_ERRORS_RESPONSE_T;
    result_json JSON_OBJECT_T := JSON_OBJECT_T();
    errors_arr  JSON_ARRAY_T := JSON_ARRAY_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
  BEGIN
    -- Load credential from config
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.LIST_WORK_REQUEST_ERRORS(
      work_request_id       => work_request_id,
      page                  => NULL,
      limit                 => NULL,
      opc_client_request_id => NULL,
      region                => region,
      endpoint              => NULL,
      credential_name       => credential_name
    );

    IF l_resp.response_body IS NOT NULL THEN
      FOR i IN 1 .. l_resp.response_body.COUNT LOOP
        DECLARE
          l_err JSON_OBJECT_T := JSON_OBJECT_T();
        BEGIN
          l_err.put('code',      l_resp.response_body(i).code);
          l_err.put('message',   l_resp.response_body(i).message);
          IF l_resp.response_body(i).l_timestamp IS NOT NULL THEN
            l_err.put('timestamp', TO_CHAR(l_resp.response_body(i).l_timestamp,'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
          END IF;
          errors_arr.append(l_err);
        END;
      END LOOP;
    END IF;

    result_json.put('status_code', l_resp.status_code);
    result_json.put('errors', errors_arr);
    IF l_resp.headers IS NOT NULL AND l_resp.headers.has('opc-request-id') THEN
      result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status','error');
      result_json.put('message', SQLERRM);
      result_json.put('work_request_id', work_request_id);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END list_work_request_errors;

  ----------------------------------------------------------------------
  -- list_work_request_logs: List logs for a work request
  ----------------------------------------------------------------------
  FUNCTION list_work_request_logs(
    work_request_id IN VARCHAR2,
    region          IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp      DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_LIST_WORK_REQUEST_LOGS_RESPONSE_T;
    result_json JSON_OBJECT_T := JSON_OBJECT_T();
    logs_arr    JSON_ARRAY_T := JSON_ARRAY_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
  BEGIN
    -- Load credential from config
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.LIST_WORK_REQUEST_LOGS(
      work_request_id  => work_request_id,
      region           => region,
      credential_name  => credential_name
    );

    IF l_resp.response_body IS NOT NULL THEN
      FOR i IN 1 .. l_resp.response_body.COUNT LOOP
        DECLARE
          l_obj JSON_OBJECT_T := JSON_OBJECT_T();
        BEGIN
          l_obj.put('message',   l_resp.response_body(i).message);
          IF l_resp.response_body(i).l_timestamp IS NOT NULL THEN
            l_obj.put('timestamp', TO_CHAR(l_resp.response_body(i).l_timestamp,'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
          END IF;
          logs_arr.append(l_obj);
        END;
      END LOOP;
    END IF;

    result_json.put('work_request_id', work_request_id);
    result_json.put('status_code', l_resp.status_code);
    result_json.put('logs', logs_arr);
    IF l_resp.headers IS NOT NULL AND l_resp.headers.has('opc-next-page') THEN
      result_json.put('next_page', l_resp.headers.get_string('opc-next-page'));
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status','error');
      result_json.put('message', SQLERRM);
      result_json.put('work_request_id', work_request_id);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END list_work_request_logs;

  ----------------------------------------------------------------------
  -- get_work_request: Retrieve work request details
  ----------------------------------------------------------------------
  FUNCTION get_work_request(
    work_request_id IN VARCHAR2,
    region          IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp      DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_GET_WORK_REQUEST_RESPONSE_T;
    result_json JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
    credential_name VARCHAR2(256);
  BEGIN
    -- Load credential from config
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params');
      credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.GET_WORK_REQUEST(
      work_request_id  => work_request_id,
      region           => region,
      credential_name  => credential_name
    );

    IF l_resp.response_body IS NOT NULL THEN
      result_json.put('work_request_id',  l_resp.response_body.id);
      result_json.put('status',           l_resp.response_body.status);
      result_json.put('operation_type',   l_resp.response_body.operation_type);
      result_json.put('percent_complete', l_resp.response_body.percent_complete);
      IF l_resp.response_body.time_accepted IS NOT NULL THEN
        result_json.put('time_accepted', TO_CHAR(l_resp.response_body.time_accepted,'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
      END IF;
      IF l_resp.response_body.time_started IS NOT NULL THEN
        result_json.put('time_started',  TO_CHAR(l_resp.response_body.time_started,'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
      END IF;
      IF l_resp.response_body.time_finished IS NOT NULL THEN
        result_json.put('time_finished', TO_CHAR(l_resp.response_body.time_finished,'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
      END IF;
    END IF;

    result_json.put('status_code', l_resp.status_code);
    IF l_resp.headers IS NOT NULL AND l_resp.headers.has('opc-request-id') THEN
      result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      result_json := JSON_OBJECT_T();
      result_json.put('status','error');
      result_json.put('message', SQLERRM);
      result_json.put('work_request_id', work_request_id);
      result_json.put('region', region);
      RETURN result_json.to_clob();
  END get_work_request;

  ----------------------------------------------------------------------
  -- create_bucket: Create a new bucket
  ----------------------------------------------------------------------
  FUNCTION create_bucket(
    bucket_name       IN VARCHAR2,
    region            IN VARCHAR2
  ) RETURN CLOB
  AS
    l_details        DBMS_CLOUD_OCI_OBJECT_STORAGE_CREATE_BUCKET_DETAILS_T;
    l_resp           DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_CREATE_BUCKET_RESPONSE_T;
    result_json      JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user   VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json       CLOB;
    l_cfg            JSON_OBJECT_T;
    l_params         JSON_OBJECT_T;
    credential_name  VARCHAR2(256);
    namespace        VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params       := l_cfg.get_object('config_params');
      credential_name:= l_params.get_string('CREDENTIAL_NAME');
      compartment_id := l_params.get_string('COMPARTMENT_OCID'); -- prefer config OCID
    END IF;

    -- resolve namespace
    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    -- details
    l_details := DBMS_CLOUD_OCI_OBJECT_STORAGE_CREATE_BUCKET_DETAILS_T(
      name                  => bucket_name,
      compartment_id        => compartment_id,
      metadata              => NULL,
      public_access_type    => 'NoPublicAccess',
      storage_tier          => 'Standard',
      object_events_enabled => 0,
      freeform_tags         => NULL,
      defined_tags          => NULL,
      kms_key_id            => NULL,
      versioning            => 'Enabled',
      auto_tiering          => NULL
    );

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.CREATE_BUCKET(
      namespace_name        => namespace,
      create_bucket_details => l_details,
      region                => region,
      credential_name       => credential_name
    );

    result_json.put('namespace',       namespace);
    result_json.put('bucket',          bucket_name);
    result_json.put('region',          region);
    result_json.put('status_code',     l_resp.status_code);
    IF l_resp.headers IS NOT NULL THEN
      IF l_resp.headers.has('opc-request-id') THEN
        result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
      END IF;
      IF l_resp.headers.has('etag') THEN
        result_json.put('etag', l_resp.headers.get_string('etag'));
      END IF;
    END IF;
    IF l_resp.response_body IS NOT NULL THEN
      result_json.put('created_by',     l_resp.response_body.created_by);
      result_json.put('compartment_id', l_resp.response_body.compartment_id);
      IF l_resp.response_body.time_created IS NOT NULL THEN
        result_json.put('time_created', TO_CHAR(l_resp.response_body.time_created,'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
      END IF;
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION WHEN OTHERS THEN
    result_json := JSON_OBJECT_T();
    result_json.put('status','error');
    result_json.put('message', SQLERRM);
    result_json.put('bucket', bucket_name);
    result_json.put('region', region);
    RETURN result_json.to_clob();
  END create_bucket;

  ----------------------------------------------------------------------
  -- delete_bucket: Delete bucket (must be empty)
  ----------------------------------------------------------------------
  FUNCTION delete_bucket(
    bucket_name       IN VARCHAR2,
    region            IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp          DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_DELETE_BUCKET_RESPONSE_T;
    result_json     JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json      CLOB; l_cfg JSON_OBJECT_T; l_params JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params'); credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.DELETE_BUCKET(
      namespace_name=>namespace, bucket_name=>bucket_name, credential_name=>credential_name, region=>region
    );

    result_json.put('namespace', namespace);
    result_json.put('bucket',    bucket_name);
    result_json.put('region',    region);
    result_json.put('status_code', l_resp.status_code);
    IF l_resp.headers IS NOT NULL THEN result_json.put('headers', l_resp.headers); END IF;

    RETURN result_json.to_clob();
  EXCEPTION WHEN OTHERS THEN
    result_json := JSON_OBJECT_T(); result_json.put('status','error'); result_json.put('message',SQLERRM);
    result_json.put('bucket', bucket_name); result_json.put('region', region); RETURN result_json.to_clob();
  END delete_bucket;

  ----------------------------------------------------------------------
  -- delete_object: Delete an object
  ----------------------------------------------------------------------
  FUNCTION delete_object(
    region            IN VARCHAR2,
    bucket_name       IN VARCHAR2,
    object_name       IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp          DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_DELETE_OBJECT_RESPONSE_T;
    result_json     JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json      CLOB; l_cfg JSON_OBJECT_T; l_params JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params'); credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.DELETE_OBJECT(
      namespace_name=>namespace, bucket_name=>bucket_name, object_name=>object_name,
      region=>region, credential_name=>credential_name
    );

    result_json.put('status','success');
    result_json.put('object_name', object_name);
    result_json.put('bucket_name', bucket_name);
    result_json.put('region', region);
    result_json.put('status_code', l_resp.status_code);
    RETURN result_json.to_clob();
  EXCEPTION WHEN OTHERS THEN
    result_json := JSON_OBJECT_T(); result_json.put('status','error'); result_json.put('message',SQLERRM);
    result_json.put('bucket_name', bucket_name); result_json.put('object_name', object_name);
    result_json.put('region', region); RETURN result_json.to_clob();
  END delete_object;

  ----------------------------------------------------------------------
  -- copy_object: Copy an object to destination bucket/region
  ----------------------------------------------------------------------
  FUNCTION copy_object(
    region                  IN VARCHAR2,
    bucket_name             IN VARCHAR2,
    source_object_name      IN VARCHAR2,
    destination_region      IN VARCHAR2,
    destination_bucket_name IN VARCHAR2,
    destination_object_name IN VARCHAR2
  ) RETURN CLOB
  AS
    l_details       DBMS_CLOUD_OCI_OBJECT_STORAGE_COPY_OBJECT_DETAILS_T;
    l_resp          DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_COPY_OBJECT_RESPONSE_T;
    result_json     JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json      CLOB; l_cfg JSON_OBJECT_T; l_params JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params'); credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    -- source namespace
    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_details := DBMS_CLOUD_OCI_OBJECT_STORAGE_COPY_OBJECT_DETAILS_T(
      source_object_name                     => source_object_name,
      source_object_if_match_e_tag           => NULL,
      source_version_id                      => NULL,
      destination_region                     => destination_region,
      destination_namespace                  => namespace,
      destination_bucket                     => destination_bucket_name,
      destination_object_name                => destination_object_name,
      destination_object_if_match_e_tag      => NULL,
      destination_object_if_none_match_e_tag => NULL,
      destination_object_metadata            => NULL,
      destination_object_storage_tier        => NULL
    );

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.COPY_OBJECT(
      namespace_name      => namespace,
      bucket_name         => bucket_name,
      copy_object_details => l_details,
      region              => region,
      credential_name     => credential_name
    );

    result_json.put('namespace',               namespace);
    result_json.put('bucket',                  bucket_name);
    result_json.put('source_object_name',      source_object_name);
    result_json.put('destination_region',      destination_region);
    result_json.put('destination_bucket',      destination_bucket_name);
    result_json.put('destination_object_name', destination_object_name);
    result_json.put('status_code',             l_resp.status_code);
    IF l_resp.headers IS NOT NULL THEN
      IF l_resp.headers.has('opc-request-id') THEN
        result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
      END IF;
      IF l_resp.headers.has('etag') THEN
        result_json.put('etag', l_resp.headers.get_string('etag'));
      END IF;
    END IF;
    RETURN result_json.to_clob();
  EXCEPTION WHEN OTHERS THEN
    result_json := JSON_OBJECT_T(); result_json.put('status','error'); result_json.put('message',SQLERRM);
    result_json.put('bucket', bucket_name); result_json.put('region', region); RETURN result_json.to_clob();
  END copy_object;


  ---------------------

    ----------------------------------------------------------------------
  -- create_multipart_upload: Start multipart upload
  ----------------------------------------------------------------------
  FUNCTION create_multipart_upload(
    region         IN VARCHAR2,
    bucket_name    IN VARCHAR2,
    object_name    IN VARCHAR2,
    content_type   IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  AS
    l_req          DBMS_CLOUD_OCI_OBJECT_STORAGE_CREATE_MULTIPART_UPLOAD_DETAILS_T;
    l_resp         DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_CREATE_MULTIPART_UPLOAD_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json     CLOB; l_cfg JSON_OBJECT_T; l_params JSON_OBJECT_T;
    credential_name VARCHAR2(256); namespace VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params'); credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_req := DBMS_CLOUD_OCI_OBJECT_STORAGE_CREATE_MULTIPART_UPLOAD_DETAILS_T(
      object=>object_name, content_type=>content_type, content_language=>NULL,
      content_encoding=>NULL, content_disposition=>NULL, cache_control=>NULL,
      storage_tier=>NULL, metadata=>NULL
    );

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.CREATE_MULTIPART_UPLOAD(
      namespace_name=>namespace, bucket_name=>bucket_name,
      create_multipart_upload_details=>l_req, region=>region, credential_name=>credential_name
    );

    result_json.put('status_code', l_resp.status_code);
    IF l_resp.response_body IS NOT NULL THEN
      result_json.put('upload_id', l_resp.response_body.upload_id);
      result_json.put('object',    l_resp.response_body.object);
      result_json.put('bucket',    l_resp.response_body.bucket);
      result_json.put('namespace', l_resp.response_body.namespace);
      IF l_resp.response_body.time_created IS NOT NULL THEN
        result_json.put('time_created', TO_CHAR(l_resp.response_body.time_created,'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
      END IF;
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION WHEN OTHERS THEN
    result_json := JSON_OBJECT_T(); result_json.put('status','error'); result_json.put('message',SQLERRM);
    result_json.put('bucket', bucket_name); result_json.put('region', region); RETURN result_json.to_clob();
  END create_multipart_upload;

  ----------------------------------------------------------------------
  -- commit_multipart_upload: Finalize multipart upload
  ----------------------------------------------------------------------
  FUNCTION commit_multipart_upload(
    region          IN VARCHAR2,
    bucket_name     IN VARCHAR2,
    object_name     IN VARCHAR2,
    upload_id       IN VARCHAR2,
    part_num_arr    IN DBMS_CLOUD_OCI_OBJECT_STORAGE_NUMBER_TBL,
    etag_arr        IN DBMS_CLOUD_OCI_OBJECT_STORAGE_VARCHAR2_TBL
  ) RETURN CLOB
  AS
    l_parts    DBMS_CLOUD_OCI_OBJECT_STORAGE_COMMIT_MULTIPART_UPLOAD_PART_DETAILS_TBL
                  := DBMS_CLOUD_OCI_OBJECT_STORAGE_COMMIT_MULTIPART_UPLOAD_PART_DETAILS_TBL();
    l_excl     DBMS_CLOUD_OCI_OBJECT_STORAGE_NUMBER_TBL
                  := DBMS_CLOUD_OCI_OBJECT_STORAGE_NUMBER_TBL();
    l_details  DBMS_CLOUD_OCI_OBJECT_STORAGE_COMMIT_MULTIPART_UPLOAD_DETAILS_T;
    l_resp     DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_COMMIT_MULTIPART_UPLOAD_RESPONSE_T;
    result_json JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json CLOB; l_cfg JSON_OBJECT_T; l_params JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params'); credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    FOR i IN 1 .. part_num_arr.COUNT LOOP
      l_parts.EXTEND;
      l_parts(i) := DBMS_CLOUD_OCI_OBJECT_STORAGE_COMMIT_MULTIPART_UPLOAD_PART_DETAILS_T(
        part_num => part_num_arr(i), etag => etag_arr(i)
      );
    END LOOP;

    l_details := DBMS_CLOUD_OCI_OBJECT_STORAGE_COMMIT_MULTIPART_UPLOAD_DETAILS_T(
      parts_to_commit=>l_parts, parts_to_exclude=>l_excl
    );

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.COMMIT_MULTIPART_UPLOAD(
      namespace_name=>namespace, bucket_name=>bucket_name, object_name=>object_name,
      upload_id=>upload_id, commit_multipart_upload_details=>l_details,
      region=>region, credential_name=>credential_name
    );

    result_json.put('status_code', l_resp.status_code);
    IF l_resp.headers IS NOT NULL THEN result_json.put('headers', l_resp.headers); END IF;
    RETURN result_json.to_clob();
  EXCEPTION WHEN OTHERS THEN
    result_json := JSON_OBJECT_T(); result_json.put('status','error'); result_json.put('message',SQLERRM);
    result_json.put('bucket_name', bucket_name); result_json.put('object_name', object_name);
    result_json.put('region', region); RETURN result_json.to_clob();
  END commit_multipart_upload;

  ----------------------------------------------------------------------
  -- abort_multipart_upload: Abort multipart upload
  ----------------------------------------------------------------------
  FUNCTION abort_multipart_upload(
    region          IN VARCHAR2,
    bucket_name     IN VARCHAR2,
    object_name     IN VARCHAR2,
    upload_id       IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp          DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_ABORT_MULTIPART_UPLOAD_RESPONSE_T;
    result_json     JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json CLOB; l_cfg JSON_OBJECT_T; l_params JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params'); credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.ABORT_MULTIPART_UPLOAD(
      namespace_name=>namespace, bucket_name=>bucket_name, object_name=>object_name,
      upload_id=>upload_id, region=>region, credential_name=>credential_name
    );

    result_json.put('status_code', l_resp.status_code);
    IF l_resp.headers IS NOT NULL THEN result_json.put('headers', l_resp.headers); END IF;
    RETURN result_json.to_clob();
  EXCEPTION WHEN OTHERS THEN
    result_json := JSON_OBJECT_T(); result_json.put('status','error'); result_json.put('message',SQLERRM);
    result_json.put('bucket_name', bucket_name); result_json.put('object_name', object_name);
    result_json.put('region', region); RETURN result_json.to_clob();
  END abort_multipart_upload;

  ----------------------------------------------------------------------
  -- create_preauthenticated_request (PAR)
  ----------------------------------------------------------------------
  FUNCTION create_preauthenticated_request(
    region           IN VARCHAR2,
    bucket_name      IN VARCHAR2,
    name             IN VARCHAR2,
    object_name      IN VARCHAR2,
    access_type      IN VARCHAR2,
    listing_action   IN VARCHAR2 DEFAULT 'Deny',
    time_expires     IN TIMESTAMP WITH TIME ZONE
  ) RETURN CLOB
  AS
    l_details      DBMS_CLOUD_OCI_OBJECT_STORAGE_CREATE_PREAUTHENTICATED_REQUEST_DETAILS_T;
    l_resp         DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_CREATE_PREAUTHENTICATED_REQUEST_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json CLOB; l_cfg JSON_OBJECT_T; l_params JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    IF access_type NOT IN (
      'ObjectRead','ObjectWrite','ObjectReadWrite','AnyObjectRead','AnyObjectWrite','AnyObjectReadWrite'
    ) THEN
      RAISE_APPLICATION_ERROR(-20001, 'Invalid access_type: '||access_type);
    END IF;

    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params'); credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_details := DBMS_CLOUD_OCI_OBJECT_STORAGE_CREATE_PREAUTHENTICATED_REQUEST_DETAILS_T(
      name=>name, bucket_listing_action=>listing_action, object_name=>object_name,
      access_type=>access_type, time_expires=>time_expires
    );

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.CREATE_PREAUTHENTICATED_REQUEST(
      namespace_name=>namespace, bucket_name=>bucket_name,
      create_preauthenticated_request_details=>l_details,
      region=>region, credential_name=>credential_name
    );

    result_json.put('namespace', namespace);
    result_json.put('bucket',    bucket_name);
    result_json.put('name',      name);
    result_json.put('access_type', access_type);
    result_json.put('object_name', object_name);
    result_json.put('listing_action', listing_action);
    result_json.put('region', region);
    result_json.put('status_code', l_resp.status_code);
    IF l_resp.headers IS NOT NULL THEN
      IF l_resp.headers.has('opc-request-id') THEN
        result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
      END IF;
      IF l_resp.headers.has('etag') THEN
        result_json.put('etag', l_resp.headers.get_string('etag'));
      END IF;
    END IF;
    IF l_resp.response_body IS NOT NULL THEN
      result_json.put('id',        l_resp.response_body.id);
      result_json.put('par_name',  l_resp.response_body.name);
      result_json.put('full_path', l_resp.response_body.full_path);
      IF l_resp.response_body.time_created IS NOT NULL THEN
        result_json.put('time_created', TO_CHAR(l_resp.response_body.time_created,'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
      END IF;
      IF l_resp.response_body.time_expires IS NOT NULL THEN
        result_json.put('time_expires', TO_CHAR(l_resp.response_body.time_expires,'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
      END IF;
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION WHEN OTHERS THEN
    result_json := JSON_OBJECT_T(); result_json.put('status','error'); result_json.put('message',SQLERRM);
    result_json.put('bucket', bucket_name); result_json.put('region', region); RETURN result_json.to_clob();
  END create_preauthenticated_request;

  ----------------------------------------------------------------------
  -- get_preauthenticated_request (PAR)
  ----------------------------------------------------------------------
  FUNCTION get_preauthenticated_request(
    region           IN VARCHAR2,
    bucket_name      IN VARCHAR2,
    par_id           IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp         DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_GET_PREAUTHENTICATED_REQUEST_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json CLOB; l_cfg JSON_OBJECT_T; l_params JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params'); credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.GET_PREAUTHENTICATED_REQUEST(
      namespace_name=>namespace, bucket_name=>bucket_name, par_id=>par_id,
      region=>region, credential_name=>credential_name
    );

    result_json.put('namespace', namespace);
    result_json.put('bucket', bucket_name);
    result_json.put('par_id', par_id);
    result_json.put('region', region);
    result_json.put('status_code', l_resp.status_code);

    IF l_resp.headers IS NOT NULL THEN
      IF l_resp.headers.has('opc-request-id') THEN
        result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
      END IF;
      IF l_resp.headers.has('etag') THEN
        result_json.put('etag', l_resp.headers.get_string('etag'));
      END IF;
    END IF;

    IF l_resp.response_body IS NOT NULL THEN
      result_json.put('id',                     l_resp.response_body.id);
      result_json.put('name',                   l_resp.response_body.name);
      result_json.put('object_name',            l_resp.response_body.object_name);
      result_json.put('bucket_listing_action',  l_resp.response_body.bucket_listing_action);
      result_json.put('access_type',            l_resp.response_body.access_type);
      IF l_resp.response_body.time_created IS NOT NULL THEN
        result_json.put('time_created', TO_CHAR(l_resp.response_body.time_created,'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
      END IF;
      IF l_resp.response_body.time_expires IS NOT NULL THEN
        result_json.put('time_expires', TO_CHAR(l_resp.response_body.time_expires,'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
      END IF;
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION WHEN OTHERS THEN
    result_json := JSON_OBJECT_T(); result_json.put('status','error'); result_json.put('message',SQLERRM);
    result_json.put('bucket', bucket_name); result_json.put('region', region); RETURN result_json.to_clob();
  END get_preauthenticated_request;

  ----------------------------------------------------------------------
  -- delete_preauthenticated_request (PAR)
  ----------------------------------------------------------------------
  FUNCTION delete_preauthenticated_request(
    region           IN VARCHAR2,
    bucket_name      IN VARCHAR2,
    par_id           IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp          DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_DELETE_PREAUTHENTICATED_REQUEST_RESPONSE_T;
    result_json     JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json CLOB; l_cfg JSON_OBJECT_T; l_params JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params'); credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.DELETE_PREAUTHENTICATED_REQUEST(
      namespace_name=>namespace, bucket_name=>bucket_name, par_id=>par_id,
      region=>region, credential_name=>credential_name
    );

    result_json.put('namespace', namespace);
    result_json.put('bucket',    bucket_name);
    result_json.put('par_id',    par_id);
    result_json.put('region',    region);
    result_json.put('status_code', l_resp.status_code);
    RETURN result_json.to_clob();
  EXCEPTION WHEN OTHERS THEN
    result_json := JSON_OBJECT_T(); result_json.put('status','error'); result_json.put('message',SQLERRM);
    result_json.put('bucket', bucket_name); result_json.put('region', region); RETURN result_json.to_clob();
  END delete_preauthenticated_request;

  ----------------------------------------------------------------------
  -- create_replication_policy
  ----------------------------------------------------------------------
  FUNCTION create_replication_policy(
    region                    IN VARCHAR2,
    bucket_name               IN VARCHAR2,
    destination_region_name   IN VARCHAR2,
    destination_bucket_name   IN VARCHAR2,
    policy_name               IN VARCHAR2
  ) RETURN CLOB
  AS
    l_details      DBMS_CLOUD_OCI_OBJECT_STORAGE_CREATE_REPLICATION_POLICY_DETAILS_T;
    l_resp         DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_CREATE_REPLICATION_POLICY_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json CLOB; l_cfg JSON_OBJECT_T; l_params JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params'); credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_details := DBMS_CLOUD_OCI_OBJECT_STORAGE_CREATE_REPLICATION_POLICY_DETAILS_T(
      name=>policy_name, destination_region_name=>destination_region_name,
      destination_bucket_name=>destination_bucket_name
    );

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.CREATE_REPLICATION_POLICY(
      namespace_name=>namespace, bucket_name=>bucket_name,
      create_replication_policy_details=>l_details,
      region=>region, credential_name=>credential_name
    );

    result_json.put('namespace', namespace);
    result_json.put('bucket', bucket_name);
    result_json.put('policy_name', policy_name);
    result_json.put('destination_region', destination_region_name);
    result_json.put('destination_bucket', destination_bucket_name);
    result_json.put('region', region);
    result_json.put('status_code', l_resp.status_code);
    IF l_resp.headers IS NOT NULL THEN
      IF l_resp.headers.has('opc-request-id') THEN
        result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
      END IF;
      IF l_resp.headers.has('etag') THEN
        result_json.put('etag', l_resp.headers.get_string('etag'));
      END IF;
    END IF;
    IF l_resp.response_body IS NOT NULL THEN
      result_json.put('replication_id', l_resp.response_body.id);
      IF l_resp.response_body.time_created IS NOT NULL THEN
        result_json.put('time_created', TO_CHAR(l_resp.response_body.time_created,'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
      END IF;
      result_json.put('status', l_resp.response_body.status);
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION WHEN OTHERS THEN
    result_json := JSON_OBJECT_T(); result_json.put('status','error'); result_json.put('message',SQLERRM);
    result_json.put('bucket', bucket_name); result_json.put('region', region); RETURN result_json.to_clob();
  END create_replication_policy;

  ----------------------------------------------------------------------
  -- delete_replication_policy
  ----------------------------------------------------------------------
  FUNCTION delete_replication_policy(
    region          IN VARCHAR2,
    bucket_name     IN VARCHAR2,
    replication_id  IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp          DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_DELETE_REPLICATION_POLICY_RESPONSE_T;
    result_json     JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json CLOB; l_cfg JSON_OBJECT_T; l_params JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params'); credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.DELETE_REPLICATION_POLICY(
      namespace_name=>namespace, bucket_name=>bucket_name, replication_id=>replication_id,
      region=>region, credential_name=>credential_name
    );

    result_json.put('namespace', namespace);
    result_json.put('bucket', bucket_name);
    result_json.put('replication_id', replication_id);
    result_json.put('region', region);
    result_json.put('status_code', l_resp.status_code);
    RETURN result_json.to_clob();
  EXCEPTION WHEN OTHERS THEN
    result_json := JSON_OBJECT_T(); result_json.put('status','error'); result_json.put('message',SQLERRM);
    result_json.put('bucket', bucket_name); result_json.put('region', region); RETURN result_json.to_clob();
  END delete_replication_policy;

  ----------------------------------------------------------------------
  -- create_retention_rule
  ----------------------------------------------------------------------
  FUNCTION create_retention_rule(
    region           IN VARCHAR2,
    bucket_name      IN VARCHAR2,
    display_name     IN VARCHAR2,
    duration_amount  IN NUMBER,
    time_unit        IN VARCHAR2
  ) RETURN CLOB
  AS
    l_duration    DBMS_CLOUD_OCI_OBJECT_STORAGE_DURATION_T;
    l_details     DBMS_CLOUD_OCI_OBJECT_STORAGE_CREATE_RETENTION_RULE_DETAILS_T;
    l_resp        DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_CREATE_RETENTION_RULE_RESPONSE_T;
    result_json   JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json CLOB; l_cfg JSON_OBJECT_T; l_params JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params'); credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_duration := DBMS_CLOUD_OCI_OBJECT_STORAGE_DURATION_T(duration_amount, time_unit);
    l_details  := DBMS_CLOUD_OCI_OBJECT_STORAGE_CREATE_RETENTION_RULE_DETAILS_T(
      display_name=>display_name, duration=>l_duration, time_rule_locked=>NULL
    );

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.CREATE_RETENTION_RULE(
      namespace_name=>namespace, bucket_name=>bucket_name,
      create_retention_rule_details=>l_details, region=>region, credential_name=>credential_name
    );

    result_json.put('namespace', namespace);
    result_json.put('bucket', bucket_name);
    result_json.put('display_name', display_name);
    result_json.put('region', region);
    result_json.put('status_code', l_resp.status_code);
    IF l_resp.headers IS NOT NULL THEN
      IF l_resp.headers.has('opc-request-id') THEN
        result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
      END IF;
      IF l_resp.headers.has('etag') THEN
        result_json.put('etag', l_resp.headers.get_string('etag'));
      END IF;
    END IF;
    IF l_resp.response_body IS NOT NULL THEN
      result_json.put('retention_rule_id', l_resp.response_body.id);
      result_json.put('display_name',      l_resp.response_body.display_name);
      IF l_resp.response_body.time_created IS NOT NULL THEN
        result_json.put('time_created', TO_CHAR(l_resp.response_body.time_created,'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
      END IF;
      IF l_resp.response_body.time_modified IS NOT NULL THEN
        result_json.put('time_modified', TO_CHAR(l_resp.response_body.time_modified,'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));
      END IF;
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION WHEN OTHERS THEN
    result_json := JSON_OBJECT_T(); result_json.put('status','error'); result_json.put('message',SQLERRM);
    result_json.put('bucket', bucket_name); result_json.put('region', region); RETURN result_json.to_clob();
  END create_retention_rule;

  ----------------------------------------------------------------------
  -- delete_retention_rule
  ----------------------------------------------------------------------
  FUNCTION delete_retention_rule(
    region            IN VARCHAR2,
    bucket_name       IN VARCHAR2,
    retention_rule_id IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp          DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_DELETE_RETENTION_RULE_RESPONSE_T;
    result_json     JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json CLOB; l_cfg JSON_OBJECT_T; l_params JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params'); credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;
    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.DELETE_RETENTION_RULE(
      namespace_name=>namespace, bucket_name=>bucket_name, retention_rule_id=>retention_rule_id,
      region=>region, credential_name=>credential_name
    );

    result_json.put('namespace', namespace);
    result_json.put('bucket', bucket_name);
    result_json.put('retention_rule_id', retention_rule_id);
    result_json.put('region', region);
    result_json.put('status_code', l_resp.status_code);
    RETURN result_json.to_clob();
  EXCEPTION WHEN OTHERS THEN
    result_json := JSON_OBJECT_T(); result_json.put('status','error'); result_json.put('message',SQLERRM);
    result_json.put('bucket', bucket_name); result_json.put('region', region); RETURN result_json.to_clob();
  END delete_retention_rule;

  ----------------------------------------------------------------------
  -- delete_object_lifecycle_policy
  ----------------------------------------------------------------------
  FUNCTION delete_object_lifecycle_policy(
    region       IN VARCHAR2,
    bucket_name  IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp          DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_DELETE_OBJECT_LIFECYCLE_POLICY_RESPONSE_T;
    result_json     JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user  VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json CLOB; l_cfg JSON_OBJECT_T; l_params JSON_OBJECT_T;
    credential_name VARCHAR2(256);
    namespace VARCHAR2(256);
    compartment_id  VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params'); credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;
    resolve_metadata(region => region, namespace => namespace, compartment_id => compartment_id);

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.DELETE_OBJECT_LIFECYCLE_POLICY(
      namespace_name=>namespace, bucket_name=>bucket_name,
      region=>region, credential_name=>credential_name
    );

    result_json.put('namespace', namespace);
    result_json.put('bucket', bucket_name);
    result_json.put('region', region);
    result_json.put('status_code', l_resp.status_code);
    RETURN result_json.to_clob();
  EXCEPTION WHEN OTHERS THEN
    result_json := JSON_OBJECT_T(); result_json.put('status','error'); result_json.put('message',SQLERRM);
    result_json.put('bucket', bucket_name); result_json.put('region', region); RETURN result_json.to_clob();
  END delete_object_lifecycle_policy;

  ----------------------------------------------------------------------
  -- cancel_work_request
  ----------------------------------------------------------------------
  FUNCTION cancel_work_request(
    work_request_id IN VARCHAR2,
    region          IN VARCHAR2
  ) RETURN CLOB
  AS
    l_resp         DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_CANCEL_WORK_REQUEST_RESPONSE_T;
    result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    l_current_user VARCHAR2(128):= SYS_CONTEXT('USERENV','CURRENT_USER');
    l_cfg_json CLOB; l_cfg JSON_OBJECT_T; l_params JSON_OBJECT_T;
    credential_name VARCHAR2(256);
  BEGIN
    l_cfg_json := get_agent_config(l_current_user,'SELECTAI_AGENT_CONFIG','OCI_OBJECT_STORAGE');
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status')='success' THEN
      l_params := l_cfg.get_object('config_params'); credential_name := l_params.get_string('CREDENTIAL_NAME');
    END IF;

    l_resp := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.CANCEL_WORK_REQUEST(
      work_request_id=>work_request_id, region=>region, credential_name=>credential_name
    );

    result_json.put('work_request_id', work_request_id);
    result_json.put('region', region);
    result_json.put('status_code', l_resp.status_code);
    IF l_resp.headers IS NOT NULL AND l_resp.headers.has('opc-request-id') THEN
      result_json.put('opc_request_id', l_resp.headers.get_string('opc-request-id'));
    END IF;

    RETURN result_json.to_clob();
  EXCEPTION WHEN OTHERS THEN
    result_json := JSON_OBJECT_T(); result_json.put('status','error'); result_json.put('message',SQLERRM);
    result_json.put('work_request_id', work_request_id); result_json.put('region', region);
    RETURN result_json.to_clob();
  END cancel_work_request;

END oci_object_storage_agents;
/

-------------------------------------------------------------------------------
-- This procedure installs or refreshes the Object Storage AI Agent tools in
-- the current schema. It drops any existing definitions and recreates the
-- tools using the latest package methods in &&INSTALL_SCHEMA,
-------------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE initialize_object_storage_tools
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
  -- AI TOOL: LIST_OBJECTS_TOOL
  -- maps to oci_object_storage_agents.list_objects
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'LIST_OBJECTS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_OBJECTS_TOOL',
    attributes => '{
      "instruction": "List all objects in a bucket using resolved namespace and configured credentials; surfaces per-object metadata for inventory, audit, and pre/post operation workflows.",
      "function": "oci_object_storage_agents.list_objects"
    }',
    description => 'Tool for listing objects in OCI Object Storage'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: LIST_BUCKETS_TOOL
  -- maps to oci_object_storage_agents.list_buckets
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'LIST_BUCKETS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_BUCKETS_TOOL',
    attributes => '{
      "instruction": "List all Object Storage buckets visible to the configured compartment scope in the given region; useful for navigation, selection, and governance views.",
      "function": "oci_object_storage_agents.list_buckets"
    }',
    description => 'Tool for listing Object Storage buckets'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: GET_BUCKET_TOOL
  -- maps to oci_object_storage_agents.get_bucket
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'GET_BUCKET_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_BUCKET_TOOL',
    attributes => '{
      "instruction": "Fetches a bucket’s configuration and summary properties in the given region to support governance, diagnostics, and detail panes.",
      "function": "oci_object_storage_agents.get_bucket"
    }',
    description => 'Tool for retrieving Object Storage bucket metadata'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: HEAD_BUCKET_TOOL
  -- maps to oci_object_storage_agents.head_bucket
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'HEAD_BUCKET_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'HEAD_BUCKET_TOOL',
    attributes => '{
      "instruction": "Performs a lightweight metadata probe (HEAD) on a bucket to validate existence and inspect headers without retrieving content.",
      "function": "oci_object_storage_agents.head_bucket"
    }',
    description => 'Tool for retrieving Object Storage bucket metadata headers'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: HEAD_OBJECT_TOOL
  -- maps to oci_object_storage_agents.head_object
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'HEAD_OBJECT_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'HEAD_OBJECT_TOOL',
    attributes => '{
      "instruction": "Performs an object metadata probe (HEAD) to validate existence and inspect headers such as etag and content-type without downloading payload.",
      "function": "oci_object_storage_agents.head_object"
    }',
    description => 'Tool for retrieving Object Storage object metadata headers'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: LIST_MULTIPART_UPLOADS_TOOL
  -- maps to oci_object_storage_agents.list_multipart_uploads
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'LIST_MULTIPART_UPLOADS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_MULTIPART_UPLOADS_TOOL',
    attributes => '{
      "instruction": "List all in-progress multipart uploads for a bucket to help resume, commit, or clean up unfinished large-object transfers.",
      "function": "oci_object_storage_agents.list_multipart_uploads"
    }',
    description => 'Tool for listing multipart uploads in Object Storage'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: LIST_MULTIPART_UPLOAD_PARTS_TOOL
  -- maps to oci_object_storage_agents.list_multipart_upload_parts
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'LIST_MULTIPART_UPLOAD_PARTS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_MULTIPART_UPLOAD_PARTS_TOOL',
    attributes => '{
      "instruction": "Inspects the parts uploaded for a given multipart session, enabling validation and completion logic for large transfers.",
      "function": "oci_object_storage_agents.list_multipart_upload_parts"
    }',
    description => 'Tool for listing multipart upload parts in Object Storage'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: MAKE_BUCKET_WRITABLE_TOOL
  -- maps to oci_object_storage_agents.make_bucket_writable
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'MAKE_BUCKET_WRITABLE_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'MAKE_BUCKET_WRITABLE_TOOL',
    attributes => '{
      "instruction": "Transitions a bucket to a writable state when it is read-only; use before performing write operations.",
      "function": "oci_object_storage_agents.make_bucket_writable"
    }',
    description => 'Tool to set an OCI Object Storage bucket as writable'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: PUT_OBJECT_LIFECYCLE_POLICY_TOOL
  -- maps to oci_object_storage_agents.put_object_lifecycle_policy
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'PUT_OBJECT_LIFECYCLE_POLICY_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'PUT_OBJECT_LIFECYCLE_POLICY_TOOL',
    attributes => '{
      "instruction": "Defines lifecycle management rules on a bucket to transition or delete objects based on age or criteria.",
      "function": "oci_object_storage_agents.put_object_lifecycle_policy"
    }',
    description => 'Tool to set lifecycle policies for OCI Object Storage buckets'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: LIST_RETENTION_RULES_TOOL
  -- maps to oci_object_storage_agents.list_retention_rules
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'LIST_RETENTION_RULES_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_RETENTION_RULES_TOOL',
    attributes => '{
      "instruction": "List retention rules on a bucket to assess compliance posture and cleanup eligibility.",
      "function": "oci_object_storage_agents.list_retention_rules"
    }',
    description => 'Tool for listing OCI Object Storage retention rules'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: GET_RETENTION_RULE_TOOL
  -- maps to oci_object_storage_agents.get_retention_rule
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'GET_RETENTION_RULE_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_RETENTION_RULE_TOOL',
    attributes => '{
      "instruction": "Retrieves the full definition of a specific retention rule for review or update workflows.",
      "function": "oci_object_storage_agents.get_retention_rule"
    }',
    description => 'Tool for retrieving Object Storage retention rule details'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: GET_OBJECT_TOOL
  -- maps to oci_object_storage_agents.get_object
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'GET_OBJECT_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_OBJECT_TOOL',
    attributes => '{
      "instruction": "Retrieves object metadata (not payload) to inform downstream decisions such as conditional reads, cache validation, or UI displays.",
      "function": "oci_object_storage_agents.get_object"
    }',
    description => 'Tool for retrieving Object Storage object metadata (summary)'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: PUT_OBJECT_TOOL
  -- maps to oci_object_storage_agents.put_object
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'PUT_OBJECT_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'PUT_OBJECT_TOOL',
    attributes => '{
      "instruction": "Upload object content to a bucket with an explicit MIME type; use for uploads and content updates.",
      "function": "oci_object_storage_agents.put_object"
    }',
    description => 'Tool to upload objects to OCI Object Storage'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: LIST_PREAUTHENTICATED_REQUESTS_TOOL
  -- maps to oci_object_storage_agents.list_preauthenticated_requests
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'LIST_PREAUTHENTICATED_REQUESTS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_PREAUTHENTICATED_REQUESTS_TOOL',
    attributes => '{
      "instruction": "Lists existing Preauthenticated Requests (PARs) for a bucket to audit access links and manage sharing.",
      "function": "oci_object_storage_agents.list_preauthenticated_requests"
    }',
    description => 'Tool for listing preauthenticated requests (PARs)'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: LIST_REPLICATION_POLICIES_TOOL
  -- maps to oci_object_storage_agents.list_replication_policies
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'LIST_REPLICATION_POLICIES_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_REPLICATION_POLICIES_TOOL',
    attributes => '{
      "instruction": "Lists replication policies configured on a bucket to understand cross-region replication posture.",
      "function": "oci_object_storage_agents.list_replication_policies"
    }',
    description => 'Tool for listing Object Storage replication policies'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: GET_REPLICATION_POLICY_TOOL
  -- maps to oci_object_storage_agents.get_replication_policy
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'GET_REPLICATION_POLICY_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_REPLICATION_POLICY_TOOL',
    attributes => '{
      "instruction": "Retrieves details of a specific replication policy for status and configuration inspection.",
      "function": "oci_object_storage_agents.get_replication_policy"
    }',
    description => 'Tool for retrieving replication policy details'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: LIST_REPLICATION_SOURCES_TOOL
  -- maps to oci_object_storage_agents.list_replication_sources
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'LIST_REPLICATION_SOURCES_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_REPLICATION_SOURCES_TOOL',
    attributes => '{
      "instruction": "Lists upstream replication sources associated with a bucket to understand replication topology.",
      "function": "oci_object_storage_agents.list_replication_sources"
    }',
    description => 'Tool for listing replication sources'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: REENCRYPT_BUCKET_TOOL
  -- maps to oci_object_storage_agents.reencrypt_bucket
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'REENCRYPT_BUCKET_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'REENCRYPT_BUCKET_TOOL',
    attributes => '{
      "instruction": "Initiates a bucket-level re-encryption operation, typically after KMS rotation or encryption policy changes.",
      "function": "oci_object_storage_agents.reencrypt_bucket"
    }',
    description => 'Tool to re-encrypt buckets'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: REENCRYPT_OBJECT_TOOL
  -- maps to oci_object_storage_agents.reencrypt_object
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'REENCRYPT_OBJECT_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'REENCRYPT_OBJECT_TOOL',
    attributes => '{
      "instruction": "Initiates re-encryption for a specific object, typically after KMS or encryption policy changes.",
      "function": "oci_object_storage_agents.reencrypt_object"
    }',
    description => 'Tool to re-encrypt objects'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: RENAME_OBJECT_TOOL
  -- maps to oci_object_storage_agents.rename_object
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'RENAME_OBJECT_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'RENAME_OBJECT_TOOL',
    attributes => '{
      "instruction": "Renames or moves an object within a bucket by changing its key name.",
      "function": "oci_object_storage_agents.rename_object"
    }',
    description => 'Tool to rename objects'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: RESTORE_OBJECTS_TOOL
  -- maps to oci_object_storage_agents.restore_objects
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'RESTORE_OBJECTS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'RESTORE_OBJECTS_TOOL',
    attributes => '{
      "instruction": "Restores archived or versioned content for a limited duration to enable reads or rehydration.",
      "function": "oci_object_storage_agents.restore_objects"
    }',
    description => 'Tool to restore objects from Object Storage'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: UPLOAD_PART_TOOL
  -- maps to oci_object_storage_agents.upload_part
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'UPLOAD_PART_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'UPLOAD_PART_TOOL',
    attributes => '{
      "instruction": "Uploads a single part for an ongoing multipart transfer; repeat to assemble large objects.",
      "function": "oci_object_storage_agents.upload_part"
    }',
    description => 'Tool for multipart upload parts'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: UPDATE_NAMESPACE_METADATA_TOOL
  -- maps to oci_object_storage_agents.update_namespace_metadata
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'UPDATE_NAMESPACE_METADATA_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'UPDATE_NAMESPACE_METADATA_TOOL',
    attributes => '{
      "instruction": "Sets default namespace metadata such as default compartments for S3/Swift interoperability.",
      "function": "oci_object_storage_agents.update_namespace_metadata"
    }',
    description => 'Tool to update namespace metadata'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: UPDATE_RETENTION_RULE_TOOL
  -- maps to oci_object_storage_agents.update_retention_rule
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'UPDATE_RETENTION_RULE_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'UPDATE_RETENTION_RULE_TOOL',
    attributes => '{
      "instruction": "Modifies an existing retention rule on a bucket to change display name or retention duration.",
      "function": "oci_object_storage_agents.update_retention_rule"
    }',
    description => 'Tool to update retention rules'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: LIST_WORK_REQUESTS_TOOL
  -- maps to oci_object_storage_agents.list_work_requests
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'LIST_WORK_REQUESTS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_WORK_REQUESTS_TOOL',
    attributes => '{
      "instruction": "Lists Object Storage work requests for the configured compartment to monitor asynchronous operations.",
      "function": "oci_object_storage_agents.list_work_requests"
    }',
    description => 'Tool for listing work requests'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: LIST_WORK_REQUEST_ERRORS_TOOL
  -- maps to oci_object_storage_agents.list_work_request_errors
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'LIST_WORK_REQUEST_ERRORS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_WORK_REQUEST_ERRORS_TOOL',
    attributes => '{
      "instruction": "Retrieves error items associated with a work request to aid troubleshooting.",
      "function": "oci_object_storage_agents.list_work_request_errors"
    }',
    description => 'Tool for listing work request errors'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: LIST_WORK_REQUEST_LOGS_TOOL
  -- maps to oci_object_storage_agents.list_work_request_logs
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'LIST_WORK_REQUEST_LOGS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_WORK_REQUEST_LOGS_TOOL',
    attributes => '{
      "instruction": "Retrieves log messages for a work request to track progress and diagnose issues.",
      "function": "oci_object_storage_agents.list_work_request_logs"
    }',
    description => 'Tool for listing work request logs'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: GET_WORK_REQUEST_TOOL
  -- maps to oci_object_storage_agents.get_work_request
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'GET_WORK_REQUEST_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_WORK_REQUEST_TOOL',
    attributes => '{
      "instruction": "Retrieves the current status and key attributes of a specific work request for monitoring.",
      "function": "oci_object_storage_agents.get_work_request"
    }',
    description => 'Tool for retrieving work request details'
  );

  ------------------------------------------------------------------------
  -- AI TOOL: UPDATE_BUCKET_TOOL
  -- maps to oci_object_storage_agents.update_bucket
  ------------------------------------------------------------------------
  drop_tool_if_exists(tool_name => 'UPDATE_BUCKET_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
      tool_name => 'UPDATE_BUCKET_TOOL',
      attributes => '{
          "instruction": "Updates bucket configuration such as display name, versioning state, public access, and object event settings.",
          "function": "oci_object_storage_agents.update_bucket"
      }',
      description => 'Tool to update OCI Object Storage buckets'
  );

  -- CREATE_BUCKET_TOOL
  drop_tool_if_exists(tool_name => 'CREATE_BUCKET_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'CREATE_BUCKET_TOOL',
    attributes => '{
      "instruction": "Creates a new Object Storage bucket in the specified region under the configured compartment scope.",
      "function": "oci_object_storage_agents.create_bucket"
    }',
    description => 'Tool to create Object Storage buckets'
  );

  -- DELETE_BUCKET_TOOL
  drop_tool_if_exists(tool_name => 'DELETE_BUCKET_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'DELETE_BUCKET_TOOL',
    attributes => '{
      "instruction": "Removes an Object Storage bucket that is already empty; use for deprovisioning.",
      "function": "oci_object_storage_agents.delete_bucket"
    }',
    description => 'Tool to delete Object Storage buckets'
  );

  -- DELETE_OBJECT_TOOL
  drop_tool_if_exists(tool_name => 'DELETE_OBJECT_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'DELETE_OBJECT_TOOL',
    attributes => '{
      "instruction": "Removes an object from a bucket; use for cleanup, archival workflows, or version management.",
      "function": "oci_object_storage_agents.delete_object"
    }',
    description => 'Tool to delete objects from Object Storage'
  );

  -- COPY_OBJECT_TOOL
  drop_tool_if_exists(tool_name => 'COPY_OBJECT_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'COPY_OBJECT_TOOL',
    attributes => '{
      "instruction": "Copies an object to a destination bucket and region, enabling cross-bucket or cross-region duplication.",
      "function": "oci_object_storage_agents.copy_object"
    }',
    description => 'Tool to copy objects between buckets/regions'
  );

  -- CREATE_MULTIPART_UPLOAD_TOOL
  drop_tool_if_exists(tool_name => 'CREATE_MULTIPART_UPLOAD_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'CREATE_MULTIPART_UPLOAD_TOOL',
    attributes => '{
      "instruction": "Initiates a multipart upload session for large object transfers.",
      "function": "oci_object_storage_agents.create_multipart_upload"
    }',
    description => 'Tool to start multipart uploads'
  );

  -- COMMIT_MULTIPART_UPLOAD_TOOL
  drop_tool_if_exists(tool_name => 'COMMIT_MULTIPART_UPLOAD_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'COMMIT_MULTIPART_UPLOAD_TOOL',
    attributes => '{
      "instruction": "Finalizes a multipart upload by committing the selected parts.",
      "function": "oci_object_storage_agents.commit_multipart_upload"
    }',
    description => 'Tool to finalize multipart uploads'
  );

  -- ABORT_MULTIPART_UPLOAD_TOOL
  drop_tool_if_exists(tool_name => 'ABORT_MULTIPART_UPLOAD_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'ABORT_MULTIPART_UPLOAD_TOOL',
    attributes => '{
      "instruction": "Cancels an in-progress multipart upload and cleans up partial state.",
      "function": "oci_object_storage_agents.abort_multipart_upload"
    }',
    description => 'Tool to abort multipart uploads'
  );

  -- CREATE_PREAUTHENTICATED_REQUEST_TOOL
  drop_tool_if_exists(tool_name => 'CREATE_PREAUTHENTICATED_REQUEST_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'CREATE_PREAUTHENTICATED_REQUEST_TOOL',
    attributes => '{
      "instruction": "Creates a Preauthenticated Request (PAR) to grant time‑bound access to a bucket or object via a signed URL.",
      "function": "oci_object_storage_agents.create_preauthenticated_request"
    }',
    description => 'Tool to create PARs for Object Storage'
  );

  -- GET_PREAUTHENTICATED_REQUEST_TOOL
  drop_tool_if_exists(tool_name => 'GET_PREAUTHENTICATED_REQUEST_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_PREAUTHENTICATED_REQUEST_TOOL',
    attributes => '{
      "instruction": "Retrieves details of a Preauthenticated Request (PAR) for review, auditing, or client presentation.",
      "function": "oci_object_storage_agents.get_preauthenticated_request"
    }',
    description => 'Tool to get PAR details'
  );

  -- DELETE_PREAUTHENTICATED_REQUEST_TOOL
  drop_tool_if_exists(tool_name => 'DELETE_PREAUTHENTICATED_REQUEST_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'DELETE_PREAUTHENTICATED_REQUEST_TOOL',
    attributes => '{
      "instruction": "Revokes a Preauthenticated Request (PAR) to immediately disable the shared link.",
      "function": "oci_object_storage_agents.delete_preauthenticated_request"
    }',
    description => 'Tool to delete PARs'
  );

  -- CREATE_REPLICATION_POLICY_TOOL
  drop_tool_if_exists(tool_name => 'CREATE_REPLICATION_POLICY_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'CREATE_REPLICATION_POLICY_TOOL',
    attributes => '{
      "instruction": "Creates a cross‑region replication policy from a source bucket to a destination bucket to enable continuous replication.",
      "function": "oci_object_storage_agents.create_replication_policy"
    }',
    description => 'Tool to create replication policies'
  );

  -- DELETE_REPLICATION_POLICY_TOOL
  drop_tool_if_exists(tool_name => 'DELETE_REPLICATION_POLICY_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'DELETE_REPLICATION_POLICY_TOOL',
    attributes => '{
      "instruction": "Removes a replication policy from a bucket to stop replication.",
      "function": "oci_object_storage_agents.delete_replication_policy"
    }',
    description => 'Tool to delete replication policies'
  );

  -- CREATE_RETENTION_RULE_TOOL
  drop_tool_if_exists(tool_name => 'CREATE_RETENTION_RULE_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'CREATE_RETENTION_RULE_TOOL',
    attributes => '{
      "instruction": "Creates a retention rule on a bucket to enforce minimum retention periods for objects.",
      "function": "oci_object_storage_agents.create_retention_rule"
    }',
    description => 'Tool to create Object Storage retention rules'
  );

  -- DELETE_RETENTION_RULE_TOOL
  drop_tool_if_exists(tool_name => 'DELETE_RETENTION_RULE_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'DELETE_RETENTION_RULE_TOOL',
    attributes => '{
      "instruction": "Removes an existing retention rule from a bucket.",
      "function": "oci_object_storage_agents.delete_retention_rule"
    }',
    description => 'Tool to delete Object Storage retention rules'
  );

  -- DELETE_OBJECT_LIFECYCLE_POLICY_TOOL
  drop_tool_if_exists(tool_name => 'DELETE_OBJECT_LIFECYCLE_POLICY_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'DELETE_OBJECT_LIFECYCLE_POLICY_TOOL',
    attributes => '{
      "instruction": "Removes the lifecycle policy from a bucket to stop automated transitions or deletions.",
      "function": "oci_object_storage_agents.delete_object_lifecycle_policy"
    }',
    description => 'Tool to delete lifecycle policy on a bucket'
  );

  -- CANCEL_WORK_REQUEST_TOOL
  drop_tool_if_exists(tool_name => 'CANCEL_WORK_REQUEST_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'CANCEL_WORK_REQUEST_TOOL',
    attributes => '{
      "instruction": "Requests cancellation of an asynchronous Object Storage work request.",
      "function": "oci_object_storage_agents.cancel_work_request"
    }',
    description => 'Tool to cancel Object Storage work requests'
  );

  -- GET_NAMESPACE_TOOL
  drop_tool_if_exists(tool_name => 'GET_NAMESPACE_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_NAMESPACE_TOOL',
    attributes => '{
      "instruction": "Resolves the tenancy’s Object Storage namespace for the given region; foundational for bucket and object operations.",
      "function": "oci_object_storage_agents.get_namespace"
    }',
    description => 'Tool to retrieve Object Storage namespace'
  );

END initialize_object_storage_tools;
/

-------------------------------------------------------------------------------
-- Call the procedure to (re)create all OCI Vault AI Agent tools
-------------------------------------------------------------------------------
BEGIN
  initialize_object_storage_tools;
END;
/

alter session set current_schema = ADMIN;