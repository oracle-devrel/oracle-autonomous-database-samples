rem ============================================================================
rem LICENSE
rem   Copyright (c) 2025 Oracle and/or its affiliates.
rem   Licensed under the Universal Permissive License (UPL), Version 1.0
rem   https://oss.oracle.com/licenses/upl/
rem
rem NAME
rem   oci_vault_agent.sql
rem
rem DESCRIPTION
rem   Installer and configuration script for OCI Vault AI Agent
rem   using DBMS_CLOUD_AI_AGENT (Select AI / Oracle AI Database).
rem
rem   This script performs an interactive installation of an
rem   OCI Vault AI Agent by:
rem     - Prompting for target schema and AI Profile
rem     - Granting required privileges to the target schema
rem     - Creating an installer procedure in the target schema
rem     - Registering an OCI Vault Task with supported Vault tools
rem     - Creating an OCI Vault AI Agent bound to the specified AI Profile
rem     - Creating an OCI Vault Team linking the agent and task
rem     - Executing the installer procedure to complete setup
rem
rem RELEASE VERSION
rem   1.1
rem
rem RELEASE DATE
rem   06-Feb-2026
rem
rem MAJOR CHANGES IN THIS RELEASE
rem   - Initial release
rem   - Added OCI Vault task, agent, and team registration
rem   - Interactive installer with schema and AI profile prompts
rem
rem SCRIPT STRUCTURE
rem   1. Initialization:
rem        - Enable output and error handling
rem        - Prompt for target schema and AI profile
rem
rem   2. Grants:
rem        - Grant DBMS_CLOUD_AI_AGENT and DBMS_CLOUD privileges
rem          to the target schema
rem
rem   3. Installer Procedure Creation:
rem        - Create INSTALL_OCI_VAULT_AGENT procedure
rem          in the target schema
rem
rem   4. AI Registration:
rem        - Drop and create OCI_VAULT_TASKS
rem        - Drop and create OCI_VAULT_ADVISOR agent
rem        - Drop and create OCI_VAULT_TEAM
rem
rem   5. Execution:
rem        - Execute installer procedure with AI profile parameter
rem
rem INSTALL INSTRUCTIONS
rem   1. Connect as ADMIN or a privileged user
rem
rem   2. Run the script using SQL*Plus or SQLcl:
rem
rem      sqlplus admin@db @oci_vault_agent.sql
rem
rem   3. Provide inputs when prompted:
rem        - Target schema name
rem        - AI Profile name
rem
rem   4. Verify installation by confirming:
rem        - OCI_VAULT_TASKS task exists
rem        - OCI_VAULT_ADVISOR agent is created
rem        - OCI_VAULT_TEAM team is registered
rem
rem PARAMETERS
rem   SCHEMA_NAME (Prompted)
rem     Target schema where the installer procedure,
rem     task, agent, and team are created.
rem
rem   AI_PROFILE_NAME (Prompted)
rem     AI Profile name used to bind the OCI Vault agent.
rem
rem NOTES
rem   - Script can be re-run; existing tasks, agents,
rem     and teams are dropped and recreated.
rem
rem   - Destructive Vault operations require user confirmation
rem     as enforced by agent task instructions.
rem
rem   - Script exits immediately on SQL errors.
rem
rem ============================================================================


SET SERVEROUTPUT ON
SET VERIFY OFF

PROMPT ======================================================
PROMPT OCI Vault AI Agent Installer
PROMPT ======================================================

-- Target schema
VAR v_schema VARCHAR2(128)
EXEC :v_schema := '&SCHEMA_NAME';

-- AI Profile
VAR v_ai_profile_name VARCHAR2(128)
EXEC :v_ai_profile_name := '&AI_PROFILE_NAME';

----------------------------------------------------------------
-- 1. Grants (safe to re-run)
----------------------------------------------------------------
DECLARE
  l_sql VARCHAR2(500);
BEGIN
  l_sql := 'GRANT EXECUTE ON DBMS_CLOUD_AI_AGENT TO ' || :v_schema;
  EXECUTE IMMEDIATE l_sql;

  l_sql := 'GRANT EXECUTE ON DBMS_CLOUD_AI TO ' || :v_schema;
  EXECUTE IMMEDIATE l_sql;

  l_sql := 'GRANT EXECUTE ON DBMS_CLOUD TO ' || :v_schema;
  EXECUTE IMMEDIATE l_sql;

  DBMS_OUTPUT.PUT_LINE('Grants completed.');
END;
/

----------------------------------------------------------------
-- 2. Create installer procedure in target schema
----------------------------------------------------------------
BEGIN
  EXECUTE IMMEDIATE
    'ALTER SESSION SET CURRENT_SCHEMA = ' || :v_schema;
END;
/

CREATE OR REPLACE PROCEDURE install_oci_vault_agent (
  p_profile_name IN VARCHAR2
)
AUTHID DEFINER
AS
BEGIN
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Starting OCI Vault AI installation');
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');

  ------------------------------------------------------------
  -- DROP and CREATE TASK
  ------------------------------------------------------------
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TASK('OCI_VAULT_TASKS');
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name   => 'OCI_VAULT_TASKS',
    description => 'Task for managing OCI Vault secrets and versions.',
    attributes  => '{
      "instruction": "Identify the intent of the user request and determine the correct OCI Vault operation. '
        || 'Prompt the user only for necessary missing details. '
        || 'Ask clarifying questions if intent is ambiguous. '
        || 'When presenting any list, object, or JSON structure to the user, format it in a human-readable way. '
        || 'Use LIST_SUBSCRIBED_REGIONS_TOOL to list regions and confirm with the user. '
        || 'Use LIST_SECRETS_TOOL to list secrets. '
        || 'Use GET_SECRET_TOOL to retrieve secret metadata. '
        || 'Use CREATE_SECRET_TOOL to create a secret. '
        || 'Use UPDATE_SECRET_TOOL to update metadata or rotate content. '
        || 'Use LIST_SECRET_VERSIONS_TOOL / GET_SECRET_VERSION_TOOL to inspect versions. '
        || 'Use SCHEDULE_SECRET_DELETION_TOOL / SCHEDULE_SECRET_VERSION_DELETION_TOOL for deletions (confirm first). '
        || 'Use CANCEL_SECRET_DELETION_TOOL / CANCEL_SECRET_VERSION_DELETION_TOOL to cancel scheduled deletion. '
        || 'Use CHANGE_SECRET_COMPARTMENT_TOOL to move a secret. '
        || 'Confirm destructive actions with the user before proceeding. '
        || 'User request: {query}",
      "tools": [
        "LIST_SUBSCRIBED_REGIONS_TOOL",
        "LIST_SECRETS_TOOL",
        "GET_SECRET_TOOL",
        "CREATE_SECRET_TOOL",
        "UPDATE_SECRET_TOOL",
        "LIST_SECRET_VERSIONS_TOOL",
        "GET_SECRET_VERSION_TOOL",
        "SCHEDULE_SECRET_DELETION_TOOL",
        "SCHEDULE_SECRET_VERSION_DELETION_TOOL",
        "CANCEL_SECRET_DELETION_TOOL",
        "CANCEL_SECRET_VERSION_DELETION_TOOL",
        "CHANGE_SECRET_COMPARTMENT_TOOL"
      ],
      "enable_human_tool": "true"
    }'
  );
  DBMS_OUTPUT.PUT_LINE('Created task OCI_VAULT_TASKS');

  ------------------------------------------------------------
  -- DROP and CREATE AGENT
  ------------------------------------------------------------
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_AGENT('OCI_VAULT_ADVISOR');
    DBMS_OUTPUT.PUT_LINE('Dropped agent OCI_VAULT_ADVISOR');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Agent OCI_VAULT_ADVISOR does not exist, skipping');
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'OCI_VAULT_ADVISOR',
    attributes =>
      '{' ||
      '"profile_name":"' || p_profile_name || '",' ||
      '"role":"You are an OCI Vault Advisor. You help users list, inspect, create, update, and manage secret versions safely. You confirm destructive actions before executing and present results clearly."' ||
      '}',
    description => 'AI agent for advising and automating OCI Vault operations'
  );
  DBMS_OUTPUT.PUT_LINE('Created agent OCI_VAULT_ADVISOR');

  ------------------------------------------------------------
  -- DROP and CREATE TEAM
  ------------------------------------------------------------
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TEAM('OCI_VAULT_TEAM');
    DBMS_OUTPUT.PUT_LINE('Dropped team OCI_VAULT_TEAM');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Team OCI_VAULT_TEAM does not exist, skipping');
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
    team_name  => 'OCI_VAULT_TEAM',
    attributes => '{
      "agents":[{"name":"OCI_VAULT_ADVISOR","task":"OCI_VAULT_TASKS"}],
      "process":"sequential"
    }'
  );
  DBMS_OUTPUT.PUT_LINE('Created team OCI_VAULT_TEAM');

  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('OCI Vault AI installation COMPLETE');
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
END install_oci_vault_agent;
/

----------------------------------------------------------------
-- 3. Execute installer in target schema
----------------------------------------------------------------
PROMPT Executing installer procedure ...
BEGIN
  install_oci_vault_agent(p_profile_name => :v_ai_profile_name);
END;
/

alter session set current_schema = ADMIN;

PROMPT ======================================================
PROMPT Installation finished successfully
PROMPT ======================================================