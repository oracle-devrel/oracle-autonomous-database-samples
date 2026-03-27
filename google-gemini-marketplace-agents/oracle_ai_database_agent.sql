rem ============================================================================
rem LICENSE
rem   Copyright (c) 2026 Oracle and/or its affiliates.
rem   Licensed under the Universal Permissive License (UPL), Version 1.0
rem   https://oss.oracle.com/licenses/upl/
rem
rem NAME
rem   oracle_ai_database_agent.sql
rem
rem DESCRIPTION
rem   Installer and configuration script for the Oracle AI Database Agent
rem   using DBMS_CLOUD_AI_AGENT (Select AI / Oracle AI Database).
rem
rem   This script performs an interactive installation of an
rem   Oracle AI Database Agent team by:
rem     - Prompting for target schema and AI Profile
rem     - Granting required Select AI privileges
rem     - Creating an installer procedure in the target schema
rem     - Registering an NL2SQL task with supported analysis tools
rem     - Creating an NL2SQL Data Retrieval AI Agent bound to the AI Profile
rem     - Creating an NL2SQL Team linking the agent and task
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
rem   - Added NL2SQL task, agent, and team registration
rem   - Supports SQL generation, metadata analysis,
rem     and chart/visualization generation
rem   - Interactive installer with schema and AI profile prompts
rem
rem SCRIPT STRUCTURE
rem   1. Initialization:
rem        - Enable output and error handling
rem        - Prompt for target schema and AI profile
rem
rem   2. Grants:
rem        - Grant DBMS_CLOUD_AI_AGENT and DBMS_CLOUD_AI
rem          privileges to the target schema
rem
rem   3. Installer Procedure Creation:
rem        - Create DATA_RETRIEVAL_AGENT procedure
rem          in the target schema
rem
rem   4. AI Registration:
rem        - Drop and create ORACLE_AI_DATABASE_TASK
rem        - Drop and create ORACLE_AI_DATABASE_AGENT
rem        - Drop and create ORACLE_AI_DATABASE_TEAM
rem
rem   5. Execution:
rem        - Execute installer procedure with AI profile parameter
rem
rem INSTALL INSTRUCTIONS
rem   1. Connect as ADMIN or a privileged user
rem
rem   2. Run the script using SQL*Plus or SQLcl:
rem
rem      sqlplus admin@db @oracle_ai_database_agent.sql
rem
rem   3. Provide inputs when prompted:
rem        - Target schema name
rem        - AI Profile name
rem
rem   4. Verify installation by confirming:
rem        - ORACLE_AI_DATABASE_TASK exists
rem        - ORACLE_AI_DATABASE_AGENT is created
rem        - ORACLE_AI_DATABASE_TEAM is registered
rem
rem PARAMETERS
rem   INSTALL_SCHEMA (Prompted)
rem     Target schema where the installer procedure,
rem     task, agent, and team are created.
rem
rem   PROFILE_NAME (Prompted)
rem     AI Profile name used to bind the Oracle AI Database Agent.
rem
rem NOTES
rem   - Script is safe to re-run; existing tasks, agents,
rem     and teams are dropped and recreated.
rem
rem   - SQL data sources are clearly attributed in the
rem     agent response.
rem
rem   - Script exits immediately on SQL errors.
rem
rem ============================================================================


SET SERVEROUTPUT ON
SET VERIFY OFF

PROMPT ======================================================
PROMPT Oracle AI Database Agent Installer
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

  ELSE
    DBMS_OUTPUT.PUT_LINE('Skipping grants for schema ' || l_schema ||
                         ' (same as session user).');
  END IF;

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

CREATE OR REPLACE PROCEDURE data_retrieval_agent (
  p_profile_name IN VARCHAR2
)
AUTHID DEFINER
AS
BEGIN
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Starting Oracle AI Database Agent team installation');
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
  
  ------------------------------------------------------------
  -- Saving the profile name in SELECTAI_AGENT_CONFIG table
  -- The same AI profile will be used with the tools.
  ------------------------------------------------------------

    BEGIN
    
    DELETE FROM SELECTAI_AGENT_CONFIG
    WHERE KEY='AGENT_AI_PROFILE' AND AGENT='ORACLE_AI_DATABASE_AGENT';
    COMMIT;
    
    INSERT INTO SELECTAI_AGENT_CONFIG ("KEY", "VALUE", "AGENT")
    VALUES (
      'AGENT_AI_PROFILE',
      p_profile_name,
      'ORACLE_AI_DATABASE_AGENT'
    );
    
    COMMIT;
    
    END;
    
  ------------------------------------------------------------
  -- DROP and CREATE TASK
  ------------------------------------------------------------
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TASK('ORACLE_AI_DATABASE_TASK');
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

    DBMS_CLOUD_AI_AGENT.CREATE_TASK(
      task_name   => 'ORACLE_AI_DATABASE_TASK',
      description => 'Task for natural language to SQL data retrieval, analysis, and visualization.',
      attributes  =>
        '{' ||
        '"instruction":"Analyze the user question: {query} and answer it using a combination of available tools. ' ||
        'Always respond in a professional manner without any greetings. ' ||
        'If the request requires database data, use SQL_TOOL to generate and execute SQL. ' ||
        'If the query involves database object metadata, you may use the following metadata: {ORA$AI_PROFILE}. ' ||
        'If the question involves charts, graphs, plots, or visualizations, first gather the required data using appropriate tools, ' ||
        'then invoke the GENERATE_CHART tool with a detailed prompt to generate the chart configuration. ' ||
        'In the final response, first provide a concise textual summary of the data or visualization, ' ||
        'then include the raw JSON output from the GENERATE_CHART tool wrapped in a markdown code block using ```chartjs and closing with ```. ' ||
        'Do not modify, reformat, or add any extra text inside the JSON block. ' ||
        'You may use DISTINCT_VALUES_CHECK or RANGE_VALUES_CHECK tools to analyze column values, ' ||
        'but you must clearly explain which values were selected and why in the final response. ' ||
        'Always present answers in a clearly formatted and readable manner using bullet points. ' ||
        'At the end of the response, add a blank line followed by a **Sources** section. ' ||
        'If SQL_TOOL was used, include the source tag * ORACLE AI DATABASE. ' ||
        'Use {current_location} to identify the user location when required. ' ||
        'Use {logged_in_user} to identify the current user when required. ' ||
        'Current system time: {current_time}. ' ||
        '",' ||
        '"tools":[' ||
          '"SQL_TOOL",' ||
          '"DISTINCT_VALUES_CHECK",' ||
          '"RANGE_VALUES_CHECK",' ||
          '"GENERATE_CHART"' ||
        '],' ||
        '"enable_human_tool":"false"' ||
        '}'
    );
  
  DBMS_OUTPUT.PUT_LINE('Created task ORACLE_AI_DATABASE_TASK');

  ------------------------------------------------------------
  -- DROP and CREATE AGENT
  ------------------------------------------------------------
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_AGENT('ORACLE_AI_DATABASE_AGENT');
    DBMS_OUTPUT.PUT_LINE('Dropped agent ORACLE_AI_DATABASE_AGENT');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Agent ORACLE_AI_DATABASE_AGENT does not exist, skipping');
  END;

    DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
      agent_name => 'ORACLE_AI_DATABASE_AGENT',
      attributes =>
        '{' || 
        '"profile_name":"' || p_profile_name || '",' ||
        '"role":"You are a professional data analyst with deep knowledge of SQL, PL/SQL, and modern database features who owns different custom databases. ' ||
        'Always answer in a professional manner without any greetings."' ||
        '}',
      description => 'AI agent for natural language to SQL data retrieval'
    );

  DBMS_OUTPUT.PUT_LINE('Created agent ORACLE_AI_DATABASE_AGENT');

  ------------------------------------------------------------
  -- DROP and CREATE TEAM
  ------------------------------------------------------------
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TEAM('ORACLE_AI_DATABASE_TEAM');
    DBMS_OUTPUT.PUT_LINE('Dropped team ORACLE_AI_DATABASE_TEAM');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Team ORACLE_AI_DATABASE_TEAM does not exist, skipping');
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
      team_name  => 'ORACLE_AI_DATABASE_TEAM',
      attributes =>
        '{' ||
        '"agents":[{"name":"ORACLE_AI_DATABASE_AGENT","task":"ORACLE_AI_DATABASE_TASK"}],' ||
        '"process":"sequential"' ||
        '}',
      description =>
        'The Oracle Autonomous AI Database Agent for Natural Language Queries (Preview) provides a seamless natural language interface for querying enterprise data stored in Oracle Database on Google Cloud. Integrated with Gemini Enterprise, this agent removes the need to build custom natural language processing pipelines by automatically translating plain text inputs into optimized SQL queries. It executes these queries against your Oracle database, retrieves results, and returns formatted data interpretations, all within the Gemini experience.'
  );

  DBMS_OUTPUT.PUT_LINE('Created team ORACLE_AI_DATABASE_TEAM');

  DBMS_OUTPUT.PUT_LINE('------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Oracle AI Database Team installation COMPLETE');
  DBMS_OUTPUT.PUT_LINE('------------------------------------------------');
  
END data_retrieval_agent;
/

----------------------------------------------------------------
-- 3. Execute installer in target schema
----------------------------------------------------------------
PROMPT Executing installer procedure ...
BEGIN
  data_retrieval_agent(p_profile_name => :v_ai_profile_name);
END;
/

PROMPT ======================================================
PROMPT Installation finished successfully
PROMPT ======================================================

alter session set current_schema = ADMIN;
