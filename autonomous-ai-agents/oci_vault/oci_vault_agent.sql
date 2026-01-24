-- Copyright (c) 2025 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/
--
-- ======================================================================
-- Purpose:
--   Install and configure an OCI Vault AI Agent using
--   DBMS_CLOUD_AI_AGENT (Select AI / Oracle AI Database).
--
-- This script:
--   • Grants required privileges to the target schema
--   • Creates an installer procedure in the target schema
--   • Registers an OCI Vault Task, Agent, and Team
--   • Binds the Agent to a specified AI Profile
--   • Executes the installer to complete setup
-- ======================================================================

SET SERVEROUTPUT ON
SET VERIFY OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT ======================================================
PROMPT OCI Vault AI Agent Installer
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

CREATE OR REPLACE PROCEDURE &&INSTALL_SCHEMA..install_oci_vault_agent (
  p_profile_name IN VARCHAR2
)
AUTHID DEFINER
AS
BEGIN
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Starting OCI Vault AI installation');
  DBMS_OUTPUT.PUT_LINE('Schema : ' || USER);
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');

  ------------------------------------------------------------
  -- DROP & CREATE TASK
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
        "CHANGE_SECRET_COMPARTMENT_TOOL",
        "HUMAN_TOOL"
      ]
    }'
  );
  DBMS_OUTPUT.PUT_LINE('Created task OCI_VAULT_TASKS');

  ------------------------------------------------------------
  -- DROP & CREATE AGENT
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
  -- DROP & CREATE TEAM
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
  &&INSTALL_SCHEMA..install_oci_vault_agent('&&PROFILE_NAME');
END;
/

PROMPT ======================================================
PROMPT Installation finished successfully
PROMPT ======================================================
