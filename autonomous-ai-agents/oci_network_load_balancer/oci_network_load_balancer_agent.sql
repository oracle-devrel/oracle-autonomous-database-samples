-- Copyright (c) 2025 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/
--
-- ======================================================================
-- Purpose:
--   Install and configure an OCI Network Load Balancer AI Agent using
--   DBMS_CLOUD_AI_AGENT (Select AI / Oracle AI Database).
-- ======================================================================

SET SERVEROUTPUT ON
SET VERIFY OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT ======================================================
PROMPT OCI Network Load Balancer AI Agent Installer
PROMPT ======================================================

-- Target schema
ACCEPT SCHEMA_NAME CHAR PROMPT 'Enter target schema name: '
DEFINE INSTALL_SCHEMA = '&SCHEMA_NAME'

-- AI Profile
ACCEPT PROFILE_NAME CHAR PROMPT 'Enter AI Profile name to be used with the Agent: '
DEFINE PROFILE_NAME = '&PROFILE_NAME'

PROMPT ------------------------------------------------------
PROMPT Installing into schema: &&INSTALL_SCHEMA
PROMPT Using AI Profile     : &&PROFILE_NAME
PROMPT ------------------------------------------------------

----------------------------------------------------------------
-- 1. Grants (safe to re-run)
----------------------------------------------------------------
BEGIN
  DBMS_OUTPUT.PUT_LINE('Granting required privileges to &&INSTALL_SCHEMA ...');
  EXECUTE IMMEDIATE 'GRANT EXECUTE ON DBMS_CLOUD_AI_AGENT TO &&INSTALL_SCHEMA';
  EXECUTE IMMEDIATE 'GRANT EXECUTE ON DBMS_CLOUD TO &&INSTALL_SCHEMA';
  DBMS_OUTPUT.PUT_LINE('Grants completed.');
END;
/

----------------------------------------------------------------
-- 2. Create installer procedure in target schema
----------------------------------------------------------------
PROMPT Creating installer procedure in &&INSTALL_SCHEMA ...

CREATE OR REPLACE PROCEDURE &&INSTALL_SCHEMA..install_oci_network_load_balancer_agent (
  p_profile_name IN VARCHAR2
)
AUTHID DEFINER
AS
BEGIN
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Starting OCI Network Load Balancer AI installation');
  DBMS_OUTPUT.PUT_LINE('Schema : ' || USER);
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');

  ------------------------------------------------------------
  -- DROP & CREATE TASK
  ------------------------------------------------------------
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TASK('OCI_NETWORK_LOAD_BALANCER_TASKS');
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name   => 'OCI_NETWORK_LOAD_BALANCER_TASKS',
    description => 'Task for managing OCI Network Load Balancers.',
    attributes  => '{
      "instruction": "Identify the intent of the user request and determine the correct OCI Network Load Balancer operation. '
        || 'Prompt the user only for necessary missing details. '
        || 'Ask clarifying questions if intent is ambiguous. '
        || 'Format lists/objects in a human-readable way. '
        || 'Use LIST_SUBSCRIBED_REGIONS_TOOL to list regions and confirm with the user. '
        || 'Use LIST_COMPARTMENTS_TOOL to list compartments and confirm with the user. '
        || 'Confirm destructive actions before execution. '
        || 'User request: {query}",
      "tools": [
        "LIST_SUBSCRIBED_REGIONS_TOOL",
        "LIST_COMPARTMENTS_TOOL",
        "LIST_NETWORK_LOAD_BALANCERS_TOOL",
        "CREATE_NETWORK_LOAD_BALANCER_TOOL",
        "UPDATE_NETWORK_LOAD_BALANCER_TOOL",
        "DELETE_NETWORK_LOAD_BALANCER_TOOL",
        "CHANGE_NLB_COMPARTMENT_TOOL",
        "LIST_LISTENERS_TOOL",
        "GET_LISTENER_TOOL",
        "CREATE_LISTENER_TOOL",
        "UPDATE_LISTENER_TOOL",
        "DELETE_LISTENER_TOOL",
        "CREATE_BACKEND_SET_TOOL",
        "LIST_BACKEND_SETS_TOOL",
        "LIST_BACKENDS_TOOL",
        "LIST_NLB_HEALTHS_TOOL",
        "LIST_NLB_POLICIES_TOOL",
        "LIST_NLB_PROTOCOLS_TOOL",
        "HUMAN_TOOL"
      ]
    }'
  );
  DBMS_OUTPUT.PUT_LINE('Created task OCI_NETWORK_LOAD_BALANCER_TASKS');

  ------------------------------------------------------------
  -- DROP & CREATE AGENT
  ------------------------------------------------------------
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_AGENT('OCI_NETWORK_LOAD_BALANCER_ADVISOR');
    DBMS_OUTPUT.PUT_LINE('Dropped agent OCI_NETWORK_LOAD_BALANCER_ADVISOR');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Agent OCI_NETWORK_LOAD_BALANCER_ADVISOR does not exist, skipping');
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'OCI_NETWORK_LOAD_BALANCER_ADVISOR',
    attributes =>
      '{' ||
      '"profile_name":"' || p_profile_name || '",' ||
      '"role":"You are an OCI Network Load Balancer expert. You help users list, create, update, and delete NLBs, listeners, backend sets, and review health. You confirm destructive actions and present results clearly."' ||
      '}',
    description => 'AI agent for advising and automating OCI Network Load Balancer operations'
  );
  DBMS_OUTPUT.PUT_LINE('Created agent OCI_NETWORK_LOAD_BALANCER_ADVISOR');

  ------------------------------------------------------------
  -- DROP & CREATE TEAM
  ------------------------------------------------------------
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TEAM('OCI_NETWORK_LOAD_BALANCER_TEAM');
    DBMS_OUTPUT.PUT_LINE('Dropped team OCI_NETWORK_LOAD_BALANCER_TEAM');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Team OCI_NETWORK_LOAD_BALANCER_TEAM does not exist, skipping');
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
    team_name  => 'OCI_NETWORK_LOAD_BALANCER_TEAM',
    attributes => '{
      "agents":[{"name":"OCI_NETWORK_LOAD_BALANCER_ADVISOR","task":"OCI_NETWORK_LOAD_BALANCER_TASKS"}],
      "process":"sequential"
    }'
  );
  DBMS_OUTPUT.PUT_LINE('Created team OCI_NETWORK_LOAD_BALANCER_TEAM');

  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('OCI Network Load Balancer AI installation COMPLETE');
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
END install_oci_network_load_balancer_agent;
/

----------------------------------------------------------------
-- 3. Execute installer in target schema
----------------------------------------------------------------
PROMPT Executing installer procedure ...
BEGIN
  &&INSTALL_SCHEMA..install_oci_network_load_balancer_agent('&&PROFILE_NAME');
END;
/

PROMPT ======================================================
PROMPT Installation finished successfully
PROMPT ======================================================
