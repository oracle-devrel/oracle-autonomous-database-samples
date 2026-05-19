rem ============================================================================
rem LICENSE
rem   Copyright (c) 2026 Oracle and/or its affiliates.
rem   Licensed under the Universal Permissive License (UPL), Version 1.0
rem   https://oss.oracle.com/licenses/upl/
rem
rem NAME
rem   dbms_scheduler_monitor_agent.sql
rem
rem DESCRIPTION
rem   Installer and configuration script for Scheduler Monitoring AI Agent Team.
rem
rem RELEASE VERSION
rem   1.0
rem
rem RELEASE DATE
rem   19-May-2026
rem ============================================================================

SET SERVEROUTPUT ON
SET VERIFY OFF

PROMPT ======================================================
PROMPT Scheduler Monitoring AI Agent Installer
PROMPT ======================================================

VAR v_schema VARCHAR2(128)
EXEC :v_schema := '&SCHEMA_NAME';

VAR v_ai_profile_name VARCHAR2(128)
EXEC :v_ai_profile_name := '&AI_PROFILE_NAME';

PROMPT
PROMPT SCHED_TARGET_OWNER:
PROMPT   Logical default owner label for responses.
PROMPT   Data is sourced from USER_SCHEDULER_* in the install schema.
PROMPT   If blank, SCHEMA_NAME is used.
PROMPT

VAR v_sched_target_owner VARCHAR2(128)
EXEC :v_sched_target_owner := '&SCHED_TARGET_OWNER';

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

CREATE OR REPLACE PROCEDURE install_scheduler_monitor_agent(
  p_install_schema     IN VARCHAR2,
  p_profile_name       IN VARCHAR2,
  p_sched_target_owner IN VARCHAR2
)
AUTHID DEFINER
AS
  l_target_owner VARCHAR2(128);
BEGIN
  l_target_owner := UPPER(TRIM(NVL(p_sched_target_owner, p_install_schema)));

  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TASK('SCHEDULER_MONITOR_TASKS');
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name   => 'SCHEDULER_MONITOR_TASKS',
    description => 'Task for Oracle DBMS_SCHEDULER monitoring, history, and CPU/load analysis',
    attributes  => '{
      "instruction": "You are an Oracle DBMS_SCHEDULER monitoring expert. '
        || 'Default owner label is ' || l_target_owner || ' when owner is omitted. '
        || 'This agent monitors USER_SCHEDULER_* objects in the install schema (local schema scope). '
        || 'For schema-wide requests, auto-discover local jobs from USER_SCHEDULER metadata and do not ask users to provide object lists. '
        || 'When user asks how many jobs or all job details, call LIST_ALL_JOBS_TOOL first and answer with count plus detailed rows. '
        || 'If user asks for full list of jobs, return the complete job-name list from LIST_ALL_JOBS_TOOL rows (not a sample). '
        || 'Do not show sample tables unless user explicitly asks for sample/top-N. '
        || 'Never use ellipsis like dot-dot-dot (N more jobs) for full-list requests. '
        || 'For full-list table requests, output every row from LIST_ALL_JOBS_TOOL rows. '
        || 'If output is too large for one response, paginate deterministically as Page 1, Page 2, ... with fixed row ranges until all rows are shown. '
        || 'Do not infer total jobs from job history or running jobs when LIST_ALL_JOBS_TOOL is available. '
        || 'If user mentions another schema name, explain this agent is local-schema scoped (USER_SCHEDULER_*), then continue using current schema data unless cross-schema support is explicitly added. '
        || 'Always return: executive summary, detailed tables, chart section, diagnostics, and recommendations. '
        || 'For any relative date/time request (today, yesterday, last day, previous day, last week), call GET_DATABASE_CURRENT_TIME_TOOL first and derive interval boundaries from database time, not model time. '
        || 'Use LIST_RUNNING_JOBS_TOOL for running jobs. '
        || 'Use LIST_JOB_HISTORY_TOOL for historical interval analysis with success/failure and p95 metrics. '
        || 'Use GET_JOB_DETAILS_TOOL for selected job metadata, args, schedule/program details, and recent run diagnostics. '
        || 'Use ANALYZE_CPU_BY_JOB_TOOL and ANALYZE_LOAD_BY_JOB_TOOL for CPU and load correlation. '
        || 'Use COMPARE_JOBS_TOOL when user asks comparison. '
        || 'Use IDENTIFY_HOTSPOTS_TOOL for contention and overlap hotspots. '
        || 'Use DETECT_FAILURES_TOOL for recurring failures and error patterns. '
        || 'Use SUMMARIZE_SCHEDULER_HEALTH_TOOL for fleet overview. '
        || 'Use GENERATE_CHARTS_TOOL for chart-ready output. '
        || 'Use EXPORT_TABLES_TOOL for exportable table payloads. '
        || 'Clearly label correlations as exact or inferred and include confidence level; do not overstate weak attribution. '
        || 'If performance views are unavailable, say so and provide nearest proxy metrics. '
        || 'User request: {query}",
      "tools": [
        "GET_DATABASE_CURRENT_TIME_TOOL",
        "LIST_ALL_JOBS_TOOL",
        "LIST_RUNNING_JOBS_TOOL",
        "LIST_JOB_HISTORY_TOOL",
        "GET_JOB_DETAILS_TOOL",
        "ANALYZE_CPU_BY_JOB_TOOL",
        "ANALYZE_LOAD_BY_JOB_TOOL",
        "COMPARE_JOBS_TOOL",
        "IDENTIFY_HOTSPOTS_TOOL",
        "DETECT_FAILURES_TOOL",
        "SUMMARIZE_SCHEDULER_HEALTH_TOOL",
        "GENERATE_CHARTS_TOOL",
        "EXPORT_TABLES_TOOL"
      ],
      "enable_human_tool": "true"
    }'
  );

  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_AGENT('SCHEDULER_MONITOR_ADVISOR');
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'SCHEDULER_MONITOR_ADVISOR',
    attributes =>
      '{' ||
      '"profile_name":"' || p_profile_name || '",' ||
      '"role":"You are a senior Oracle scheduler operations and performance advisor. You diagnose running and historical scheduler behavior, correlate workload with CPU/load, and provide actionable operational recommendations."' ||
      '}',
    description => 'AI agent for DBMS_SCHEDULER monitoring and performance diagnostics'
  );

  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TEAM('DBMS_SCHEDULER_MONITOR_TEAM');
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
    team_name  => 'DBMS_SCHEDULER_MONITOR_TEAM',
    attributes => '{
      "agents":[{"name":"SCHEDULER_MONITOR_ADVISOR","task":"SCHEDULER_MONITOR_TASKS"}],
      "process":"sequential"
    }'
  );

  DBMS_OUTPUT.PUT_LINE('Scheduler monitor task, agent, and team created successfully.');
END install_scheduler_monitor_agent;
/

PROMPT Executing installer procedure ...
BEGIN
  install_scheduler_monitor_agent(
    p_install_schema     => :v_schema,
    p_profile_name       => :v_ai_profile_name,
    p_sched_target_owner => :v_sched_target_owner
  );
END;
/

ALTER SESSION SET CURRENT_SCHEMA = ADMIN;

PROMPT ======================================================
PROMPT Scheduler Monitoring Agent installation complete
PROMPT ======================================================
