rem ============================================================================
rem LICENSE
rem   Copyright (c) 2026 Oracle and/or its affiliates.
rem   Licensed under the Universal Permissive License (UPL), Version 1.0
rem   https://oss.oracle.com/licenses/upl/
rem
rem NAME
rem   jira_inspect_agent.sql
rem
rem DESCRIPTION
rem   Installer and configuration script for Jira AI Agent Team
rem   using DBMS_CLOUD_AI_AGENT (Select AI / Oracle AI Database).
rem
rem   This script performs interactive installation of Jira task,
rem   agent, and team by:
rem     - Prompting for target schema and AI profile
rem     - Granting required privileges to target schema
rem     - Creating installer procedure in target schema
rem     - Registering Jira task with supported Jira tools
rem     - Creating Jira AI agent bound to AI profile
rem     - Creating Jira team linking the agent and task
rem
rem RELEASE VERSION
rem   1.0
rem
rem RELEASE DATE
rem   20-Feb-2026
rem
rem MAJOR CHANGES IN THIS RELEASE
rem   - Initial release
rem   - Added Jira task, agent, and team registration
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
rem        - Create INSTALL_JIRA_AGENT procedure in target schema
rem
rem   4. AI Registration:
rem        - Drop and create JIRA_TASKS
rem        - Drop and create JIRA_ADVISOR agent
rem        - Drop and create JIRA_INSPECT_TEAM
rem
rem   5. Execution:
rem        - Execute installer procedure with AI profile parameter
rem
rem INSTALL INSTRUCTIONS
rem   1. Run jira_inspect_tools.sql first.
rem
rem   2. Connect as ADMIN or a privileged user.
rem
rem   3. Run the script using SQL*Plus or SQLcl:
rem
rem      sqlplus admin@db @jira_inspect_agent.sql
rem
rem   4. Provide inputs when prompted:
rem        - Target schema name
rem        - AI Profile name
rem
rem PARAMETERS
rem   SCHEMA_NAME (Prompted)
rem     Target schema where the installer procedure,
rem     task, agent, and team are created.
rem
rem   AI_PROFILE_NAME (Prompted)
rem     AI Profile name used to bind the Jira agent.
rem
rem NOTES
rem   - Script can be re-run; existing Jira task, agent,
rem     and team are dropped and recreated.
rem
rem ============================================================================

SET SERVEROUTPUT ON
SET VERIFY OFF

PROMPT ======================================================
PROMPT Jira AI Agent Installer
PROMPT ======================================================

VAR v_schema VARCHAR2(128)
EXEC :v_schema := '&SCHEMA_NAME';

VAR v_ai_profile_name VARCHAR2(128)
EXEC :v_ai_profile_name := '&AI_PROFILE_NAME';

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

BEGIN
  EXECUTE IMMEDIATE 'ALTER SESSION SET CURRENT_SCHEMA = ' || :v_schema;
END;
/

CREATE OR REPLACE PROCEDURE install_jira_agent(
  p_profile_name IN VARCHAR2
)
AUTHID DEFINER
AS
BEGIN
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Starting Jira AI installation');
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');

  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TASK('JIRA_TASKS');
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name   => 'JIRA_TASKS',
    description => 'Task for Jira issue search and Jira metadata retrieval',
    attributes  => '{
      "instruction": "Identify the user request and choose the right Jira tool. '
        || 'Ask only for missing business inputs. '
        || 'Use SEARCH_JIRA_TOOL to find issues by keyword. '
        || 'Use GET_JIRA_TOOL for issue details by key. '
        || 'Use GET_ASSIGNEE_ACCOUNT_ID_TOOL to resolve assignee account id. '
        || 'Use GET_JIRA_ASSIGNED_ISSUES_TOOL for assignee issue lists. '
        || 'Use GET_JIRA_COMMENTS_TOOL, GET_JIRA_CHANGELOG_TOOL, and GET_JIRA_WORKLOG_TOOL for issue history. '
        || 'Use GET_JIRA_PROJECT_TOOL for project metadata. '
        || 'Use GET_ATLASSIAN_USER_TOOL for user profile lookup. '
        || 'Use GET_JIRA_BOARDS_TOOL for board metadata. '
        || 'Present results clearly and in human-readable format. '
        || 'User request: {query}",
      "tools": [
        "SEARCH_JIRA_TOOL",
        "GET_JIRA_TOOL",
        "GET_ASSIGNEE_ACCOUNT_ID_TOOL",
        "GET_JIRA_ASSIGNED_ISSUES_TOOL",
        "GET_JIRA_COMMENTS_TOOL",
        "GET_JIRA_CHANGELOG_TOOL",
        "GET_JIRA_WORKLOG_TOOL",
        "GET_JIRA_PROJECT_TOOL",
        "GET_ATLASSIAN_USER_TOOL",
        "GET_JIRA_BOARDS_TOOL"
      ],
      "enable_human_tool": "true"
    }'
  );
  DBMS_OUTPUT.PUT_LINE('Created task JIRA_TASKS');

  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_AGENT('JIRA_ADVISOR');
    DBMS_OUTPUT.PUT_LINE('Dropped agent JIRA_ADVISOR');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Agent JIRA_ADVISOR does not exist, skipping');
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'JIRA_ADVISOR',
    attributes =>
      '{' ||
      '"profile_name":"' || p_profile_name || '",' ||
      '"role":"You are a Jira Advisor. You help users search issues and inspect Jira metadata. You call Jira tools based on intent and present clean summaries."' ||
      '}',
    description => 'AI agent for Jira search and metadata retrieval'
  );
  DBMS_OUTPUT.PUT_LINE('Created agent JIRA_ADVISOR');

  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TEAM('JIRA_INSPECT_TEAM');
    DBMS_OUTPUT.PUT_LINE('Dropped team JIRA_INSPECT_TEAM');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Team JIRA_INSPECT_TEAM does not exist, skipping');
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
    team_name  => 'JIRA_INSPECT_TEAM',
    attributes => '{
      "agents":[{"name":"JIRA_ADVISOR","task":"JIRA_TASKS"}],
      "process":"sequential"
    }'
  );
  DBMS_OUTPUT.PUT_LINE('Created team JIRA_INSPECT_TEAM');

  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Jira AI installation COMPLETE');
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
END install_jira_agent;
/

PROMPT Executing installer procedure ...
BEGIN
  install_jira_agent(p_profile_name => :v_ai_profile_name);
END;
/

ALTER SESSION SET CURRENT_SCHEMA = ADMIN;

PROMPT ======================================================
PROMPT Installation finished successfully
PROMPT ======================================================
