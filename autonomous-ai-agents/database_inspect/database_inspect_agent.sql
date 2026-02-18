rem ============================================================================
rem LICENSE
rem   Copyright (c) 2026 Oracle and/or its affiliates.
rem   Licensed under the Universal Permissive License (UPL), Version 1.0
rem   https://oss.oracle.com/licenses/upl/
rem
rem NAME
rem   database_inspect_agent.sql
rem
rem DESCRIPTION
rem   Installer and configuration script for DATABASE_INSPECT AI team.
rem   (Select AI Agent / Oracle AI Database)
rem
rem   This script:
rem     - Accepts target schema, AI profile name, and optional team attributes
rem     - Grants required privileges
rem     - Validates AI profile has embedding_model attribute
rem     - Recreates DATABASE_INSPECT team using DATABASE_INSPECT package
rem       (task, agent, and tools are created internally by package APIs)
rem
rem PARAMETERS
rem   INSTALL_SCHEMA_NAME (Required)
rem     Schema where the team is created.
rem
rem   AI_PROFILE_NAME (Required)
rem     AI profile used for reasoning + embeddings.
rem
rem   TEAM_ATTRIBUTES_JSON (Optional)
rem     Full attributes JSON passed to DATABASE_INSPECT.create_inspect_agent_team.
rem     If not provided (or provided as NULL), default object scope is:
rem       {"object_list":[{"owner":"<INSTALL_SCHEMA_NAME>","type":"SCHEMA"}]}
rem
rem     Note: profile_name from AI_PROFILE_NAME is always enforced by this
rem     installer, even if TEAM_ATTRIBUTES_JSON includes profile_name.
rem
rem IMPORTANT
rem   The AI profile must be associated with an embedding model
rem   (`embedding_model` profile attribute).
rem
rem INSTALL INSTRUCTIONS
rem   1. Connect as ADMIN or a user with required privileges.
rem   2. Run this script using SQL*Plus/SQLcl/SQL Developer.
rem   3. Provide INSTALL_SCHEMA_NAME and AI_PROFILE_NAME when prompted.
rem   4. Optionally provide TEAM_ATTRIBUTES_JSON.
rem
rem EXAMPLE TEAM_ATTRIBUTES_JSON VALUES
rem   1. Default-equivalent scope (single schema):
rem      {"object_list":[{"owner":"AGENT_TEST_USER","type":"SCHEMA"}]}
rem
rem   2. Multiple schema owners:
rem      {"object_list":[{"owner":"SH","type":"SCHEMA"},{"owner":"HR","type":"SCHEMA"}]}
rem
rem   3. Mixed object-level and schema-level scope:
rem      {"match_limit":20,"object_list":[{"owner":"SH","type":"TABLE","name":"SALES"},{"owner":"HR","type":"PACKAGE","name":"EMP_PKG"},{"owner":"OE","type":"SCHEMA"}]}
rem
rem NOTES
rem   - Script is safe to re-run; team is dropped/recreated.
rem   - Team name is fixed as DATABASE_INSPECT.
rem ============================================================================

SET SERVEROUTPUT ON
SET VERIFY OFF

PROMPT ======================================================
PROMPT DATABASE_INSPECT Agent Installer
PROMPT ======================================================

-- Target schema
VAR v_schema VARCHAR2(128)
EXEC :v_schema := '&INSTALL_SCHEMA_NAME';

-- AI profile name
VAR v_ai_profile_name VARCHAR2(128)
EXEC :v_ai_profile_name := '&AI_PROFILE_NAME';

PROMPT
PROMPT Optional TEAM_ATTRIBUTES_JSON (press Enter or type NULL to use default):
PROMPT Default:
PROMPT {"object_list":[{"owner":"<INSTALL_SCHEMA_NAME>","type":"SCHEMA"}]}
PROMPT
PROMPT Example 1 (multiple owners):
PROMPT {"object_list":[{"owner":"SH","type":"SCHEMA"},{"owner":"HR","type":"SCHEMA"}]}
PROMPT
PROMPT Example 2 (mixed object-level + schema-level scope):
PROMPT {"match_limit":20,"object_list":[{"owner":"SH","type":"TABLE","name":"SALES"},{"owner":"HR","type":"PACKAGE","name":"EMP_PKG"},{"owner":"OE","type":"SCHEMA"}]}
PROMPT
PROMPT AI_PROFILE_NAME is always enforced as profile_name by this installer.
PROMPT

VAR v_team_attributes_json CLOB
EXEC :v_team_attributes_json := '&TEAM_ATTRIBUTES_JSON';


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

  l_sql := 'GRANT EXECUTE ON DBMS_CLOUD_REPO TO ' || :v_schema;
  EXECUTE IMMEDIATE l_sql;

  l_sql := 'GRANT EXECUTE ON DBMS_VECTOR_CHAIN TO ' || :v_schema;
  EXECUTE IMMEDIATE l_sql;

  BEGIN
    l_sql := 'GRANT EXECUTE ON CTXSYS.CTX_DDL TO ' || :v_schema;
    EXECUTE IMMEDIATE l_sql;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Warning: failed to grant CTXSYS.CTX_DDL - ' || SQLERRM);
  END;

  DBMS_OUTPUT.PUT_LINE('Grants completed.');
END;
/


----------------------------------------------------------------
-- 2. Switch to target schema
----------------------------------------------------------------
BEGIN
  EXECUTE IMMEDIATE
    'ALTER SESSION SET CURRENT_SCHEMA = ' || :v_schema;
END;
/


----------------------------------------------------------------
-- 3. Create installer procedure in target schema
----------------------------------------------------------------
CREATE OR REPLACE PROCEDURE database_inspect_agent (
  p_install_schema        IN VARCHAR2,
  p_profile_name          IN VARCHAR2,
  p_team_attributes_json  IN CLOB DEFAULT NULL
)
AUTHID DEFINER
AS
  l_install_schema      VARCHAR2(128);
  l_profile_name        VARCHAR2(128);
  l_has_embedding_model NUMBER := 0;
  l_team_name           CONSTANT VARCHAR2(128) :=
                          DATABASE_INSPECT.DATABASE_INSPECT_PACKAGE;
  l_object_list_count   NUMBER := 0;
  l_team_attributes_json CLOB := p_team_attributes_json;

  l_attributes           JSON_OBJECT_T := JSON_OBJECT_T('{}');
  l_default_object_list  JSON_ARRAY_T  := JSON_ARRAY_T();
  l_default_object_item  JSON_OBJECT_T := JSON_OBJECT_T('{}');
BEGIN
  DBMS_UTILITY.canonicalize(
    DBMS_ASSERT.SIMPLE_SQL_NAME(p_install_schema),
    l_install_schema,
    LENGTHB(p_install_schema)
  );

  DBMS_UTILITY.canonicalize(
    DBMS_ASSERT.SIMPLE_SQL_NAME(p_profile_name),
    l_profile_name,
    LENGTHB(p_profile_name)
  );

  ----------------------------------------------------------------
  -- Validate that profile has embedding_model configured.
  ----------------------------------------------------------------
  BEGIN
    EXECUTE IMMEDIATE
      'SELECT COUNT(*) FROM user_cloud_ai_profile_attributes ' ||
      'WHERE profile_name = :1 ' ||
      '  AND LOWER(attribute_name) = ''embedding_model'' ' ||
      '  AND attribute_value IS NOT NULL'
      INTO l_has_embedding_model
      USING l_profile_name;
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -942 THEN
        RAISE_APPLICATION_ERROR(
          -20000,
          'USER_CLOUD_AI_PROFILE_ATTRIBUTES is not available in this schema context. ' ||
          'Validate DBMS_CLOUD_AI profile metadata visibility and retry.'
        );
      ELSE
        RAISE;
      END IF;
  END;

  IF l_has_embedding_model = 0 THEN
    RAISE_APPLICATION_ERROR(
      -20000,
      'AI profile ' || l_profile_name ||
      ' must include attribute embedding_model. '
      || 'Please configure an embedding model and re-run installer.'
    );
  END IF;

  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Starting DATABASE_INSPECT team installation');
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('AI profile: ' || l_profile_name);
  DBMS_OUTPUT.PUT_LINE('Embedding model attribute is configured.');

  ----------------------------------------------------------------
  -- Resolve team attributes.
  ----------------------------------------------------------------
  IF l_team_attributes_json IS NULL OR
     NVL(DBMS_LOB.GETLENGTH(l_team_attributes_json), 0) = 0 OR
     UPPER(TRIM(DBMS_LOB.SUBSTR(l_team_attributes_json, 4, 1))) = 'NULL'
  THEN
    l_default_object_item.put('owner', l_install_schema);
    l_default_object_item.put('type', 'SCHEMA');
    l_default_object_list.append(l_default_object_item);
    l_attributes.put('object_list', l_default_object_list);

    DBMS_OUTPUT.PUT_LINE(
      'TEAM_ATTRIBUTES_JSON not provided. Using default object_list for schema ' ||
      l_install_schema || '.'
    );
  ELSE
    BEGIN
      l_attributes := JSON_OBJECT_T.parse(l_team_attributes_json);
      DBMS_OUTPUT.PUT_LINE('Using custom TEAM_ATTRIBUTES_JSON.');
    EXCEPTION
      WHEN OTHERS THEN
        RAISE_APPLICATION_ERROR(
          -20000,
          'Invalid TEAM_ATTRIBUTES_JSON. Provide a valid JSON object. ' ||
          SQLERRM
        );
    END;
  END IF;

  -- Always enforce the AI profile parameter.
  l_attributes.put('profile_name', l_profile_name);

  IF l_attributes.get('object_list') IS NULL THEN
    RAISE_APPLICATION_ERROR(
      -20000,
      'TEAM_ATTRIBUTES_JSON must include object_list.'
    );
  END IF;

  BEGIN
    l_object_list_count := JSON_ARRAY_T(l_attributes.get('object_list')).get_size;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE_APPLICATION_ERROR(
        -20000,
        'TEAM_ATTRIBUTES_JSON object_list must be a JSON array.'
      );
  END;

  IF l_object_list_count = 0 THEN
    RAISE_APPLICATION_ERROR(
      -20000,
      'TEAM_ATTRIBUTES_JSON object_list must not be empty.'
    );
  END IF;
  DBMS_OUTPUT.PUT_LINE('object_list entries: ' || l_object_list_count);

  ----------------------------------------------------------------
  -- Recreate team to ensure task/agent/tools are recreated.
  ----------------------------------------------------------------
  DATABASE_INSPECT.drop_inspect_agent_team(
    agent_team_name => l_team_name,
    force           => TRUE
  );

  DATABASE_INSPECT.create_inspect_agent_team(
    agent_team_name => l_team_name,
    attributes      => l_attributes.to_clob
  );

  DBMS_OUTPUT.PUT_LINE('Created team ' || l_team_name ||
                       ' (agent/task/tools created internally by DATABASE_INSPECT package).');

  ----------------------------------------------------------------
  -- Verification for recreated tools with expected team-id suffix.
  ----------------------------------------------------------------
  DECLARE
    l_count       NUMBER := 0;
    l_team_id     NUMBER;
    l_tool_suffix VARCHAR2(100);
    l_sql         CLOB;
    l_cursor      SYS_REFCURSOR;
    l_tool_name   VARCHAR2(4000);
    l_expected_tools SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
      DATABASE_INSPECT.TOOL_LIST_OBJECTS,
      DATABASE_INSPECT.TOOL_LIST_INCOMING_DEPENDENCIES,
      DATABASE_INSPECT.TOOL_LIST_OUTGOING_DEPENDENCIES,
      DATABASE_INSPECT.TOOL_RETRIEVE_OBJECT_METADATA,
      DATABASE_INSPECT.TOOL_RETRIEVE_OBJECT_METADATA_CHUNKS,
      DATABASE_INSPECT.TOOL_EXPAND_OBJECT_METADATA_CHUNK,
      DATABASE_INSPECT.TOOL_SUMMARIZE_OBJECT,
      DATABASE_INSPECT.TOOL_GENERATE_PLDOC
    );
  BEGIN
    l_sql := 'SELECT id# FROM ' || DATABASE_INSPECT.INSPECT_AGENT_TEAMS || ' ' ||
             'WHERE agent_team_name = :1';
    EXECUTE IMMEDIATE l_sql INTO l_team_id USING l_team_name;

    l_tool_suffix := '_' || TO_CHAR(l_team_id);

    SELECT COUNT(*)
      INTO l_count
      FROM user_ai_agent_tools t
     WHERE UPPER(t.tool_name) IN (
       SELECT UPPER(COLUMN_VALUE || l_tool_suffix)
         FROM TABLE(l_expected_tools)
     );

    DBMS_OUTPUT.PUT_LINE('Tool suffix for team ' || l_team_name ||
                         ': ' || l_tool_suffix);
    DBMS_OUTPUT.PUT_LINE('Expected tools found: ' || l_count || ' / ' ||
                         l_expected_tools.COUNT);

    IF l_count != l_expected_tools.COUNT THEN
      RAISE_APPLICATION_ERROR(
        -20000,
        'Tool recreation check failed. Expected ' || l_expected_tools.COUNT ||
        ' tools with suffix ' ||
        l_tool_suffix || ', found ' || l_count || '.'
      );
    END IF;

    l_sql := 'SELECT tool_name FROM user_ai_agent_tools ' ||
             'WHERE tool_name LIKE :1 ORDER BY tool_name';
    OPEN l_cursor FOR l_sql USING '%' || l_tool_suffix;
    LOOP
      FETCH l_cursor INTO l_tool_name;
      EXIT WHEN l_cursor%NOTFOUND;
      DBMS_OUTPUT.PUT_LINE('  - ' || l_tool_name);
    END LOOP;
    CLOSE l_cursor;
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -942 THEN
        DBMS_OUTPUT.PUT_LINE(
          'Warning: tool verification skipped because required table/view is not visible: ' ||
          SQLERRM
        );
      ELSE
        RAISE;
      END IF;
  END;

  DBMS_OUTPUT.PUT_LINE('------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('DATABASE_INSPECT Team installation COMPLETE');
  DBMS_OUTPUT.PUT_LINE('------------------------------------------------');
END database_inspect_agent;
/


----------------------------------------------------------------
-- 4. Execute installer in target schema
----------------------------------------------------------------
PROMPT Executing installer procedure ...
BEGIN
  database_inspect_agent(
    p_install_schema       => :v_schema,
    p_profile_name         => :v_ai_profile_name,
    p_team_attributes_json => :v_team_attributes_json
  );
END;
/

PROMPT ======================================================
PROMPT Installation finished successfully
PROMPT ======================================================

alter session set current_schema = ADMIN;
