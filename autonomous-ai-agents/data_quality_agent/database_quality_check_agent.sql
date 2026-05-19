rem ============================================================================
rem LICENSE
rem   Copyright (c) 2026 Oracle and/or its affiliates.
rem   Licensed under the Universal Permissive License (UPL), Version 1.0
rem   https://oss.oracle.com/licenses/upl/
rem
rem NAME
rem   database_quality_check_agent.sql
rem
rem DESCRIPTION
rem   Installer and configuration script for Data Quality Check AI Agent Team.
rem
rem RELEASE VERSION
rem   1.0
rem
rem RELEASE DATE
rem   18-May-2026
rem ============================================================================

SET SERVEROUTPUT ON
SET VERIFY OFF

PROMPT ======================================================
PROMPT Data Quality Check AI Agent Installer
PROMPT ======================================================

VAR v_schema VARCHAR2(128)
EXEC :v_schema := '&SCHEMA_NAME';

VAR v_ai_profile_name VARCHAR2(128)
EXEC :v_ai_profile_name := '&AI_PROFILE_NAME';

PROMPT
PROMPT DQ_TARGET_SCHEMA:
PROMPT   Schema to inspect by default for data quality checks.
PROMPT   If blank, SCHEMA_NAME is used as default.
PROMPT

VAR v_dq_target_schema VARCHAR2(128)
EXEC :v_dq_target_schema := '&DQ_TARGET_SCHEMA';

DECLARE
  l_sql          VARCHAR2(500);
  l_schema       VARCHAR2(128);
  l_session_user VARCHAR2(128);
BEGIN
  l_schema := DBMS_ASSERT.SIMPLE_SQL_NAME(:v_schema);
  l_session_user := SYS_CONTEXT('USERENV', 'SESSION_USER');

  IF UPPER(l_schema) <> UPPER(l_session_user) THEN
    l_sql := 'GRANT EXECUTE ON DBMS_CLOUD_AI_AGENT TO ' || l_schema;
    EXECUTE IMMEDIATE l_sql;

    l_sql := 'GRANT EXECUTE ON DBMS_CLOUD_AI TO ' || l_schema;
    EXECUTE IMMEDIATE l_sql;

    l_sql := 'GRANT EXECUTE ON DBMS_CLOUD TO ' || l_schema;
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

CREATE OR REPLACE PROCEDURE install_data_quality_check_agent(
  p_install_schema   IN VARCHAR2,
  p_profile_name     IN VARCHAR2,
  p_dq_target_schema IN VARCHAR2
)
AUTHID DEFINER
AS
  l_target_schema VARCHAR2(128);
BEGIN
  l_target_schema := UPPER(TRIM(NVL(p_dq_target_schema, p_install_schema)));

  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Starting Data Quality Check AI installation');
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');

  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TASK('DATA_QUALITY_TASKS');
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name   => 'DATA_QUALITY_TASKS',
    description => 'Task for data quality profiling, scoring, and remediation planning',
    attributes  => '{
      "instruction": "You are a Data Quality specialist for Oracle Autonomous Database. '
        || 'Default target schema for data quality checks is ' || l_target_schema || '. '
        || 'If the user does not provide owner_name, use owner_name=' || l_target_schema || '. '
        || 'If the user provides a different schema explicitly, use that schema. '
        || 'Cross-schema analysis is allowed when object privileges are granted to the install schema. '
        || 'When the user asks for all tables or schema-wide analysis, automatically discover table names from the target schema and run checks without asking the user to provide table lists. '
        || 'If no owner_name is provided in schema-wide requests, use owner_name=' || l_target_schema || '. '
        || 'Do not ask the user for table names when this can be derived from ALL_TABLES/USER_TABLES metadata. '
        || 'Use PROFILE_TABLE_TOOL first to establish table baseline when user provides owner/table. '
        || 'Use DETECT_NULLS_TOOL, DETECT_DUPLICATES_TOOL, and DETECT_OUTLIERS_TOOL to identify quality issues with severity. '
        || 'Use GENERATE_QUALITY_RULES_TOOL to propose enforceable quality rules. '
        || 'Use EVALUATE_QUALITY_SCORE_TOOL to compute/store overall quality score and history point. '
        || 'Use DETECT_DRIFT_TOOL to identify recent score drift against baseline history. '
        || 'Use SETUP_OML_DATA_MONITORING_TOOL for automated OML Services data monitoring setup when requested. '
        || 'Use RUN_OML_DATA_MONITORING_TOOL to trigger OML monitoring jobs and report run response. '
        || 'Use LIST_QUALITY_ISSUES_TOOL for issue review. '
        || 'Use SUGGEST_REMEDIATION_TOOL to produce practical SQL-based fixes. '
        || 'Only use APPLY_REMEDIATION_TOOL in PREVIEW mode unless the user explicitly asks to apply changes and provides approval_code. '
        || 'Always return: issue summary, severity, quality score, and next remediation step. '
        || 'User request: {query}",
      "tools": [
        "PROFILE_TABLE_TOOL",
        "DETECT_NULLS_TOOL",
        "DETECT_DUPLICATES_TOOL",
        "DETECT_OUTLIERS_TOOL",
        "DETECT_DRIFT_TOOL",
        "SETUP_OML_DATA_MONITORING_TOOL",
        "RUN_OML_DATA_MONITORING_TOOL",
        "GENERATE_QUALITY_RULES_TOOL",
        "EVALUATE_QUALITY_SCORE_TOOL",
        "LIST_QUALITY_ISSUES_TOOL",
        "SUGGEST_REMEDIATION_TOOL",
        "APPLY_REMEDIATION_TOOL"
      ],
      "enable_human_tool": "true"
    }'
  );
  DBMS_OUTPUT.PUT_LINE('Created task DATA_QUALITY_TASKS');

  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_AGENT('DATA_QUALITY_ADVISOR');
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'DATA_QUALITY_ADVISOR',
    attributes =>
      '{' ||
      '"profile_name":"' || p_profile_name || '",' ||
      '"role":"You are a Data Quality Advisor. You profile data, detect anomalies and drift, compute quality scores, and recommend safe remediation steps for Oracle Autonomous Database tables."' ||
      '}',
    description => 'AI agent for Oracle Autonomous Database data quality monitoring and remediation guidance'
  );
  DBMS_OUTPUT.PUT_LINE('Created agent DATA_QUALITY_ADVISOR');

  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TEAM('DATA_QUALITY_TEAM');
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
    team_name  => 'DATA_QUALITY_TEAM',
    attributes => '{
      "agents":[{"name":"DATA_QUALITY_ADVISOR","task":"DATA_QUALITY_TASKS"}],
      "process":"sequential"
    }'
  );

  DBMS_OUTPUT.PUT_LINE('Created team DATA_QUALITY_TEAM');
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Data Quality Check AI installation COMPLETE');
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
END install_data_quality_check_agent;
/

PROMPT Executing installer procedure ...
BEGIN
  install_data_quality_check_agent(
    p_install_schema   => :v_schema,
    p_profile_name     => :v_ai_profile_name,
    p_dq_target_schema => :v_dq_target_schema
  );
END;
/

ALTER SESSION SET CURRENT_SCHEMA = ADMIN;

PROMPT ======================================================
PROMPT Installation finished successfully
PROMPT ======================================================
