rem ============================================================================
rem LICENSE
rem   Copyright (c) 2026 Oracle and/or its affiliates.
rem   Licensed under the Universal Permissive License (UPL), Version 1.0
rem   https://oss.oracle.com/licenses/upl/
rem
rem NAME
rem   jira_inspect_tools.sql
rem
rem DESCRIPTION
rem   Installer script for Jira Select AI tools
rem   (Select AI Agent / Oracle AI Database).
rem
rem   This script installs Jira PL/SQL packages and registers
rem   AI Agent tools used to query Jira and Atlassian APIs
rem   via Select AI Agent.
rem
rem RELEASE VERSION
rem   1.0
rem
rem RELEASE DATE
rem   20-Feb-2026
rem
rem MAJOR CHANGES IN THIS RELEASE
rem - Initial release
rem - Added Jira configuration bootstrap using SELECTAI_AGENT_CONFIG
rem - Added Jira tools installer procedure
rem
rem SCRIPT STRUCTURE
rem   1. Initialization:
rem        - Grants
rem        - Configuration setup
rem
rem   2. Package Deployment:
rem        - jira_selectai (package specification and body)
rem        - select_ai_jira_agent (package specification and body)
rem
rem   3. AI Tool Setup:
rem        - Creation of all Jira agent tools
rem
rem INSTALL INSTRUCTIONS
rem   1. Connect as ADMIN or a user with required privileges
rem
rem   2. Run the script using SQL Developer / Web SQL Developer.
rem
rem   3. Provide inputs when prompted:
rem        - Target schema name
rem        - Optional CONFIG_JSON values
rem
rem   4. Verify installation:
rem        - Package compilation status is VALID
rem        - Jira tools exist in USER_AI_AGENT_TOOLS
rem        - SELECTAI_AGENT_CONFIG contains JIRA keys
rem
rem PARAMETERS
rem   SCHEMA_NAME (Required)
rem     Schema in which packages and tools are created.
rem
rem   CONFIG_JSON (Optional)
rem     JSON string used to persist Jira runtime config.
rem
rem     Example:
rem       {"credential_name":"ATLASSIAN_CRED","cloud_id":"<your-cloud-id>"}
rem
rem NOTES
rem   - Required config keys for AGENT='JIRA':
rem       * CREDENTIAL_NAME
rem       * CLOUD_ID
rem
rem   - Configuration can be updated after installation
rem     in the SELECTAI_AGENT_CONFIG table.
rem
rem ============================================================================

SET SERVEROUTPUT ON
SET VERIFY OFF

VAR v_schema VARCHAR2(128)
EXEC :v_schema := '&SCHEMA_NAME';

PROMPT
PROMPT Enter Jira agent configuration values in JSON format.
PROMPT Required keys: credential_name, cloud_id
PROMPT
PROMPT Example:
PROMPT {"credential_name":"ATLASSIAN_CRED","cloud_id":"my-jira-cloud-id"}
PROMPT
PROMPT Press ENTER to skip this step.
PROMPT If skipped, values can be inserted later in SELECTAI_AGENT_CONFIG.
PROMPT

VAR v_config VARCHAR2(4000)
EXEC :v_config := '&CONFIG_JSON';

CREATE OR REPLACE PROCEDURE initialize_jira_agent(
  p_install_schema_name IN VARCHAR2,
  p_config_json         IN CLOB
)
IS
  l_schema_name      VARCHAR2(128);
  l_credential_name  VARCHAR2(4000);
  l_cloud_id         VARCHAR2(4000);
  c_jira_agent CONSTANT VARCHAR2(64) := 'JIRA';

  TYPE priv_list_t IS VARRAY(20) OF VARCHAR2(4000);
  l_priv_list CONSTANT priv_list_t := priv_list_t(
    'DBMS_CLOUD',
    'DBMS_CLOUD_AI',
    'DBMS_CLOUD_AI_AGENT',
    'DBMS_CLOUD_TYPES'
  );

  PROCEDURE execute_grants(p_schema IN VARCHAR2, p_objects IN priv_list_t) IS
  BEGIN
    FOR i IN 1 .. p_objects.COUNT LOOP
      BEGIN
        EXECUTE IMMEDIATE 'GRANT EXECUTE ON ' || p_objects(i) || ' TO ' || p_schema;
      EXCEPTION
        WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('Warning: failed to grant ' || p_objects(i) ||
                               ' to ' || p_schema || ' - ' || SQLERRM);
      END;
    END LOOP;
  END execute_grants;

  PROCEDURE get_config(
    p_json           IN  CLOB,
    o_credential     OUT VARCHAR2,
    o_cloud_id       OUT VARCHAR2
  ) IS
    l_cfg JSON_OBJECT_T := NULL;
  BEGIN
    o_credential := NULL;
    o_cloud_id := NULL;

    IF p_json IS NOT NULL AND TRIM(p_json) IS NOT NULL THEN
      BEGIN
        l_cfg := JSON_OBJECT_T.parse(p_json);
        IF l_cfg.has('credential_name') THEN
          o_credential := l_cfg.get_string('credential_name');
        END IF;
        IF l_cfg.has('cloud_id') THEN
          o_cloud_id := l_cfg.get_string('cloud_id');
        END IF;
      EXCEPTION
        WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('Config JSON parse failed: ' || SQLERRM);
          o_credential := NULL;
          o_cloud_id := NULL;
      END;
    ELSE
      DBMS_OUTPUT.PUT_LINE('No config JSON provided, using existing table values.');
    END IF;
  END get_config;

  PROCEDURE merge_config_key(
    p_schema IN VARCHAR2,
    p_key    IN VARCHAR2,
    p_val    IN CLOB,
    p_agent  IN VARCHAR2
  ) IS
    l_sql CLOB;
  BEGIN
    l_sql :=
      'MERGE INTO ' || p_schema || '.SELECTAI_AGENT_CONFIG c
         USING (SELECT :k AS "KEY", :v AS "VALUE", :a AS "AGENT" FROM DUAL) src
           ON (c."KEY" = src."KEY" AND c."AGENT" = src."AGENT")
       WHEN MATCHED THEN
         UPDATE SET c."VALUE" = src."VALUE"
       WHEN NOT MATCHED THEN
         INSERT ("KEY", "VALUE", "AGENT") VALUES (src."KEY", src."VALUE", src."AGENT")';

    EXECUTE IMMEDIATE l_sql USING p_key, p_val, p_agent;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Warning: failed to persist ' || p_key || ' config: ' || SQLERRM);
  END merge_config_key;
BEGIN
  l_schema_name := DBMS_ASSERT.SIMPLE_SQL_NAME(p_install_schema_name);

  execute_grants(l_schema_name, l_priv_list);
  get_config(
    p_json       => p_config_json,
    o_credential => l_credential_name,
    o_cloud_id   => l_cloud_id
  );

  BEGIN
    EXECUTE IMMEDIATE
      'CREATE TABLE ' || l_schema_name || '.SELECTAI_AGENT_CONFIG (
         "ID"     NUMBER GENERATED BY DEFAULT AS IDENTITY,
         "KEY"    VARCHAR2(200) NOT NULL,
         "VALUE"  CLOB,
         "AGENT"  VARCHAR2(128) NOT NULL,
         CONSTRAINT SELECTAI_AGENT_CONFIG_PK PRIMARY KEY ("ID"),
         CONSTRAINT SELECTAI_AGENT_CONFIG_UK UNIQUE ("KEY","AGENT")
       )';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -955 THEN
        NULL;
      ELSE
        RAISE;
      END IF;
  END;

  IF l_credential_name IS NOT NULL THEN
    merge_config_key(l_schema_name, 'CREDENTIAL_NAME', l_credential_name, c_jira_agent);
  END IF;

  IF l_cloud_id IS NOT NULL THEN
    merge_config_key(l_schema_name, 'CLOUD_ID', l_cloud_id, c_jira_agent);
  END IF;

  DBMS_OUTPUT.PUT_LINE('initialize_jira_agent completed for schema ' || l_schema_name);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Fatal error in initialize_jira_agent: ' || SQLERRM);
    RAISE;
END initialize_jira_agent;
/

BEGIN
  initialize_jira_agent(
    p_install_schema_name => :v_schema,
    p_config_json         => :v_config
  );
END;
/

BEGIN
  EXECUTE IMMEDIATE 'ALTER SESSION SET CURRENT_SCHEMA = ' || :v_schema;
END;
/

CREATE OR REPLACE PACKAGE jira_selectai AS
  FUNCTION get_jira(
    cloud_id        VARCHAR2,
    credential_name VARCHAR2,
    jira            VARCHAR2
  ) RETURN CLOB;

  FUNCTION search_jiras(
    cloud_id        VARCHAR2,
    credential_name VARCHAR2,
    key             VARCHAR2
  ) RETURN CLOB;

  FUNCTION get_jira_assigned_issues(
    cloud_id             VARCHAR2,
    credential_name      VARCHAR2,
    assignee_account_id  VARCHAR2,
    max_results          NUMBER DEFAULT 50
  ) RETURN CLOB;

  FUNCTION get_assignee_account_id(
    cloud_id        VARCHAR2,
    credential_name VARCHAR2,
    assignee_query  VARCHAR2
  ) RETURN CLOB;

  FUNCTION get_jira_comments(
    cloud_id        VARCHAR2,
    credential_name VARCHAR2,
    jira            VARCHAR2,
    max_results     NUMBER DEFAULT 50
  ) RETURN CLOB;

  FUNCTION get_jira_changelog(
    cloud_id        VARCHAR2,
    credential_name VARCHAR2,
    jira            VARCHAR2,
    max_results     NUMBER DEFAULT 50
  ) RETURN CLOB;

  FUNCTION get_jira_worklog(
    cloud_id        VARCHAR2,
    credential_name VARCHAR2,
    jira            VARCHAR2,
    max_results     NUMBER DEFAULT 50
  ) RETURN CLOB;

  FUNCTION get_jira_project(
    cloud_id        VARCHAR2,
    credential_name VARCHAR2,
    project_key     VARCHAR2
  ) RETURN CLOB;

  FUNCTION get_atlassian_user(
    cloud_id        VARCHAR2,
    credential_name VARCHAR2,
    account_id      VARCHAR2
  ) RETURN CLOB;

  FUNCTION get_jira_boards(
    cloud_id        VARCHAR2,
    credential_name VARCHAR2,
    project_key     VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;
END jira_selectai;
/

CREATE OR REPLACE PACKAGE BODY jira_selectai AS
  FUNCTION jira_api_base_url(cloud_id VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN 'bearer://api.atlassian.com/ex/jira/' || cloud_id || '/rest/api/3';
  END jira_api_base_url;

  FUNCTION jira_agile_api_base_url(cloud_id VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN 'bearer://api.atlassian.com/ex/jira/' || cloud_id || '/rest/agile/1.0';
  END jira_agile_api_base_url;

  FUNCTION get_response(credential_name VARCHAR2, uri VARCHAR2) RETURN CLOB IS
    l_resp DBMS_CLOUD_TYPES.resp;
  BEGIN
    l_resp := DBMS_CLOUD.send_request(
      credential_name => credential_name,
      uri             => uri,
      method          => DBMS_CLOUD.METHOD_GET
    );
    RETURN DBMS_CLOUD.get_response_text(l_resp);
  END get_response;

  FUNCTION get_jira(
    cloud_id        VARCHAR2,
    credential_name VARCHAR2,
    jira            VARCHAR2
  ) RETURN CLOB IS
    l_url VARCHAR2(4000);
  BEGIN
    l_url := jira_api_base_url(cloud_id) || '/issue/' ||
             UTL_URL.escape(jira, TRUE) ||
             '?expand=renderedFields,names,schema';
    RETURN get_response(credential_name, l_url);
  END get_jira;

  FUNCTION search_jiras(
    cloud_id        VARCHAR2,
    credential_name VARCHAR2,
    key             VARCHAR2
  ) RETURN CLOB IS
    l_url            VARCHAR2(4000);
    l_jql            VARCHAR2(4000);
    l_sanitized_key  VARCHAR2(4000);
  BEGIN
    l_sanitized_key := REPLACE(key, '"', ' ');
    l_jql := 'text~"' || l_sanitized_key || '"';
    l_url := jira_api_base_url(cloud_id) ||
             '/search/jql?fields=key,summary,status,assignee,issuetype,project' ||
             chr(38) || 'jql=' || UTL_URL.escape(l_jql, TRUE);
    RETURN get_response(credential_name, l_url);
  END search_jiras;

  FUNCTION get_jira_assigned_issues(
    cloud_id             VARCHAR2,
    credential_name      VARCHAR2,
    assignee_account_id  VARCHAR2,
    max_results          NUMBER DEFAULT 50
  ) RETURN CLOB IS
    l_url                   VARCHAR2(4000);
    l_jql                   VARCHAR2(4000);
    l_sanitized_account_id  VARCHAR2(4000);
    l_limit                 NUMBER;
  BEGIN
    l_sanitized_account_id := REPLACE(assignee_account_id, '"', ' ');
    l_jql := 'assignee = "' || l_sanitized_account_id || '" ORDER BY updated DESC';
    l_limit := LEAST(NVL(max_results, 50), 1000);

    l_url := jira_api_base_url(cloud_id) ||
             '/search/jql?fields=key,summary,status,assignee,issuetype,project,updated' ||
             chr(38) || 'maxResults=' || l_limit ||
             chr(38) || 'jql=' || UTL_URL.escape(l_jql, TRUE);
    RETURN get_response(credential_name, l_url);
  END get_jira_assigned_issues;

  FUNCTION get_assignee_account_id(
    cloud_id        VARCHAR2,
    credential_name VARCHAR2,
    assignee_query  VARCHAR2
  ) RETURN CLOB IS
    l_url            VARCHAR2(4000);
    l_response       CLOB;
    l_users_arr      JSON_ARRAY_T;
    l_candidates     JSON_ARRAY_T := JSON_ARRAY_T();
    l_user_obj       JSON_OBJECT_T;
    l_candidate_obj  JSON_OBJECT_T;
    l_result_obj     JSON_OBJECT_T := JSON_OBJECT_T();
    l_error_obj      JSON_OBJECT_T := JSON_OBJECT_T();
    l_size           NUMBER;
  BEGIN
    l_url := jira_api_base_url(cloud_id) || '/user/search?maxResults=20' ||
             chr(38) || 'query=' || UTL_URL.escape(assignee_query, TRUE);

    l_response := get_response(credential_name, l_url);
    l_users_arr := JSON_ARRAY_T.parse(l_response);
    l_size := l_users_arr.get_size;

    l_result_obj.put('query', assignee_query);
    l_result_obj.put('match_count', l_size);

    IF l_size > 0 THEN
      l_user_obj := TREAT(l_users_arr.get(0) AS JSON_OBJECT_T);
      l_result_obj.put('account_id', l_user_obj.get_string('accountId'));
      l_result_obj.put('display_name', l_user_obj.get_string('displayName'));
    ELSE
      l_result_obj.put_null('account_id');
      l_result_obj.put_null('display_name');
    END IF;

    IF l_size > 0 THEN
      FOR i IN 0 .. LEAST(l_size, 10) - 1 LOOP
        l_user_obj := TREAT(l_users_arr.get(i) AS JSON_OBJECT_T);
        l_candidate_obj := JSON_OBJECT_T();
        l_candidate_obj.put('account_id', l_user_obj.get_string('accountId'));
        l_candidate_obj.put('display_name', l_user_obj.get_string('displayName'));
        l_candidates.append(l_candidate_obj);
      END LOOP;
    END IF;

    l_result_obj.put('candidates', l_candidates);
    RETURN l_result_obj.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_error_obj.put('status', 'error');
      l_error_obj.put('message', 'get_assignee_account_id failed: ' || SQLERRM);
      IF l_response IS NOT NULL THEN
        l_error_obj.put('raw_response', l_response);
      END IF;
      RETURN l_error_obj.to_clob();
  END get_assignee_account_id;

  FUNCTION get_jira_comments(
    cloud_id        VARCHAR2,
    credential_name VARCHAR2,
    jira            VARCHAR2,
    max_results     NUMBER DEFAULT 50
  ) RETURN CLOB IS
    l_url VARCHAR2(4000);
  BEGIN
    l_url := jira_api_base_url(cloud_id) || '/issue/' ||
             UTL_URL.escape(jira, TRUE) || '/comment?maxResults=' ||
             NVL(max_results, 50);
    RETURN get_response(credential_name, l_url);
  END get_jira_comments;

  FUNCTION get_jira_changelog(
    cloud_id        VARCHAR2,
    credential_name VARCHAR2,
    jira            VARCHAR2,
    max_results     NUMBER DEFAULT 50
  ) RETURN CLOB IS
    l_url VARCHAR2(4000);
  BEGIN
    l_url := jira_api_base_url(cloud_id) || '/issue/' ||
             UTL_URL.escape(jira, TRUE) || '/changelog?maxResults=' ||
             NVL(max_results, 50);
    RETURN get_response(credential_name, l_url);
  END get_jira_changelog;

  FUNCTION get_jira_worklog(
    cloud_id        VARCHAR2,
    credential_name VARCHAR2,
    jira            VARCHAR2,
    max_results     NUMBER DEFAULT 50
  ) RETURN CLOB IS
    l_url VARCHAR2(4000);
  BEGIN
    l_url := jira_api_base_url(cloud_id) || '/issue/' ||
             UTL_URL.escape(jira, TRUE) || '/worklog?maxResults=' ||
             NVL(max_results, 50);
    RETURN get_response(credential_name, l_url);
  END get_jira_worklog;

  FUNCTION get_jira_project(
    cloud_id        VARCHAR2,
    credential_name VARCHAR2,
    project_key     VARCHAR2
  ) RETURN CLOB IS
    l_url VARCHAR2(4000);
  BEGIN
    l_url := jira_api_base_url(cloud_id) || '/project/' ||
             UTL_URL.escape(project_key, TRUE);
    RETURN get_response(credential_name, l_url);
  END get_jira_project;

  FUNCTION get_atlassian_user(
    cloud_id        VARCHAR2,
    credential_name VARCHAR2,
    account_id      VARCHAR2
  ) RETURN CLOB IS
    l_url VARCHAR2(4000);
  BEGIN
    l_url := jira_api_base_url(cloud_id) || '/user?accountId=' ||
             UTL_URL.escape(account_id, TRUE);
    RETURN get_response(credential_name, l_url);
  END get_atlassian_user;

  FUNCTION get_jira_boards(
    cloud_id        VARCHAR2,
    credential_name VARCHAR2,
    project_key     VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_url VARCHAR2(4000);
  BEGIN
    l_url := jira_agile_api_base_url(cloud_id) || '/board';
    IF project_key IS NOT NULL THEN
      l_url := l_url || '?projectKeyOrId=' || UTL_URL.escape(project_key, TRUE);
    END IF;
    RETURN get_response(credential_name, l_url);
  END get_jira_boards;
END jira_selectai;
/

CREATE OR REPLACE PACKAGE select_ai_jira_agent AS
  FUNCTION search_jira(
    keyword IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION get_jira(
    jira_key IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION get_jira_assigned_issues(
    assignee_account_id IN VARCHAR2,
    max_results         IN NUMBER DEFAULT 50
  ) RETURN CLOB;

  FUNCTION get_assignee_account_id(
    assignee_query IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION get_jira_comments(
    jira_key    IN VARCHAR2,
    max_results IN NUMBER DEFAULT 50
  ) RETURN CLOB;

  FUNCTION get_jira_changelog(
    jira_key    IN VARCHAR2,
    max_results IN NUMBER DEFAULT 50
  ) RETURN CLOB;

  FUNCTION get_jira_worklog(
    jira_key    IN VARCHAR2,
    max_results IN NUMBER DEFAULT 50
  ) RETURN CLOB;

  FUNCTION get_jira_project(
    project_key IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION get_atlassian_user(
    account_id IN VARCHAR2
  ) RETURN CLOB;

  FUNCTION get_jira_boards(
    project_key IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION get_agent_config(
    schema_name IN VARCHAR2,
    table_name  IN VARCHAR2,
    agent_name  IN VARCHAR2
  ) RETURN CLOB;
END select_ai_jira_agent;
/

CREATE OR REPLACE PACKAGE BODY select_ai_jira_agent AS
  c_agent_name CONSTANT VARCHAR2(64) := 'JIRA';

  FUNCTION build_error_response(
    action_name IN VARCHAR2,
    message_txt IN VARCHAR2
  ) RETURN CLOB IS
    l_result_json JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    l_result_json.put('status', 'error');
    l_result_json.put('message', action_name || ' failed: ' || message_txt);
    RETURN l_result_json.to_clob();
  END build_error_response;

  FUNCTION get_agent_config(
    schema_name IN VARCHAR2,
    table_name  IN VARCHAR2,
    agent_name  IN VARCHAR2
  ) RETURN CLOB
  IS
    l_sql          VARCHAR2(4000);
    l_cursor       SYS_REFCURSOR;
    l_config_json  JSON_OBJECT_T := JSON_OBJECT_T();
    l_key          VARCHAR2(200);
    l_value        CLOB;
    l_result_json  JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    l_sql := 'SELECT "KEY", "VALUE" FROM ' || schema_name || '.' || table_name ||
             ' WHERE "AGENT" = :agent';

    OPEN l_cursor FOR l_sql USING agent_name;
    LOOP
      FETCH l_cursor INTO l_key, l_value;
      EXIT WHEN l_cursor%NOTFOUND;
      l_config_json.put(l_key, l_value);
    END LOOP;
    CLOSE l_cursor;

    l_result_json.put('status', 'success');
    l_result_json.put('config_params', l_config_json);
    RETURN l_result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      IF l_cursor%ISOPEN THEN
        CLOSE l_cursor;
      END IF;
      l_result_json := JSON_OBJECT_T();
      l_result_json.put('status', 'error');
      l_result_json.put('message', 'Error: ' || SQLERRM);
      RETURN l_result_json.to_clob();
  END get_agent_config;

  PROCEDURE get_runtime_config(
    o_credential_name OUT VARCHAR2,
    o_cloud_id        OUT VARCHAR2
  ) IS
    l_current_user  VARCHAR2(128) := SYS_CONTEXT('USERENV', 'CURRENT_USER');
    l_cfg_json      CLOB;
    l_cfg_obj       JSON_OBJECT_T;
    l_cfg_params    JSON_OBJECT_T;
  BEGIN
    l_cfg_json := get_agent_config(
      schema_name => l_current_user,
      table_name  => 'SELECTAI_AGENT_CONFIG',
      agent_name  => c_agent_name
    );

    l_cfg_obj := JSON_OBJECT_T.parse(l_cfg_json);

    IF NOT l_cfg_obj.has('status') OR l_cfg_obj.get_string('status') <> 'success' THEN
      RAISE_APPLICATION_ERROR(-20001, 'Unable to read SELECTAI_AGENT_CONFIG for agent JIRA');
    END IF;

    l_cfg_params := l_cfg_obj.get_object('config_params');
    o_credential_name := NULL;
    o_cloud_id := NULL;

    IF l_cfg_params IS NOT NULL AND l_cfg_params.has('CREDENTIAL_NAME') THEN
      o_credential_name := l_cfg_params.get_string('CREDENTIAL_NAME');
    END IF;

    IF l_cfg_params IS NOT NULL AND l_cfg_params.has('CLOUD_ID') THEN
      o_cloud_id := l_cfg_params.get_string('CLOUD_ID');
    END IF;

    IF o_credential_name IS NULL THEN
      RAISE_APPLICATION_ERROR(-20002, 'Missing CREDENTIAL_NAME for agent JIRA in SELECTAI_AGENT_CONFIG');
    END IF;

    IF o_cloud_id IS NULL THEN
      RAISE_APPLICATION_ERROR(-20003, 'Missing CLOUD_ID for agent JIRA in SELECTAI_AGENT_CONFIG');
    END IF;
  END get_runtime_config;

  FUNCTION search_jira(
    keyword IN VARCHAR2
  ) RETURN CLOB
  IS
    l_response         CLOB;
    l_credential_name  VARCHAR2(4000);
    l_cloud_id         VARCHAR2(4000);
  BEGIN
    get_runtime_config(l_credential_name, l_cloud_id);
    l_response := jira_selectai.search_jiras(
      credential_name => l_credential_name,
      cloud_id        => l_cloud_id,
      key             => keyword
    );
    RETURN l_response;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('search_jira', SQLERRM);
  END search_jira;

  FUNCTION get_jira(
    jira_key IN VARCHAR2
  ) RETURN CLOB
  IS
    l_response         CLOB;
    l_credential_name  VARCHAR2(4000);
    l_cloud_id         VARCHAR2(4000);
  BEGIN
    get_runtime_config(l_credential_name, l_cloud_id);
    l_response := jira_selectai.get_jira(
      credential_name => l_credential_name,
      cloud_id        => l_cloud_id,
      jira            => jira_key
    );
    RETURN l_response;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('get_jira', SQLERRM);
  END get_jira;

  FUNCTION get_jira_assigned_issues(
    assignee_account_id IN VARCHAR2,
    max_results         IN NUMBER DEFAULT 50
  ) RETURN CLOB
  IS
    l_response         CLOB;
    l_credential_name  VARCHAR2(4000);
    l_cloud_id         VARCHAR2(4000);
  BEGIN
    get_runtime_config(l_credential_name, l_cloud_id);
    l_response := jira_selectai.get_jira_assigned_issues(
      credential_name     => l_credential_name,
      cloud_id            => l_cloud_id,
      assignee_account_id => assignee_account_id,
      max_results         => max_results
    );
    RETURN l_response;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('get_jira_assigned_issues', SQLERRM);
  END get_jira_assigned_issues;

  FUNCTION get_assignee_account_id(
    assignee_query IN VARCHAR2
  ) RETURN CLOB
  IS
    l_response         CLOB;
    l_credential_name  VARCHAR2(4000);
    l_cloud_id         VARCHAR2(4000);
  BEGIN
    get_runtime_config(l_credential_name, l_cloud_id);
    l_response := jira_selectai.get_assignee_account_id(
      credential_name => l_credential_name,
      cloud_id        => l_cloud_id,
      assignee_query  => assignee_query
    );
    RETURN l_response;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('get_assignee_account_id', SQLERRM);
  END get_assignee_account_id;

  FUNCTION get_jira_comments(
    jira_key    IN VARCHAR2,
    max_results IN NUMBER DEFAULT 50
  ) RETURN CLOB
  IS
    l_response         CLOB;
    l_credential_name  VARCHAR2(4000);
    l_cloud_id         VARCHAR2(4000);
  BEGIN
    get_runtime_config(l_credential_name, l_cloud_id);
    l_response := jira_selectai.get_jira_comments(
      credential_name => l_credential_name,
      cloud_id        => l_cloud_id,
      jira            => jira_key,
      max_results     => max_results
    );
    RETURN l_response;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('get_jira_comments', SQLERRM);
  END get_jira_comments;

  FUNCTION get_jira_changelog(
    jira_key    IN VARCHAR2,
    max_results IN NUMBER DEFAULT 50
  ) RETURN CLOB
  IS
    l_response         CLOB;
    l_credential_name  VARCHAR2(4000);
    l_cloud_id         VARCHAR2(4000);
  BEGIN
    get_runtime_config(l_credential_name, l_cloud_id);
    l_response := jira_selectai.get_jira_changelog(
      credential_name => l_credential_name,
      cloud_id        => l_cloud_id,
      jira            => jira_key,
      max_results     => max_results
    );
    RETURN l_response;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('get_jira_changelog', SQLERRM);
  END get_jira_changelog;

  FUNCTION get_jira_worklog(
    jira_key    IN VARCHAR2,
    max_results IN NUMBER DEFAULT 50
  ) RETURN CLOB
  IS
    l_response         CLOB;
    l_credential_name  VARCHAR2(4000);
    l_cloud_id         VARCHAR2(4000);
  BEGIN
    get_runtime_config(l_credential_name, l_cloud_id);
    l_response := jira_selectai.get_jira_worklog(
      credential_name => l_credential_name,
      cloud_id        => l_cloud_id,
      jira            => jira_key,
      max_results     => max_results
    );
    RETURN l_response;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('get_jira_worklog', SQLERRM);
  END get_jira_worklog;

  FUNCTION get_jira_project(
    project_key IN VARCHAR2
  ) RETURN CLOB
  IS
    l_response         CLOB;
    l_credential_name  VARCHAR2(4000);
    l_cloud_id         VARCHAR2(4000);
  BEGIN
    get_runtime_config(l_credential_name, l_cloud_id);
    l_response := jira_selectai.get_jira_project(
      credential_name => l_credential_name,
      cloud_id        => l_cloud_id,
      project_key     => project_key
    );
    RETURN l_response;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('get_jira_project', SQLERRM);
  END get_jira_project;

  FUNCTION get_atlassian_user(
    account_id IN VARCHAR2
  ) RETURN CLOB
  IS
    l_response         CLOB;
    l_credential_name  VARCHAR2(4000);
    l_cloud_id         VARCHAR2(4000);
  BEGIN
    get_runtime_config(l_credential_name, l_cloud_id);
    l_response := jira_selectai.get_atlassian_user(
      credential_name => l_credential_name,
      cloud_id        => l_cloud_id,
      account_id      => account_id
    );
    RETURN l_response;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('get_atlassian_user', SQLERRM);
  END get_atlassian_user;

  FUNCTION get_jira_boards(
    project_key IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_response         CLOB;
    l_credential_name  VARCHAR2(4000);
    l_cloud_id         VARCHAR2(4000);
  BEGIN
    get_runtime_config(l_credential_name, l_cloud_id);
    l_response := jira_selectai.get_jira_boards(
      credential_name => l_credential_name,
      cloud_id        => l_cloud_id,
      project_key     => project_key
    );
    RETURN l_response;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('get_jira_boards', SQLERRM);
  END get_jira_boards;
END select_ai_jira_agent;
/

CREATE OR REPLACE PROCEDURE initialize_jira_tools
IS
  PROCEDURE drop_tool_if_exists(tool_name IN VARCHAR2) IS
    l_tool_count NUMBER;
    l_sql        CLOB;
  BEGIN
    l_sql := 'SELECT COUNT(*) FROM USER_AI_AGENT_TOOLS WHERE TOOL_NAME = :1';
    EXECUTE IMMEDIATE l_sql INTO l_tool_count USING tool_name;
    IF l_tool_count > 0 THEN
      DBMS_CLOUD_AI_AGENT.DROP_TOOL(tool_name);
    END IF;
  END drop_tool_if_exists;
BEGIN
  drop_tool_if_exists('SEARCH_JIRA_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'SEARCH_JIRA_TOOL',
    attributes => '{
      "instruction": "Search Jira issues by keyword.",
      "function": "select_ai_jira_agent.search_jira"
    }',
    description => 'Search Jira issues by keyword'
  );

  drop_tool_if_exists('GET_JIRA_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_JIRA_TOOL',
    attributes => '{
      "instruction": "Fetch Jira issue details by issue key.",
      "function": "select_ai_jira_agent.get_jira"
    }',
    description => 'Get Jira issue details'
  );

  drop_tool_if_exists('GET_ASSIGNEE_ACCOUNT_ID_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_ASSIGNEE_ACCOUNT_ID_TOOL',
    attributes => '{
      "instruction": "Resolve Jira assignee account id by email, name, or search text.",
      "function": "select_ai_jira_agent.get_assignee_account_id"
    }',
    description => 'Resolve Jira assignee account id'
  );

  drop_tool_if_exists('GET_JIRA_ASSIGNED_ISSUES_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_JIRA_ASSIGNED_ISSUES_TOOL',
    attributes => '{
      "instruction": "Fetch Jira issues assigned to a given assignee account id.",
      "function": "select_ai_jira_agent.get_jira_assigned_issues"
    }',
    description => 'Get Jira issues assigned to an account'
  );

  drop_tool_if_exists('GET_JIRA_COMMENTS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_JIRA_COMMENTS_TOOL',
    attributes => '{
      "instruction": "Fetch Jira issue comments by issue key.",
      "function": "select_ai_jira_agent.get_jira_comments"
    }',
    description => 'Get Jira issue comments'
  );

  drop_tool_if_exists('GET_JIRA_CHANGELOG_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_JIRA_CHANGELOG_TOOL',
    attributes => '{
      "instruction": "Fetch Jira issue changelog history by issue key.",
      "function": "select_ai_jira_agent.get_jira_changelog"
    }',
    description => 'Get Jira issue changelog'
  );

  drop_tool_if_exists('GET_JIRA_WORKLOG_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_JIRA_WORKLOG_TOOL',
    attributes => '{
      "instruction": "Fetch Jira issue worklog entries by issue key.",
      "function": "select_ai_jira_agent.get_jira_worklog"
    }',
    description => 'Get Jira issue worklogs'
  );

  drop_tool_if_exists('GET_JIRA_PROJECT_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_JIRA_PROJECT_TOOL',
    attributes => '{
      "instruction": "Fetch Jira project details by project key.",
      "function": "select_ai_jira_agent.get_jira_project"
    }',
    description => 'Get Jira project metadata'
  );

  drop_tool_if_exists('GET_ATLASSIAN_USER_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_ATLASSIAN_USER_TOOL',
    attributes => '{
      "instruction": "Fetch Atlassian user details by account id.",
      "function": "select_ai_jira_agent.get_atlassian_user"
    }',
    description => 'Get Atlassian user profile'
  );

  drop_tool_if_exists('GET_JIRA_BOARDS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_JIRA_BOARDS_TOOL',
    attributes => '{
      "instruction": "Fetch Jira boards. Optionally filter by project key.",
      "function": "select_ai_jira_agent.get_jira_boards"
    }',
    description => 'Get Jira boards'
  );

  DBMS_OUTPUT.PUT_LINE('initialize_jira_tools completed.');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error in initialize_jira_tools: ' || SQLERRM);
    RAISE;
END initialize_jira_tools;
/

BEGIN
  initialize_jira_tools;
END;
/

ALTER SESSION SET CURRENT_SCHEMA = ADMIN;
