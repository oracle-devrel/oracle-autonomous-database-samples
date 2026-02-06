rem ============================================================================
rem LICENSE
rem   Copyright (c) 2025 Oracle and/or its affiliates.
rem   Licensed under the Universal Permissive License (UPL), Version 1.0
rem   https://oss.oracle.com/licenses/upl/
rem
rem NAME
rem   oci_autonomous_database_agent.sql
rem
rem DESCRIPTION
rem   Installer and configuration script for OCI Autonomous Database
rem   AI Agent using DBMS_CLOUD_AI_AGENT
rem   (Select AI / Oracle Autonomous AI Database).
rem
rem   This script performs an interactive installation of an
rem   OCI Autonomous Database AI Agent by:
rem     - Prompting for target schema and AI Profile
rem     - Granting required privileges to the target schema
rem     - Creating an installer procedure in the target schema
rem     - Registering an OCI Autonomous Database Task
rem     - Creating an OCI Autonomous Database AI Agent bound
rem       to the specified AI Profile
rem     - Creating an OCI Autonomous Database Team linking
rem       the agent and task
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
rem   - Added OCI Autonomous Database task, agent, and team
rem   - Interactive installer with schema and AI profile prompts
rem   - Bug Fixes
rem
rem SCRIPT STRUCTURE
rem   1. Initialization:
rem        - Enable SQL*Plus settings and error handling
rem        - Prompt for target schema and AI profile
rem
rem   2. Grants:
rem        - Grant DBMS_CLOUD_AI_AGENT and DBMS_CLOUD privileges
rem          to the target schema
rem
rem   3. Installer Procedure Creation:
rem        - Create INSTALL_OCI_AUTONOMOUS_DATABASE_AGENT
rem          procedure in the target schema
rem
rem   4. AI Registration:
rem        - Drop and create OCI_AUTONOMOUS_DATABASE_TASKS
rem        - Drop and create OCI_AUTONOMOUS_DATABASE_ADVISOR
rem          agent
rem        - Drop and create OCI_AUTONOMOUS_DATABASE_TEAM
rem
rem   5. Execution:
rem        - Execute installer procedure with AI profile parameter
rem
rem INSTALL INSTRUCTIONS
rem   1. Connect as ADMIN or a user with required privileges
rem
rem   2. Run the script using SQL*Plus or SQLcl:
rem
rem      sqlplus admin@db @oci_autonomous_database_agent.sql
rem
rem   3. Provide inputs when prompted:
rem        - Target schema name
rem        - AI Profile name
rem
rem   4. Verify installation by confirming:
rem        - OCI_AUTONOMOUS_DATABASE_TASKS task exists
rem        - OCI_AUTONOMOUS_DATABASE_ADVISOR agent is created
rem        - OCI_AUTONOMOUS_DATABASE_TEAM team is registered
rem
rem PARAMETERS
rem   SCHEMA_NAME (Prompted)
rem     Target schema where the installer procedure,
rem     task, agent, and team are created.
rem
rem   AI_PROFILE_NAME (Prompted)
rem     AI Profile name used to bind the OCI Autonomous
rem     Database agent.
rem
rem NOTES
rem   - Script is safe to re-run; existing tasks, agents,
rem     and teams are dropped and recreated.
rem
rem   - Destructive Autonomous Database operations require
rem     explicit user confirmation as enforced by task instructions.
rem
rem   - Script exits immediately on SQL errors.
rem
rem ============================================================================


SET SERVEROUTPUT ON
SET VERIFY OFF

PROMPT ======================================================
PROMPT OCI Autonomous Database AI Agent Installer
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

CREATE OR REPLACE PROCEDURE install_oci_autonomous_database_agent (
  p_profile_name IN VARCHAR2
)
AUTHID DEFINER
AS
BEGIN
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Starting OCI Autonomous Database AI installation');
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');

  ------------------------------------------------------------
  -- DROP and CREATE TASK
  ------------------------------------------------------------
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TASK('OCI_AUTONOMOUS_DATABASE_TASKS');
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name   => 'OCI_AUTONOMOUS_DATABASE_TASKS',
    description => 'Task for provisioning and managing OCI Autonomous Databases.',
    attributes  => '{
      "instruction": "Identify the intent of the user request and determine the correct Autonomous Database operation. '
        || 'Prompt the user only for necessary missing details. '
        || 'Ask clarifying questions if intent is ambiguous. '
        || 'When presenting any list, object, or JSON structure to the user, format it in a human-readable way. '
        || 'Confirm destructive actions before execution. '
        || 'User request: {query}",
      "tools": [
        "LIST_SUBSCRIBED_REGIONS_TOOL",
        "LIST_COMPARTMENTS_TOOL",
        "GET_COMPARTMENT_OCID_BY_NAME_TOOL",
        "LIST_AUTONOMOUS_DATABASES_TOOL",
        "GET_AUTONOMOUS_DATABASE_DETAILS_TOOL",
        "ADBS_PROVISIONING_TOOL",
        "ADBS_UNPROVISION_TOOL",
        "START_AUTONOMOUS_DATABASE_TOOL",
        "STOP_AUTONOMOUS_DATABASE_TOOL",
        "DATABASE_RESTART_TOOL",
        "MANAGE_AUTONOMOUS_DB_POWER_TOOL",
        "UPDATE_AUTONOMOUS_DB_RESOURCES_TOOL",
        "GET_MAINTENANCE_RUN_HISTORY_TOOL",
        "UPDATE_AUTONOMOUS_DATABASE_TOOL",
        "LIST_KEY_STORES_TOOL",
        "LIST_DB_HOMES_TOOL",
        "SHRINK_AUTONOMOUS_DATABASE_TOOL",
        "DELETE_KEY_STORE_TOOL",
        "LIST_ACDS_TOOL",
        "LIST_ADB_BACKUPS_TOOL"
      ],
      "enable_human_tool": "true"
    }'
  );
  DBMS_OUTPUT.PUT_LINE('Created task OCI_AUTONOMOUS_DATABASE_TASKS');

  ------------------------------------------------------------
  -- DROP and CREATE AGENT
  ------------------------------------------------------------
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_AGENT('OCI_AUTONOMOUS_DATABASE_ADVISOR');
    DBMS_OUTPUT.PUT_LINE('Dropped agent OCI_AUTONOMOUS_DATABASE_ADVISOR');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Agent OCI_AUTONOMOUS_DATABASE_ADVISOR does not exist, skipping');
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'OCI_AUTONOMOUS_DATABASE_ADVISOR',
    attributes =>
      '{' ||
      '"profile_name":"' || p_profile_name || '",' ||
      '"role":"You are an OCI Autonomous Database Advisor. You help users provision, list, start/stop/restart, resize, update configuration, and inspect ADB-related resources safely. You confirm destructive actions and present results clearly."' ||
      '}',
    description => 'AI agent for advising and automating OCI Autonomous Database operations'
  );
  DBMS_OUTPUT.PUT_LINE('Created agent OCI_AUTONOMOUS_DATABASE_ADVISOR');

  ------------------------------------------------------------
  -- DROP and CREATE TEAM
  ------------------------------------------------------------
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TEAM('OCI_AUTONOMOUS_DATABASE_TEAM');
    DBMS_OUTPUT.PUT_LINE('Dropped team OCI_AUTONOMOUS_DATABASE_TEAM');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Team OCI_AUTONOMOUS_DATABASE_TEAM does not exist, skipping');
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
    team_name  => 'OCI_AUTONOMOUS_DATABASE_TEAM',
    attributes => '{
      "agents":[{"name":"OCI_AUTONOMOUS_DATABASE_ADVISOR","task":"OCI_AUTONOMOUS_DATABASE_TASKS"}],
      "process":"sequential"
    }'
  );
  DBMS_OUTPUT.PUT_LINE('Created team OCI_AUTONOMOUS_DATABASE_TEAM');

  DBMS_OUTPUT.PUT_LINE('-------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('OCI Autonomous Database AI installation COMPLETE');
  DBMS_OUTPUT.PUT_LINE('-------------------------------------------------');
END install_oci_autonomous_database_agent;
/

----------------------------------------------------------------
-- 3. Execute installer in target schema
----------------------------------------------------------------
PROMPT Executing installer procedure ...
BEGIN
  install_oci_autonomous_database_agent( p_profile_name => :v_ai_profile_name);
END;
/

PROMPT ======================================================
PROMPT Installation finished successfully
PROMPT ======================================================


alter session set current_schema = ADMIN;