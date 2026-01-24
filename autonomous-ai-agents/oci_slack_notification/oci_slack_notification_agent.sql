-- Copyright (c) 2025 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/
--
-- ======================================================================
-- Purpose:
--   Install and configure an OCI Slack Notification AI Agent using
--   DBMS_CLOUD_AI_AGENT (Select AI / Oracle AI Database).
-- ======================================================================

SET SERVEROUTPUT ON
SET VERIFY OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT ======================================================
PROMPT OCI Slack Notification AI Agent Installer
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

CREATE OR REPLACE PROCEDURE &&INSTALL_SCHEMA..install_oci_slack_notification_agent (
  p_profile_name IN VARCHAR2
)
AUTHID DEFINER
AS
BEGIN
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Starting OCI Slack Notification AI installation');
  DBMS_OUTPUT.PUT_LINE('Schema : ' || USER);
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');

  ------------------------------------------------------------
  -- DROP & CREATE TASK
  ------------------------------------------------------------
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TASK('OCI_SLACK_NOTIFICATION_TASKS');
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name   => 'OCI_SLACK_NOTIFICATION_TASKS',
    description => 'Task for interactively sending Slack messages using OCI Notifications.',
    attributes  => '{
      "instruction": "Help the user send a message to Slack using OCI Notifications. '
        || 'Collect required inputs (Slack credential name unless configured, and message content). '
        || 'Optional inputs include Slack params such as channel, blocks, attachments, etc. '
        || 'Before sending, summarize details and ask for final confirmation. '
        || 'Only after confirmation, call SEND_SLACK_MESSAGE_TOOL. '
        || 'User request: {query}",
      "tools": [
        "SEND_SLACK_MESSAGE_TOOL",
        "HUMAN_TOOL"
      ]
    }'
  );
  DBMS_OUTPUT.PUT_LINE('Created task OCI_SLACK_NOTIFICATION_TASKS');

  ------------------------------------------------------------
  -- DROP & CREATE AGENT
  ------------------------------------------------------------
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_AGENT('OCI_SLACK_NOTIFICATION_ADVISOR');
    DBMS_OUTPUT.PUT_LINE('Dropped agent OCI_SLACK_NOTIFICATION_ADVISOR');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Agent OCI_SLACK_NOTIFICATION_ADVISOR does not exist, skipping');
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'OCI_SLACK_NOTIFICATION_ADVISOR',
    attributes =>
      '{' ||
      '"profile_name":"' || p_profile_name || '",' ||
      '"role":"You are a Notification and Automation Specialist with expertise in Slack integrations. You help users compose, validate, and send Slack messages using OCI notification credentials. You ensure required inputs are collected, optional Slack parameters are handled correctly, and confirmations are obtained before sending."' ||
      '}',
    description => 'AI agent for composing, validating, and sending Slack notifications'
  );
  DBMS_OUTPUT.PUT_LINE('Created agent OCI_SLACK_NOTIFICATION_ADVISOR');

  ------------------------------------------------------------
  -- DROP & CREATE TEAM
  ------------------------------------------------------------
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TEAM('OCI_SLACK_NOTIFICATION_TEAM');
    DBMS_OUTPUT.PUT_LINE('Dropped team OCI_SLACK_NOTIFICATION_TEAM');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Team OCI_SLACK_NOTIFICATION_TEAM does not exist, skipping');
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
    team_name  => 'OCI_SLACK_NOTIFICATION_TEAM',
    attributes => '{
      "agents":[{"name":"OCI_SLACK_NOTIFICATION_ADVISOR","task":"OCI_SLACK_NOTIFICATION_TASKS"}],
      "process":"sequential"
    }'
  );
  DBMS_OUTPUT.PUT_LINE('Created team OCI_SLACK_NOTIFICATION_TEAM');

  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('OCI Slack Notification AI installation COMPLETE');
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
END install_oci_slack_notification_agent;
/

----------------------------------------------------------------
-- 3. Execute installer in target schema
----------------------------------------------------------------
PROMPT Executing installer procedure ...
BEGIN
  &&INSTALL_SCHEMA..install_oci_slack_notification_agent('&&PROFILE_NAME');
END;
/

PROMPT ======================================================
PROMPT Installation finished successfully
PROMPT ======================================================
