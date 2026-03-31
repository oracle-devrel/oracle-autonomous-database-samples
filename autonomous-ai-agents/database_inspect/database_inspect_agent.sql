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
rem   Installer and configuration script for DATABASE_INSPECT AI teams.
rem   (Select AI Agent / Oracle AI Database)
rem
rem RELEASE VERSION
rem   1.1
rem
rem RELEASE DATE
rem   5-Feb-2026
rem
rem   This script:
rem     - Accepts target schema, AI profile name, agent team name, recreate
rem       choice, and guided scope inputs
rem     - Grants required privileges for agent submission and background jobs
rem     - Creates a log table for monitoring asynchronous agent creation
rem     - Submits agent creation as a DBMS_SCHEDULER background job
rem     - Persists success/failure/progress details in a log table
rem
rem PARAMETERS
rem   INSTALL_SCHEMA_NAME (Required)
rem     Schema where the team is created.
rem
rem   AI_PROFILE_NAME (Required)
rem     AI profile used for reasoning + embeddings.
rem
rem   AGENT_TEAM_NAME (Required)
rem     Team name to create or recreate.
rem
rem   RECREATE_EXISTING (Optional)
rem     Enter Y to drop and recreate an existing team with the same name.
rem     Default is N.
rem
rem   SCOPE_MODE (Optional)
rem     Guided scope input mode for building TEAM_ATTRIBUTES_JSON.
rem     Supported values: SCHEMA, TABLE, PACKAGE, JSON.
rem     Default is SCHEMA.
rem
rem   SCOPE_OWNERS (Optional)
rem     For SCHEMA mode, enter one or more schema owners separated by commas.
rem     Default is INSTALL_SCHEMA_NAME.
rem
rem   OBJECT_OWNER (Optional)
rem     For TABLE or PACKAGE mode, enter the owner/schema of the listed
rem     objects. Default is INSTALL_SCHEMA_NAME.
rem
rem   OBJECT_NAMES (Optional)
rem     For TABLE or PACKAGE mode, enter object names separated by commas.
rem
rem   MATCH_LIMIT (Optional)
rem     Optional match_limit value to include in built team attributes.
rem
rem   TEAM_ATTRIBUTES_JSON (Optional, JSON Mode)
rem     Full attributes JSON passed to DATABASE_INSPECT.create_inspect_agent_team.
rem     This is only prompted when SCOPE_MODE = JSON.
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
rem   2. Run this script as a SQL script using SQL*Plus/SQLcl/SQL Developer.
rem   3. Provide INSTALL_SCHEMA_NAME, AI_PROFILE_NAME, and AGENT_TEAM_NAME.
rem   4. Provide RECREATE_EXISTING if you want to replace an existing team.
rem   5. Use guided prompts to choose SCHEMA, TABLE, PACKAGE, or JSON scope.
rem   6. If SCOPE_MODE = JSON, provide TEAM_ATTRIBUTES_JSON.
rem   7. Monitor DATABASE_INSPECT_AGENT_JOB_LOG$ for background progress.
rem
rem GUIDED INPUT EXAMPLES
rem   1. Default-equivalent scope (single schema):
rem      SCOPE_MODE   = SCHEMA
rem      SCOPE_OWNERS = <INSTALL_SCHEMA_NAME>
rem
rem   2. Multiple schema owners:
rem      SCOPE_MODE   = SCHEMA
rem      SCOPE_OWNERS = SH,HR
rem
rem   3. Multiple tables in one schema:
rem      SCOPE_MODE   = TABLE
rem      OBJECT_OWNER = SH
rem      OBJECT_NAMES = SALES,CUSTOMERS,PRODUCTS
rem
rem   4. Multiple packages in one schema:
rem      SCOPE_MODE   = PACKAGE
rem      OBJECT_OWNER = HR
rem      OBJECT_NAMES = EMP_PKG,PAYROLL_PKG
rem
rem JSON MODE TEAM_ATTRIBUTES_JSON EXAMPLE
rem   Mixed object-level and schema-level scope:
rem      {"match_limit":20,"object_list":[{"owner":"SH","type":"TABLE","name":"SALES"},{"owner":"HR","type":"PACKAGE","name":"EMP_PKG"},{"owner":"OE","type":"SCHEMA"}]}
rem
rem NOTES
rem   - Script is safe to re-run.
rem   - Existing teams are only dropped when RECREATE_EXISTING = Y.
rem   - One row is written to DATABASE_INSPECT_AGENT_JOB_LOG$ per submission.
rem ============================================================================

SET SERVEROUTPUT ON
SET VERIFY OFF

PROMPT ======================================================
PROMPT DATABASE_INSPECT Agent Installer
PROMPT ======================================================

-- Target schema
VAR v_schema VARCHAR2(128)
EXEC :v_schema := '&&INSTALL_SCHEMA_NAME';
VAR v_invoker_schema VARCHAR2(128)
EXEC :v_invoker_schema := SYS_CONTEXT('USERENV', 'SESSION_USER');

-- AI profile name
VAR v_ai_profile_name VARCHAR2(128)
EXEC :v_ai_profile_name := '&&AI_PROFILE_NAME';

-- Agent team name
VAR v_agent_team_name VARCHAR2(128)
EXEC :v_agent_team_name := '&AGENT_TEAM_NAME';

PROMPT
PROMPT RECREATE_EXISTING:
PROMPT   Do you want to drop the existing team and recreate it if it already exists?
PROMPT   Enter Y for Yes or N for No.
PROMPT   Default is N.

-- Recreate flag
VAR v_recreate_existing VARCHAR2(1)
EXEC :v_recreate_existing := NVL(UPPER(TRIM('&RECREATE_EXISTING')), 'N');

PROMPT
PROMPT Guided Object Scope Setup
PROMPT   Common scope modes:
PROMPT   SCHEMA  - inspect one or more schemas
PROMPT   TABLE   - inspect one or more tables from one owner
PROMPT   PACKAGE - inspect one or more packages from one owner
PROMPT   JSON    - advanced mode; enter full TEAM_ATTRIBUTES_JSON
PROMPT   Default is SCHEMA.
PROMPT
PROMPT SCOPE_MODE:
PROMPT   Enter SCHEMA, TABLE, PACKAGE, or JSON.

VAR v_scope_mode VARCHAR2(20)
EXEC :v_scope_mode := NVL(UPPER(TRIM('&SCOPE_MODE')), 'SCHEMA');

VAR v_scope_owners VARCHAR2(4000)
VAR v_object_owner VARCHAR2(128)
VAR v_object_names VARCHAR2(4000)
VAR v_match_limit VARCHAR2(30)
VAR v_raw_team_attributes_json CLOB

BEGIN
  IF :v_scope_mode NOT IN ('SCHEMA', 'TABLE', 'PACKAGE', 'JSON') THEN
    RAISE_APPLICATION_ERROR(
      -20000,
      'Invalid SCOPE_MODE. Use SCHEMA, TABLE, PACKAGE, or JSON.'
    );
  END IF;
END;
/

PROMPT
PROMPT Scope Detail Inputs
PROMPT   If SCOPE_MODE = SCHEMA, enter SCOPE_OWNERS and optionally MATCH_LIMIT.
PROMPT   If SCOPE_MODE = TABLE or PACKAGE, enter OBJECT_OWNER, OBJECT_NAMES, and optionally MATCH_LIMIT.
PROMPT   If SCOPE_MODE = JSON, enter TEAM_ATTRIBUTES_JSON.
PROMPT   Leave inputs blank when they do not apply.
PROMPT

ACCEPT SCOPE_OWNERS CHAR PROMPT 'SCOPE_OWNERS (optional, comma-separated): '
ACCEPT OBJECT_OWNER CHAR PROMPT 'OBJECT_OWNER (optional): '
ACCEPT OBJECT_NAMES CHAR PROMPT 'OBJECT_NAMES (optional, comma-separated): '
ACCEPT MATCH_LIMIT CHAR PROMPT 'MATCH_LIMIT (optional): '
ACCEPT TEAM_ATTRIBUTES_JSON CHAR PROMPT 'TEAM_ATTRIBUTES_JSON (optional): '

BEGIN
  :v_scope_owners := '&&SCOPE_OWNERS';
  :v_object_owner := '&&OBJECT_OWNER';
  :v_object_names := '&&OBJECT_NAMES';
  :v_match_limit := '&&MATCH_LIMIT';
  :v_raw_team_attributes_json := q'~&&TEAM_ATTRIBUTES_JSON~';
END;
/

PROMPT
PROMPT AI_PROFILE_NAME is always enforced as profile_name by this installer.
PROMPT

VAR v_team_attributes_json CLOB
DECLARE
  l_scope_mode          VARCHAR2(30);
  l_scope_owners        VARCHAR2(4000);
  l_object_owner        VARCHAR2(128);
  l_object_names        VARCHAR2(4000);
  l_match_limit_input   VARCHAR2(30);
  l_raw_attributes_json CLOB;
  l_attributes          JSON_OBJECT_T := JSON_OBJECT_T('{}');
  l_object_list         JSON_ARRAY_T  := JSON_ARRAY_T();
  l_object_item         JSON_OBJECT_T;
  l_match_limit         NUMBER;
  l_token               VARCHAR2(4000);
  l_idx                 PLS_INTEGER;

  FUNCTION normalize_input(
    p_value IN VARCHAR2
  ) RETURN VARCHAR2
  IS
  BEGIN
    IF p_value IS NULL OR TRIM(p_value) IS NULL OR UPPER(TRIM(p_value)) = 'NULL'
    THEN
      RETURN NULL;
    END IF;

    RETURN TRIM(p_value);
  END normalize_input;

  FUNCTION normalize_clob_input(
    p_value IN CLOB
  ) RETURN CLOB
  IS
  BEGIN
    IF p_value IS NULL OR
       DBMS_LOB.GETLENGTH(p_value) = 0 OR
       UPPER(TRIM(DBMS_LOB.SUBSTR(p_value, 32767, 1))) = 'NULL'
    THEN
      RETURN NULL;
    END IF;

    RETURN p_value;
  END normalize_clob_input;

  PROCEDURE append_schema_owners(
    p_owner_csv IN VARCHAR2
  )
  IS
    l_owner_csv VARCHAR2(4000);
    l_raw_token VARCHAR2(4000);
  BEGIN
    l_owner_csv := normalize_input(p_owner_csv);

    IF l_owner_csv IS NULL THEN
      l_object_item := JSON_OBJECT_T('{}');
      l_object_item.put('owner', :v_schema);
      l_object_item.put('type', 'SCHEMA');
      l_object_list.append(l_object_item);
      RETURN;
    END IF;

    l_idx := 1;
    LOOP
      l_raw_token := REGEXP_SUBSTR(l_owner_csv, '[^,]+', 1, l_idx);
      EXIT WHEN l_raw_token IS NULL;
      l_token := normalize_input(l_raw_token);

      IF l_token IS NOT NULL THEN
        l_object_item := JSON_OBJECT_T('{}');
        l_object_item.put('owner', l_token);
        l_object_item.put('type', 'SCHEMA');
        l_object_list.append(l_object_item);
      END IF;

      l_idx := l_idx + 1;
    END LOOP;
  END append_schema_owners;

  PROCEDURE append_named_objects(
    p_owner       IN VARCHAR2,
    p_type        IN VARCHAR2,
    p_name_csv    IN VARCHAR2
  )
  IS
    l_owner    VARCHAR2(128);
    l_name_csv VARCHAR2(4000);
    l_raw_token VARCHAR2(4000);
  BEGIN
    l_owner := NVL(normalize_input(p_owner), :v_schema);
    l_name_csv := normalize_input(p_name_csv);

    IF l_name_csv IS NULL THEN
      RAISE_APPLICATION_ERROR(
        -20000,
        'OBJECT_NAMES is required when SCOPE_MODE is ' || p_type || '. ' ||
        'Enter one or more object names separated by commas.'
      );
    END IF;

    l_idx := 1;
    LOOP
      l_raw_token := REGEXP_SUBSTR(l_name_csv, '[^,]+', 1, l_idx);
      EXIT WHEN l_raw_token IS NULL;
      l_token := normalize_input(l_raw_token);

      IF l_token IS NOT NULL THEN
        l_object_item := JSON_OBJECT_T('{}');
        l_object_item.put('owner', l_owner);
        l_object_item.put('type', p_type);
        l_object_item.put('name', l_token);
        l_object_list.append(l_object_item);
      END IF;

      l_idx := l_idx + 1;
    END LOOP;
  END append_named_objects;
BEGIN
  l_scope_mode := NVL(normalize_input(:v_scope_mode), 'SCHEMA');
  l_scope_owners := :v_scope_owners;
  l_object_owner := :v_object_owner;
  l_object_names := :v_object_names;
  l_match_limit_input := normalize_input(:v_match_limit);
  l_raw_attributes_json := normalize_clob_input(:v_raw_team_attributes_json);

  IF l_scope_mode = 'JSON' THEN
    IF l_raw_attributes_json IS NULL THEN
      RAISE_APPLICATION_ERROR(
        -20000,
        'TEAM_ATTRIBUTES_JSON is required when SCOPE_MODE is JSON.'
      );
    END IF;

    :v_team_attributes_json := l_raw_attributes_json;
  ELSE
    IF l_scope_mode NOT IN ('SCHEMA', 'TABLE', 'PACKAGE', 'JSON') THEN
      RAISE_APPLICATION_ERROR(
        -20000,
        'Invalid SCOPE_MODE. Use SCHEMA, TABLE, PACKAGE, or JSON.'
      );
    END IF;

    CASE l_scope_mode
      WHEN 'SCHEMA' THEN
        append_schema_owners(l_scope_owners);
      WHEN 'TABLE' THEN
        append_named_objects(l_object_owner, 'TABLE', l_object_names);
      WHEN 'PACKAGE' THEN
        append_named_objects(l_object_owner, 'PACKAGE', l_object_names);
    END CASE;

    l_attributes.put('object_list', l_object_list);

    IF l_match_limit_input IS NOT NULL THEN
      BEGIN
        l_match_limit := TO_NUMBER(l_match_limit_input);
      EXCEPTION
        WHEN OTHERS THEN
          RAISE_APPLICATION_ERROR(
            -20000,
            'MATCH_LIMIT must be an integer between 1 and 100.'
          );
      END;

      IF l_match_limit <= 0 OR l_match_limit > 100 OR MOD(l_match_limit, 1) != 0
      THEN
        RAISE_APPLICATION_ERROR(
          -20000,
          'MATCH_LIMIT must be an integer between 1 and 100.'
        );
      END IF;

      l_attributes.put('match_limit', l_match_limit);
    END IF;

    :v_team_attributes_json := l_attributes.to_clob;
  END IF;

END;
/


----------------------------------------------------------------
-- 1. Grants (safe to re-run)
----------------------------------------------------------------
DECLARE
  l_sql VARCHAR2(500);
  l_session_user VARCHAR2(128) := SYS_CONTEXT('USERENV', 'SESSION_USER');
BEGIN
  -- Granting privileges to the current session user is a no-op and raises
  -- ORA-01749. Skip that case to keep reruns clean.
  IF UPPER(:v_schema) = UPPER(l_session_user) THEN
    DBMS_OUTPUT.PUT_LINE(
      'Skipping grants because target schema ' || :v_schema ||
      ' is the current session user.'
    );
  ELSE
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

    BEGIN
      l_sql := 'GRANT CREATE JOB TO ' || :v_schema;
      EXECUTE IMMEDIATE l_sql;
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE(
          'Warning: failed to grant CREATE JOB - ' || SQLERRM ||
          '. Ensure schema ' || :v_schema ||
          ' already has CREATE JOB before running the background installer.'
        );
    END;

    BEGIN
      l_sql := 'GRANT CREATE SEQUENCE TO ' || :v_schema;
      EXECUTE IMMEDIATE l_sql;
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE(
          'Warning: failed to grant CREATE SEQUENCE - ' || SQLERRM ||
          '. Ensure schema ' || :v_schema ||
          ' already has CREATE SEQUENCE before running the installer.'
        );
    END;

    BEGIN
      l_sql := 'GRANT CREATE PROCEDURE TO ' || :v_schema;
      EXECUTE IMMEDIATE l_sql;
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE(
          'Warning: failed to grant CREATE PROCEDURE - ' || SQLERRM ||
          '. Ensure schema ' || :v_schema ||
          ' already has CREATE PROCEDURE before running the installer.'
        );
    END;

    BEGIN
      l_sql := 'GRANT CREATE VIEW TO ' || :v_schema;
      EXECUTE IMMEDIATE l_sql;
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE(
          'Warning: failed to grant CREATE VIEW - ' || SQLERRM ||
          '. Ensure schema ' || :v_schema ||
          ' already has CREATE VIEW before running the installer.'
        );
    END;
  END IF;

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
-- 3. Create monitoring log table in target schema
----------------------------------------------------------------
BEGIN
  EXECUTE IMMEDIATE q'[
    CREATE TABLE DATABASE_INSPECT_AGENT_JOB_LOG$
    (
      run_id                        NUMBER GENERATED ALWAYS AS IDENTITY,
      team_name                     VARCHAR2(128) NOT NULL,
      install_schema                VARCHAR2(128) NOT NULL,
      profile_name                  VARCHAR2(128) NOT NULL,
      recreate_existing             VARCHAR2(1)   NOT NULL,
      requested_attributes_json     CLOB,
      effective_attributes_json     CLOB,
      existing_attributes_snapshot  CLOB,
      object_list_count             NUMBER,
      job_name                      VARCHAR2(128),
      status                        VARCHAR2(30)  NOT NULL,
      current_step                  VARCHAR2(100),
      status_message                CLOB,
      error_code                    NUMBER,
      error_message                 CLOB,
      error_stack                   CLOB,
      created_by                    VARCHAR2(128) DEFAULT SYS_CONTEXT('USERENV', 'SESSION_USER') NOT NULL,
      created_at                    TIMESTAMP(6)  DEFAULT SYSTIMESTAMP NOT NULL,
      queued_at                     TIMESTAMP(6),
      started_at                    TIMESTAMP(6),
      completed_at                  TIMESTAMP(6),
      updated_at                    TIMESTAMP(6)  DEFAULT SYSTIMESTAMP NOT NULL,
      CONSTRAINT DATABASE_INSPECT_AGENT_JOB_LOG_PK PRIMARY KEY (run_id)
    )
  ]';
  DBMS_OUTPUT.PUT_LINE('Created log table DATABASE_INSPECT_AGENT_JOB_LOG$.');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -955 THEN
      DBMS_OUTPUT.PUT_LINE('Log table DATABASE_INSPECT_AGENT_JOB_LOG$ already exists.');
    ELSE
      RAISE;
    END IF;
END;
/


----------------------------------------------------------------
-- 4. Create background worker procedure in target schema
----------------------------------------------------------------
CREATE OR REPLACE PROCEDURE &&INSTALL_SCHEMA_NAME..database_inspect_agent_worker (
  p_run_id IN NUMBER
)
AUTHID DEFINER
AS
  l_inspect_agent_teams           CONSTANT VARCHAR2(128) :=
                                    'DATABASE_INSPECT_AGENT_TEAMS$';
  l_inspect_agent_team_attributes CONSTANT VARCHAR2(128) :=
                                    'DATABASE_INSPECT_AGENT_TEAM_ATTRIBUTES$';
  l_inspect_agent_prefix          CONSTANT VARCHAR2(128) := 'INSPECT_AGENT';
  l_inspect_task_prefix           CONSTANT VARCHAR2(128) := 'INSPECT_TASK';

  l_install_schema               VARCHAR2(128);
  l_profile_name                 VARCHAR2(128);
  l_team_name                    VARCHAR2(128);
  l_recreate_existing            VARCHAR2(1);
  l_requested_attributes_json    CLOB;
  l_effective_attributes_json    CLOB;
  l_existing_attributes_snapshot CLOB;
  l_has_embedding_model          NUMBER := 0;
  l_profile_provider             VARCHAR2(128);
  l_has_oci_compartment_id       NUMBER := 0;
  l_object_list_count            NUMBER := 0;
  l_current_step                 VARCHAR2(100) := 'INITIALIZING';
  l_verification_message         CLOB;
  l_error_code                   NUMBER;
  l_error_message                VARCHAR2(32767);
  l_error_stack                  VARCHAR2(32767);
  l_friendly_status_message      VARCHAR2(32767);
  l_friendly_error_message       VARCHAR2(32767);

  l_attributes           JSON_OBJECT_T := JSON_OBJECT_T('{}');
  l_default_object_list  JSON_ARRAY_T  := JSON_ARRAY_T();
  l_default_object_item  JSON_OBJECT_T := JSON_OBJECT_T('{}');

  FUNCTION team_exists(
    p_team_name IN VARCHAR2
  ) RETURN BOOLEAN
  IS
    l_sql   VARCHAR2(4000);
    l_count NUMBER;
  BEGIN
    l_sql := 'SELECT COUNT(*) FROM ' || l_inspect_agent_teams ||
             ' WHERE agent_team_name = :1';
    EXECUTE IMMEDIATE l_sql INTO l_count USING p_team_name;
    RETURN l_count > 0;
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -942 THEN
        RAISE_APPLICATION_ERROR(
          -20000,
          'DATABASE_INSPECT internal tables are not available. ' ||
          'Run database_inspect_tool.sql before running this installer.'
        );
      ELSE
        RAISE;
      END IF;
  END team_exists;

  FUNCTION get_existing_attributes_snapshot(
    p_team_name IN VARCHAR2
  ) RETURN CLOB
  IS
    l_snapshot   CLOB;
    l_sql        VARCHAR2(4000);
    l_cursor     SYS_REFCURSOR;
    l_attr_name  VARCHAR2(128);
    l_attr_value CLOB;
    l_line       VARCHAR2(32767);
  BEGIN
    DBMS_LOB.CREATETEMPORARY(l_snapshot, TRUE);

    l_sql := 'SELECT attribute_name, attribute_value FROM ' ||
             l_inspect_agent_team_attributes ||
             ' WHERE agent_team_name = :1 ORDER BY attribute_name';

    OPEN l_cursor FOR l_sql USING p_team_name;
    LOOP
      FETCH l_cursor INTO l_attr_name, l_attr_value;
      EXIT WHEN l_cursor%NOTFOUND;

      l_line := l_attr_name || ' = ' ||
                CASE
                  WHEN l_attr_value IS NULL THEN
                    'NULL'
                  WHEN DBMS_LOB.GETLENGTH(l_attr_value) <= 3000 THEN
                    DBMS_LOB.SUBSTR(l_attr_value, 3000, 1)
                  ELSE
                    DBMS_LOB.SUBSTR(l_attr_value, 3000, 1) ||
                    '... [truncated]'
                END || CHR(10);

      DBMS_LOB.WRITEAPPEND(l_snapshot, LENGTH(l_line), l_line);
    END LOOP;
    CLOSE l_cursor;

    IF DBMS_LOB.GETLENGTH(l_snapshot) = 0 THEN
      DBMS_LOB.FREETEMPORARY(l_snapshot);
      RETURN NULL;
    END IF;

    RETURN l_snapshot;
  EXCEPTION
    WHEN OTHERS THEN
      IF l_cursor%ISOPEN THEN
        CLOSE l_cursor;
      END IF;

      IF DBMS_LOB.ISTEMPORARY(l_snapshot) = 1 THEN
        DBMS_LOB.FREETEMPORARY(l_snapshot);
      END IF;

      RETURN 'Unable to retrieve existing team attributes: ' || SQLERRM;
  END get_existing_attributes_snapshot;

  PROCEDURE cleanup_external_agent_objects(
    p_team_name IN VARCHAR2
  )
  IS
    l_agent_name VARCHAR2(261);
    l_task_name  VARCHAR2(261);
  BEGIN
    l_agent_name := l_inspect_agent_prefix || '_' || p_team_name;
    l_task_name  := l_inspect_task_prefix  || '_' || p_team_name;

    BEGIN
      DBMS_CLOUD_AI_AGENT.drop_team(p_team_name, TRUE);
    EXCEPTION
      WHEN OTHERS THEN
        NULL;
    END;

    BEGIN
      DBMS_CLOUD_AI_AGENT.drop_agent(l_agent_name, TRUE);
    EXCEPTION
      WHEN OTHERS THEN
        NULL;
    END;

    BEGIN
      DBMS_CLOUD_AI_AGENT.drop_task(l_task_name, TRUE);
    EXCEPTION
      WHEN OTHERS THEN
        NULL;
    END;
  END cleanup_external_agent_objects;

  FUNCTION build_friendly_install_error(
    p_error_code    IN NUMBER,
    p_error_message IN VARCHAR2,
    p_error_stack   IN VARCHAR2
  ) RETURN VARCHAR2
  IS
    l_error_text      VARCHAR2(32767);
    l_tablespace_name VARCHAR2(128);
    l_friendly_text   VARCHAR2(32767);
  BEGIN
    l_error_text := UPPER(NVL(p_error_message, ''));

    IF p_error_stack IS NOT NULL THEN
      l_error_text := l_error_text || CHR(10) || UPPER(p_error_stack);
    END IF;

    l_tablespace_name := REGEXP_SUBSTR(
      l_error_text,
      'TABLESPACE ''([^'']+)''',
      1,
      1,
      NULL,
      1
    );

    IF INSTR(l_error_text, 'COMPARTMENT ID MUST BE PROVIDED') > 0 THEN
      l_friendly_text :=
        'The selected AI profile uses OCI Generative AI embeddings but does not include oci_compartment_id. ' ||
        'Update the AI profile to set oci_compartment_id and rerun the installer.';
    ELSIF INSTR(l_error_text, 'ORA-01950') > 0 OR
          INSTR(l_error_text, 'NO PRIVILEGES ON TABLESPACE') > 0
    THEN
      l_friendly_text :=
        'Schema ' || l_install_schema || ' does not have quota on tablespace ' ||
        NVL(l_tablespace_name, 'required by the install') || '. ' ||
        'Grant quota on that tablespace and rerun the installer.';
    ELSIF INSTR(l_error_text, 'ORA-01536') > 0 OR
          INSTR(l_error_text, 'SPACE QUOTA EXCEEDED FOR TABLESPACE') > 0
    THEN
      l_friendly_text :=
        'Schema ' || l_install_schema || ' has exceeded its quota on tablespace ' ||
        NVL(l_tablespace_name, 'required by the install') || '. ' ||
        'Increase the quota or free space, then rerun the installer.';
    ELSIF INSTR(l_error_text, 'ORA-51808') > 0 OR
          INSTR(l_error_text, 'SAME DIMENSION COUNT') > 0 OR
          INSTR(l_error_text, 'DIMENSION COUNT') > 0
    THEN
      l_friendly_text :=
        'The embedding dimension does not match the existing vector objects. ' ||
        'This usually means the AI profile embedding model changed or stale inspect vector data already exists. ' ||
        'Recreate the team with RECREATE_EXISTING = Y and rerun the installer. ' ||
        'If the problem continues, drop the existing inspect team objects and retry with one consistent embedding model.';
    ELSE
      RETURN p_error_message;
    END IF;

    RETURN l_friendly_text || CHR(10) || CHR(10) ||
           'Original error:' || CHR(10) || p_error_message;
  END build_friendly_install_error;

  FUNCTION build_friendly_status_message(
    p_error_code    IN NUMBER,
    p_error_message IN VARCHAR2,
    p_error_stack   IN VARCHAR2
  ) RETURN VARCHAR2
  IS
    l_error_text      VARCHAR2(32767);
    l_tablespace_name VARCHAR2(128);
  BEGIN
    l_error_text := UPPER(NVL(p_error_message, ''));

    IF p_error_stack IS NOT NULL THEN
      l_error_text := l_error_text || CHR(10) || UPPER(p_error_stack);
    END IF;

    l_tablespace_name := REGEXP_SUBSTR(
      l_error_text,
      'TABLESPACE ''([^'']+)''',
      1,
      1,
      NULL,
      1
    );

    IF INSTR(l_error_text, 'COMPARTMENT ID MUST BE PROVIDED') > 0 THEN
      RETURN 'Agent installation failed because the OCI AI profile is missing oci_compartment_id.';
    ELSIF INSTR(l_error_text, 'ORA-01950') > 0 OR
          INSTR(l_error_text, 'NO PRIVILEGES ON TABLESPACE') > 0
    THEN
      RETURN 'Agent installation failed because schema ' || l_install_schema ||
             ' does not have quota on tablespace ' ||
             NVL(l_tablespace_name, 'required by the install') || '.';
    ELSIF INSTR(l_error_text, 'ORA-01536') > 0 OR
          INSTR(l_error_text, 'SPACE QUOTA EXCEEDED FOR TABLESPACE') > 0
    THEN
      RETURN 'Agent installation failed because schema ' || l_install_schema ||
             ' exceeded its quota on tablespace ' ||
             NVL(l_tablespace_name, 'required by the install') || '.';
    ELSIF INSTR(l_error_text, 'ORA-51808') > 0 OR
          INSTR(l_error_text, 'SAME DIMENSION COUNT') > 0 OR
          INSTR(l_error_text, 'DIMENSION COUNT') > 0
    THEN
      RETURN 'Agent installation failed because the embedding dimension does not match the existing inspect vector objects.';
    ELSE
      RETURN 'Agent installation failed.';
    END IF;
  END build_friendly_status_message;

  PROCEDURE update_log(
    p_status                       IN VARCHAR2,
    p_current_step                 IN VARCHAR2,
    p_status_message               IN CLOB,
    p_effective_attributes_json    IN CLOB     DEFAULT NULL,
    p_existing_attributes_snapshot IN CLOB     DEFAULT NULL,
    p_object_list_count            IN NUMBER   DEFAULT NULL,
    p_error_code                   IN NUMBER   DEFAULT NULL,
    p_error_message                IN CLOB     DEFAULT NULL,
    p_error_stack                  IN CLOB     DEFAULT NULL,
    p_mark_started                 IN VARCHAR2 DEFAULT 'N',
    p_mark_completed               IN VARCHAR2 DEFAULT 'N'
  )
  IS
  BEGIN
    UPDATE DATABASE_INSPECT_AGENT_JOB_LOG$
       SET status = p_status,
           current_step = p_current_step,
           status_message = p_status_message,
           effective_attributes_json =
             CASE
               WHEN p_effective_attributes_json IS NOT NULL THEN
                 p_effective_attributes_json
               ELSE
                 effective_attributes_json
             END,
           existing_attributes_snapshot =
             CASE
               WHEN p_existing_attributes_snapshot IS NOT NULL THEN
                 p_existing_attributes_snapshot
               ELSE
                 existing_attributes_snapshot
             END,
           object_list_count =
             CASE
               WHEN p_object_list_count IS NOT NULL THEN
                 p_object_list_count
               ELSE
                 object_list_count
             END,
           error_code = p_error_code,
           error_message = p_error_message,
           error_stack = p_error_stack,
           started_at =
             CASE
               WHEN p_mark_started = 'Y' AND started_at IS NULL THEN
                 SYSTIMESTAMP
               ELSE
                 started_at
             END,
           completed_at =
             CASE
               WHEN p_mark_completed = 'Y' THEN
                 SYSTIMESTAMP
               ELSE
                 completed_at
             END,
           updated_at = SYSTIMESTAMP
     WHERE run_id = p_run_id;

    COMMIT;
  END update_log;
BEGIN
  SELECT install_schema,
         profile_name,
         team_name,
         recreate_existing,
         requested_attributes_json
    INTO l_install_schema,
         l_profile_name,
         l_team_name,
         l_recreate_existing,
         l_requested_attributes_json
    FROM DATABASE_INSPECT_AGENT_JOB_LOG$
   WHERE run_id = p_run_id;

  l_current_step := 'VALIDATING_PROFILE';
  update_log(
    p_status         => 'RUNNING',
    p_current_step   => l_current_step,
    p_status_message => 'Background job started. Validating AI profile.',
    p_mark_started   => 'Y'
  );

  l_current_step := 'ENSURING_SETUP';
  update_log(
    p_status         => 'RUNNING',
    p_current_step   => l_current_step,
    p_status_message => 'Ensuring DATABASE_INSPECT internal tables exist.'
  );

  BEGIN
    -- Do not rely on package initialization side effects. Explicit setup
    -- guarantees the internal tables exist before we query them.
    DATABASE_INSPECT.setup;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE_APPLICATION_ERROR(
        -20000,
        'DATABASE_INSPECT package setup failed. Run database_inspect_tool.sql before running this installer. ' ||
        SQLERRM
      );
  END;

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
      ' must include attribute embedding_model. ' ||
      'Please configure an embedding model and re-run installer.'
    );
  END IF;

  BEGIN
    EXECUTE IMMEDIATE
      'SELECT MAX(CASE WHEN LOWER(attribute_name) = ''provider'' ' ||
      '                THEN DBMS_LOB.SUBSTR(attribute_value, 4000, 1) END), ' ||
      '       MAX(CASE WHEN LOWER(attribute_name) = ''oci_compartment_id'' ' ||
      '                 AND attribute_value IS NOT NULL THEN 1 ELSE 0 END) ' ||
      '  FROM user_cloud_ai_profile_attributes ' ||
      ' WHERE profile_name = :1'
      INTO l_profile_provider,
           l_has_oci_compartment_id
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

  l_profile_provider := LOWER(TRIM(l_profile_provider));

  IF l_profile_provider = 'oci' AND l_has_oci_compartment_id = 0 THEN
    RAISE_APPLICATION_ERROR(
      -20000,
      'AI profile ' || l_profile_name ||
      ' uses OCI Generative AI and must include attribute oci_compartment_id. ' ||
      'Please configure oci_compartment_id and re-run installer.'
    );
  END IF;

  l_current_step := 'RESOLVING_ATTRIBUTES';
  update_log(
    p_status         => 'RUNNING',
    p_current_step   => l_current_step,
    p_status_message => 'Resolving team attributes and object scope.'
  );

  IF l_requested_attributes_json IS NULL OR
     NVL(DBMS_LOB.GETLENGTH(l_requested_attributes_json), 0) = 0 OR
     UPPER(TRIM(DBMS_LOB.SUBSTR(l_requested_attributes_json, 4, 1))) = 'NULL'
  THEN
    l_default_object_item.put('owner', l_install_schema);
    l_default_object_item.put('type', 'SCHEMA');
    l_default_object_list.append(l_default_object_item);
    l_attributes.put('object_list', l_default_object_list);
  ELSE
    BEGIN
      l_attributes := JSON_OBJECT_T.parse(l_requested_attributes_json);
    EXCEPTION
      WHEN OTHERS THEN
        RAISE_APPLICATION_ERROR(
          -20000,
          'Invalid TEAM_ATTRIBUTES_JSON. Provide a valid JSON object. ' ||
          SQLERRM
        );
    END;
  END IF;

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

  l_effective_attributes_json := l_attributes.to_clob;

  update_log(
    p_status                    => 'RUNNING',
    p_current_step              => l_current_step,
    p_status_message            => 'Effective team attributes resolved.',
    p_effective_attributes_json => l_effective_attributes_json,
    p_object_list_count         => l_object_list_count
  );

  IF l_recreate_existing = 'Y' THEN
    l_current_step := 'CLEANING_EXTERNAL_OBJECTS';
    update_log(
      p_status                    => 'RUNNING',
      p_current_step              => l_current_step,
      p_status_message            => 'RECREATE_EXISTING = Y. Cleaning up any existing external AI team, agent, and task objects before creation.',
      p_effective_attributes_json => l_effective_attributes_json,
      p_object_list_count         => l_object_list_count
    );

    cleanup_external_agent_objects(l_team_name);
  END IF;

  IF team_exists(l_team_name) THEN
    l_existing_attributes_snapshot :=
      get_existing_attributes_snapshot(l_team_name);

    IF l_recreate_existing = 'Y' THEN
      l_current_step := 'DROPPING_EXISTING_TEAM';
      update_log(
        p_status                       => 'RUNNING',
        p_current_step                 => l_current_step,
        p_status_message               => 'Existing team found. Dropping team before recreation.',
        p_effective_attributes_json    => l_effective_attributes_json,
        p_existing_attributes_snapshot => l_existing_attributes_snapshot,
        p_object_list_count            => l_object_list_count
      );

      DATABASE_INSPECT.drop_inspect_agent_team(
        agent_team_name => l_team_name,
        force           => TRUE
      );
    ELSE
      RAISE_APPLICATION_ERROR(
        -20000,
        'Agent team ' || l_team_name ||
        ' already exists. Re-run installer with RECREATE_EXISTING = Y ' ||
        'to drop and recreate it.'
      );
    END IF;
  END IF;

  l_current_step := 'CREATING_TEAM';
  update_log(
    p_status                    => 'RUNNING',
    p_current_step              => l_current_step,
    p_status_message            => 'Creating team, task, tools, and vectorized object metadata. This step can take time for large object lists.',
    p_effective_attributes_json => l_effective_attributes_json,
    p_object_list_count         => l_object_list_count
  );

  DATABASE_INSPECT.create_inspect_agent_team(
    agent_team_name => l_team_name,
    attributes      => l_effective_attributes_json
  );

  l_current_step := 'VERIFYING_TOOLS';
  update_log(
    p_status                    => 'RUNNING',
    p_current_step              => l_current_step,
    p_status_message            => 'Team created. Verifying tool recreation.',
    p_effective_attributes_json => l_effective_attributes_json,
    p_object_list_count         => l_object_list_count
  );

  DECLARE
    l_count          NUMBER := 0;
    l_team_id        NUMBER;
    l_tool_suffix    VARCHAR2(100);
    l_sql            CLOB;
    l_expected_tools SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
      'list_objects',
      'list_incoming_dependencies',
      'list_outgoing_dependencies',
      'retrieve_object_metadata',
      'retrieve_object_metadata_chunks',
      'expand_object_metadata_chunk',
      'summarize_object',
      'generate_pldoc'
    );
  BEGIN
    l_sql := 'SELECT id# FROM ' || l_inspect_agent_teams ||
             ' WHERE agent_team_name = :1';
    EXECUTE IMMEDIATE l_sql INTO l_team_id USING l_team_name;

    l_tool_suffix := '_' || TO_CHAR(l_team_id);

    SELECT COUNT(*)
      INTO l_count
      FROM user_ai_agent_tools t
     WHERE UPPER(t.tool_name) IN (
       SELECT UPPER(COLUMN_VALUE || l_tool_suffix)
         FROM TABLE(l_expected_tools)
     );

    IF l_count != l_expected_tools.COUNT THEN
      RAISE_APPLICATION_ERROR(
        -20000,
        'Tool recreation check failed. Expected ' || l_expected_tools.COUNT ||
        ' tools with suffix ' || l_tool_suffix || ', found ' || l_count || '.'
      );
    END IF;

    l_verification_message :=
      'Team created successfully. Verified ' || l_count ||
      ' expected tools using suffix ' || l_tool_suffix || '.';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -942 THEN
        l_verification_message :=
          'Team created successfully. Tool verification was skipped because a required view/table is not visible: ' ||
          SQLERRM;
      ELSE
        RAISE;
      END IF;
  END;

  l_current_step := 'COMPLETED';
  update_log(
    p_status                    => 'SUCCEEDED',
    p_current_step              => l_current_step,
    p_status_message            => l_verification_message,
    p_effective_attributes_json => l_effective_attributes_json,
    p_object_list_count         => l_object_list_count,
    p_mark_completed            => 'Y'
  );
EXCEPTION
  WHEN OTHERS THEN
    l_error_code := SQLCODE;
    l_error_message := SQLERRM;
    l_error_stack := DBMS_UTILITY.format_error_stack || CHR(10) ||
                     DBMS_UTILITY.format_error_backtrace;
    l_friendly_status_message := build_friendly_status_message(
                                   p_error_code    => l_error_code,
                                   p_error_message => l_error_message,
                                   p_error_stack   => l_error_stack
                                 );
    l_friendly_error_message := build_friendly_install_error(
                                  p_error_code    => l_error_code,
                                  p_error_message => l_error_message,
                                  p_error_stack   => l_error_stack
                                );

    UPDATE DATABASE_INSPECT_AGENT_JOB_LOG$
       SET status = 'FAILED',
           current_step = l_current_step,
           status_message = l_friendly_status_message,
           effective_attributes_json =
             CASE
               WHEN l_effective_attributes_json IS NOT NULL THEN
                 l_effective_attributes_json
               ELSE
                 effective_attributes_json
             END,
           existing_attributes_snapshot =
             CASE
               WHEN l_existing_attributes_snapshot IS NOT NULL THEN
                 l_existing_attributes_snapshot
               ELSE
                 existing_attributes_snapshot
             END,
           object_list_count =
             CASE
               WHEN l_object_list_count IS NOT NULL THEN
                 l_object_list_count
               ELSE
                 object_list_count
             END,
           error_code = l_error_code,
           error_message = l_friendly_error_message,
           error_stack = l_error_stack,
           completed_at = SYSTIMESTAMP,
           updated_at = SYSTIMESTAMP
     WHERE run_id = p_run_id;

    COMMIT;
    RAISE;
END database_inspect_agent_worker;
/

show errors procedure database_inspect_agent_worker;


----------------------------------------------------------------
-- 5. Create installer submitter procedure in target schema
----------------------------------------------------------------
CREATE OR REPLACE PROCEDURE &&INSTALL_SCHEMA_NAME..database_inspect_agent (
  p_install_schema        IN VARCHAR2,
  p_profile_name          IN VARCHAR2,
  p_team_name             IN VARCHAR2,
  p_team_attributes_json  IN CLOB     DEFAULT NULL,
  p_recreate_existing     IN VARCHAR2 DEFAULT 'N'
)
AUTHID DEFINER
AS
  l_inspect_agent_teams           CONSTANT VARCHAR2(128) :=
                                    'DATABASE_INSPECT_AGENT_TEAMS$';
  l_inspect_agent_team_attributes CONSTANT VARCHAR2(128) :=
                                    'DATABASE_INSPECT_AGENT_TEAM_ATTRIBUTES$';

  l_install_schema               VARCHAR2(128);
  l_profile_name                 VARCHAR2(128);
  l_team_name                    VARCHAR2(128);
  l_recreate_existing            VARCHAR2(1);
  l_existing_attributes_snapshot CLOB;
  l_job_name                     VARCHAR2(128);
  l_run_id                       NUMBER;
  l_error_code                   NUMBER;
  l_error_message                CLOB;
  l_error_stack                  CLOB;

  FUNCTION team_exists(
    p_team_name IN VARCHAR2
  ) RETURN BOOLEAN
  IS
    l_sql   VARCHAR2(4000);
    l_count NUMBER;
  BEGIN
    l_sql := 'SELECT COUNT(*) FROM ' || l_inspect_agent_teams ||
             ' WHERE agent_team_name = :1';
    EXECUTE IMMEDIATE l_sql INTO l_count USING p_team_name;
    RETURN l_count > 0;
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -942 THEN
        RAISE_APPLICATION_ERROR(
          -20000,
          'DATABASE_INSPECT internal tables are not available. ' ||
          'Run database_inspect_tool.sql before running this installer.'
        );
      ELSE
        RAISE;
      END IF;
  END team_exists;

  FUNCTION get_existing_attributes_snapshot(
    p_team_name IN VARCHAR2
  ) RETURN CLOB
  IS
    l_snapshot   CLOB;
    l_sql        VARCHAR2(4000);
    l_cursor     SYS_REFCURSOR;
    l_attr_name  VARCHAR2(128);
    l_attr_value CLOB;
    l_line       VARCHAR2(32767);
  BEGIN
    DBMS_LOB.CREATETEMPORARY(l_snapshot, TRUE);

    l_sql := 'SELECT attribute_name, attribute_value FROM ' ||
             l_inspect_agent_team_attributes ||
             ' WHERE agent_team_name = :1 ORDER BY attribute_name';

    OPEN l_cursor FOR l_sql USING p_team_name;
    LOOP
      FETCH l_cursor INTO l_attr_name, l_attr_value;
      EXIT WHEN l_cursor%NOTFOUND;

      l_line := l_attr_name || ' = ' ||
                CASE
                  WHEN l_attr_value IS NULL THEN
                    'NULL'
                  WHEN DBMS_LOB.GETLENGTH(l_attr_value) <= 3000 THEN
                    DBMS_LOB.SUBSTR(l_attr_value, 3000, 1)
                  ELSE
                    DBMS_LOB.SUBSTR(l_attr_value, 3000, 1) ||
                    '... [truncated]'
                END || CHR(10);

      DBMS_LOB.WRITEAPPEND(l_snapshot, LENGTH(l_line), l_line);
    END LOOP;
    CLOSE l_cursor;

    IF DBMS_LOB.GETLENGTH(l_snapshot) = 0 THEN
      DBMS_LOB.FREETEMPORARY(l_snapshot);
      RETURN NULL;
    END IF;

    RETURN l_snapshot;
  EXCEPTION
    WHEN OTHERS THEN
      IF l_cursor%ISOPEN THEN
        CLOSE l_cursor;
      END IF;

      IF DBMS_LOB.ISTEMPORARY(l_snapshot) = 1 THEN
        DBMS_LOB.FREETEMPORARY(l_snapshot);
      END IF;

      RETURN 'Unable to retrieve existing team attributes: ' || SQLERRM;
  END get_existing_attributes_snapshot;

  PROCEDURE print_clob(
    p_text IN CLOB
  )
  IS
    l_pos NUMBER := 1;
  BEGIN
    IF p_text IS NULL THEN
      RETURN;
    END IF;

    WHILE l_pos <= DBMS_LOB.GETLENGTH(p_text) LOOP
      DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(p_text, 3000, l_pos));
      l_pos := l_pos + 3000;
    END LOOP;
  END print_clob;

  PROCEDURE print_monitor_query(
    p_run_id IN NUMBER
  )
  IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE('### Monitor Progress');
    DBMS_OUTPUT.PUT_LINE(
      'Use the query below to track this request in ' ||
      l_install_schema || '.DATABASE_INSPECT_AGENT_JOB_LOG$:'
    );
    DBMS_OUTPUT.PUT_LINE('SELECT');
    DBMS_OUTPUT.PUT_LINE('  run_id,');
    DBMS_OUTPUT.PUT_LINE('  team_name,');
    DBMS_OUTPUT.PUT_LINE('  status,');
    DBMS_OUTPUT.PUT_LINE('  current_step,');
    DBMS_OUTPUT.PUT_LINE('  job_name,');
    DBMS_OUTPUT.PUT_LINE('  created_at,');
    DBMS_OUTPUT.PUT_LINE('  started_at,');
    DBMS_OUTPUT.PUT_LINE('  completed_at,');
    DBMS_OUTPUT.PUT_LINE('  error_code,');
    DBMS_OUTPUT.PUT_LINE(
      '  DBMS_LOB.SUBSTR(status_message, 4000, 1) AS status_message'
    );
    DBMS_OUTPUT.PUT_LINE(
      'FROM ' || l_install_schema || '.DATABASE_INSPECT_AGENT_JOB_LOG$'
    );
    DBMS_OUTPUT.PUT_LINE('WHERE run_id = ' || p_run_id || ';');
  END print_monitor_query;
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

  DBMS_UTILITY.canonicalize(
    DBMS_ASSERT.SIMPLE_SQL_NAME(p_team_name),
    l_team_name,
    LENGTHB(p_team_name)
  );

  l_recreate_existing := NVL(UPPER(TRIM(p_recreate_existing)), 'N');

  IF l_recreate_existing NOT IN ('Y', 'N') THEN
    RAISE_APPLICATION_ERROR(
      -20000,
      'Invalid RECREATE_EXISTING value. Use Y or N.'
    );
  END IF;

  INSERT INTO DATABASE_INSPECT_AGENT_JOB_LOG$
    (
      team_name,
      install_schema,
      profile_name,
      recreate_existing,
      requested_attributes_json,
      status,
      current_step,
      status_message,
      updated_at
    )
  VALUES
    (
      l_team_name,
      l_install_schema,
      l_profile_name,
      l_recreate_existing,
      p_team_attributes_json,
      'PRECHECK',
      'PRECHECK',
      'Validating team request before scheduling.',
      SYSTIMESTAMP
    )
  RETURNING run_id INTO l_run_id;

  COMMIT;

  BEGIN
    -- Make sure internal team tables exist before precheck queries.
    DATABASE_INSPECT.setup;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE_APPLICATION_ERROR(
        -20000,
        'DATABASE_INSPECT package setup failed. Run database_inspect_tool.sql before running this installer. ' ||
        SQLERRM
      );
  END;

  IF team_exists(l_team_name) THEN
    l_existing_attributes_snapshot :=
      get_existing_attributes_snapshot(l_team_name);

    IF l_recreate_existing = 'N' THEN
      UPDATE DATABASE_INSPECT_AGENT_JOB_LOG$
         SET status = 'TEAM_EXISTS',
             current_step = 'PRECHECK_TEAM_EXISTS',
             status_message =
               'Agent team already exists. Re-run with RECREATE_EXISTING = Y to drop and recreate it.',
             existing_attributes_snapshot = l_existing_attributes_snapshot,
             completed_at = SYSTIMESTAMP,
             updated_at = SYSTIMESTAMP
       WHERE run_id = l_run_id;

      COMMIT;

      DBMS_OUTPUT.PUT_LINE('### Team Already Exists');
      DBMS_OUTPUT.PUT_LINE(
        'Agent team ' || l_team_name || ' already exists in schema ' ||
        l_install_schema || '.'
      );
      DBMS_OUTPUT.PUT_LINE(
        'Current attributes from ' ||
        l_install_schema || '.DATABASE_INSPECT_AGENT_TEAM_ATTRIBUTES$:'
      );
      print_clob(l_existing_attributes_snapshot);
      DBMS_OUTPUT.PUT_LINE('Run id: ' || l_run_id);
      DBMS_OUTPUT.PUT_LINE(
        'No background job was submitted. Re-run with RECREATE_EXISTING = Y to drop and recreate this team.'
      );
      print_monitor_query(l_run_id);
      RETURN;
    END IF;
  END IF;

  l_job_name := 'DBIA_JOB_' || TO_CHAR(l_run_id);

  UPDATE DATABASE_INSPECT_AGENT_JOB_LOG$
     SET status = 'QUEUED',
         current_step = 'JOB_SUBMITTED',
         status_message =
           CASE
             WHEN l_existing_attributes_snapshot IS NOT NULL THEN
               'Existing team found. Background job submitted and will drop/recreate the team.'
             ELSE
               'Background job submitted. Waiting for scheduler to start.'
           END,
         existing_attributes_snapshot =
           CASE
             WHEN l_existing_attributes_snapshot IS NOT NULL THEN
               l_existing_attributes_snapshot
             ELSE
               existing_attributes_snapshot
           END,
         job_name = l_job_name,
         queued_at = SYSTIMESTAMP,
         updated_at = SYSTIMESTAMP
   WHERE run_id = l_run_id;

  COMMIT;

  DBMS_SCHEDULER.create_job(
    job_name            => l_job_name,
    job_type            => 'STORED_PROCEDURE',
    job_action          => l_install_schema || '.DATABASE_INSPECT_AGENT_WORKER',
    number_of_arguments => 1,
    start_date          => SYSTIMESTAMP,
    enabled             => FALSE,
    auto_drop           => TRUE
  );

  DBMS_SCHEDULER.set_job_argument_value(
    job_name          => l_job_name,
    argument_position => 1,
    argument_value    => TO_CHAR(l_run_id)
  );

  DBMS_SCHEDULER.enable(l_job_name);

  DBMS_OUTPUT.PUT_LINE('### Background Job Submitted');
  DBMS_OUTPUT.PUT_LINE('Submitted background job ' || l_job_name ||
                       ' for team ' || l_team_name || '.');
  DBMS_OUTPUT.PUT_LINE('Run id: ' || l_run_id);
  print_monitor_query(l_run_id);
EXCEPTION
  WHEN OTHERS THEN
    l_error_code := SQLCODE;
    l_error_message := SQLERRM;
    l_error_stack := DBMS_UTILITY.format_error_stack || CHR(10) ||
                     DBMS_UTILITY.format_error_backtrace;

    IF l_run_id IS NOT NULL THEN
      UPDATE DATABASE_INSPECT_AGENT_JOB_LOG$
         SET status = 'FAILED_TO_QUEUE',
             current_step = 'JOB_SUBMISSION_FAILED',
             status_message = 'Failed to submit background job.',
             error_code = l_error_code,
             error_message = l_error_message,
             error_stack = l_error_stack,
             completed_at = SYSTIMESTAMP,
             updated_at = SYSTIMESTAMP
       WHERE run_id = l_run_id;

      COMMIT;
    END IF;

    RAISE;
END database_inspect_agent;
/

show errors procedure database_inspect_agent;


----------------------------------------------------------------
-- 6. Execute installer submitter in target schema
----------------------------------------------------------------
PROMPT Executing installer procedure ...
BEGIN
  &&INSTALL_SCHEMA_NAME..database_inspect_agent(
    p_install_schema       => :v_schema,
    p_profile_name         => :v_ai_profile_name,
    p_team_name            => :v_agent_team_name,
    p_team_attributes_json => :v_team_attributes_json,
    p_recreate_existing    => :v_recreate_existing
  );
END;
/

PROMPT ======================================================
PROMPT Installer request completed
PROMPT Monitor DATABASE_INSPECT_AGENT_JOB_LOG$ for progress
PROMPT ======================================================

BEGIN
  EXECUTE IMMEDIATE
    'ALTER SESSION SET CURRENT_SCHEMA = ' || :v_invoker_schema;
END;
/
