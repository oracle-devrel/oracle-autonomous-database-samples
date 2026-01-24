-- Copyright (c) 2025 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

-- ======================================================================
-- Purpose:
--   Install and configure an OCI Object Storage AI Agent using
--   DBMS_CLOUD_AI_AGENT (Select AI / Oracle AI Database).
--
--   This script:
--     • Grants required privileges to the target schema
--     • Creates an installer procedure in the target schema
--     • Registers an Object Storage AI Task, Agent, and Team
--     • Binds the Agent to a specified AI Profile
--     • Executes the installer to complete setup
--
-- Script Structure:
--   1) Initialization
--      - SQL*Plus settings, input prompts
--      - Target schema and AI profile selection
--
--   2) Grants
--      - Grant required DBMS_CLOUD and DBMS_CLOUD_AI_AGENT privileges
--
--   3) Installer Procedure Creation
--      - Creates &&INSTALL_SCHEMA..install_oci_objectstore_agent
--      - Drops and recreates:
--          • OCI Object Storage Task
--          • OCI Object Storage Agent
--          • OCI Object Storage Team
--
--   4) Task Registration
--      - Defines user intent handling and safe execution rules
--      - Registers all supported OCI Object Storage tools
--      - Enforces human-readable output and confirmation for destructive actions
--
--   5) Agent Registration
--      - Creates OCI_OBJECT_STORAGE_ADVISOR agent
--      - Associates the agent with the provided AI Profile
--      - Defines the agent role and behavior
--
--   6) Team Registration
--      - Creates OCI_OBJECTSTORE_TEAM
--      - Links the agent to the task in sequential execution mode
--
--   7) Execution
--      - Executes the installer procedure in the target schema
--
-- Usage:
--   sqlplus admin@db @oci_object_storage_ai_agent_install.sql
--
--   You will be prompted for:
--     • Target schema name
--     • AI Profile name to be used by the agent
--
-- Notes:
--   • Script is safe to re-run; existing tasks, agents, and teams
--     are dropped and recreated.
--   • Destructive Object Storage operations always require user confirmation.
--   • Tool names referenced in the task must exactly match
--     USER_CLOUD_AI_AGENT_TOOLS.TOOL_NAME values.
--
-- ======================================================================


SET SERVEROUTPUT ON
SET VERIFY OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT ======================================================
PROMPT OCI Object Storage AI Agent Installer
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

CREATE OR REPLACE PROCEDURE &&INSTALL_SCHEMA..install_oci_objectstore_agent (
    p_profile_name IN VARCHAR2
)
AUTHID DEFINER
AS
BEGIN
    DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('Starting OCI Object Storage AI installation');
    DBMS_OUTPUT.PUT_LINE('Schema : ' || USER);
    DBMS_OUTPUT.PUT_LINE('--------------------------------------------');

    ------------------------------------------------------------
    -- DROP TASK
    ------------------------------------------------------------
    BEGIN
        DBMS_CLOUD_AI_AGENT.DROP_TASK('OCI_OBJECTSTORE_TASKS');
        DBMS_OUTPUT.PUT_LINE('Dropped task OCI_OBJECTSTORE_TASKS');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Task OCI_OBJECTSTORE_TASKS does not exist, skipping');
    END;

    ------------------------------------------------------------
    -- CREATE TASK
    ------------------------------------------------------------
    DBMS_CLOUD_AI_AGENT.CREATE_TASK(
        task_name   => 'OCI_OBJECTSTORE_TASKS',
        description => 'Comprehensive task covering OCI Object Storage operations',
        attributes  => '{
                      "instruction": "Identify the intent of the user request and determine the correct object storage operation. '
                || 'Prompt the user only for necessary missing details. '
                || 'Ask clarifying questions if intent is ambiguous. '
                || 'When presenting any list, object, or JSON structure to the user, format it in a human-readable way — such as: '
                || '- Bullet points for simple lists. '
                || '- Indented JSON for structured responses. '
                || 'Use LIST_COMPARTMENTS_TOOL to list compartments. '
                || 'Use LIST_SUBSCRIBED_REGIONS_TOOL to list regions and confirm with user. '
                || 'Automatically derive namespace using GET_NAMESPACE_TOOL. '
                || 'Confirm destructive actions before execution. '
                || 'User request: {query}",
          "tools": [
                "LIST_COMPARTMENTS_TOOL",
                "LIST_SUBSCRIBED_REGIONS_TOOL",
                "GET_NAMESPACE_TOOL",
                "CREATE_BUCKET_TOOL",
                "DELETE_BUCKET_TOOL",
                "UPDATE_BUCKET_TOOL",
                "MAKE_BUCKET_WRITABLE_TOOL",
                "REENCRYPT_BUCKET_TOOL",
                "UPDATE_NAMESPACE_METADATA_TOOL",
                "LIST_BUCKETS_TOOL",
                "GET_BUCKET_TOOL",
                "LIST_OBJECTS_TOOL",
                "HEAD_OBJECT_TOOL",
                "GET_OBJECT_TOOL",
                "RENAME_OBJECT_TOOL",
                "COPY_OBJECT_TOOL",
                "DELETE_OBJECT_TOOL",
                "PUT_OBJECT_TOOL",
                "CREATE_PREAUTHENTICATED_REQUEST_TOOL",
                "LIST_PREAUTHENTICATED_REQUESTS_TOOL",
                "GET_PREAUTHENTICATED_REQUEST_TOOL",
                "DELETE_PREAUTHENTICATED_REQUEST_TOOL",
                "CREATE_RETENTION_RULE_TOOL",
                "LIST_RETENTION_RULES_TOOL",
                "GET_RETENTION_RULE_TOOL",
                "UPDATE_RETENTION_RULE_TOOL",
                "DELETE_RETENTION_RULE_TOOL",
                "CREATE_REPLICATION_POLICY_TOOL",
                "LIST_REPLICATION_POLICIES_TOOL",
                "GET_REPLICATION_POLICY_TOOL",
                "DELETE_REPLICATION_POLICY_TOOL",
                "LIST_REPLICATION_SOURCES_TOOL",
                "PUT_OBJECT_LIFECYCLE_POLICY_TOOL",
                "DELETE_OBJECT_LIFECYCLE_POLICY_TOOL",
                "CREATE_MULTIPART_UPLOAD_TOOL",
                "LIST_MULTIPART_UPLOADS_TOOL",
                "UPLOAD_PART_TOOL",
                "LIST_MULTIPART_UPLOAD_PARTS_TOOL",
                "COMMIT_MULTIPART_UPLOAD_TOOL",
                "ABORT_MULTIPART_UPLOAD_TOOL",
                "LIST_WORK_REQUESTS_TOOL",
                "GET_WORK_REQUEST_TOOL",
                "LIST_WORK_REQUEST_LOGS_TOOL",
                "LIST_WORK_REQUEST_ERRORS_TOOL",
                "CANCEL_WORK_REQUEST_TOOL",
                "HUMAN_TOOL"
          ]
        }'
    );
    DBMS_OUTPUT.PUT_LINE('Created task OCI_OBJECTSTORE_TASKS');

    ------------------------------------------------------------
    -- DROP AGENT
    ------------------------------------------------------------
    BEGIN
        DBMS_CLOUD_AI_AGENT.DROP_AGENT('OCI_OBJECT_STORAGE_ADVISOR');
        DBMS_OUTPUT.PUT_LINE('Dropped agent OCI_OBJECT_STORAGE_ADVISOR');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Agent OCI_OBJECT_STORAGE_ADVISOR does not exist, skipping');
    END;

    ------------------------------------------------------------
    -- CREATE AGENT
    ------------------------------------------------------------
    DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
        agent_name => 'OCI_OBJECT_STORAGE_ADVISOR',
        attributes =>
            '{' ||
            '"profile_name":"' || p_profile_name || '",' ||
            '"role":"You are an OCI Object Storage Advisor and Automation Specialist. ' ||
            'You assist users with bucket and object management, lifecycle policies, retention rules, replication, multipart uploads, and work request monitoring. ' ||
            'You confirm destructive actions and present results clearly using human-readable formatting."' ||
            '}',
        description =>
            'AI agent for advising and automating OCI Object Storage operations'
    );
    DBMS_OUTPUT.PUT_LINE('Created agent OCI_OBJECT_STORAGE_ADVISOR');

    ------------------------------------------------------------
    -- DROP TEAM
    ------------------------------------------------------------
    BEGIN
        DBMS_CLOUD_AI_AGENT.DROP_TEAM('OCI_OBJECTSTORE_TEAM');
        DBMS_OUTPUT.PUT_LINE('Dropped team OCI_OBJECTSTORE_TEAM');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Team OCI_OBJECTSTORE_TEAM does not exist, skipping');
    END;

    ------------------------------------------------------------
    -- CREATE TEAM
    ------------------------------------------------------------
    DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
        team_name  => 'OCI_OBJECTSTORE_TEAM',
        attributes => '{
            "agents":[{"name":"OCI_OBJECT_STORAGE_ADVISOR","task":"OCI_OBJECTSTORE_TASKS"}],
            "process":"sequential"
        }'
    );
    DBMS_OUTPUT.PUT_LINE('Created team OCI_OBJECTSTORE_TEAM');

    DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('OCI Object Storage AI installation COMPLETE');
    DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
END install_oci_objectstore_agent;
/
----------------------------------------------------------------
-- 3. Execute installer in target schema
----------------------------------------------------------------
PROMPT Executing installer procedure ...

BEGIN
    &&INSTALL_SCHEMA..install_oci_objectstore_agent('&&PROFILE_NAME');
END;
/

PROMPT ======================================================
PROMPT Installation finished successfully
PROMPT ======================================================
