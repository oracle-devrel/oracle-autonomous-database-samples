rem ============================================================================
rem LICENSE
rem   Copyright (c) 2025 Oracle and/or its affiliates.
rem   Licensed under the Universal Permissive License (UPL), Version 1.0
rem   https://oss.oracle.com/licenses/upl/
rem
rem NAME
rem   nl2sql_data_retrieval_agent.sql
rem
rem DESCRIPTION
rem   Installer and configuration script for the NL2SQL Data Retrieval
rem   AI Agent using DBMS_CLOUD_AI_AGENT (Select AI / Oracle AI Database).
rem
rem   This script performs an interactive installation of an
rem   NL2SQL Data Retrieval AI Team by:
rem     - Prompting for target schema and AI Profile
rem     - Granting required DBMS_CLOUD and Select AI privileges
rem     - Creating an installer procedure in the target schema
rem     - Registering an NL2SQL task with supported analysis tools
rem     - Creating an NL2SQL Data Retrieval AI Agent bound to the AI Profile
rem     - Creating an NL2SQL Team linking the agent and task
rem     - Executing the installer procedure to complete setup
rem
rem RELEASE VERSION
rem   1.0
rem
rem RELEASE DATE
rem   26-Jan-2026
rem
rem MAJOR CHANGES IN THIS RELEASE
rem   - Initial release
rem   - Added NL2SQL task, agent, and team registration
rem   - Supports SQL generation, metadata analysis, web search,
rem     and chart/visualization generation
rem   - Interactive installer with schema and AI profile prompts
rem
rem SCRIPT STRUCTURE
rem   1. Initialization:
rem        - Enable output and error handling
rem        - Prompt for target schema and AI profile
rem
rem   2. Grants:
rem        - Grant DBMS_CLOUD_AI_AGENT, DBMS_CLOUD_AI,
rem          and DBMS_CLOUD privileges to the target schema
rem
rem   3. Installer Procedure Creation:
rem        - Create DATA_RETRIEVAL_AGENT procedure
rem          in the target schema
rem
rem   4. AI Registration:
rem        - Drop and create NL2SQL_DATA_RETRIEVAL_TASK
rem        - Drop and create NL2SQL_DATA_RETRIEVAL_AGENT
rem        - Drop and create NL2SQL_DATA_RETRIEVAL_TEAM
rem
rem   5. Execution:
rem        - Execute installer procedure with AI profile parameter
rem
rem INSTALL INSTRUCTIONS
rem   1. Connect as ADMIN or a privileged user
rem
rem   2. Run the script using SQL*Plus or SQLcl:
rem
rem      sqlplus admin@db @nl2sql_data_retrieval_agent.sql
rem
rem   3. Provide inputs when prompted:
rem        - Target schema name
rem        - AI Profile name
rem
rem   4. Verify installation by confirming:
rem        - NL2SQL_DATA_RETRIEVAL_TASK exists
rem        - NL2SQL_DATA_RETRIEVAL_AGENT is created
rem        - NL2SQL_DATA_RETRIEVAL_TEAM is registered
rem
rem PARAMETERS
rem   INSTALL_SCHEMA (Prompted)
rem     Target schema where the installer procedure,
rem     task, agent, and team are created.
rem
rem   PROFILE_NAME (Prompted)
rem     AI Profile name used to bind the NL2SQL agent.
rem
rem NOTES
rem   - Script is safe to re-run; existing tasks, agents,
rem     and teams are dropped and recreated.
rem
rem   - SQL and web-based data sources are clearly
rem     attributed in the agent response.
rem
rem   - Script exits immediately on SQL errors.
rem
rem ============================================================================


SET SERVEROUTPUT ON
SET VERIFY OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT ======================================================
PROMPT NL2SQL Data Retrieval Agent Installer
PROMPT ======================================================

-- Target schema (MANDATORY)
ACCEPT SCHEMA_NAME CHAR PROMPT 'Enter target schema name (required): '
DEFINE INSTALL_SCHEMA = '&SCHEMA_NAME'

-- AI Profile (MANDATORY)
ACCEPT PROFILE_NAME CHAR PROMPT 'Enter AI Profile name (required): '
DEFINE PROFILE_NAME = '&PROFILE_NAME'


PROMPT ------------------------------------------------------
PROMPT Installing into schema: &&INSTALL_SCHEMA
PROMPT Using AI Profile      : &&PROFILE_NAME
PROMPT ------------------------------------------------------

----------------------------------------------------------------
-- 1. Grants (safe to re-run)
----------------------------------------------------------------
BEGIN
  DBMS_OUTPUT.PUT_LINE('Granting required privileges to &&INSTALL_SCHEMA ...');
  EXECUTE IMMEDIATE 'GRANT EXECUTE ON DBMS_CLOUD_AI_AGENT TO &&INSTALL_SCHEMA';
  EXECUTE IMMEDIATE 'GRANT EXECUTE ON DBMS_CLOUD_AI TO &&INSTALL_SCHEMA';
  EXECUTE IMMEDIATE 'GRANT EXECUTE ON DBMS_CLOUD TO &&INSTALL_SCHEMA';
  DBMS_OUTPUT.PUT_LINE('Grants completed.');
END;
/


----------------------------------------------------------------
-- 2. Create installer procedure in target schema
----------------------------------------------------------------
PROMPT Creating installer procedure in &&INSTALL_SCHEMA ...

CREATE OR REPLACE PROCEDURE &&INSTALL_SCHEMA..data_retrieval_agent (
  p_profile_name IN VARCHAR2
)
AUTHID DEFINER
AS
BEGIN
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Starting Data Retrieval Agent Team installation');
  DBMS_OUTPUT.PUT_LINE('Schema : ' || USER);
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
  
  ------------------------------------------------------------
  -- Saving the profile name in SELECTAI_AGENT_CONFIG table
  -- The same AI profile will be used with the tools.
  ------------------------------------------------------------

    BEGIN
    
    DELETE FROM SELECTAI_AGENT_CONFIG
    WHERE KEY='AGENT_AI_PROFILE' AND AGENT='NL2SQL_DATA_RETRIEVAL_AGENT';
    COMMIT;
    
    INSERT INTO SELECTAI_AGENT_CONFIG ("KEY", "VALUE", "AGENT")
    VALUES (
      'AGENT_AI_PROFILE',
      p_profile_name,
      'NL2SQL_DATA_RETRIEVAL_AGENT'
    );
    
    COMMIT;
    
    END;
    
  ------------------------------------------------------------
  -- DROP & CREATE TASK
  ------------------------------------------------------------
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TASK('NL2SQL_DATA_RETRIEVAL_TASK');
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

    DBMS_CLOUD_AI_AGENT.CREATE_TASK(
      task_name   => 'NL2SQL_DATA_RETRIEVAL_TASK',
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
        'You may use WEBSEARCH to retrieve external information. If the answer cannot be verified directly from the search snippet, ' ||
        'invoke GET_URL_CONTENT to validate the source content. ' ||
        'Always present answers in a clearly formatted and readable manner using bullet points. ' ||
        'At the end of the response, add a blank line followed by a **Sources** section. ' ||
        'If SQL_TOOL was used, include the source tag * DATABASE. ' ||
        'If WEBSEARCH was used, include a * WEBSEARCH section followed by a markdown list of referenced URLs. ' ||
        'If both were used, include both source sections. ' ||
        'Use {current_location} to identify the user location when required. ' ||
        'Use {logged_in_user} to identify the current user when required. ' ||
        'Current system time: {current_time}. ' ||
        '",' ||
        '"tools":[' ||
          '"SQL_TOOL",' ||
          '"DISTINCT_VALUES_CHECK",' ||
          '"RANGE_VALUES_CHECK",' ||
          '"WEBSEARCH",' ||
          '"GET_URL_CONTENT",' ||
          '"GENERATE_CHART"' ||
        '],' ||
        '"enable_human_tool":"false"' ||
        '}'
    );
  
  DBMS_OUTPUT.PUT_LINE('Created task NL2SQL_DATA_RETRIEVAL_TASK');

  ------------------------------------------------------------
  -- DROP & CREATE AGENT
  ------------------------------------------------------------
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_AGENT('NL2SQL_DATA_RETRIEVAL_AGENT');
    DBMS_OUTPUT.PUT_LINE('Dropped agent NL2SQL_DATA_RETRIEVAL_AGENT');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Agent NL2SQL_DATA_RETRIEVAL_AGENT does not exist, skipping');
  END;

    DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
      agent_name => 'NL2SQL_DATA_RETRIEVAL_AGENT',
      attributes =>
        '{' || 
        '"profile_name":"' || p_profile_name || '",' ||
        '"role":"You are a professional data analyst with deep knowledge of SQL, PL/SQL, and modern database features who owns different custom databases. ' ||
        'You are also highly informed about current affairs and general knowledge about world demographics. ' ||
        'Always answer in a professional manner without any greetings."' ||
        '}',
      description => 'AI agent for natural language to SQL data retrieval'
    );

  DBMS_OUTPUT.PUT_LINE('Created agent NL2SQL_DATA_RETRIEVAL_AGENT');

  ------------------------------------------------------------
  -- DROP & CREATE TEAM
  ------------------------------------------------------------
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TEAM('NL2SQL_DATA_RETRIEVAL_TEAM');
    DBMS_OUTPUT.PUT_LINE('Dropped team NL2SQL_DATA_RETRIEVAL_TEAM');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Team NL2SQL_DATA_RETRIEVAL_TEAM does not exist, skipping');
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
      team_name  => 'NL2SQL_DATA_RETRIEVAL_TEAM',
      attributes =>
        '{' ||
        '"agents":[{"name":"NL2SQL_DATA_RETRIEVAL_AGENT","task":"NL2SQL_DATA_RETRIEVAL_TASK"}],' ||
        '"process":"sequential"' ||
        '}'
  );

  
  DBMS_OUTPUT.PUT_LINE('Created team NL2SQL_DATA_RETRIEVAL_TEAM');

  DBMS_OUTPUT.PUT_LINE('------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('NL2SQL Data Retrieval Team installation COMPLETE');
  DBMS_OUTPUT.PUT_LINE('------------------------------------------------');
  
END data_retrieval_agent;
/

----------------------------------------------------------------
-- 3. Execute installer in target schema
----------------------------------------------------------------
PROMPT Executing installer procedure ...
BEGIN
  &&INSTALL_SCHEMA..data_retrieval_agent('&&PROFILE_NAME');
END;
/

PROMPT ======================================================
PROMPT Installation finished successfully
PROMPT ======================================================

alter session set current_schema = ADMIN;







