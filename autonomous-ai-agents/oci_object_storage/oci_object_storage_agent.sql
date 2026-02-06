rem ============================================================================
rem LICENSE
rem   Copyright (c) 2025 Oracle and/or its affiliates.
rem   Licensed under the Universal Permissive License (UPL), Version 1.0
rem   https://oss.oracle.com/licenses/upl/
rem
rem NAME
rem   oci_object_storage_agent.sql
rem
rem DESCRIPTION
rem   Installer and configuration script for OCI Object Storage AI Agent
rem   using DBMS_CLOUD_AI_AGENT (Select AI / Oracle AI Database).
rem
rem   This script performs an interactive installation of an
rem   OCI Object Storage AI Agent by:
rem     - Prompting for target schema and AI Profile
rem     - Granting required privileges to the target schema
rem     - Creating an installer procedure in the target schema
rem     - Registering an OCI Object Storage Task with supported tools
rem     - Creating an OCI Object Storage AI Agent bound to the AI Profile
rem     - Creating an OCI Object Storage Team linking the agent and task
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
rem   - Added OCI Object Storage task, agent, and team registration
rem   - Interactive installer with schema and AI profile prompts
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
rem        - Create INSTALL_OCI_OBJECTSTORE_AGENT procedure
rem          in the target schema
rem
rem   4. AI Registration:
rem        - Drop and create OCI_OBJECTSTORE_TASKS
rem        - Drop and create OCI_OBJECT_STORAGE_ADVISOR agent
rem        - Drop and create OCI_OBJECTSTORE_TEAM
rem
rem   5. Execution:
rem        - Execute installer procedure with AI profile parameter
rem
rem INSTALL INSTRUCTIONS
rem   1. Connect as ADMIN or a user with required privileges
rem
rem   2. Run the script using SQL*Plus or SQLcl:
rem
rem      sqlplus admin@db @oci_object_storage_agent.sql
rem
rem   3. Provide inputs when prompted:
rem        - Target schema name
rem        - AI Profile name
rem
rem   4. Verify installation by confirming:
rem        - OCI_OBJECTSTORE_TASKS task exists
rem        - OCI_OBJECT_STORAGE_ADVISOR agent is created
rem        - OCI_OBJECTSTORE_TEAM team is registered
rem
rem PARAMETERS
rem   INSTALL_SCHEMA (Prompted)
rem     Target schema where the installer procedure,
rem     task, agent, and team are created.
rem
rem   PROFILE_NAME (Prompted)
rem     AI Profile name used to bind the OCI Object Storage agent.
rem
rem NOTES
rem   - Script is safe to re-run; existing tasks, agents,
rem     and teams are dropped and recreated.
rem
rem   - Destructive Object Storage operations require
rem     explicit user confirmation as enforced by task instructions.
rem
rem   - Tool names referenced in the task must exactly match
rem     USER_CLOUD_AI_AGENT_TOOLS.TOOL_NAME values.
rem
rem   - Script exits immediately on SQL errors.
rem
rem ============================================================================


SET SERVEROUTPUT ON
SET VERIFY OFF


PROMPT ======================================================
PROMPT OCI Object Storage AI Agent Installer
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

CREATE OR REPLACE PROCEDURE install_oci_objectstore_agent (
    p_profile_name IN VARCHAR2
)
AUTHID DEFINER
AS
BEGIN
    DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('Starting OCI Object Storage AI installation');
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
                "CANCEL_WORK_REQUEST_TOOL"
          ],
          "enable_human_tool": "true"
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
    install_oci_objectstore_agent(p_profile_name => :v_ai_profile_name);
END;
/

alter session set current_schema = ADMIN;

PROMPT ======================================================
PROMPT Installation finished successfully
PROMPT ======================================================
