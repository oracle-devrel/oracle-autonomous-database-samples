rem ============================================================================
rem LICENSE
rem   Copyright (c) 2026 Oracle and/or its affiliates.
rem   Licensed under the Universal Permissive License (UPL), Version 1.0
rem   https://oss.oracle.com/licenses/upl/
rem
rem NAME
rem   cloud_repo_connector_agent.sql
rem
rem DESCRIPTION
rem   Installer and configuration script for Cloud Repo Connector AI Agent Team
rem   using DBMS_CLOUD_AI_AGENT (Select AI / Oracle AI Database).
rem
rem   This script performs interactive installation of cloud repository task,
rem   agent, and team by:
rem     - Prompting for target schema and AI profile
rem     - Granting required privileges to target schema
rem     - Creating installer procedure in target schema
rem     - Registering cloud repo task with DBMS_CLOUD_REPO-backed tools
rem     - Creating Cloud Repo Connector AI agent bound to AI profile
rem     - Creating cloud repo team linking the agent and task
rem
rem RELEASE VERSION
rem   1.1
rem
rem RELEASE DATE
rem   24-Feb-2026
rem
rem ============================================================================

SET SERVEROUTPUT ON
SET VERIFY OFF

PROMPT ======================================================
PROMPT Cloud Repo Connector AI Agent Installer
PROMPT ======================================================

VAR v_schema VARCHAR2(128)
EXEC :v_schema := '&SCHEMA_NAME';

VAR v_ai_profile_name VARCHAR2(128)
EXEC :v_ai_profile_name := '&AI_PROFILE_NAME';

DECLARE
  l_sql          VARCHAR2(500);
  l_schema       VARCHAR2(128);
  l_session_user VARCHAR2(128);
BEGIN
  l_schema := DBMS_ASSERT.SIMPLE_SQL_NAME(:v_schema);
  l_session_user := SYS_CONTEXT('USERENV', 'SESSION_USER');

  -- Avoid self-grant errors (ORA-01749) when target schema == connected user.
  IF UPPER(l_schema) <> UPPER(l_session_user) THEN
    l_sql := 'GRANT EXECUTE ON DBMS_CLOUD_AI_AGENT TO ' || l_schema;
    EXECUTE IMMEDIATE l_sql;

    l_sql := 'GRANT EXECUTE ON DBMS_CLOUD_AI TO ' || l_schema;
    EXECUTE IMMEDIATE l_sql;

    l_sql := 'GRANT EXECUTE ON DBMS_CLOUD TO ' || l_schema;
    EXECUTE IMMEDIATE l_sql;

    l_sql := 'GRANT EXECUTE ON DBMS_CLOUD_REPO TO ' || l_schema;
    EXECUTE IMMEDIATE l_sql;
  ELSE
    DBMS_OUTPUT.PUT_LINE('Skipping grants for schema ' || l_schema ||
                         ' (same as session user).');
  END IF;

  DBMS_OUTPUT.PUT_LINE('Grants completed.');
END;
/

BEGIN
  EXECUTE IMMEDIATE 'ALTER SESSION SET CURRENT_SCHEMA = ' || :v_schema;
END;
/

CREATE OR REPLACE PROCEDURE install_cloud_repo_connector(
  p_profile_name IN VARCHAR2
)
AUTHID DEFINER
AS
BEGIN
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Starting Cloud Repo Connector AI installation');
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');

  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TASK('CLOUD_REPO_TASKS');
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TASK('GITHUB_TASKS');
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name   => 'CLOUD_REPO_TASKS',
    description => 'Task for repository/branch/file management and SQL install operations via DBMS_CLOUD_REPO',
    attributes  => '{
      "instruction": "Identify user intent and use the correct DBMS_CLOUD_REPO-backed tool. '
        || 'Always use config-first execution: read defaults from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG for AGENT=CLOUD_REPO_CONNECTOR (fallback GITHUB_CONNECTOR and GITHUB). '
        || 'For all tools, resolve repository context from config first and pass NULL for optional context fields repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless the user explicitly overrides a value. '
        || 'Never pass placeholder literals such as DEFAULT_REPO, DEFAULT_OWNER, DEFAULT_CREDENTIAL, or DEFAULT_BRANCH as tool inputs. '
        || 'Do not ask the user for optional context values such as credential, owner, repo, branch, provider, region, organization, or project. '
        || 'Ask only for operation-required business inputs that cannot be inferred from config (for example branch names for merge, file path for file operations, SQL text for install_sql). '
        || 'Use INIT_GENERIC_REPO_TOOL, INIT_GITHUB_REPO_TOOL, INIT_AWS_REPO_TOOL, or INIT_AZURE_REPO_TOOL for repository handles. '
        || 'Use CREATE_REPOSITORY_TOOL, UPDATE_REPOSITORY_TOOL, LIST_REPOSITORIES_TOOL, GET_REPOSITORY_TOOL, and DELETE_REPOSITORY_TOOL for repository lifecycle. '
        || 'Use CREATE_BRANCH_TOOL, DELETE_BRANCH_TOOL, LIST_BRANCHES_TOOL, LIST_COMMITS_TOOL, and MERGE_BRANCH_TOOL for branch management. '
        || 'Use PUT_REPO_FILE_TOOL, GET_REPO_FILE_TOOL, LIST_REPO_FILES_TOOL, and DELETE_REPO_FILE_TOOL for file operations. '
        || 'Use EXPORT_DB_OBJECT_REPO_TOOL and EXPORT_SCHEMA_REPO_TOOL to export DB metadata to repository files. '
        || 'Use INSTALL_REPO_FILE_TOOL and INSTALL_SQL_BUFFER_TOOL to install SQL from repository files or SQL buffers. '
        || 'Confirm branch/path and commit details before write or delete operations when ambiguous. '
        || 'Present concise human-readable output. '
        || 'User request: {query}",
      "tools": [
        "INIT_GENERIC_REPO_TOOL",
        "INIT_GITHUB_REPO_TOOL",
        "INIT_AWS_REPO_TOOL",
        "INIT_AZURE_REPO_TOOL",
        "CREATE_REPOSITORY_TOOL",
        "UPDATE_REPOSITORY_TOOL",
        "LIST_REPOSITORIES_TOOL",
        "GET_REPOSITORY_TOOL",
        "DELETE_REPOSITORY_TOOL",
        "CREATE_BRANCH_TOOL",
        "DELETE_BRANCH_TOOL",
        "LIST_BRANCHES_TOOL",
        "LIST_COMMITS_TOOL",
        "MERGE_BRANCH_TOOL",
        "PUT_REPO_FILE_TOOL",
        "GET_REPO_FILE_TOOL",
        "LIST_REPO_FILES_TOOL",
        "DELETE_REPO_FILE_TOOL",
        "EXPORT_DB_OBJECT_REPO_TOOL",
        "EXPORT_SCHEMA_REPO_TOOL",
        "INSTALL_REPO_FILE_TOOL",
        "INSTALL_SQL_BUFFER_TOOL"
      ],
      "enable_human_tool": "true"
    }'
  );
  DBMS_OUTPUT.PUT_LINE('Created task CLOUD_REPO_TASKS');

  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_AGENT('CLOUD_REPO_CONNECTOR');
    DBMS_OUTPUT.PUT_LINE('Dropped agent CLOUD_REPO_CONNECTOR');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Agent CLOUD_REPO_CONNECTOR does not exist, skipping');
  END;

  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_AGENT('GITHUB_CONNECTOR');
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'CLOUD_REPO_CONNECTOR',
    attributes =>
      '{' ||
      '"profile_name":"' || p_profile_name || '",' ||
      '"role":"You are a Cloud Repo Connector built on DBMS_CLOUD_REPO. You help users initialize repository handles, manage repositories and branches, manage files, export metadata, and install SQL safely across GitHub, AWS CodeCommit, and Azure Repos."' ||
      '}',
    description => 'AI agent for DBMS_CLOUD_REPO operations across GitHub, AWS, and Azure'
  );
  DBMS_OUTPUT.PUT_LINE('Created agent CLOUD_REPO_CONNECTOR');

  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TEAM('CLOUD_REPO_CONNECTOR_TEAM');
    DBMS_OUTPUT.PUT_LINE('Dropped team CLOUD_REPO_CONNECTOR_TEAM');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Team CLOUD_REPO_CONNECTOR_TEAM does not exist, skipping');
  END;

  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TEAM('GITHUB_CONNECTOR_TEAM');
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
    team_name  => 'CLOUD_REPO_CONNECTOR_TEAM',
    attributes => '{
      "agents":[{"name":"CLOUD_REPO_CONNECTOR","task":"CLOUD_REPO_TASKS"}],
      "process":"sequential"
    }'
  );
  DBMS_OUTPUT.PUT_LINE('Created team CLOUD_REPO_CONNECTOR_TEAM');

  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Cloud Repo Connector AI installation COMPLETE');
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
END install_cloud_repo_connector;
/

PROMPT Executing installer procedure ...
BEGIN
  install_cloud_repo_connector(p_profile_name => :v_ai_profile_name);
END;
/

ALTER SESSION SET CURRENT_SCHEMA = ADMIN;

PROMPT ======================================================
PROMPT Installation finished successfully
PROMPT ======================================================
