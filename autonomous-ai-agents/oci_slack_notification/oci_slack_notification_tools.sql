-- Copyright (c) 2025 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/
--
-- Installer script for OCI Slack Notification AI tools (Select AI Agent / Oracle AI Database)
--
-- Purpose:
--   Install a consolidated PL/SQL package and AI Agent tool registration
--   to send Slack messages via DBMS_CLOUD_NOTIFICATION.SEND_MESSAGE.
--
-- Script Structure
--   1) Initialization: grants, configuration setup.
--   2) Package deployment: &&INSTALL_SCHEMA.oci_slack_notification_agents (spec and body).
--   3) AI tool setup: creation of Slack notification agent tools.
--
-- Usage:
--   sqlplus admin@db @oci_slack_notification_tools.sql <INSTALL_SCHEMA> [CONFIG_JSON]
--
-- Notes:
--   - Optional CONFIG_JSON keys:
--       * use_resource_principal (boolean)
--       * credential_name (string)   -- OCI Notification credential configured for provider=slack
--   - You may also update config in OCI_AGENT_CONFIG after install.
--

SET SERVEROUTPUT ON
SET VERIFY OFF

-- First argument: Schema Name (Required)
ACCEPT SCHEMA_NAME CHAR PROMPT 'Enter schema name: '
DEFINE INSTALL_SCHEMA = '&SCHEMA_NAME'

-- Second argument: JSON config (optional)
-- DEFINE INSTALL_CONFIG_JSON = q'({"credential_name": "MY_SLACK_CRED"})'
DEFINE INSTALL_CONFIG_JSON = NULL

-------------------------------------------------------------------------------
-- Initializes the OCI Slack Notification AI Agent.
-------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE initilize_slack_notification_agent(
  p_install_schema_name IN VARCHAR2,
  p_config_json         IN CLOB
)
IS
  l_use_rp              BOOLEAN := NULL;
  l_credential_name     VARCHAR2(4000) := NULL;
  l_schema_name         VARCHAR2(128);
  c_slack_agent CONSTANT VARCHAR2(64) := 'OCI_SLACK_NOTIFICATION';

  TYPE priv_list_t IS VARRAY(50) OF VARCHAR2(4000);
  l_priv_list CONSTANT priv_list_t := priv_list_t(
    'DBMS_CLOUD',
    'DBMS_CLOUD_ADMIN',
    'DBMS_CLOUD_AI_AGENT',
    'DBMS_CLOUD_NOTIFICATION'
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
    p_config_json       IN  CLOB,
    o_use_rp            OUT BOOLEAN,
    o_credential_name   OUT VARCHAR2
  ) IS
    l_cfg JSON_OBJECT_T := NULL;
  BEGIN
    o_use_rp := NULL;
    o_credential_name := NULL;

    IF p_config_json IS NOT NULL AND TRIM(p_config_json) IS NOT NULL THEN
      BEGIN
        l_cfg := JSON_OBJECT_T.parse(p_config_json);
        IF l_cfg.has('use_resource_principal') THEN
          o_use_rp := l_cfg.get_boolean('use_resource_principal');
        END IF;
        IF l_cfg.has('credential_name') THEN
          o_credential_name := l_cfg.get_string('credential_name');
        END IF;
      EXCEPTION
        WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('Config JSON parse failed: ' || SQLERRM);
          o_use_rp := NULL;
          o_credential_name := NULL;
      END;
    ELSE
      DBMS_OUTPUT.PUT_LINE('No config JSON provided, using defaults.');
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
      'MERGE INTO ' || p_schema || '.OCI_AGENT_CONFIG c
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

  PROCEDURE apply_config(
    p_schema          IN VARCHAR2,
    p_use_rp          IN BOOLEAN,
    p_credential_name IN VARCHAR2
  ) IS
    l_effective_use_rp BOOLEAN;
    l_enable_rp_str    VARCHAR2(3);
  BEGIN
    l_effective_use_rp := CASE WHEN p_use_rp IS NULL THEN TRUE ELSE p_use_rp END;

    IF p_credential_name IS NOT NULL THEN
      merge_config_key(p_schema, 'CREDENTIAL_NAME', p_credential_name, c_slack_agent);
    END IF;

    l_enable_rp_str := CASE WHEN l_effective_use_rp THEN 'YES' ELSE 'NO' END;
    merge_config_key(p_schema, 'ENABLE_RESOURCE_PRINCIPAL', l_enable_rp_str, c_slack_agent);

    IF l_effective_use_rp THEN
      BEGIN
        DBMS_CLOUD_ADMIN.ENABLE_RESOURCE_PRINCIPAL(USERNAME => p_schema);
        DBMS_OUTPUT.PUT_LINE('Resource principal enabled for ' || p_schema);
      EXCEPTION
        WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('Failed to enable resource principal for ' || p_schema || ' - ' || SQLERRM);
      END;
    END IF;
  END apply_config;

BEGIN
  l_schema_name := DBMS_ASSERT.SIMPLE_SQL_NAME(p_install_schema_name);

  execute_grants(l_schema_name, l_priv_list);
  get_config(
    p_config_json     => p_config_json,
    o_use_rp          => l_use_rp,
    o_credential_name => l_credential_name
  );

  BEGIN
    EXECUTE IMMEDIATE
      'CREATE TABLE ' || l_schema_name || '.OCI_AGENT_CONFIG (
         "ID"     NUMBER GENERATED BY DEFAULT AS IDENTITY,
         "KEY"    VARCHAR2(200) NOT NULL,
         "VALUE"  CLOB,
         "AGENT"  VARCHAR2(128) NOT NULL,
         CONSTRAINT OCI_AGENT_CONFIG_PK PRIMARY KEY ("ID"),
         CONSTRAINT OCI_AGENT_CONFIG_UK UNIQUE ("KEY","AGENT")
       )';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -955 THEN
        NULL;
      ELSE
        RAISE;
      END IF;
  END;

  apply_config(
    p_schema          => l_schema_name,
    p_use_rp          => l_use_rp,
    p_credential_name => l_credential_name
  );

  DBMS_OUTPUT.PUT_LINE('initilize_slack_notification_agent completed for schema ' || l_schema_name);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Fatal error in initilize_slack_notification_agent: ' || SQLERRM);
    RAISE;
END initilize_slack_notification_agent;
/

-------------------------------------------------------------------------------
-- Run initialization
-------------------------------------------------------------------------------
BEGIN
  initilize_slack_notification_agent(
    p_install_schema_name => '&&INSTALL_SCHEMA',
    p_config_json         => &&INSTALL_CONFIG_JSON
  );
END;
/

alter session set current_schema = &&INSTALL_SCHEMA;

------------------------------------------------------------------------
-- Package specification
------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE oci_slack_notification_agents
AS
  FUNCTION send_slack_message(
    credential_name IN VARCHAR2 DEFAULT NULL,
    message         IN CLOB,
    params          IN CLOB DEFAULT NULL
  ) RETURN CLOB;
END oci_slack_notification_agents;
/

------------------------------------------------------------------------
-- Package body
------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY oci_slack_notification_agents
AS
  c_slack_agent CONSTANT VARCHAR2(64) := 'OCI_SLACK_NOTIFICATION';

  FUNCTION get_agent_config(
    schema_name   IN VARCHAR2,
    table_name    IN VARCHAR2,
    agent_name    IN VARCHAR2
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
      BEGIN
        IF l_cursor%ISOPEN THEN
          CLOSE l_cursor;
        END IF;
      EXCEPTION
        WHEN OTHERS THEN NULL;
      END;
      l_result_json := JSON_OBJECT_T();
      l_result_json.put('status', 'error');
      l_result_json.put('message', 'Error: ' || SQLERRM);
      RETURN l_result_json.to_clob();
  END get_agent_config;

  PROCEDURE resolve_credential(
    p_credential_name IN  VARCHAR2,
    o_credential_name OUT VARCHAR2
  ) IS
    l_current_user VARCHAR2(128) := SYS_CONTEXT('USERENV', 'CURRENT_USER');
    l_cfg_json     CLOB;
    l_cfg          JSON_OBJECT_T;
    l_params       JSON_OBJECT_T;
  BEGIN
    o_credential_name := p_credential_name;
    IF o_credential_name IS NOT NULL THEN
      RETURN;
    END IF;

    l_cfg_json := get_agent_config(l_current_user, 'OCI_AGENT_CONFIG', c_slack_agent);
    l_cfg := JSON_OBJECT_T.parse(l_cfg_json);
    IF l_cfg.get_string('status') = 'success' THEN
      l_params := l_cfg.get_object('config_params');
      IF l_params.has('CREDENTIAL_NAME') THEN
        o_credential_name := l_params.get_string('CREDENTIAL_NAME');
      END IF;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      o_credential_name := p_credential_name;
  END resolve_credential;

  FUNCTION send_slack_message(
    credential_name IN VARCHAR2 DEFAULT NULL,
    message         IN CLOB,
    params          IN CLOB DEFAULT NULL
  ) RETURN CLOB
  IS
    l_result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    l_credential     VARCHAR2(256);
  BEGIN
    resolve_credential(credential_name, l_credential);
    IF l_credential IS NULL THEN
      l_result_json.put('status','error');
      l_result_json.put('message','Missing Slack credential_name (set OCI_AGENT_CONFIG.CREDENTIAL_NAME for OCI_SLACK_NOTIFICATION or pass explicitly).');
      RETURN l_result_json.to_clob();
    END IF;

    DBMS_CLOUD_NOTIFICATION.SEND_MESSAGE(
      provider        => 'slack',
      credential_name => l_credential,
      message         => message,
      params          => params
    );

    l_result_json.put('status', 'success');
    l_result_json.put('message', 'Slack message sent.');
    RETURN l_result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      l_result_json := JSON_OBJECT_T();
      l_result_json.put('status', 'error');
      l_result_json.put('message', 'Error: ' || SQLERRM);
      RETURN l_result_json.to_clob();
  END send_slack_message;

END oci_slack_notification_agents;
/

-------------------------------------------------------------------------------
-- This procedure installs or refreshes the OCI Slack Notification AI Agent tools.
-------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE initilize_slack_notification_tools
IS
  PROCEDURE drop_tool_if_exists (tool_name IN VARCHAR2) IS
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
  drop_tool_if_exists(tool_name => 'SEND_SLACK_MESSAGE_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'SEND_SLACK_MESSAGE_TOOL',
    attributes => '{
      "instruction": "Send a message to Slack using DBMS_CLOUD_NOTIFICATION.SEND_MESSAGE(provider=slack). Collect required inputs (credential_name and message). Optional params may include channel, blocks, attachments, etc. Confirm before sending.",
      "function": "oci_slack_notification_agents.send_slack_message"
    }',
    description => 'Sends a Slack message using an OCI notification credential configured for Slack.'
  );

  DBMS_OUTPUT.PUT_LINE('initilize_slack_notification_tools completed.');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error in initilize_slack_notification_tools: ' || SQLERRM);
    RAISE;
END initilize_slack_notification_tools;
/

BEGIN
  initilize_slack_notification_tools;
END;
/

alter session set current_schema = ADMIN;
