rem ============================================================================
rem LICENSE
rem   Copyright (c) 2026 Oracle and/or its affiliates.
rem   Licensed under the Universal Permissive License (UPL), Version 1.0
rem   https://oss.oracle.com/licenses/upl/
rem
rem NAME
rem   database_inspect_tool.sql
rem
rem DESCRIPTION
rem   Installer script for DATABASE_INSPECT package and tool framework.
rem   (Select AI Agent / Oracle AI Database)
rem
rem   This script:
rem     - Grants required privileges to the target schema
rem     - Switches session to the target schema
rem     - Compiles DATABASE_INSPECT package specification and body inline
rem     - Executes package setup via package body initialization block
rem
rem PARAMETERS
rem   SCHEMA_NAME (Required)
rem     Schema where DATABASE_INSPECT package and internal objects are created.
rem
rem INSTALL INSTRUCTIONS
rem   1. Connect as ADMIN or a user with required privileges.
rem   2. Run this script using SQL*Plus/SQLcl/SQL Developer.
rem   3. Provide SCHEMA_NAME when prompted.
rem
rem NOTES
rem   - This script follows the NL2SQL installer pattern and is safe to re-run.
rem   - Agent/team/task creation is handled by database_inspect_agent.sql.
rem   - Package spec/body SQL is embedded directly in this script.
rem ============================================================================

SET SERVEROUTPUT ON
SET VERIFY OFF

PROMPT ======================================================
PROMPT DATABASE_INSPECT Tools Installer
PROMPT ======================================================

-- Target schema
VAR v_schema VARCHAR2(128)
EXEC :v_schema := '&SCHEMA_NAME';


CREATE OR REPLACE PROCEDURE initialize_database_inspect_tools(
  p_install_schema_name IN VARCHAR2
)
IS
  l_schema_name VARCHAR2(128);

  TYPE priv_list_t IS VARRAY(50) OF VARCHAR2(4000);
  l_priv_list CONSTANT priv_list_t := priv_list_t(
    'DBMS_CLOUD',
    'DBMS_CLOUD_AI',
    'DBMS_CLOUD_AI_AGENT',
    'DBMS_CLOUD_REPO',
    'DBMS_VECTOR_CHAIN',
    'CTXSYS.CTX_DDL'
  );

  PROCEDURE execute_grants(
    p_schema  IN VARCHAR2,
    p_objects IN priv_list_t
  )
  IS
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

BEGIN
  l_schema_name := DBMS_ASSERT.SIMPLE_SQL_NAME(p_install_schema_name);
  execute_grants(l_schema_name, l_priv_list);

  DBMS_OUTPUT.PUT_LINE('initialize_database_inspect_tools completed for schema ' ||
                       l_schema_name);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Fatal error in initialize_database_inspect_tools: ' ||
                         SQLERRM);
    RAISE;
END initialize_database_inspect_tools;
/


BEGIN
  initialize_database_inspect_tools(
    p_install_schema_name => :v_schema
  );
END;
/


BEGIN
  EXECUTE IMMEDIATE
    'ALTER SESSION SET CURRENT_SCHEMA = ' || :v_schema;
END;
/

-------------------------------------------------------------------------------
-- Drop existing package to avoid stale spec/body signature mismatch.
-------------------------------------------------------------------------------
BEGIN
  EXECUTE IMMEDIATE 'DROP PACKAGE DATABASE_INSPECT';
  DBMS_OUTPUT.PUT_LINE('Dropped existing package DATABASE_INSPECT.');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -4043 THEN
      DBMS_OUTPUT.PUT_LINE('Package DATABASE_INSPECT does not exist, continuing.');
    ELSE
      RAISE;
    END IF;
END;
/

PROMPT Compiling DATABASE_INSPECT package specification in target schema...

--------------------------------------------------------------------------------------------------------------------------------
----------------------------                               PACKAGE SPEC                             ----------------------------
--------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE database_inspect AUTHID CURRENT_USER AS
  DATABASE_INSPECT_PACKAGE  CONSTANT DBMS_ID := 'DATABASE_INSPECT';

  -- Object types
  OBJECT_TABLE          CONSTANT DBMS_ID := 'TABLE';
  OBJECT_SCHEMA         CONSTANT DBMS_ID := 'SCHEMA';
  OBJECT_PACKAGE        CONSTANT DBMS_ID := 'PACKAGE';
  OBJECT_PACKAGE_BODY   CONSTANT DBMS_ID := 'PACKAGE BODY';
  OBJECT_PROCEDURE      CONSTANT DBMS_ID := 'PROCEDURE';
  OBJECT_FUNCTION       CONSTANT DBMS_ID := 'FUNCTION';
  OBJECT_TRIGGER        CONSTANT DBMS_ID := 'TRIGGER';
  OBJECT_VIEW           CONSTANT DBMS_ID := 'VIEW';
  OBJECT_TYPE           CONSTANT DBMS_ID := 'TYPE';

  -- Reserved name for internal tables
  INSPECT_AGENT_TEAMS             CONSTANT DBMS_ID := 'DATABASE_INSPECT_AGENT_TEAMS$';
  INSPECT_AGENT_TEAM_ATTRIBUTES   CONSTANT DBMS_ID := 'DATABASE_INSPECT_AGENT_TEAM_ATTRIBUTES$';
  INSPECT_OBJECTS                 CONSTANT DBMS_ID := 'DATABASE_INSPECT_OBJECTS$';

  -- Prefix for agent objects
  INSPECT_AGENT_PREFIX            CONSTANT DBMS_ID := 'INSPECT_AGENT';
  INSPECT_AGENT_TASK_PREFIX       CONSTANT DBMS_ID := 'INSPECT_TASK';

  -- Prefix for vector table or index
  VECTOR_TABLE_PREFIX             CONSTANT DBMS_ID := 'INSPECT_AGENT_VECTOR$';
  VECTOR_INDEX_PREFIX             CONSTANT DBMS_ID := 'INSPECT_AGENT_VECTOR_INDEX$';
  ORACLE_TEXT_INDEX_PREFIX        CONSTANT DBMS_ID := 'INSPECT_AGENT_ORACLE_TEXT_INDEX$';

  -- Agent tools
  TOOL_LIST_OBJECTS                     CONSTANT DBMS_ID := 'list_objects';
  TOOL_LIST_INCOMING_DEPENDENCIES       CONSTANT DBMS_ID := 'list_incoming_dependencies';
  TOOL_LIST_OUTGOING_DEPENDENCIES       CONSTANT DBMS_ID := 'list_outgoing_dependencies';
  TOOL_RETRIEVE_OBJECT_METADATA         CONSTANT DBMS_ID := 'retrieve_object_metadata';
  TOOL_RETRIEVE_OBJECT_METADATA_CHUNKS  CONSTANT DBMS_ID := 'retrieve_object_metadata_chunks';
  TOOL_EXPAND_OBJECT_METADATA_CHUNK     CONSTANT DBMS_ID := 'expand_object_metadata_chunk';
  TOOL_SUMMARIZE_OBJECT                 CONSTANT DBMS_ID := 'summarize_object';
  TOOL_GENERATE_PLDOC                   CONSTANT DBMS_ID := 'generate_pldoc';

  -- Vector distance types
  VEC_DIST_COSINE        CONSTANT DBMS_ID     := 'cosine';
  VEC_DIST_DOT           CONSTANT DBMS_ID     := 'dot';
  VEC_DIST_MANHATTAN     CONSTANT DBMS_ID     := 'manhattan';
  VEC_DIST_HAMMING       CONSTANT DBMS_ID     := 'hamming';
  VEC_DIST_EUCLIDEAN     CONSTANT DBMS_ID     := 'euclidean';
  VEC_DIST_L2_SQUARED    CONSTANT DBMS_ID     := 'l2_squared';

  -- Chunk sizes
  DEFAULT_CHUNK_SIZE              CONSTANT PLS_INTEGER := 1024;
  DEFAULT_CHUNK_SIZE_OCI          CONSTANT PLS_INTEGER := 512;

  -- Supported AI providers
  PROVIDER_OPENAI        CONSTANT DBMS_ID     := 'openai';
  PROVIDER_COHERE        CONSTANT DBMS_ID     := 'cohere';
  PROVIDER_AZURE         CONSTANT DBMS_ID     := 'azure';
  PROVIDER_OCI           CONSTANT DBMS_ID     := 'oci';
  PROVIDER_AWS           CONSTANT DBMS_ID     := 'aws';
  PROVIDER_GOOGLE        CONSTANT DBMS_ID     := 'google';
  PROVIDER_DATABASE      CONSTANT DBMS_ID     := 'database';

  TYPE inspect_object IS RECORD(object_name    DBMS_ID,
                                object_type    DBMS_ID,
                                object_owner   DBMS_ID);

  TYPE inspect_object_t IS TABLE OF inspect_object;


  -----------------------------------------------------------------------------
  -- list_objects: returns a list of set database objects for the agent team. 
  -- The result set can be optionally filtered by object name, object type, 
  -- and/or object owner to narrow the scope of returned objects.
  -- Tool name will contain the id for the agent team.
  -----------------------------------------------------------------------------
  FUNCTION list_objects(
    tool_name         IN VARCHAR2,
    object_name       IN VARCHAR2 DEFAULT NULL,
    object_type       IN VARCHAR2 DEFAULT NULL,
    object_owner      IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;


  -----------------------------------------------------------------------------
  -- list_incoming_dependencies: list objects that DEPEND ON or REFERENCE the 
  -- target object.
  -- Tool name will contain the id for the agent team.
  -----------------------------------------------------------------------------
  FUNCTION list_incoming_dependencies(
    tool_name       IN VARCHAR2,
    object_name     IN VARCHAR2,
    object_type     IN VARCHAR2 DEFAULT NULL,
    object_owner    IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;


  -----------------------------------------------------------------------------
  -- list_outgoing_dependencies: list objects that the target object ITSELF 
  -- DEPENDS ON or REFERENCES.
  -- Tool name will contain the id for the agent team.
  -----------------------------------------------------------------------------
  FUNCTION list_outgoing_dependencies(
    tool_name       IN VARCHAR2,
    object_name     IN VARCHAR2,
    object_type     IN VARCHAR2 DEFAULT NULL,
    object_owner    IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;


  -----------------------------------------------------------------------------
  -- retrieve_object_metadata: Retrieve the metadata for given object
  -----------------------------------------------------------------------------
  FUNCTION retrieve_object_metadata(
    object_name            IN VARCHAR2,
    object_type            IN VARCHAR2,
    object_owner           IN VARCHAR2
  ) RETURN CLOB;


  -----------------------------------------------------------------------------
  -- retrieve_object_metadata_chunks: Get list of search results from the 
  -- vector table using either vector search or hybrid search (vector search + 
  -- text search).
  -- Tool name will contain the id for the agent team.
  -----------------------------------------------------------------------------
  FUNCTION retrieve_object_metadata_chunks(
    tool_name           IN VARCHAR2,
    user_prompt         IN CLOB,
    keyword             IN CLOB DEFAULT NULL,
    object_list         IN CLOB DEFAULT NULL
  ) RETURN CLOB;


  -----------------------------------------------------------------------------
  -- expand_object_metadata_chunk: Returns a concatenated CLOB of 
  -- vectorized code snippets surrounding a specified content index for a given
  -- object.
  --
  -- The function retrieves snippets whose content_index falls within
  -- ± search_range of the provided content_index, ordered by content_index
  -- to preserve the original code sequence.
  -- Tool name will contain the id for the agent team.
  -----------------------------------------------------------------------------
  FUNCTION expand_object_metadata_chunk(
    tool_name              IN VARCHAR2,
    object_name            IN VARCHAR2,
    object_type            IN VARCHAR2,
    object_owner           IN VARCHAR2,
    content_index          IN NUMBER,
    search_range           IN NUMBER DEFAULT 5
  ) RETURN CLOB;


  -----------------------------------------------------------------------------
  -- summarize_object: Summarizes a single object. Summarizing schema is not 
  -- supported
  -- Tool name will contain the id for the agent team.
  -----------------------------------------------------------------------------
  FUNCTION summarize_object(
    tool_name         IN VARCHAR2,
    object_name       IN VARCHAR2,
    object_type       IN VARCHAR2,
    object_owner      IN VARCHAR2,
    user_prompt       IN CLOB     DEFAULT NULL
  ) RETURN CLOB;


  -----------------------------------------------------------------------------
  -- generate_pldoc: Generates a PLDoc/JavaDoc-style comment block (/** ... */)
  -- for a given object. Generating doc for schema object is not supported.
  -- Tool name will contain the id for the agent team.
  -----------------------------------------------------------------------------
  FUNCTION generate_pldoc(
    tool_name         IN VARCHAR2,
    object_name       IN VARCHAR2,
    object_type       IN VARCHAR2,
    object_owner      IN VARCHAR2,
    user_prompt       IN CLOB DEFAULT NULL
  ) RETURN CLOB;


  -----------------------------------------------------------------------------
  -- setup: create basic internal tables
  -----------------------------------------------------------------------------
  PROCEDURE setup;


  -----------------------------------------------------------------------------
  -- cleanup: cleanup all agents, attributes, internal tables and indexes
  -----------------------------------------------------------------------------
  PROCEDURE cleanup;


  -----------------------------------------------------------------------------
  -- create_inspect_agent_team: create an agent team with given attributes
  -----------------------------------------------------------------------------
  PROCEDURE create_inspect_agent_team(
    agent_team_name   IN VARCHAR2,
    attributes        IN CLOB
  );


  -----------------------------------------------------------------------------
  -- update_inspect_agent_team: update an existing agent team with given 
  -- attributes
  -----------------------------------------------------------------------------
  PROCEDURE update_inspect_agent_team(
    agent_team_name   IN VARCHAR2,
    attributes        IN CLOB
  );


  -----------------------------------------------------------------------------
  -- drop_inspect_agent_team: drop an existing agent team and all related 
  -- information
  -----------------------------------------------------------------------------
  PROCEDURE drop_inspect_agent_team(
    agent_team_name   IN VARCHAR2,
    force             IN BOOLEAN DEFAULT FALSE
  );

END;
/

show errors package database_inspect;

PROMPT Compiling DATABASE_INSPECT package body in target schema...

--------------------------------------------------------------------------------------------------------------------------------
----------------------------                               PACKAGE BODY                             ----------------------------
--------------------------------------------------------------------------------------------------------------------------------
SET SERVEROUTPUT ON;
CREATE OR REPLACE PACKAGE BODY database_inspect AS
  VECTOR_EMBEDDING_BATCH_SIZE   CONSTANT PLS_INTEGER := 96;


  ------------------------------------------------------------------------------------------------------------------
  ------------------------------------------------------------------------------------------------------------------
  ----------------------------                Private Helper Functions                  ----------------------------
  ------------------------------------------------------------------------------------------------------------------
  ------------------------------------------------------------------------------------------------------------------


  -----------------------------------------------------------------------------
  -- validate_object_name: helper function to validate the object name
  -----------------------------------------------------------------------------
  FUNCTION validate_object_name(
    obj_name            IN VARCHAR2
  ) RETURN VARCHAR2
  IS
    l_obj_name          DBMS_ID;
  BEGIN
    IF obj_name IS NULL THEN
      RETURN NULL;
    END IF;
 
    DBMS_UTILITY.canonicalize(
      DBMS_ASSERT.simple_sql_name(obj_name), l_obj_name, LENGTHB(obj_name));
    RETURN l_obj_name;
  END validate_object_name;


  -----------------------------------------------------------------------------
  -- validate_tool_output_length: a temporary helper function to prevent tool 
  -- output from becoming too long and causing agent errors. Ideally, this 
  -- error should be raised by the LLM; this is currently an agent-side bug 
  -- that has not yet been fixed in production.
  -----------------------------------------------------------------------------
  FUNCTION validate_tool_output_length(
    tool_output         IN  CLOB
  ) RETURN BOOLEAN
  IS
  BEGIN
    RETURN LENGTH(tool_output) <= 200000;
  END validate_tool_output_length;


  -----------------------------------------------------------------------------
  -- get_attribute: helper function to get an attribute value for the given 
  -- attribute name and agent team
  -----------------------------------------------------------------------------
  FUNCTION get_attribute(
    agent_team_name   IN VARCHAR2,
    attribute_name    IN VARCHAR2
  ) RETURN CLOB
  IS
    l_attribute_value CLOB;
  BEGIN
    EXECUTE IMMEDIATE
        'SELECT attribute_value FROM ' || INSPECT_AGENT_TEAM_ATTRIBUTES ||
        ' WHERE agent_team_name = :1 AND attribute_name = :2'
        INTO l_attribute_value
        USING agent_team_name, attribute_name;

    RETURN l_attribute_value;
  EXCEPTION
    WHEN no_data_found THEN
      RETURN NULL;
  END get_attribute;


  -----------------------------------------------------------------------------
  -- get_attributes: helper function to get all attributes for the given agent 
  -- team as a JSON
  -----------------------------------------------------------------------------
  FUNCTION get_attributes(
    agent_team_name   IN VARCHAR2
  ) RETURN JSON_OBJECT_T
  IS
    l_stmt            VARCHAR2(4000);
    l_attributes      JSON_OBJECT_T := JSON_OBJECT_T('{}');
    l_attribute_name  DBMS_ID;
    l_attribute_value CLOB;
    l_cursor          SYS_REFCURSOR;
  BEGIN
    l_stmt := 'SELECT attribute_name, attribute_value FROM ' || 
              INSPECT_AGENT_TEAM_ATTRIBUTES ||
              ' WHERE agent_team_name = :1';
    
    OPEN l_cursor FOR l_stmt USING agent_team_name;
    LOOP
      FETCH l_cursor INTO l_attribute_name, l_attribute_value;
      EXIT WHEN l_cursor%NOTFOUND;

      l_attributes.put(l_attribute_name, l_attribute_value);
    END LOOP;
    
    RETURN l_attributes;
  END get_attributes;


  -----------------------------------------------------------------------------
  -- set_attribute: helper function to set an attribute value for the given 
  -- attribute_name and agent team
  -----------------------------------------------------------------------------
  PROCEDURE set_attribute(
    agent_team_name   IN VARCHAR2,
    attribute_name    IN VARCHAR2,
    attribute_value   IN CLOB
  )
  IS
    l_count           NUMBER;
  BEGIN
    -- Check if attribute exists
    EXECUTE IMMEDIATE
        'SELECT COUNT(*) FROM ' || INSPECT_AGENT_TEAM_ATTRIBUTES ||
        ' WHERE agent_team_name = :1 AND attribute_name = :2'
        INTO l_count
        USING agent_team_name, attribute_name;
    
    -- If not exists, insert the attribute
    IF l_count = 0 THEN
      EXECUTE IMMEDIATE
        'INSERT INTO ' || INSPECT_AGENT_TEAM_ATTRIBUTES ||
        ' (agent_team_name, attribute_name, attribute_value) ' ||
        ' VALUES (:1, :2, :3)'
        USING agent_team_name, attribute_name, attribute_value;
    ELSE
      EXECUTE IMMEDIATE
        'UPDATE ' || INSPECT_AGENT_TEAM_ATTRIBUTES ||
        ' SET attribute_value = :1 ' ||
        ' WHERE agent_team_name = :2 AND attribute_name = :3'
        USING attribute_value, agent_team_name, attribute_name;
    END IF;
  END set_attribute;


  -----------------------------------------------------------------------------
  -- set_attributes: helper function to set multiple attribute values for the 
  -- given agent team
  -----------------------------------------------------------------------------
  PROCEDURE set_attributes(
    agent_team_name       IN VARCHAR2,
    attributes            IN JSON_OBJECT_T
  )
  IS
    l_attribute_keys      JSON_KEY_LIST;
    l_attribute_key       DBMS_ID;
    l_attribute_value     CLOB;
    l_elem                JSON_ELEMENT_T;
  BEGIN
    l_attribute_keys := attributes.get_keys;
    FOR i IN 1..l_attribute_keys.COUNT LOOP
      l_attribute_key := l_attribute_keys(i);
      l_elem := attributes.get(l_attribute_key);

      IF l_elem IS NULL THEN
        l_attribute_value := NULL;
      ELSE
        l_attribute_value := l_elem.to_clob;
      END IF;

      set_attribute(agent_team_name  => agent_team_name,
                    attribute_name   => l_attribute_key,
                    attribute_value  => l_attribute_value);
    END LOOP;
  END set_attributes;


  -----------------------------------------------------------------------------
  -- drop_attribute: helper function to drop an attribute value for the given 
  -- attribute_name and agent team
  -----------------------------------------------------------------------------
  PROCEDURE drop_attribute(
    agent_team_name   IN VARCHAR2,
    attribute_name    IN VARCHAR2,
    force             IN BOOLEAN DEFAULT FALSE
  )
  IS
    l_count           NUMBER;
  BEGIN
    -- Check if attribute exists
    EXECUTE IMMEDIATE
        'SELECT COUNT(*) FROM ' || INSPECT_AGENT_TEAM_ATTRIBUTES ||
        ' WHERE agent_team_name = :1 AND attribute_name = :2'
        INTO l_count
        USING agent_team_name, attribute_name;
    
    IF l_count = 0 THEN
      IF force THEN
        RETURN;
      ELSE
        raise_application_error(-20000, 'Attribute not found - ' || 
                                attribute_name);
      END IF;
    END IF;

    EXECUTE IMMEDIATE
        'DELETE FROM ' || INSPECT_AGENT_TEAM_ATTRIBUTES ||
        ' WHERE agent_team_name = :1 AND attribute_name = :2'
        USING agent_team_name, attribute_name;
  END drop_attribute;


  -----------------------------------------------------------------------------
  -- drop_attributes: helper function to drop all attributes for the given 
  -- agent team
  -----------------------------------------------------------------------------
  PROCEDURE drop_attributes(
    agent_team_name   IN VARCHAR2
  )
  IS
    l_attributes      JSON_OBJECT_T;
  BEGIN
    l_attributes := get_attributes(agent_team_name);
    IF l_attributes.get_size = 0 THEN
      RETURN;
    END IF;

    EXECUTE IMMEDIATE
        'DELETE FROM ' || INSPECT_AGENT_TEAM_ATTRIBUTES ||
        ' WHERE agent_team_name = :1'
        USING agent_team_name;
  END drop_attributes;


  -----------------------------------------------------------------------------
  -- get_agent_team_name_from_tool: helper function to get the agent team name
  -- from a tool.
  -- The format is <tool_name>_<agent_team_id>, e.g. TOOL_LIST_OBJECTS_123. 
  -- The agent team id will then be used to get the agent team name.
  -----------------------------------------------------------------------------
  FUNCTION get_agent_team_name_from_tool(
    tool_name         IN VARCHAR2,
    tool_type         IN VARCHAR2
  ) RETURN VARCHAR2
  IS
    l_agent_team_id   NUMBER;
    l_agent_team_name DBMS_ID;
  BEGIN
    IF tool_type NOT IN (TOOL_LIST_OBJECTS, TOOL_LIST_INCOMING_DEPENDENCIES, 
                         TOOL_LIST_OUTGOING_DEPENDENCIES, 
                         TOOL_RETRIEVE_OBJECT_METADATA, 
                         TOOL_RETRIEVE_OBJECT_METADATA_CHUNKS,
                         TOOL_EXPAND_OBJECT_METADATA_CHUNK, 
                         TOOL_SUMMARIZE_OBJECT, TOOL_GENERATE_PLDOC) 
    THEN
      raise_application_error(-20000, 'Invalid tool type - ' || tool_type);
    END IF;
    l_agent_team_id := to_number( SUBSTR(tool_name, LENGTH(tool_type) + 2));
    
    EXECUTE IMMEDIATE
      'SELECT agent_team_name FROM ' || INSPECT_AGENT_TEAMS || 
      '  WHERE id# = :1'
      INTO l_agent_team_name USING IN l_agent_team_id;

    RETURN l_agent_team_name;
  END get_agent_team_name_from_tool;


  -----------------------------------------------------------------------------
  -- get_agent_team_name_from_tool: helper function to generate tool name 
  -- suffix using agent team name.
  -----------------------------------------------------------------------------
  FUNCTION generate_tool_name_suffix(
    agent_team_name       IN VARCHAR2
  ) RETURN VARCHAR2
  IS
    l_agent_team_id       NUMBER;
    l_tool_name_suffix    VARCHAR2(100);
  BEGIN
    EXECUTE IMMEDIATE 
      'SELECT id# FROM ' || INSPECT_AGENT_TEAMS || ' WHERE agent_team_name = :1'
      INTO l_agent_team_id USING agent_team_name;
    l_tool_name_suffix := '_' || l_agent_team_id;
    RETURN l_tool_name_suffix;
  END generate_tool_name_suffix;


  -----------------------------------------------------------------------------
  -- get_vecotr_table_name: helper function to get the vector table name for 
  -- the given agent team.
  -- The format is VECTOR_TABLE_PREFIX || agent_team_name, 
  -- e.g. INSPECT_AGENT_VECTOR$TEST_TEAM.
  -----------------------------------------------------------------------------
  FUNCTION get_vecotr_table_name(
    agent_team_name   IN VARCHAR2
  ) RETURN VARCHAR2
  IS 
  BEGIN
    RETURN VECTOR_TABLE_PREFIX || agent_team_name;
  END get_vecotr_table_name;


  -----------------------------------------------------------------------------
  -- get_vecotr_table_name: helper function to get the vector table name for 
  -- the given agent team.
  -- The format is VECTOR_TABLE_PREFIX || agent_team_name, 
  -- e.g. INSPECT_AGENT_VECTOR$TEST_TEAM.
  -----------------------------------------------------------------------------
  FUNCTION validate_profile_name(
    profile_name        IN VARCHAR2
  ) RETURN VARCHAR2
  IS
    l_profile_name      DBMS_ID;
    l_count             NUMBER;
  BEGIN
    l_profile_name := validate_object_name(profile_name);
    EXECUTE IMMEDIATE 
        'SELECT COUNT(*) FROM user_cloud_ai_profiles WHERE profile_name = :1'
      INTO l_count USING l_profile_name;
      IF l_count != 1 THEN
        raise_application_error(-20000, 'Invalid profile name - ' || 
                                profile_name);
      END IF;
    RETURN l_profile_name;
  END validate_profile_name;


  -----------------------------------------------------------------------------
  -- get_profile_attributes: helper function to get profile attributes
  -----------------------------------------------------------------------------
  FUNCTION get_profile_attributes(
    profile_name        IN  VARCHAR2
  ) RETURN JSON_OBJECT_T
  IS
    l_attributes_str    CLOB;
    l_attributes        JSON_OBJECT_T;
  BEGIN
    EXECUTE IMMEDIATE 
        'SELECT JSON_OBJECTAGG(attribute_name VALUE attribute_value) ' ||
        '   AS combined_json FROM user_cloud_ai_profile_attributes '   ||
        '   WHERE profile_name = :1'
      INTO l_attributes_str USING IN profile_name;

    IF l_attributes_str IS NULL THEN
      l_attributes := JSON_OBJECT_T('{}');
    ELSE
      l_attributes := JSON_OBJECT_T(l_attributes_str);
    END IF;
    
    RETURN l_attributes;
  END get_profile_attributes;


  -----------------------------------------------------------------------------
  -- get_embedding_batch: get embeddings in batch
  -----------------------------------------------------------------------------
  PROCEDURE get_embedding_batch(
    agent_team_name     IN VARCHAR2,
    points_arr          IN  JSON_ARRAY_T
  )
  IS
    l_uri               VARCHAR2(4000);
    l_req_obj           JSON_OBJECT_T := JSON_OBJECT_T('{}');
    l_endpoint          VARCHAR2(4000);
    l_arr               JSON_ARRAY_T := JSON_ARRAY_T('[]');
    l_point_obj         JSON_OBJECT_T;
    l_data              CLOB;
    l_rsp               DBMS_CLOUD_TYPES.resp;
    l_result            CLOB; 
    l_embed_arr         JSON_ARRAY_T;
    l_profile_name      DBMS_ID;
    l_compartment_id    VARCHAR2(1000);
    l_credential_name   DBMS_ID;
    l_region            DBMS_ID;
    l_attributes        JSON_OBJECT_T;
    l_attributes_str    CLOB;
    l_provider          DBMS_ID;
    l_embedding_model   DBMS_ID;
    l_password          VARCHAR2(4000);
    l_text              JSON_OBJECT_T;
    l_parts             JSON_ARRAY_T;
    l_single_request    JSON_OBJECT_T;
    l_content           JSON_OBJECT_T;
    l_apiformat         DBMS_ID;
    l_requests          JSON_ARRAY_T;

    PROCEDURE get_one_embedding IS
    BEGIN
      FOR i IN 0..points_arr.get_size() - 1 LOOP
        l_point_obj := TREAT(points_arr.get(i) AS JSON_OBJECT_T);
        l_data := l_point_obj.get_object('payload').get_clob('content');
        l_req_obj := JSON_OBJECT_T('{}');


        CASE l_provider
          WHEN PROVIDER_AZURE THEN
            l_req_obj.put('input', l_data);
          WHEN PROVIDER_AWS THEN
            CASE l_apiformat
              WHEN 'COHERE' THEN
                l_parts := JSON_ARRAY_T('[]');
                l_parts.append(l_data);
                l_req_obj.put('texts', l_parts);
                l_req_obj.put('input_type', 'search_document');
              WHEN 'TITAN' THEN
                l_req_obj.put('inputText', l_data);
            END CASE;
        END CASE;

        l_rsp := DBMS_CLOUD.send_request(
                            credential_name   => l_credential_name,
                            uri               => l_uri,
                            body              => l_req_obj.to_blob,
                            method            => 'POST');
        l_result := TO_CLOB(DBMS_CLOUD.get_response_raw(l_rsp));

        CASE l_provider
          WHEN PROVIDER_AZURE THEN
            l_arr := JSON_OBJECT_T(
                        JSON_OBJECT_T(l_result).get_array(
                          'data').get(0)).get_array('embedding');
          WHEN PROVIDER_AWS THEN
            CASE l_apiformat
              WHEN 'COHERE' THEN
                l_arr := JSON_ARRAY_T(JSON_OBJECT_T(l_result).
                            get_array('embeddings').get(0));
              WHEN 'TITAN' THEN
                l_arr :=  JSON_OBJECT_T(l_result).get_array('embedding');
            END CASE;
        END CASE;

        l_point_obj.put('vector', l_arr);
      END LOOP;
    END get_one_embedding;

  BEGIN

    FOR i IN 0..points_arr.get_size() - 1 LOOP
      l_point_obj := TREAT(points_arr.get(i) AS JSON_OBJECT_T);
      l_data := l_point_obj.get_object('payload').get_clob('content');
      l_arr.append(l_data);
    END LOOP;

    l_profile_name := get_attribute(agent_team_name, 'profile_name');
    l_attributes := get_profile_attributes(l_profile_name);

    l_provider := LOWER(l_attributes.get_string('provider'));
    l_embedding_model := l_attributes.get_string('embedding_model');
    l_credential_name := l_attributes.get_string('credential_name');

    CASE l_provider
      WHEN PROVIDER_AZURE THEN
        IF l_attributes.get_string('credential_name') = 'AZURE$PA' THEN
          -- Azure principal authentication 
          l_uri := 'azure://<resource_name>.openai.azure.com/openai/' ||
                   'deployments/<deployment_name>/<endpoint_suffix>?' ||
                   'api-version=2023-05-15';
        ELSE
          -- Bearer token authentication 
          l_uri := 'bearer://<resource_name>.openai.azure.com/openai/' ||
                   'deployments/<deployment_name>/<endpoint_suffix>?'  ||
                   'api-version=2023-05-15';
        END IF;
        l_uri := REPLACE(l_uri, '<endpoint_suffix>', 'embeddings');
        l_uri := REPLACE(l_uri, '<resource_name>',
                         l_attributes.get_string('azure_resource_name'));
        l_uri := REPLACE(l_uri, '<deployment_name>',
                         l_attributes.get_string(
                           'azure_embedding_deployment_name'));

        get_one_embedding;
        RETURN;

      WHEN PROVIDER_OPENAI THEN
        IF l_attributes.get_string('provider_endpoint') IS NULL THEN
          -- Use default embedding model if not specified
          IF l_embedding_model IS NULL THEN 
            l_embedding_model := 'text-embedding-ada-002';
          END IF;
          l_uri := 'bearer://api.openai.com/v1/embeddings';
        ELSE
          -- Embedding model must be specified for OPENAI Compatible provider
          IF l_embedding_model IS NULL THEN 
            raise_application_error(-20000,
                                   'Embedding Model must be specified for ' ||
                                   'vector embeddings with OPENAI ' || 
                                   'Compatible Provider.');
          END IF;
          l_endpoint := TRIM('/' FROM 
                             l_attributes.get_string('provider_endpoint'));
          l_endpoint := REGEXP_REPLACE(l_endpoint, '/v1$', '', 1, 0, 'i');
          IF  REGEXP_LIKE(l_endpoint, '^http://',  'i') THEN
            l_endpoint := l_endpoint || '/v1/embeddings';
          ELSE
            l_endpoint := 'bearer://' || 
                          REGEXP_REPLACE(l_endpoint, '^https://', '') || 
                                         '/v1/embeddings';
          END IF;
        END IF;
        l_req_obj.put('input', l_arr);
        l_req_obj.put('model', l_embedding_model);

      WHEN PROVIDER_OCI THEN 
        l_region := NVL(l_attributes.get_string('region'), 'us-chicago-1');
        l_compartment_id := l_attributes.get_string('oci_compartment_id');

        l_uri := 'https://inference.generativeai.' || l_region || 
                 '.oci.my$cloud_domain/20231130/actions/embedText';
        l_req_obj.put('inputs', l_arr);
        l_req_obj.put('inputType', 'SEARCH_DOCUMENT');
        l_req_obj.put('compartmentId', l_compartment_id);
        l_req_obj.put('servingMode', 
                      JSON_OBJECT_T(
                        '{"modelId": "cohere.embed-english-v3.0",' ||
                        '"servingType": "ON_DEMAND"}'));
      
      WHEN PROVIDER_COHERE THEN
        IF l_embedding_model IS NULL THEN
          l_embedding_model := 'embed-english-v2.0';
        END IF;
        l_uri := 'bearer://api.cohere.ai/v2/embed';
        l_req_obj.put('texts', l_arr);
        l_req_obj.put('input_type', 'SEARCH_DOCUMENT');
        l_req_obj.put('model', l_embedding_model);

      WHEN PROVIDER_GOOGLE THEN
        IF l_embedding_model IS NULL THEN
          l_embedding_model := 'text-embedding-004';
        END IF;

        l_password := get_attribute(agent_team_name, 'google_key');
        IF l_password IS NULL THEN
          raise_application_error(-20000, 'google_key attribute must be set.');
        END IF;

        -- Google has a specific batch embedding endpoint
        l_uri := REPLACE('https://generativelanguage.' ||
                         'googleapis.com/' ||
                         'v1/models/<model_name>:', 
                         '<model_name>', l_embedding_model) ||
                        'batchEmbedContents' || '?key=' || l_password;
        l_requests := JSON_ARRAY_T('[]');
        -- Loop through the array and construct the JSON objects
        FOR i IN 0..l_arr.get_size() - 1 LOOP
          l_text := JSON_OBJECT_T('{}');
          l_text.put('text', l_arr.get_clob(i));
          l_parts := JSON_ARRAY_T('[]');
          l_parts.append(l_text);
          l_content := JSON_OBJECT_T('{}');
          l_content.put('parts', l_parts);
          l_single_request := JSON_OBJECT_T(
            '{"model": "models/' || l_embedding_model || 
            '", "content": ' || l_content.to_clob || 
            ', "task_type": "RETRIEVAL_DOCUMENT"}');
          l_requests.append(l_single_request);
        END LOOP;
        l_req_obj.put('requests', l_requests);

      WHEN PROVIDER_AWS THEN
        IF l_embedding_model IS NULL THEN
          raise_application_error(-20000,
              'For AWS embedding, embedding_model attribute must be ' ||
              'specified');
        END IF; 
        l_apiformat := l_attributes.get_string('aws_apiformat');
        IF l_apiformat IS NULL THEN
          CASE
            WHEN INSTR(l_embedding_model, LOWER('COHERE')) > 0 THEN
              l_apiformat := 'COHERE';
            WHEN INSTR(l_embedding_model, LOWER('TITAN')) > 0 THEN
              l_apiformat := 'TITAN';
            ELSE
              raise_application_error(-20000,
                  'AWS embedding format is not supported');
          END CASE;
        END IF;
        -- url escape colon character in modelID
        l_embedding_model := REPLACE(l_embedding_model, ':', '%3A');
        l_uri := REPLACE('s3://bedrock-runtime.<region>.amazonaws.com', 
                         '<region>', 
                         NVL(l_attributes.get_string('region'), 
                             'us-east-1')) ||
                         '/model/' || l_embedding_model || '/invoke';

        -- Construct single embedding request
        get_one_embedding;
        RETURN;  

      ELSE
        raise_application_error(-20000, 'Invalid vector database ' ||
                                'provider - ' || l_provider);
    END CASE;

    l_rsp := DBMS_CLOUD.send_request(
                        credential_name   => l_credential_name,
                        uri               => l_uri,
                        body              => l_req_obj.to_blob,
                        method            => 'POST');
    l_result := TO_CLOB(DBMS_CLOUD.get_response_raw(l_rsp));

    -- Parse the response to get array of embeddings
    CASE
      WHEN l_provider IN (PROVIDER_OPENAI, PROVIDER_AZURE) THEN
        l_arr := JSON_OBJECT_T(l_result).get_array('data');
      WHEN l_provider IN (PROVIDER_OCI, PROVIDER_GOOGLE) THEN
        l_arr :=  JSON_OBJECT_T(l_result).get_array('embeddings');
      WHEN l_provider = PROVIDER_COHERE THEN
        l_arr :=  JSON_OBJECT_T(l_result).get_object('embeddings')
                                         .get_array('float');
      ELSE
        raise_application_error(-20000, 'Invalid vector database ' ||
                                'provider - ' || l_provider);
    END CASE;

    -- Make sure that the embeddings requested match the embeddings received
    IF points_arr.get_size() != l_arr.get_size() THEN
      raise_application_error(-20000, 'Mismatch in embeddings requested (' || 
          TO_CHAR(points_arr.get_size) || 
          ') and embeddings received (' || TO_CHAR(l_arr.get_size) || ')');
    END IF;

    FOR i IN 0..l_arr.get_size() - 1 LOOP
      l_point_obj := TREAT(points_arr.get(i) AS JSON_OBJECT_T);
      CASE
        WHEN l_provider IN (PROVIDER_OPENAI, PROVIDER_AZURE) THEN
          l_embed_arr := TREAT(l_arr.get(i) AS JSON_OBJECT_T)
                         .get_array('embedding');
        WHEN l_provider IN (PROVIDER_COHERE, PROVIDER_OCI) THEN
          l_embed_arr := TREAT(l_arr.get(i) AS JSON_ARRAY_T);
        WHEN l_provider = PROVIDER_GOOGLE THEN        
          l_embed_arr := TREAT(l_arr.get(i) AS JSON_OBJECT_T)
                         .get_array('values');
        ELSE
          raise_application_error(-20000, 'Invalid vector database ' ||
                                  'provider - ' || l_provider);
      END CASE;

      l_point_obj.put('vector', l_embed_arr);
    END LOOP;
  END get_embedding_batch;


  -----------------------------------------------------------------------------
  -- get_vector_sql: get sql for vector search
  -----------------------------------------------------------------------------
  FUNCTION get_vector_sql(
    agent_team_name       IN VARCHAR2,
    p_filter_objects      IN BOOLEAN DEFAULT FALSE
  ) RETURN CLOB
  IS
    l_rag_sql             CLOB;
    l_vector_db_dis_type  DBMS_ID := 'cosine';
    l_search_limit        NUMBER;
    l_vector_table_name   VARCHAR2(30) := VECTOR_TABLE_PREFIX || 
                                          agent_team_name;
  BEGIN
    l_search_limit := NVL(TO_NUMBER(get_attribute(agent_team_name, 
                                                'search_limit')), 
                          10);
    l_vector_db_dis_type := NVL(get_attribute(agent_team_name,
                                              'vector_distance_type'),
                                VEC_DIST_COSINE);

    l_rag_sql :=
        'SELECT JSON_SERIALIZE(' ||
        '  JSON_ARRAYAGG(' ||
        '    JSON_OBJECT(' ||
        '      ''data''       VALUE data,' ||
        '      ''attributes'' VALUE attributes,' ||
        '      ''score''      VALUE ROUND(1 - dist_score, 2)' ||
        '    ) RETURNING CLOB' ||
        '  ) RETURNING CLOB PRETTY)' ||
        'FROM ';

    l_rag_sql := l_rag_sql ||
        '(SELECT data, attributes, distance AS dist_score FROM (' ||
        '   SELECT ' ||
        '     content    AS data, ' ||
        '     attributes AS attributes, ' ||
        '     VECTOR_DISTANCE(embedding, TO_VECTOR(:embed), ' || 
        l_vector_db_dis_type || ') AS distance ' ||
        '   FROM ' || l_vector_table_name;

    -- Optional filter by obj_list (owner/name/type; NULL fields 
    -- treated as wildcards)
    IF p_filter_objects THEN
      l_rag_sql := l_rag_sql ||
        '   WHERE EXISTS (' ||
        '     SELECT 1' ||
        '     FROM JSON_TABLE(' ||
        '            :obj_list, ''$[*]''' ||
        '            COLUMNS (' ||
        '              object_owner VARCHAR2(128) PATH ''$.object_owner'',' ||
        '              object_name  VARCHAR2(128) PATH ''$.object_name'','  ||
        '              object_type  VARCHAR2(30)  PATH ''$.object_type'''   ||
        '            )' ||
        '          ) j' ||
        '     WHERE (j.object_owner IS NULL OR ' ||
        '            j.object_owner = JSON_VALUE(attributes, ' ||
        '''$.object_owner''))' ||
        '       AND (j.object_name  IS NULL OR ' ||
        '            j.object_name  = JSON_VALUE(attributes, ' ||
        '''$.object_name''))' ||
        '       AND (j.object_type  IS NULL OR ' ||
        '            j.object_type  = JSON_VALUE(attributes, ' ||
        '''$.object_type''))' ||
        '   )';
    END IF;

    l_rag_sql := l_rag_sql ||
        ' ) ORDER BY dist_score ' ||
        ' FETCH APPROXIMATE FIRST ' || TO_CHAR(l_search_limit) || 
        ' ROWS ONLY)';

    RETURN l_rag_sql;
  END get_vector_sql;


  -----------------------------------------------------------------------------
  -- get_hybrid_sql: get sql for hybrid search 
  -- oracle text search + vector search
  -----------------------------------------------------------------------------
  /*
    WITH
      vec_base    AS (...),
      vec_chunks  AS (...),
      txt_hits    AS (...),
      fused       AS (...),
      scored      AS (...),
      topk        AS (...)
    SELECT JSON_SERIALIZE(JSON_ARRAYAGG(JSON_OBJECT(...)))
    FROM topk;

    Conceptually:
    vec_base: do the pure vector search (compute distances), optionally filter 
    by object list.
    vec_chunks: turn distances into a vector score 0–100 and a vector rank.
    txt_hits: do the pure text search (CONTAINS), compute text scores and text 
    ranks.
    fused: join vector+text branches per chunk (union-style fusion).
    scored: compute the final hybrid score using an RSF-like formula.
    topk: take top N by hybrid score.
    outer SELECT: return them as a JSON array.


    search_scorer is RSF.
    search_fusion is UNION.
    for vector: "score_weight" = 1,"rank_penalty" = 5
    for text: "score_weight" = 10,"rank_penalty" = 1
  */
  FUNCTION get_hybrid_sql(
    agent_team_name         IN VARCHAR2,
    p_filter_objects        IN BOOLEAN DEFAULT FALSE
  ) RETURN CLOB
  IS
    l_sql                   CLOB;
    l_vector_db_dis_type    DBMS_ID;
    l_search_limit          NUMBER;
    l_vector_table_name     VARCHAR2(200) := VECTOR_TABLE_PREFIX || 
                                             agent_team_name;
  BEGIN
    l_search_limit := NVL(TO_NUMBER(get_attribute(agent_team_name, 
                                                  'search_limit')), 
                          10);
    l_vector_db_dis_type := NVL(get_attribute(agent_team_name,
                                              'vector_distance_type'),
                                VEC_DIST_COSINE);

    l_sql := ''
        || 'WITH' || CHR(10)
        || '  vec_base AS (' || CHR(10)
        || '    SELECT' || CHR(10)
        || '      t.rowid      AS chunk_id,' || CHR(10)
        || '      t.content    AS data,' || CHR(10)
        || '      t.attributes AS attributes,' || CHR(10)
        || '      VECTOR_DISTANCE(t.embedding, TO_VECTOR(:embed), ' 
        || l_vector_db_dis_type || ') AS dist' || CHR(10)
        || '    FROM ' || l_vector_table_name || ' t' || CHR(10);

    IF p_filter_objects THEN
        l_sql := l_sql
        || '    WHERE EXISTS (' || CHR(10)
        || '            SELECT 1' || CHR(10)
        || '            FROM JSON_TABLE(' || CHR(10)
        || '                   :obj_list, ''$[*]''' || CHR(10)
        || '                   COLUMNS (' || CHR(10)
        || '                     object_owner VARCHAR2(128) ' 
        || 'PATH ''$.object_owner'',' || CHR(10)
        || '                     object_name  VARCHAR2(128) ' 
        || 'PATH ''$.object_name'',' || CHR(10)
        || '                     object_type  VARCHAR2(30)  ' 
        || 'PATH ''$.object_type''' || CHR(10)
        || '                   )' || CHR(10)
        || '                 ) j' || CHR(10)
        || '            WHERE (j.object_owner IS NULL OR' || CHR(10)
        || '                   j.object_owner = JSON_VALUE(t.attributes, ' 
        || '''$.object_owner''))' || CHR(10)
        || '              AND (j.object_name  IS NULL OR' || CHR(10)
        || '                   j.object_name  = JSON_VALUE(t.attributes, ' 
        || '''$.object_name''))' || CHR(10)
        || '              AND (j.object_type  IS NULL OR' || CHR(10)
        || '                   j.object_type  = JSON_VALUE(t.attributes, ' 
        || '''$.object_type''))' || CHR(10)
        || '          )' || CHR(10);
    END IF;

    l_sql := l_sql
        || '  ),' || CHR(10)
        || '  vec_chunks AS (' || CHR(10)
        || '    SELECT' || CHR(10)
        || '      b.chunk_id,' || CHR(10)
        || '      b.data,' || CHR(10)
        || '      b.attributes,' || CHR(10)
        || '      b.dist,' || CHR(10)
        || '      ROUND((1 - CUME_DIST() OVER (ORDER BY b.dist)) * 100, 2) ' 
        || 'AS vector_score,' || CHR(10)
        || '      RANK() OVER (ORDER BY b.dist) AS vector_rank' 
        || CHR(10)
        || '    FROM vec_base b' || CHR(10)
        || '  ),' || CHR(10)
        || '  txt_hits AS (' || CHR(10)
        || '    SELECT' || CHR(10)
        || '      t.rowid AS chunk_id,' || CHR(10)
        || '      NVL(SCORE(1), 0)                     ' 
        || 'AS text_score_raw,' || CHR(10)
        || '      RANK() OVER (ORDER BY SCORE(1) DESC) AS text_rank' 
        || CHR(10)
        || '    FROM ' || l_vector_table_name || ' t' 
        || CHR(10)
        || '    WHERE CONTAINS(t.content, :kw, 1) > 0' || CHR(10);

    IF p_filter_objects THEN
        l_sql := l_sql
        || '      AND EXISTS (' || CHR(10)
        || '            SELECT 1' || CHR(10)
        || '            FROM JSON_TABLE(' || CHR(10)
        || '                   :obj_list, ''$[*]''' || CHR(10)
        || '                   COLUMNS (' || CHR(10)
        || '                     object_owner VARCHAR2(128) PATH ' 
        || '''$.object_owner'',' || CHR(10)
        || '                     object_name  VARCHAR2(128) PATH ' 
        || '''$.object_name'',' || CHR(10)
        || '                     object_type  VARCHAR2(30)  PATH ' 
        || '''$.object_type''' || CHR(10)
        || '                   )' || CHR(10)
        || '                 ) j' || CHR(10)
        || '            WHERE (j.object_owner IS NULL OR' || CHR(10)
        || '                   j.object_owner = JSON_VALUE(t.attributes, ' 
        || '''$.object_owner''))' || CHR(10)
        || '              AND (j.object_name  IS NULL OR' || CHR(10)
        || '                   j.object_name  = JSON_VALUE(t.attributes, ' 
        || '''$.object_name''))' || CHR(10)
        || '              AND (j.object_type  IS NULL OR' || CHR(10)
        || '                   j.object_type  = JSON_VALUE(t.attributes, ' 
        || '''$.object_type''))' || CHR(10)
        || '          )' || CHR(10);
    END IF;

    l_sql := l_sql
        || '  ),' || CHR(10)
        || '  fused AS (' || CHR(10)
        || '    SELECT' || CHR(10)
        || '      v.chunk_id,' || CHR(10)
        || '      v.data,' || CHR(10)
        || '      v.attributes,' || CHR(10)
        || '      v.vector_score,' || CHR(10)
        || '      v.vector_rank,' || CHR(10)
        || '      NVL(t.text_score_raw, 0) AS text_score,' || CHR(10)
        || '      t.text_rank' || CHR(10)
        || '    FROM vec_chunks v' || CHR(10)
        || '    LEFT JOIN txt_hits t' || CHR(10)
        || '      ON v.chunk_id = t.chunk_id' || CHR(10)
        || '  ),' || CHR(10)
        || '  scored AS (' || CHR(10)
        || '    SELECT' || CHR(10)
        || '      data,' || CHR(10)
        || '      attributes,' || CHR(10)
        || '      vector_score,' || CHR(10)
        || '      text_score,' || CHR(10)
        || '      (' || CHR(10)
        || '        CASE' || CHR(10)
        || '          WHEN vector_score > 0 THEN' || CHR(10)
        || '            1 * vector_score / (5 + vector_rank)' || CHR(10)
        || '          ELSE 0' || CHR(10)
        || '        END' || CHR(10)
        || '        +' || CHR(10)
        || '        CASE' || CHR(10)
        || '          WHEN text_score > 0 AND text_rank IS NOT NULL THEN' 
        || CHR(10)
        || '            10 * text_score / (1 + text_rank)' || CHR(10)
        || '          ELSE 0' || CHR(10)
        || '        END' || CHR(10)
        || '      ) AS hybrid_score' || CHR(10)
        || '    FROM fused' || CHR(10)
        || '  ),' || CHR(10)
        || '  topk AS (' || CHR(10)
        || '    SELECT' || CHR(10)
        || '      data,' || CHR(10)
        || '      attributes,' || CHR(10)
        || '      vector_score,' || CHR(10)
        || '      text_score,' || CHR(10)
        || '      hybrid_score' || CHR(10)
        || '    FROM scored' || CHR(10)
        || '    ORDER BY hybrid_score DESC' || CHR(10)
        || '    FETCH APPROXIMATE FIRST ' || TO_CHAR(l_search_limit)
        || ' ROWS ONLY' || CHR(10)
        || '  )' || CHR(10)
        || 'SELECT JSON_SERIALIZE(' || CHR(10)
        || '         JSON_ARRAYAGG(' || CHR(10)
        || '           JSON_OBJECT(' || CHR(10)
        || '             ''data''         VALUE data,' || CHR(10)
        || '             ''attributes''   VALUE attributes,' || CHR(10)
        || '             ''vector_score'' VALUE ROUND(vector_score, 2),' 
        || CHR(10)
        || '             ''text_score''   VALUE ROUND(text_score, 2),' 
        || CHR(10)
        || '             ''score''        VALUE ROUND(hybrid_score, 2)' 
        || CHR(10)
        || '           )' || CHR(10)
        || '         RETURNING CLOB)' || CHR(10)
        || '       RETURNING CLOB PRETTY)' || CHR(10)
        || 'FROM topk';

    RETURN l_sql;
  END get_hybrid_sql;


  -----------------------------------------------------------------------------
  -- vectorize_object: vectorize object
  -----------------------------------------------------------------------------
  PROCEDURE vectorize_object(
    agent_team_name         IN VARCHAR2,
    obj_name                IN VARCHAR2,
    obj_type                IN VARCHAR2,
    owner_name              IN VARCHAR2 DEFAULT NULL
  )
  IS
    l_metdata               CLOB := '';
    l_chunk_size            NUMBER;
    l_start_position        NUMBER;
    l_chunk                 CLOB;
    l_new_line_index        NUMBER;
    l_metadata_js           JSON_OBJECT_T;
    l_point                 JSON_OBJECT_T;
    l_points_arr            JSON_ARRAY_T := JSON_ARRAY_T('[]');
    l_cnt                   NUMBER := 0;
    l_stmt                  CLOB;
    l_content_index         NUMBER := 0;
    l_profile_name          DBMS_ID;
    l_attributes            JSON_OBJECT_T;
    l_provider              DBMS_ID;
    l_vector_table_name     VARCHAR2(200) := VECTOR_TABLE_PREFIX || 
                                             agent_team_name;

    PROCEDURE store_vector
    IS
      l_stmt    CLOB;
    BEGIN
      get_embedding_batch(agent_team_name => agent_team_name, 
                          points_arr      => l_points_arr);
      l_stmt :=
        'DECLARE ' ||
        '  TYPE vectab_t IS TABLE OF ' || l_vector_table_name || '%ROWTYPE;' ||
        '  l_records vectab_t := vectab_t(); ' ||
        '  l_p_arr JSON_ARRAY_T := JSON_ARRAY_T(:p_arr); ' ||
        '  l_p_obj JSON_OBJECT_T; ' ||
        '  l_metadata_obj JSON_OBJECT_T; ' ||
        '  l_vector       CLOB; ' ||
        'BEGIN ' ||
        '  l_records.EXTEND(l_p_arr.get_size); ' ||
        '  FOR i IN 0..l_p_arr.get_size - 1 LOOP ' ||
        '    l_p_obj := TREAT(l_p_arr.get(i) AS JSON_OBJECT_T); ' ||
        '    l_metadata_obj := l_p_obj.get_object(''payload''); ' ||
        '    l_records(i+1).content := ' ||
                'l_metadata_obj.get_clob(''content''); ' ||
        '    l_metadata_obj.remove(''content''); ' ||
        '    l_records(i+1).attributes := ' ||
                'JSON(l_metadata_obj.to_clob); ' ||
        '    l_vector := l_p_obj.get_array(''vector'').to_clob; ' ||
        '    l_records(i+1).embedding := ' ||
                'VECTOR(l_vector); ' ||
        '  END LOOP; ' ||
        '  FORALL i IN l_records.FIRST..l_records.LAST ' ||
        '  INSERT INTO ' || l_vector_table_name ||
        '    (content, attributes, embedding) ' ||
        '  VALUES (l_records(i).content, l_records(i).attributes, ' ||
        '          l_records(i).embedding); ' ||
        'END;';
      EXECUTE IMMEDIATE l_stmt USING IN l_points_arr.to_clob;
    END store_vector;

    PROCEDURE store_chunk(
      content         IN CLOB,
      content_index   IN NUMBER
    ) 
    IS
    BEGIN
      l_metadata_js := JSON_OBJECT_T('{}');
      l_metadata_js.put('object_owner', owner_name);
      l_metadata_js.put('object_name', obj_name);
      l_metadata_js.put('object_type', obj_type);
      l_metadata_js.put('content_index', content_index);
      l_metadata_js.put('content', content);

      l_point := JSON_OBJECT_T('{}');
      l_point.put('payload', l_metadata_js);
      l_points_arr.append(l_point);
      l_cnt := l_cnt + 1;

      IF l_cnt = VECTOR_EMBEDDING_BATCH_SIZE THEN
        store_vector();
        l_points_arr := JSON_ARRAY_T('[]');
        l_cnt := 0;
      END IF;
    END store_chunk;

  BEGIN
    l_metdata := retrieve_object_metadata(obj_name, obj_type, owner_name);

    l_profile_name := get_attribute(agent_team_name, 'profile_name');
    l_attributes := get_profile_attributes(l_profile_name);
    l_provider := LOWER(l_attributes.get_string('provider'));

    -- get the chunk size
    IF l_provider IN (PROVIDER_OCI, PROVIDER_COHERE, PROVIDER_AWS)
    THEN
      l_chunk_size := DEFAULT_CHUNK_SIZE_OCI;
    ELSIF l_provider IN (PROVIDER_OPENAI, PROVIDER_AZURE, PROVIDER_GOOGLE) 
    THEN
      l_chunk_size := DEFAULT_CHUNK_SIZE;
    END IF;

    l_start_position := 1;
    WHILE l_start_position < LENGTH(l_metdata) LOOP
      l_chunk := SUBSTR(l_metdata, l_start_position, l_chunk_size);
      l_new_line_index := INSTR(l_chunk, CHR(10), -1, 1);
      IF l_start_position + l_chunk_size < LENGTH(l_metdata) AND 
         l_new_line_index > 0 
      THEN
        l_chunk := SUBSTR(l_chunk, 1, l_new_line_index);
        l_start_position := l_start_position + l_new_line_index;
      ELSE
        l_start_position := l_start_position + l_chunk_size;
      END IF;
      l_content_index := l_content_index + 1;

      store_chunk(l_chunk, l_content_index);
    END LOOP;

    IF l_points_arr.get_size > 0 THEN
      store_vector();
    END IF;
  END vectorize_object;


  -----------------------------------------------------------------------------
  -- is_soda_collection: validate if an object is soda collection
  -----------------------------------------------------------------------------
  FUNCTION is_soda_collection(
    object_name         VARCHAR2,
    object_owner        VARCHAR2,
    object_type         VARCHAR2
  ) RETURN BOOLEAN
  IS
    l_object_count      NUMBER;
    l_object_name       DBMS_ID := object_name;
    l_object_owner      DBMS_ID := object_owner;
  BEGIN
    IF object_type != 'TABLE' THEN
      RETURN FALSE;
    END IF;

    SELECT COUNT(*) INTO l_object_count FROM all_synonyms 
        WHERE table_name = l_object_name AND owner = l_object_owner;

    RETURN l_object_count > 0;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN FALSE;
  END is_soda_collection;


  -----------------------------------------------------------------------------
  -- drop_vector_table: drop a vector table and relevant indexes for an 
  -- agent team
  -----------------------------------------------------------------------------
  PROCEDURE drop_vector_table(
    agent_team_name     IN VARCHAR2
  )
  IS
    l_vector_table_name VARCHAR2(200) := VECTOR_TABLE_PREFIX || 
                                         agent_team_name;
    l_vector_index_name VARCHAR2(200) := VECTOR_INDEX_PREFIX || 
                                         agent_team_name;
    l_text_index_name   VARCHAR2(200) := ORACLE_TEXT_INDEX_PREFIX || 
                                         agent_team_name;
    l_count             NUMBER;
  BEGIN
    -- Drop vector index if exists
    EXECUTE IMMEDIATE 
        'SELECT count(*) FROM user_indexes ' ||
        '  WHERE index_type = ''VECTOR'' AND index_name = :1'
        INTO l_count USING l_vector_index_name;
    IF l_count > 0 THEN
      EXECUTE IMMEDIATE 
        'DROP INDEX ' || l_vector_index_name;
    END IF; 

    -- Drop oracle text index if exists
    EXECUTE IMMEDIATE 
      'SELECT count(*) FROM user_indexes ' ||
      '  WHERE index_type = ''DOMAIN'' AND index_name = :1'
      INTO l_count USING l_text_index_name;
    IF l_count > 0 THEN
      EXECUTE IMMEDIATE 
        'DROP INDEX ' || l_text_index_name;
    END IF; 

    -- Drop vector table if exists
    EXECUTE IMMEDIATE 
        'SELECT COUNT(*) FROM user_tables WHERE table_name = :1'
      INTO l_count USING l_vector_table_name;
    IF l_count > 0 THEN
      EXECUTE IMMEDIATE 
        'DROP TABLE ' || l_vector_table_name || ' PURGE';
    END IF;
  END drop_vector_table;


  -----------------------------------------------------------------------------
  -- create_vector_table: create a vector table and required indexes for an 
  -- agent team
  -----------------------------------------------------------------------------
  PROCEDURE create_vector_table(
    agent_team_name     IN VARCHAR2,
    profile_name        IN VARCHAR2
  )
  IS
    l_embedding         JSON_ARRAY_T;
    l_chunk_size        NUMBER;
    l_dummy_prompt      CLOB;
    l_vector_dimension  NUMBER;
    l_provider          DBMS_ID;
    l_attributes        JSON_OBJECT_T;
    l_vector_table_name VARCHAR2(200);
    l_vector_index_name VARCHAR2(200);
    l_text_index_name   VARCHAR2(200);
    l_count             NUMBER;
    l_distance_type     DBMS_ID := VEC_DIST_COSINE;
  BEGIN
    l_vector_table_name := VECTOR_TABLE_PREFIX || agent_team_name;
    l_vector_index_name := VECTOR_INDEX_PREFIX || agent_team_name;
    l_text_index_name   := ORACLE_TEXT_INDEX_PREFIX || agent_team_name;

    l_attributes := get_profile_attributes(profile_name);
    l_provider := LOWER(l_attributes.get_string('provider'));

    IF l_provider IN (PROVIDER_OCI, PROVIDER_COHERE, PROVIDER_AWS)
    THEN
      l_chunk_size := DEFAULT_CHUNK_SIZE_OCI;
    ELSIF l_provider IN (PROVIDER_OPENAI, PROVIDER_AZURE, 
                         PROVIDER_GOOGLE, PROVIDER_DATABASE) 
    THEN
      l_chunk_size := DEFAULT_CHUNK_SIZE;
    ELSE
      raise_application_error(-20000,
        INITCAP(l_provider) || ' is not supported for vector embeddings.');
    END IF;

    -- Validate the dimension using a dummy vector embedding request
    l_dummy_prompt := DBMS_RANDOM.string('a', l_chunk_size);
    l_embedding := JSON_ARRAY_T(
                        DBMS_CLOUD_AI.generate(
                          prompt        => l_dummy_prompt,
                          profile_name  => profile_name,
                          action        => 'embedding'));

    -- Get value for dimension
    l_vector_dimension := l_embedding.get_size();
    
    drop_vector_table(agent_team_name);

    -- Create vector table with dynamic dimension and distance type.
    EXECUTE IMMEDIATE 
        'CREATE TABLE ' || l_vector_table_name ||
        ' (content   CLOB, attributes JSON, ' ||
        '  embedding VECTOR(' ||
        NVL(TO_CHAR(l_vector_dimension), '*') || ', ' ||
        CASE WHEN l_distance_type = VEC_DIST_HAMMING
        THEN 'INT8' ELSE '*' END || '))';

    -- Drop vector index if exists
    EXECUTE IMMEDIATE 
        'SELECT count(*) FROM user_indexes ' ||
        '  WHERE index_type = ''VECTOR'' AND index_name = :1'
        INTO l_count USING l_vector_index_name;
    IF l_count > 0 THEN
      EXECUTE IMMEDIATE 
        'DROP INDEX ' || l_vector_index_name || ' PURGE';
    END IF; 

    -- Create vector index
    EXECUTE IMMEDIATE 
        'CREATE VECTOR INDEX ' || l_vector_index_name     ||
        ' ON ' || l_vector_table_name                     ||
        '  (embedding) ORGANIZATION NEIGHBOR PARTITIONS ' ||
        '  DISTANCE ' || l_distance_type                  || 
        '  WITH TARGET ACCURACY 95 '                      ||
        '  PARALLEL 4';

    -- DROP oracle text index if exists
    EXECUTE IMMEDIATE 
      'SELECT count(*) FROM user_indexes ' ||
      '  WHERE index_type = ''DOMAIN'' AND index_name = :1'
      INTO l_count USING l_text_index_name;
    IF l_count > 0 THEN
      EXECUTE IMMEDIATE 
        'DROP INDEX ' || l_text_index_name || ' PURGE';
    END IF; 

    -- Create oracle text index
    EXECUTE IMMEDIATE
      'CREATE SEARCH INDEX ' || l_text_index_name || ' ON ' || 
      l_vector_table_name ||
      '(CONTENT)';  
  END create_vector_table;


  -----------------------------------------------------------------------------
  -- unset_object: remove an object from the vector table for an agent team
  -----------------------------------------------------------------------------
  PROCEDURE unset_object(
    agent_team_name       IN VARCHAR2,
    obj_name              IN VARCHAR2 DEFAULT NULL,
    obj_type              IN VARCHAR2,
    owner_name            IN VARCHAR2 DEFAULT NULL
  )
  IS
    l_vector_table_name   VARCHAR2(200) := VECTOR_TABLE_PREFIX || 
                                           agent_team_name;
  BEGIN
    -- Remove the object records from inspect table and vector table. 
    -- If obj_name is null, it means remove all objects of the type and owner.
    IF obj_name IS NULL THEN
      EXECUTE IMMEDIATE 
        'DELETE FROM ' || INSPECT_OBJECTS || 
        ' WHERE agent_team_name =:1 AND owner =:2' 
          USING IN agent_team_name, owner_name;

      EXECUTE IMMEDIATE 
        'DELETE FROM ' || l_vector_table_name || 
        ' WHERE JSON_VALUE(attributes, ''$.object_owner'') =:1' 
          USING IN owner_name;
    ELSE
      EXECUTE IMMEDIATE 
        'DELETE FROM ' || INSPECT_OBJECTS || 
        ' WHERE agent_team_name =:1 AND object_name =:2 AND ' ||
        '       object_type =:3 AND owner =:4' 
          USING IN agent_team_name, obj_name, obj_type, owner_name;

      EXECUTE IMMEDIATE 
      'DELETE FROM ' || l_vector_table_name                           || 
      '   WHERE JSON_VALUE(attributes, ''$.object_name'')  =:1 AND '  ||
      '         JSON_VALUE(attributes, ''$.object_type'')  =:2 AND '  ||
      '         JSON_VALUE(attributes, ''$.object_owner'') =:3' 
          USING IN obj_name, IN obj_type, IN owner_name;
    END IF;
  END unset_object;


  -----------------------------------------------------------------------------
  -- set_object: add an object to the vector table for an agent team
  -----------------------------------------------------------------------------
  PROCEDURE set_object(
    agent_team_name       IN VARCHAR2,
    obj_name              IN VARCHAR2 DEFAULT NULL,
    obj_type              IN VARCHAR2,
    owner_name            IN VARCHAR2 DEFAULT NULL
  )
  IS
    l_object_count        NUMBER;
    l_count               NUMBER;
    l_object_name         DBMS_ID;
    l_object_type         DBMS_ID;
    l_object_owner        DBMS_ID;
    l_obj_info            inspect_object;
    l_obj_list            inspect_object_t := inspect_object_t();
    l_vector_table_name   VARCHAR2(200) := VECTOR_TABLE_PREFIX || 
                                           agent_team_name;
    l_text_index_name     VARCHAR2(200) := ORACLE_TEXT_INDEX_PREFIX || 
                                           agent_team_name;
  BEGIN
    -- Create records to store all objects to be set.
    IF obj_type != OBJECT_SCHEMA THEN
      l_obj_info := inspect_object(obj_name, obj_type, owner_name);
      l_obj_list.EXTEND(1);
      l_obj_list(l_obj_list.COUNT) := l_obj_info;
    ELSE
      -- Find all objects in the schema.
      FOR m IN (
        SELECT object_name, object_type FROM all_objects
          WHERE owner = owner_name AND 
                object_type IN (OBJECT_TABLE, OBJECT_VIEW, OBJECT_TRIGGER,
                                OBJECT_TYPE, OBJECT_FUNCTION, OBJECT_PROCEDURE,
                                OBJECT_PACKAGE, OBJECT_PACKAGE_BODY)
      ) LOOP
          IF m.object_type IN (OBJECT_TABLE, OBJECT_VIEW, OBJECT_TRIGGER,
                               OBJECT_TYPE, OBJECT_FUNCTION, OBJECT_PROCEDURE,
                               OBJECT_PACKAGE, OBJECT_PACKAGE_BODY) AND
            -- Avoid set the database_inspect package
            (m.object_type NOT IN (OBJECT_PACKAGE, OBJECT_PACKAGE_BODY) OR 
             m.object_name NOT IN (DATABASE_INSPECT_PACKAGE)) 
            AND
            -- Avoid set the pre-defined and system tables
            (m.object_type != OBJECT_TABLE OR 
              -- Internal tables for Select AI Inspect
             (m.object_name NOT IN (INSPECT_AGENT_TEAMS, 
                                    INSPECT_AGENT_TEAM_ATTRIBUTES, 
                                    INSPECT_OBJECTS) AND
              m.object_name NOT LIKE VECTOR_TABLE_PREFIX || '%' AND                    
              -- Internal tables for Select AI Agent
              m.object_name NOT IN ('ADB_CHAT_PROMPTS', 
                                    'DBTOOLS$EXECUTION_HISTORY', 
                                    'PIN_CONVERSATIONS', 
                                    'CONVERSATION_TIME') AND
              m.object_name NOT LIKE 'SYS_%'))
              -- Internal pakcage, procedures for Select AI Agent
            AND (m.object_type NOT IN (OBJECT_PACKAGE, OBJECT_PACKAGE_BODY, 
                                       OBJECT_PROCEDURE) OR
                 m.object_name NOT IN ('ADB_CHAT', 'PROCESS_PROMPT_REQUEST', 
                                       'SET_THEME_STYLE_FOR_APP', 
                                       'SET_THEME_STYLE_FOR_APP')
            )
          -- You can add more tables here that you want to skip during 
          -- schema registration.
          THEN
            l_obj_info := inspect_object(m.object_name, m.object_type, 
                                         owner_name);
            l_obj_list.EXTEND(1);
            l_obj_list(l_obj_list.COUNT) := l_obj_info;
          END IF;
        END LOOP;
    END IF;

    -- Set all objects
    FOR i IN 1..l_obj_list.COUNT LOOP
      l_obj_info := l_obj_list(i);
      l_object_name  := l_obj_info.object_name;
      l_object_type  := l_obj_info.object_type;
      l_object_owner := l_obj_info.object_owner;

      BEGIN
        -- Check if the input object is set
        EXECUTE IMMEDIATE 
        'SELECT COUNT(*) FROM ' || INSPECT_OBJECTS || 
        '   WHERE agent_team_name =:1 AND object_name =:2 AND ' ||
        '         object_type =:3 AND owner =:4' 
            INTO l_object_count USING IN agent_team_name, IN l_object_name, 
                                      IN l_object_type,   IN l_object_owner;

        -- unset object first and then set the object to update any potential 
        -- changes in metadata
        IF l_object_count > 0 THEN
          unset_object(agent_team_name  => agent_team_name, 
                       obj_name         => l_object_name, 
                       obj_type         => l_object_type, 
                       owner_name       => l_object_owner);
        END IF;

        -- Insert the record and vectorize the object        
        vectorize_object(agent_team_name  => agent_team_name,
                         obj_name         => l_object_name,
                         obj_type         => l_object_type,
                         owner_name       => l_object_owner);

        -- Insert the record to inspect table to make it visible to 
        -- list_objects tool.
        EXECUTE IMMEDIATE
          'INSERT INTO '|| INSPECT_OBJECTS ||
          ' (agent_team_name, object_name, object_type, owner) ' ||
          'VALUES (:1, :2, :3, :4)'
              USING IN agent_team_name, IN l_object_name, 
                    IN l_object_type,   IN l_object_owner;
      EXCEPTION
        WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('Getting Error When registering object -- ' ||
                               'object_name: '    || l_object_name || 
                               ', object_owner: ' || l_object_owner || 
                               ', object_type: '  || l_object_type ||
                               CHR(10) || SQLERRM);
      END;
    END LOOP;

    -- Sync up the text index
    BEGIN
      EXECUTE IMMEDIATE 
          'BEGIN ' ||
          '  CTXSYS.CTX_DDL.SYNC_INDEX(''' || l_text_index_name || '''); ' ||
          'END;';
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Sync text index failed: ' || SQLERRM);
    END;
  END set_object;


  -----------------------------------------------------------------------------
  -- create_tools: create agent tools
  -----------------------------------------------------------------------------
  PROCEDURE create_tools(
    tool_name_suffix      IN VARCHAR2
  )
  IS
    l_tool_name                 VARCHAR2(200);
    l_tool_list_objects         VARCHAR2(200) := TOOL_LIST_OBJECTS || 
                                                 tool_name_suffix;
    l_tool_list_incoming_deps   VARCHAR2(200) := TOOL_LIST_INCOMING_DEPENDENCIES || 
                                                 tool_name_suffix;
    l_tool_list_outgoing_deps   VARCHAR2(200) := TOOL_LIST_OUTGOING_DEPENDENCIES ||
                                                 tool_name_suffix;
    l_tool_retrieve_object_metadata   VARCHAR2(200) := TOOL_RETRIEVE_OBJECT_METADATA || 
                                                 tool_name_suffix;
    l_tool_retrieve_object_metadata_chunks VARCHAR2(200) := TOOL_RETRIEVE_OBJECT_METADATA_CHUNKS || 
                                                 tool_name_suffix;
    l_tool_expand_object_metadata_chunk VARCHAR2(200) := TOOL_EXPAND_OBJECT_METADATA_CHUNK || 
                                                 tool_name_suffix;
    l_tool_summarize_object VARCHAR2(200) := TOOL_SUMMARIZE_OBJECT || 
                                                 tool_name_suffix;
    l_tool_generate_pldoc VARCHAR2(200) := TOOL_GENERATE_PLDOC || 
                                                 tool_name_suffix;
  BEGIN
    -- TOOL: list_objects
    BEGIN
      DBMS_CLOUD_AI_AGENT.drop_tool(l_tool_list_objects);
    EXCEPTION 
      WHEN OTHERS THEN 
        NULL;
    END;
    DBMS_CLOUD_AI_AGENT.create_tool(
      tool_name => l_tool_list_objects,
      attributes => '{
                      "instruction": "Use this tool to retrieve a list of database objects that are accessible to your agent team in current environment. ' ||
                                     'It is typically the first tool to call when you need to discover available objects, narrow down the search scope for follow-up tools, or validate whether a specific object can be directly referenced. ' ||
                                     'The result is a JSON array where each item contains object_name, object_type, and object_owner. ' ||
                                     'If any filter arguments (object_name, object_type, object_owner) are provided, only matching objects will be returned. ' ||
                                     'If the response is an empty array, it means the object is either not registered or not visible to you (for example, private elements inside a package cannot be accessed as standalone objects).",
                      "tool_inputs": [
                        {
                          "name": "tool_name",
                          "mandatory": true,
                          "description": "The name of the current tool to call."
                        },
                        {
                          "name": "object_name",
                          "mandatory": false,
                          "description": "Optional. The object name to filter or validate."
                        },
                        {
                          "name": "object_type",
                          "mandatory": false,
                          "description": "Optional. The object type to filter for. Must be one of: [TABLE, SCHEMA, PACKAGE, PACKAGE BODY, PROCEDURE, FUNCTION, TRIGGER, VIEW, TYPE]."
                        },
                        {
                          "name": "object_owner",
                          "mandatory": false,
                          "description": "Optional. The schema/owner of the object."
                        }
                      ],
                      "function": "' || DATABASE_INSPECT_PACKAGE || '.' || TOOL_LIST_OBJECTS || '"
        }'
    );

    -- TOOL: list_incoming_dependencies
    BEGIN
        DBMS_CLOUD_AI_AGENT.drop_tool(l_tool_list_incoming_deps);
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    DBMS_CLOUD_AI_AGENT.create_tool(
        tool_name => l_tool_list_incoming_deps,
        attributes => '{
                        "instruction": "Use this tool to trace the *incoming* dependencies of a specified object. ' ||
                                      'Incoming dependencies are the database objects that DEPEND ON or REFERENCE the target object. ' ||
                                      'For example, given a table, this tool can list packages, procedures, functions, views, triggers, or child tables that reference it. ' ||
                                      'This is typically used for impact analysis when you are changing a table, view, or program and want to know which downstream objects might be affected. ' ||
                                      'You should first call list_objects tool to validate the object_name, object_type, and object_owner so that the correct object is identified. ' ||
                                      'The result is a JSON array, where each item represents an object that depends on (i.e., references) the specified object.",
                        "tool_inputs": [
                            {
                            "name": "object_name",
                            "mandatory": true,
                            "description": "The name of the object whose *incoming* dependencies (dependents) should be traced. Must match exactly the value returned by ' || l_tool_list_objects || '."
                            },
                            {
                            "name": "object_type",
                            "mandatory": false,
                            "description": "Optional. The type of the object. If provided, it must be one of: [TABLE, PACKAGE, PACKAGE BODY, PROCEDURE, FUNCTION, TRIGGER, VIEW, TYPE]."
                            },
                            {
                            "name": "object_owner",
                            "mandatory": false,
                            "description": "Optional. The schema (owner) of the object. Must match the owner returned by ' || l_tool_list_objects || '."
                            }
                        ],
                        "function": "' || DATABASE_INSPECT_PACKAGE || '.' || TOOL_LIST_INCOMING_DEPENDENCIES || '"
        }'
    );

    -- TOOL: list_outgoing_dependencies
    BEGIN
        DBMS_CLOUD_AI_AGENT.drop_tool(l_tool_list_outgoing_deps);
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    DBMS_CLOUD_AI_AGENT.create_tool(
        tool_name => l_tool_list_outgoing_deps,
        attributes => '{
                        "instruction": "Use this tool to trace the *outgoing* dependencies of a specified object. ' ||
                                      'Outgoing dependencies are the database objects that the target object ITSELF DEPENDS ON or REFERENCES. ' ||
                                      'For example, given a package or procedure, this tool can list the tables, views, types, and other programs that it uses. ' ||
                                      'This is typically used when you are analyzing or changing a program and want to understand which underlying tables, views, or other objects it relies on. ' ||
                                      'You should first call list_objects to validate the object_name, object_type, and object_owner so that the correct object is identified. ' ||
                                      'The result is a JSON array, where each item represents an object that the specified object depends on (i.e., its referenced objects).",
                        "tool_inputs": [
                            {
                              "name": "tool_name",
                              "mandatory": true,
                              "description": "The name of the current tool to call."
                            },
                            {
                            "name": "object_name",
                            "mandatory": true,
                            "description": "The name of the object whose *outgoing* dependencies (referenced objects) should be traced. Must match exactly the value returned by ' || l_tool_list_objects || '."
                            },
                            {
                            "name": "object_type",
                            "mandatory": false,
                            "description": "Optional. The type of the object. If provided, it must be one of: [TABLE, PACKAGE, PACKAGE BODY, PROCEDURE, FUNCTION, TRIGGER, VIEW, TYPE]."
                            },
                            {
                            "name": "object_owner",
                            "mandatory": false,
                            "description": "Optional. The schema (owner) of the object. Must match the owner returned by ' || l_tool_list_objects || '."
                            }
                        ],
                        "function": "' || DATABASE_INSPECT_PACKAGE || '.' || TOOL_LIST_OUTGOING_DEPENDENCIES || '"
        }'
    );

    -- TOOL: retrieve_object_metadata
    BEGIN
      DBMS_CLOUD_AI_AGENT.drop_tool(l_tool_retrieve_object_metadata);
    EXCEPTION 
      WHEN OTHERS THEN 
        NULL;
    END; 
    DBMS_CLOUD_AI_AGENT.create_tool(
      tool_name => l_tool_retrieve_object_metadata,
      attributes => '{
                      "instruction": "Use this tool to retrieve the full metadata (DDL) of a specified database object. ' ||
                                     'This is useful when you need to inspect the complete definition of an object (for example, table structure, trigger definition, or a standalone procedure/function) as part of a code analysis or impact assessment. ' ||
                                     'It is recommended to use this tool directly for relatively small object types such as: [TABLE, VIEW, TRIGGER, PROCEDURE, FUNCTION, TYPE], because their metadata is usually compact and unlikely to exceed the LLM token limit. ' ||
                                     'However, for large objects such as PACKAGE, PACKAGE BODY, or SCHEMA-level metadata, the result can be very large and may exceed the LLM''s token budget. For these cases, only call retrieve_object_metadata when you truly need the full DDL; otherwise, prefer using retrieve_object_metadata_chunks (optionally scoped by object_list) and expand_object_metadata_chunk to retrieve just the relevant code sections. ' ||
                                     'Before calling this tool, you should always identify and validate the correct object_name, object_type, and object_owner using ' || l_tool_list_objects || ' (or ' || l_tool_list_incoming_deps || ' or ' || l_tool_list_outgoing_deps || ' when doing impact analysis).",
                      "tool_inputs": [
                            {
                              "name": "tool_name",
                              "mandatory": true,
                              "description": "The name of the current tool to call."
                            },
                            {
                              "name": "object_name",
                              "mandatory": true,
                              "description": "The exact name of the object whose metadata should be retrieved. Must match the value returned by ' || l_tool_list_objects || ', ' || l_tool_list_incoming_deps || ' or ' || l_tool_list_outgoing_deps || '."
                            },
                            {
                              "name": "object_type",
                              "mandatory": true,
                              "description": "The type of the object. Must match the value returned by ' || l_tool_list_objects || ', ' || l_tool_list_incoming_deps || ' or ' || l_tool_list_outgoing_deps || '."
                            },
                            {
                              "name": "object_owner",
                              "mandatory": true,
                              "description": "The schema (owner) of the object. Must match the value returned by ' || l_tool_list_objects || ', ' || l_tool_list_incoming_deps || ' or ' || l_tool_list_outgoing_deps || '."
                            }
                          ],
                          "function": "' || DATABASE_INSPECT_PACKAGE || '.' || TOOL_RETRIEVE_OBJECT_METADATA || '"
        }'
    );

    -- Tool: retrieve_object_metadata_chunks
    BEGIN
      DBMS_CLOUD_AI_AGENT.drop_tool(l_tool_retrieve_object_metadata_chunks);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    DBMS_CLOUD_AI_AGENT.create_tool(
      tool_name => l_tool_retrieve_object_metadata_chunks,
      attributes => '{
                      "instruction": "Use this tool to retrieve a list of PL/SQL code snippets or metadata blocks from the vector index that may help answer the user_question. ' ||
                                    'The tool performs semantic search using the user_question, and optionally Oracle Text search when a keyword is provided. ' ||
                                    'Providing a keyword is recommended whenever possible, as it significantly improves search accuracy and helps surface the most relevant code segments. ' ||
                                    'The keyword MUST follow Oracle Text syntax and be wrapped in braces, for example: ''{keyword_1}''. ' ||
                                    'To specify multiple keywords, you may use logical expressions such as ''{keyword_1} OR {keyword_2}'' or ''{keyword_1} AND {keyword_2}''. ' ||
                                    'If object_list is provided, search results are further restricted to the specified objects. ' ||
                                    'Each returned JSON item contains: the code snippet (data), metadata including object_owner, object_name, object_type, and content_index, as well as scoring information used to rank the results. ' ||
                                    'Do not rely solely on the score when selecting relevant snippets; always inspect the actual content in the data field.",
                      "tool_inputs": [
                        {
                          "name": "tool_name",
                          "mandatory": true,
                          "description": "The name of the current tool to call."
                        },
                        {
                          "name": "user_question",
                          "mandatory": true,
                          "description": "The natural-language question or prompt whose embedding will be used for semantic vector search."
                        },
                        {
                          "name": "keyword",
                          "mandatory": false,
                          "description": "Optional Oracle Text query expression. Must be formatted with braces (e.g., ''{keyword_1}''). Multiple keywords may be combined (''{keyword_1} OR {keyword_2}'' or ''{keyword_1} AND {keyword_2}''). ' ||
                                        'Providing a keyword is recommended for improving search accuracy."
                        },
                        {
                          "name": "object_list",
                          "mandatory": false,
                          "description": "Optional JSON array that restricts results to specific database objects, for example: [{\"object_owner\":\"<object_owner>\",\"object_name\":\"<object_name>\",\"object_type\":\"<object_type>\"}]. ' ||
                                        'The values for object_owner, object_name, and object_type should be retrieved and validated from tools such as ' || l_tool_list_objects || ' or ' || l_tool_list_incoming_deps || ' or ' || l_tool_list_outgoing_deps || ' before calling this tool."
                        }
                      ],
                      "function": "' || DATABASE_INSPECT_PACKAGE || '.' || TOOL_RETRIEVE_OBJECT_METADATA_CHUNKS || '"
      }'
    );

    -- Tool: expand_object_metadata_chunk
    BEGIN
      DBMS_CLOUD_AI_AGENT.drop_tool(l_tool_expand_object_metadata_chunk);
    EXCEPTION WHEN OTHERS THEN NULL;
    END; 
    DBMS_CLOUD_AI_AGENT.create_tool(
      tool_name => l_tool_expand_object_metadata_chunk,
      attributes => '{
                      "instruction": "Use this tool to retrieve the surrounding source-code section for a snippet selected from the ' || l_tool_retrieve_object_metadata_chunks || ' tool''s response. ' ||
                                    'Note: For the input value, you must use the exact values of object_name, object_owner, object_type in the selected json object response from ' || l_tool_retrieve_object_metadata_chunks || ' tool. ' ||
                                    'If multiple code snippets are selected from the ' || l_tool_retrieve_object_metadata_chunks || ' response, call this tool separately for each one. ' ||
                                    'Behavior: the tool returns the code block centered around the specified content_index and may include surrounding lines not strictly limited to the target function or procedure. ' ||
                                    'If the returned section does not include the full function or procedure, retry with a larger search_range value (up to a maximum of 100). ' ||
                                    'If multiple nearby snippets are relevant (adjacent content_index values), increase search_range so that the combined region is captured. ",
                      "tool_inputs": [
                        {
                          "name": "tool_name",
                          "mandatory": true,
                          "description": "The name of the current tool to call."
                        },
                        {
                          "name": "object_name",
                          "mandatory": true,
                          "description": "The name of the database object that contains the source code.  Value must exactly match the one from the ''object_name'' field in the selected JSON item of the ' || l_tool_retrieve_object_metadata_chunks || ' response."
                        },
                        {
                          "name": "object_type",
                          "mandatory": true,
                          "description": "The type of the object. Value must exactly must the one from the ''object_type'' field in the selected JSON item of the ' || l_tool_retrieve_object_metadata_chunks || ' response. "
                        },
                        {
                          "name": "object_owner",
                          "mandatory": true,
                          "description": "The schema or owner of the object. Value must exactly must the one from the ''object_owner'' field in the selected JSON item of the ' || l_tool_retrieve_object_metadata_chunks || ' response. "
                        },
                        {
                          "name": "content_index",
                          "mandatory": true,
                          "description": "The numeric index of the snippet code in the object. Value must exactly must the one from the ''content_index'' field in the selected JSON item of the ' || l_tool_retrieve_object_metadata_chunks || ' response. "
                        },
                        {
                          "name": "search_range",
                          "mandatory": false,
                          "description": "Optional. The number of code chunks to include before and after the content_index (default = 5, maximum = 100)."
                        }
                      ],
                      "function": "' || DATABASE_INSPECT_PACKAGE || '.' || TOOL_EXPAND_OBJECT_METADATA_CHUNK || '"
      }'
    );

    -- Tool: summarize_object
    BEGIN
      DBMS_CLOUD_AI_AGENT.drop_tool(l_tool_summarize_object);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    DBMS_CLOUD_AI_AGENT.create_tool(
      tool_name => l_tool_summarize_object,
      attributes => '{
        "instruction": "Use this tool to generate a concise, high-level natural-language summary for a single Oracle object (PACKAGE, PACKAGE BODY, PROCEDURE, FUNCTION, TRIGGER, VIEW, TYPE, or TABLE). ' ||
                       'It retrieves the full object metadata internally, automatically split large objects into smaller chunks before sending them to the LLM to avoid token-limit issues, and returns a brief summary. ' ||
                       'Use this tool when the user explicitly asks to summarize or explain what a specific object does. ' ||
                       'Do NOT use this tool for SCHEMA-level summarization or for summarizing multiple objects at once. This tool is not intended for private procedures or functions inside a package that are not exposed as top-level objects. ' ||
                       'The value for arguments object_name, object_type, and object_owner should be validated or retrieved from tools such as ' || l_tool_list_objects || ', ' || l_tool_list_incoming_deps || ', or ' || l_tool_list_outgoing_deps || '. Do not invent or guess them from natural-language input. ' ||
                       'If the user asks a broad question requiring contextual or cross-object reasoning, rely on the agent''s own reasoning (optionally using ' || l_tool_retrieve_object_metadata || ' and ' || l_tool_retrieve_object_metadata_chunks || ') instead of this tool.",
        "tool_inputs": [
                        {
                          "name": "tool_name",
                          "mandatory": true,
                          "description": "The name of the current tool to call."
                        },
                        {
                          "name": "object_name",
                          "mandatory": true,
                          "description": "Exact object name. This value should match exactly the object_name returned by tools such as ' || l_tool_list_objects || ', ' || l_tool_list_incoming_deps || ', or ' || l_tool_list_outgoing_deps || '."
                        },
                        {
                          "name": "object_type",
                          "mandatory": true,
                          "description": "Object type. Must be one of: PACKAGE, PACKAGE BODY, PROCEDURE, FUNCTION, TRIGGER, VIEW, TYPE, or TABLE (SCHEMA is not supported). This value should match exactly the object_type returned by the discovery tools."
                        },
                        {
                          "name": "object_owner",
                          "mandatory": true,
                          "description": "Schema or owner of the object. This value should match exactly the object_owner returned by the discovery tools."
                        },
                        {
                          "name": "user_prompt",
                          "mandatory": false,
                          "description": "Optional instructions to customize the summary''s tone or focus."
                        }
                      ],
                      "function": "' || DATABASE_INSPECT_PACKAGE || '.' || TOOL_SUMMARIZE_OBJECT || '"
      }'
    );

    -- Tool: generate_pldoc
    BEGIN
      DBMS_CLOUD_AI_AGENT.drop_tool(l_tool_generate_pldoc);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    DBMS_CLOUD_AI_AGENT.create_tool(
      tool_name => l_tool_generate_pldoc,
      attributes => '{
                      "instruction": "Use this tool to generate a PLDoc-style documentation block for a single Oracle object (PACKAGE, PACKAGE BODY, PROCEDURE, FUNCTION, TRIGGER, VIEW, TYPE, or TABLE). ' ||
                                     'It retrieves the object metadata internally, truncates large objects before sending them to the LLM to avoid token-limit issues, and returns ONLY the PLDoc block (/** ... */). ' ||
                                     'Use this tool when the user explicitly asks for PLDoc comments or formal documentation for an object. ' ||
                                     'This tool does not support SCHEMA-level documentation or multi-object documentation. ' ||
                                     'The value for arguments object_name, object_type, and object_owner should be validated or retrieved from tools such as ' || l_tool_list_objects || ', ' || l_tool_list_incoming_deps || ', or ' || l_tool_list_outgoing_deps || '. Do not invent or guess them from natural-language input. ' ||
                                     'Do NOT use this tool when the user is asking for contextual explanation, architectural analysis, or broad reasoning across multiple objects; those are better handled directly by the agent, potentially using ' || l_tool_retrieve_object_metadata || ', ' || l_tool_retrieve_object_metadata_chunks || ', and ' || l_tool_expand_object_metadata_chunk || ' for additional context.",
                      "tool_inputs": [
                        {
                          "name": "tool_name",
                          "mandatory": true,
                          "description": "The name of the current tool to call."
                        },
                        {
                          "name": "object_name",
                          "mandatory": true,
                          "description": "Exact object name for which PLDoc documentation should be generated. This value should match exactly the object_name returned by discovery tools such as ' || l_tool_list_objects || ', ' || l_tool_list_incoming_deps || ', or ' || l_tool_list_outgoing_deps || '."
                        },
                        {
                          "name": "object_type",
                          "mandatory": true,
                          "description": "Object type. Must be one of: PACKAGE, PACKAGE BODY, PROCEDURE, FUNCTION, TRIGGER, VIEW, TYPE, or TABLE (SCHEMA is not supported). This value should match exactly the object_type returned by the discovery tools."
                        },
                        {
                          "name": "object_owner",
                          "mandatory": true,
                          "description": "Schema or owner of the object. This value should match exactly the object_owner returned by the discovery tools."
                        },
                        {
                          "name": "user_prompt",
                          "mandatory": false,
                          "description": "Optional instructions for customizing tone or level of detail in the PLDoc block."
                        }
                      ],
                      "function": "' || DATABASE_INSPECT_PACKAGE || '.' || TOOL_GENERATE_PLDOC || '"
      }'
    );
  END create_tools;


  -----------------------------------------------------------------------------
  -- create_agent_team: create agent team
  -----------------------------------------------------------------------------
  PROCEDURE create_agent_team(
    profile_name      IN VARCHAR2,
    agent_team_name   IN VARCHAR2
  )
  IS
    l_count               NUMBER;
    l_agent_name          DBMS_ID := INSPECT_AGENT_PREFIX || '_' || 
                                     agent_team_name;
    l_task_name           DBMS_ID := INSPECT_AGENT_TASK_PREFIX || '_' || 
                                     agent_team_name;
    l_task_instruction    CLOB;
    l_tool_name_suffix    VARCHAR2(200);
    l_agent_team_id       NUMBER;
    l_attr                JSON_OBJECT_T;
    l_tools               JSON_ARRAY_T := JSON_ARRAY_T('[]');
  BEGIN
    l_tool_name_suffix := generate_tool_name_suffix(agent_team_name);

    -- Validate if agent already exists
    EXECUTE IMMEDIATE 
        'SELECT COUNT(*) FROM user_ai_agents WHERE agent_name = :1' 
        INTO l_count 
        USING l_agent_name;

    -- STEP 1: Create agent
    IF l_count = 0 THEN
      BEGIN
        DBMS_CLOUD_AI_AGENT.drop_agent(l_agent_name);
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
      
      DBMS_CLOUD_AI_AGENT.create_agent(
        agent_name => l_agent_name,
        attributes => '{
          "profile_name": "' || profile_name || '",
          "role": "You are a knowledgeable Oracle database expert ' ||
                  'assisting with a wide range of database related tasks."
        }'
      );
    END IF;

    -- STEP 2: Recreate tools on every team creation to avoid stale task/tool
    -- state where existing task names can skip tool recreation.
    create_tools(l_tool_name_suffix);

    -- STEP 3: Recreate task so its tool list is always aligned to the current
    -- suffix and recreated tool objects.
    BEGIN
      DBMS_CLOUD_AI_AGENT.drop_task(l_task_name);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    
      l_task_instruction := 
            'The user''s request is: {query}. Analyze the request to determine the specific Oracle database and PL/SQL codebase task being asked (for example, ' ||
            'finding all programs that reference a column, assessing the impact of a logic change, or explaining how a program uses a particular field). ' ||
            'Use the available tools to gather the necessary context from the codebase before forming your answer. ' ||

            'Tool usage and strategy: ' ||
            '  - Object discovery and validation: When the user references specific objects (such as tables, packages, procedures, or views), ' ||
            'first call {list_objects} to validate object_name, object_type, and object_owner, and to narrow down the set of relevant objects. ' ||
            'Do not invent or guess object names, owners, or types. Note that {list_objects} only lists top-level database objects and does ' ||
            'NOT include private procedures or functions inside a package; if you need to identify or analyze private routines, or you do not find expected object ' ||
            'from {list_objects}, use {retrieve_object_metadata_chunks} (optionally with a validated object_list) followed by {expand_object_metadata_chunk} to inspect the ' ||
            'package''s internal implementation. ' ||

            '  - Case sensitivity and strict reuse of returned values: Whenever you use an object returned by a tool such as {list_objects}, {list_incoming_dependencies}, ' ||
            '{list_outgoing_dependencies}, or any other discovery tool, you must use the exact values for object_name, object_owner, and object_type exactly as returned by the tool. ' ||
            'These fields are case sensitive and must not be altered, reformatted, uppercased, lowercased, inferred from the code text, or reconstructed manually. ' ||
            'Always copy these values directly from the tool response into follow-up tool calls such as {retrieve_object_metadata_chunks}, {expand_object_metadata_chunk}, or {retrieve_object_metadata}. ' ||

            '  - Dependency and impact analysis: For questions about cross-object usage or impact analysis, use the two dependency tools in a complementary way: ' ||
            '      * Use {list_incoming_dependencies} to find *incoming* dependencies: objects that depend on or reference the target object (for example, programs that ' ||
            'read from a table, views built on a table, or child tables with foreign keys). This is useful when the user is changing a table, view, or API and wants ' ||
            'to know which downstream objects might break or need to be updated. ' ||
            '      * Use {list_outgoing_dependencies} to find *outgoing* dependencies: objects that the target object itself depends on or references (for example, tables, ' ||
            'views, or other packages used by a given package or procedure). This is useful when the user asks how a program works internally, which data sources it uses, ' ||
            'or what other components it calls. ' ||
            '    Use these validated dependency lists together with {list_objects} to build the object_list argument for {retrieve_object_metadata_chunks} when you need to ' ||
            'constrain vector search to a concrete set of related objects. ' ||

            '  - Keyword usage for {retrieve_object_metadata_chunks}: When searching code with {retrieve_object_metadata_chunks}, provide a keyword whenever possible to improve search accuracy. ' ||
            'The keyword must follow Oracle Text syntax and must be wrapped in braces, for example: ''{<keyword_1>}''. To specify multiple keywords, use expressions ' ||
            'like ''{<keyword_1>} OR {<keyword_2>}'' or ''{<keyword_1>} AND {<keyword_2>}''). Do not pass raw text (such as a bare column name) without braces as the keyword. ' ||

            '  - object_list usage for {retrieve_object_metadata_chunks}: The object_list parameter is optional, but when you do use it, it must always be a valid JSON array of JSON objects, ' ||
            'each containing key-value pairs for object_owner, object_name, and object_type. Conceptually: [{\"object_owner\":\"<object_owner>\",\"object_name\":\"<object_name>\",\"object_type\":\"<object_type>\"}]. ' ||
            'You must not pass a plain string such as ''<OBJECT_NAME>'' as object_list. Note: You CANNOT provide an empty JSON array. If no object list to provide, just provide NULL value. ' ||
            '    Before using object_list, you must retrieve and validate the object_owner, object_name, and object_type values from tools such as {list_objects}, ' ||
            '{list_incoming_dependencies}, or {list_outgoing_dependencies}. Do not invent or infer these values purely from natural language. If you do not have a validated list of ' ||
            'objects, call {retrieve_object_metadata_chunks} without object_list instead of guessing. ' ||

            '  - Code search and context expansion: Use {retrieve_object_metadata_chunks} to identify relevant PL/SQL snippets or metadata blocks, guided by user_question, keyword, and ' ||
            'optionally object_list. Once you identify promising snippets, call {expand_object_metadata_chunk} to retrieve the broader source-code context around those snippets ' ||
            '(for example, entire procedures or functions) before drawing conclusions. If you decide to use multiple snippets from the {retrieve_object_metadata_chunks} response, ' ||
            'invoke {expand_object_metadata_chunk} individually for each snippet. ' ||
            '    When calling {expand_object_metadata_chunk}, the values for object_name, object_owner, object_type, and content_index must exactly match the corresponding fields in the ' ||
            'selected JSON item from the {retrieve_object_metadata_chunks} response. Do not derive or guess these values from the code text in the data field; always copy them directly from ' ||
            'the structured attributes. ' ||

            '  - Full object metadata: When you need the full definition of a relatively small object (TABLE, VIEW, TRIGGER, PROCEDURE, FUNCTION, TYPE), you may call ' ||
            '{retrieve_object_metadata} directly, since these are usually small enough not to exceed the LLM''s token limit. For large objects such as PACKAGE, PACKAGE BODY, or ' ||
            'SCHEMA-level metadata, avoid calling {retrieve_object_metadata} unless you truly need the full DDL. Prefer using {retrieve_object_metadata_chunks} (optionally with a validated ' ||
            'object_list) plus {expand_object_metadata_chunk} to stay within token limits while focusing on relevant regions of code. ' ||

            '  - Documentation and summarization: For single-object descriptions or PLDoc-style documentation, use the specialized tools in a scoped way: ' ||
            '      * Use {summarize_object} to produce a concise, high-level natural-language summary of a single object when the user explicitly asks what that object does or requests a short summary. ' ||
            'This tool retrieves metadata internally and truncates large objects before sending them to the LLM. It does not support SCHEMA-level or multi-object summarization. ' ||
            'Before calling {summarize_object}, you should usually use {list_objects} (or {list_incoming_dependencies} or {list_outgoing_dependencies}) to discover and validate the object, ' ||
            'and the values for object_name, object_type, and object_owner must match the values returned by those tools. ' ||
            '      * Use {generate_pldoc} when the user explicitly asks for PLDoc-style documentation for a specific object. This tool returns ONLY the PLDoc block (/** ... */) and does not include the code. ' ||
            'It does not support SCHEMA-level documentation or generating documentation for multiple objects at once. As with {summarize_object}, object_name, object_type, and object_owner ' ||
            'must match the values returned by discovery tools such as {list_objects}, {list_incoming_dependencies}, or {list_outgoing_dependencies}. ' ||
            '      * Distinguish between tool-based summarization and broader contextual reasoning: when the user''s question requires cross-object analysis, architectural explanation, or a narrative that ' ||
            'depends on prior conversation context, rely on the agent''s own reasoning (optionally using {retrieve_object_metadata}, {retrieve_object_metadata_chunks}, and {expand_object_metadata_chunk}) instead of these ' ||
            'documentation/summarization tools. Use the tools only to generate focused, single-object summaries or documentation blocks. ' ||

            'Handling empty or partial results: ' ||
            '  - If {retrieve_object_metadata_chunks} returns an empty result, treat this as "no relevant matches found for this particular search configuration," not as proof that no such ' ||
            'code exists in the database. Before concluding that something does not exist, consider adjusting the keyword, removing or broadening object_list, or using other tools ' ||
            '(such as {list_objects}, {list_incoming_dependencies}, {list_outgoing_dependencies}, or {retrieve_object_metadata}) to explore further. ' ||
            '  - Only state that no relevant references or programs exist when you have performed reasonable searches (for example, tried without overly restrictive object_list ' ||
            'and with appropriate keywords) and still found no evidence. If you are uncertain, explicitly say that no relevant matches were found in the searched scope, rather than ' ||
            'asserting that nothing exists. ' ||

            'Handling error from {list_objects}: ' ||
            '  - If you receive an error indicating that the output of {list_objects} exceeds 200,000 characters, it means too many objects are registered and the result is too large for efficient LLM processing. ' ||
            'To reduce the scope, provide a specific object_name to filter the results, or use {retrieve_object_metadata_chunks} tool to do a vector search and retrieve the relevant object information instead. ' ||

            'Answer construction: ' ||
            '  - Explain your reasoning in terms of the relevant objects and code regions you inspected. Summarize what each key program or object does and how it uses the fields or ' ||
            'logic mentioned in the user''s request. ' ||
            '  - For impact assessment questions, use {list_incoming_dependencies} to identify the affected programs/objects, describe how they depend on the changed behavior, and outline ' ||
            'the changes or validations that would be required. Use {list_outgoing_dependencies} to explain the internal dependencies of the object being modified (for example, which tables or ' ||
            'packages it relies on) and how that shapes the risk and testing scope. ' ||

            'Response format: ' ||
            '  - Present results in a well-structured, readable layout with sections, bullet lists, and tables where helpful. Add one empty line between major sections. ' ||
            '  - If you are using {retrieve_object_metadata_chunks} and {expand_object_metadata_chunk} to gather results, indicate whether your findings likely cover all relevant code. If you are unsure, add a ' ||
            'brief note that the list may not be exhaustive. ' ||
            '  - If no relevant results are found, or if no issues are detected, provide a short, concise message clearly stating that outcome, and, when appropriate, mention what search steps you performed.';
      
    l_task_instruction := REPLACE(l_task_instruction, '{list_objects}', TOOL_LIST_OBJECTS || l_tool_name_suffix);
    l_task_instruction := REPLACE(l_task_instruction, '{list_incoming_dependencies}', TOOL_LIST_INCOMING_DEPENDENCIES || l_tool_name_suffix);
    l_task_instruction := REPLACE(l_task_instruction, '{list_outgoing_dependencies}', TOOL_LIST_OUTGOING_DEPENDENCIES || l_tool_name_suffix);
    l_task_instruction := REPLACE(l_task_instruction, '{retrieve_object_metadata}', TOOL_RETRIEVE_OBJECT_METADATA || l_tool_name_suffix);
    l_task_instruction := REPLACE(l_task_instruction, '{retrieve_object_metadata_chunks}', TOOL_RETRIEVE_OBJECT_METADATA_CHUNKS || l_tool_name_suffix);
    l_task_instruction := REPLACE(l_task_instruction, '{expand_object_metadata_chunk}', TOOL_EXPAND_OBJECT_METADATA_CHUNK || l_tool_name_suffix);
    l_task_instruction := REPLACE(l_task_instruction, '{summarize_object}', TOOL_SUMMARIZE_OBJECT || l_tool_name_suffix);
    l_task_instruction := REPLACE(l_task_instruction, '{generate_pldoc}', TOOL_GENERATE_PLDOC || l_tool_name_suffix);

    l_tools.append(TOOL_LIST_OBJECTS || l_tool_name_suffix);
    l_tools.append(TOOL_LIST_INCOMING_DEPENDENCIES || l_tool_name_suffix);
    l_tools.append(TOOL_LIST_OUTGOING_DEPENDENCIES || l_tool_name_suffix);
    l_tools.append(TOOL_RETRIEVE_OBJECT_METADATA || l_tool_name_suffix);
    l_tools.append(TOOL_RETRIEVE_OBJECT_METADATA_CHUNKS || l_tool_name_suffix);
    l_tools.append(TOOL_EXPAND_OBJECT_METADATA_CHUNK || l_tool_name_suffix);
    l_tools.append(TOOL_SUMMARIZE_OBJECT || l_tool_name_suffix);
    l_tools.append(TOOL_GENERATE_PLDOC || l_tool_name_suffix);

    l_attr := JSON_OBJECT_T('{}');
    l_attr.put('instruction', l_task_instruction);
    l_attr.put('enable_human_tool', FALSE);
    l_attr.put('tools', l_tools);

    DBMS_CLOUD_AI_AGENT.create_task(
      task_name   => l_task_name,
      attributes  => l_attr.to_clob
    );

    -- STEP 4: Create Team
    DBMS_CLOUD_AI_AGENT.create_team(
      team_name  => agent_team_name,
      attributes => '{"agents": [{"name":"' || l_agent_name || 
                      '","task" : "' || l_task_name || '"}],
                      "process": "sequential"}'
    );
  END create_agent_team;


  -----------------------------------------------------------------------------
  -- drop_agent_team: drop agent team
  -----------------------------------------------------------------------------
  PROCEDURE drop_agent_team(
    agent_team_name   IN VARCHAR2
  )
  IS
    l_agent_name          DBMS_ID := INSPECT_AGENT_PREFIX || '_' || 
                                     agent_team_name;
    l_task_name           DBMS_ID := INSPECT_AGENT_TASK_PREFIX || '_' || 
                                     agent_team_name;
    l_tool_name_suffix    VARCHAR2(200);
  BEGIN
    l_tool_name_suffix := generate_tool_name_suffix(agent_team_name);

    -- Drop agent team
    DBMS_CLOUD_AI_AGENT.drop_team(agent_team_name, true);

    -- Drop agent
    DBMS_CLOUD_AI_AGENT.drop_agent(l_agent_name, true);

    -- Drop agent task
    DBMS_CLOUD_AI_AGENT.drop_task(l_task_name, true);

    -- Drop tools
    DBMS_CLOUD_AI_AGENT.drop_tool(TOOL_LIST_OBJECTS || l_tool_name_suffix,
                                  true);
    DBMS_CLOUD_AI_AGENT.drop_tool(TOOL_LIST_INCOMING_DEPENDENCIES || 
                                  l_tool_name_suffix,
                                  true);
    DBMS_CLOUD_AI_AGENT.drop_tool(TOOL_LIST_OUTGOING_DEPENDENCIES || 
                                  l_tool_name_suffix,
                                  true);
    DBMS_CLOUD_AI_AGENT.drop_tool(TOOL_RETRIEVE_OBJECT_METADATA || 
                                  l_tool_name_suffix,
                                  true);
    DBMS_CLOUD_AI_AGENT.drop_tool(TOOL_RETRIEVE_OBJECT_METADATA_CHUNKS || 
                                  l_tool_name_suffix,
                                  true);
    DBMS_CLOUD_AI_AGENT.drop_tool(TOOL_EXPAND_OBJECT_METADATA_CHUNK || 
                                  l_tool_name_suffix,
                                  true);
    DBMS_CLOUD_AI_AGENT.drop_tool(TOOL_SUMMARIZE_OBJECT || 
                                  l_tool_name_suffix,
                                  true);
    DBMS_CLOUD_AI_AGENT.drop_tool(TOOL_GENERATE_PLDOC || 
                                  l_tool_name_suffix,
                                  true);
  END drop_agent_team;


  -----------------------------------------------------------------------------
  -- parse_attributes: helper function to parse and validate the JSON 
  -- attributes for agent team
  -----------------------------------------------------------------------------
  FUNCTION parse_attributes(
    attributes          IN CLOB
  ) RETURN JSON_OBJECT_T
  IS
    l_attributes        JSON_OBJECT_T;
    l_parsed_attributes JSON_OBJECT_T := JSON_OBJECT_T('{}');
    l_dummy             CLOB;
    l_keys              JSON_KEY_LIST;
    l_key               DBMS_ID;
    l_key_processed     DBMS_ID;
    l_value             CLOB;
    l_invalid_attribute EXCEPTION;
    l_missing_value     EXCEPTION;
    l_invalid_value     EXCEPTION;
    l_value_too_long    EXCEPTION;
  BEGIN
    IF attributes IS NULL THEN
      l_attributes := JSON_OBJECT_T('{}');
    ELSE
      BEGIN
        EXECUTE IMMEDIATE
          'SELECT 1 FROM SYS.DUAL WHERE ' ||
          'JSON_SERIALIZE(:1 RETURNING CLOB) IS JSON WITH UNIQUE KEYS'
          INTO l_dummy
          USING IN attributes;

        l_attributes := JSON_OBJECT_T(attributes);
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          raise_application_error(
                -20000, 'Duplicate keys found in attributes.');
        WHEN OTHERS THEN
          raise_application_error(
                -20000, 'Invalid attributes argument.' );
      END;
    END IF;

    l_keys := l_attributes.get_keys;
    IF l_keys IS NULL THEN
      RETURN l_attributes;
    END IF;

    FOR i IN 1..l_keys.COUNT LOOP
      l_key := l_keys(i);
      l_key_processed := LOWER(TRIM(l_keys(i)));

      -- Check whether the key is duplicated, ignoring case differences
      IF l_parsed_attributes.has(l_key_processed) THEN
        raise_application_error(-20000, 'Duplicate attribute ' || 
                                l_key_processed || ' found.');
      END IF;

      IF l_attributes.get(l_key).is_null() THEN
        l_value := NULL;
      ELSIF l_attributes.get(l_key).is_array() THEN
        l_value := l_attributes.get_array(l_key).to_clob;
      ELSE
        l_value := TRIM(l_attributes.get_clob(l_key));
      END IF;

      BEGIN
        CASE l_key_processed
          WHEN 'profile_name' THEN
            IF l_value IS NULL THEN
              RAISE l_missing_value;
            END IF;

            DECLARE
              l_profile_name        DBMS_ID;
              l_profile_attributes  JSON_OBJECT_T;
              l_provider            DBMS_ID;
            BEGIN
              l_profile_name := validate_profile_name(l_value);
              l_profile_attributes := get_profile_attributes(l_profile_name);
              l_provider := LOWER(l_profile_attributes.get_string('provider'));

              IF l_provider NOT IN (PROVIDER_OPENAI, PROVIDER_COHERE, 
                                    PROVIDER_AZURE, PROVIDER_OCI, PROVIDER_AWS, 
                                    PROVIDER_GOOGLE, PROVIDER_DATABASE) 
              THEN
                raise_application_error(-20000,
                  INITCAP(l_provider) || ' is not supported for this agent ' ||
                  'since it is not supported for vector embedding.');
              END IF;

              l_parsed_attributes.put(l_key_processed, l_profile_name);
            END;
          
          WHEN 'object_list' THEN
            IF l_value IS NULL THEN
              RAISE l_missing_value;
            END IF;

            DECLARE
              l_obj_list            JSON_ARRAY_T;
              l_curr_obj            JSON_OBJECT_T;
              l_obj_keys            JSON_KEY_LIST;
              l_obj_key             DBMS_ID;
              l_curr_obj_processed  JSON_OBJECT_T;
              l_obj_list_processed  JSON_ARRAY_T := JSON_ARRAY_T();
              l_obj_type            DBMS_ID;
              l_obj_name            DBMS_ID;
              l_obj_owner           DBMS_ID;
              l_count               NUMBER;
            BEGIN
              l_obj_list := JSON_ARRAY_T(l_value);
              FOR i IN 0..l_obj_list.get_size - 1 LOOP
                l_curr_obj := JSON_OBJECT_T(l_obj_list.get(i));
                l_curr_obj_processed := JSON_OBJECT_T();
                l_obj_keys := l_curr_obj.get_keys;

                FOR j IN 1..l_obj_keys.COUNT LOOP
                  l_obj_key := LOWER(TRIM(l_obj_keys(j)));
                  IF l_obj_key NOT IN ('owner', 'name', 'type') THEN
                    RAISE l_invalid_value;
                  END IF;

                  l_curr_obj_processed.put(l_obj_key, 
                                           l_curr_obj.get(l_obj_keys(j)));
                END LOOP;

                l_obj_type  := UPPER(TRIM(
                                    l_curr_obj_processed.get_string('type')));
                l_obj_name  := TRIM(
                                    l_curr_obj_processed.get_string('name'));
                l_obj_owner := TRIM(
                                    l_curr_obj_processed.get_string('owner'));
              
                IF l_obj_type IS NULL OR
                   (l_obj_name IS NULL AND l_obj_owner IS NULL)
                THEN
                  RAISE l_invalid_value;
                END IF;

                -- Validate the object type
                IF l_obj_type NOT IN (OBJECT_TABLE, OBJECT_SCHEMA, 
                                      OBJECT_PACKAGE, OBJECT_PACKAGE_BODY, 
                                      OBJECT_PROCEDURE, OBJECT_FUNCTION, 
                                      OBJECT_TRIGGER, OBJECT_VIEW, OBJECT_TYPE)
                THEN
                  RAISE l_invalid_value;
                END IF;

                IF l_obj_owner IS NULL THEN
                  l_obj_owner := SYS_CONTEXT('USERENV', 'CURRENT_USER');
                ELSE
                  l_obj_owner := validate_object_name(l_obj_owner);
                END IF;

                IF l_obj_name IS NOT NULL AND 
                   NOT is_soda_collection(l_obj_name, l_obj_owner, 
                                          l_obj_type)
                THEN
                  l_obj_name :=validate_object_name(l_obj_name);
                END IF;

                -- Validate if we have access to the object
                IF l_obj_type = OBJECT_SCHEMA THEN
                  -- Validate if we have access to the schema
                  EXECUTE IMMEDIATE 
                     'SELECT COUNT(*) FROM all_users WHERE username = :1' 
                     INTO l_count 
                     USING l_obj_owner;
                  IF l_count = 0 THEN
                    raise_application_error(-20000, 'Schema (user) not visible or ' ||
                                                    'does not exist - ' || l_obj_owner);
                  END IF;
                ELSE
                  -- For regular objects, verify we can see it in ALL_OBJECTS
                  EXECUTE IMMEDIATE 
                     'SELECT COUNT(*) FROM all_objects WHERE owner = :1 AND ' ||
                     'object_name = :2 AND object_type = :3' 
                     INTO l_count 
                     USING l_obj_owner, l_obj_name, l_obj_type;

                  IF l_count = 0 THEN
                    raise_application_error(-20000, 'Object not found or not ' ||
                                                    'accessible - ' || l_obj_name);
                  END IF;
                END IF;

                l_curr_obj_processed.put('name', l_obj_name);
                l_curr_obj_processed.put('owner', l_obj_owner);
                l_curr_obj_processed.put('type', l_obj_type);

                l_obj_list_processed.append(l_curr_obj_processed);
              END LOOP;

              l_parsed_attributes.put(l_key_processed, l_obj_list_processed);
            END;

          -- Match limit
          WHEN 'match_limit' THEN
            IF l_value IS NULL THEN
              RAISE l_missing_value;
            END IF;

            DECLARE
              l_match_limit NUMBER;
            BEGIN
              l_match_limit := TO_NUMBER(l_value);
              IF l_match_limit <= 0 OR l_match_limit > 100 OR 
                 MOD(l_match_limit, 1) != 0 
              THEN
                RAISE l_invalid_value;
              END IF;

              l_parsed_attributes.put(l_key_processed, l_match_limit);
            EXCEPTION
              WHEN OTHERS THEN
                RAISE l_invalid_value;
            END;
          
          -- Google key
          WHEN 'google_key' THEN
            IF l_value IS NULL THEN
              RAISE l_missing_value;
            END IF;
            IF LENGTH(l_value) > 4000 THEN
              RAISE l_value_too_long;
            END IF;

            l_parsed_attributes.put(l_key_processed, l_value);

          -- Vector distance type
          WHEN 'vector_distance_type' THEN
            IF l_value IS NULL THEN
              RAISE l_missing_value;
            END IF;

            IF l_value NOT IN (VEC_DIST_COSINE, VEC_DIST_DOT, 
                               VEC_DIST_MANHATTAN, VEC_DIST_HAMMING, 
                               VEC_DIST_EUCLIDEAN, VEC_DIST_L2_SQUARED) 
            THEN
              RAISE l_invalid_value;
            END IF;

            l_parsed_attributes.put(l_key_processed, l_value);

          ELSE
            RAISE l_invalid_attribute;
        END CASE;

      EXCEPTION
        WHEN l_invalid_attribute THEN
          raise_application_error(-20000, 'Invalid attribute ' || 
              l_key_processed);
        WHEN l_missing_value THEN
          raise_application_error(-20000, 'Missing attribute value for ' || 
              l_key_processed);
        WHEN l_invalid_value THEN
          raise_application_error(-20000, 'Invalid attribute value for ' || 
              l_key_processed);
        WHEN l_value_too_long THEN
          raise_application_error(-20000, 'Attribute value is too long for ' ||
              l_key_processed);
        WHEN OTHERS THEN
          RAISE;
      END;
    END LOOP;

    RETURN l_parsed_attributes;
  END parse_attributes;


  -----------------------------------------------------------------------------
  -- check_team_exists: helper function to check if an agent team already 
  -- exists with the given name
  -----------------------------------------------------------------------------
  FUNCTION check_team_exists(
    agent_team_name         IN VARCHAR2
  ) RETURN BOOLEAN
  IS
    l_count           NUMBER;
  BEGIN
    EXECUTE IMMEDIATE 
        'SELECT COUNT(*) FROM ' || INSPECT_AGENT_TEAMS || 
        ' WHERE agent_team_name = :1' 
        INTO l_count USING agent_team_name;
    RETURN (l_count > 0);
  END check_team_exists;


    ---------------------------------------------------------------------------
    -- check_if_object_exists_in_list
    ---------------------------------------------------------------------------
    FUNCTION check_if_object_exists_in_list(
      object_list       IN JSON_ARRAY_T,
      to_check_object   IN JSON_OBJECT_T
    ) RETURN BOOLEAN
    IS
      l_owner           DBMS_ID;
      l_name            DBMS_ID;
      l_type            DBMS_ID;

      l_curr_obj        JSON_OBJECT_T;
      l_curr_obj_owner  DBMS_ID;
      l_curr_obj_name   DBMS_ID;
      l_curr_obj_type   DBMS_ID;
    BEGIN
      l_owner := to_check_object.get_string('owner');
      l_name  := to_check_object.get_string('name');
      l_type  := to_check_object.get_string('type');

      -- Loop through array
      FOR i IN 0 .. object_list.get_size - 1 LOOP
        l_curr_obj := JSON_OBJECT_T(object_list.get(i));

        l_curr_obj_owner := l_curr_obj.get_string('owner');
        l_curr_obj_name  := l_curr_obj.get_string('name');
        l_curr_obj_type  := l_curr_obj.get_string('type');

        IF l_curr_obj_owner = l_owner AND l_curr_obj_name = l_name AND 
           l_curr_obj_type = l_type
        THEN
          RETURN TRUE;
        END IF;
      END LOOP;

      RETURN FALSE;
    END check_if_object_exists_in_list;


  -----------------------------------------------------------------------------
  -- add_inspect_object_list: helper function to add an object list to an 
  -- existing agent team
  -----------------------------------------------------------------------------
  PROCEDURE add_inspect_object_list(
    agent_team_name   IN VARCHAR2,
    object_list       IN JSON_ARRAY_T
  )
  IS
    l_curr_object       JSON_OBJECT_T;
    l_name              DBMS_ID;  
    l_owner             DBMS_ID;  
    l_type              DBMS_ID;
  BEGIN
    FOR i IN 0..object_list.get_size - 1 LOOP
      l_curr_object := JSON_OBJECT_T(object_list.get(i));
      l_name  := l_curr_object.get_string('name');
      l_owner := l_curr_object.get_string('owner');
      l_type  := l_curr_object.get_string('type');

      set_object(agent_team_name  => agent_team_name,
                 obj_name         => l_name,
                 obj_type         => l_type,
                 owner_name       => l_owner);
    END LOOP;
  END add_inspect_object_list;


  -----------------------------------------------------------------------------
  -- drop_inspect_object_list: helper function to drop an object list from an 
  -- existing agent team
  -----------------------------------------------------------------------------
  PROCEDURE drop_inspect_object_list(
    agent_team_name   IN VARCHAR2,
    object_list       IN JSON_ARRAY_T DEFAULT NULL,
    force             IN BOOLEAN DEFAULT FALSE
  )
  IS
    l_to_drop_object    JSON_OBJECT_T;
    l_name              DBMS_ID;  
    l_owner             DBMS_ID;  
    l_type              DBMS_ID;
    l_old_object_list   JSON_ARRAY_T;
    l_new_object_list   JSON_ARRAY_T := JSON_ARRAY_T('[]');
    l_to_drop_index     JSON_OBJECT_T := JSON_OBJECT_T('{}');
  BEGIN
    l_old_object_list := JSON_ARRAY_T(
                            get_attribute(agent_team_name => agent_team_name, 
                                          attribute_name  => 'object_list'));   
    FOR i IN 0..object_list.get_size - 1 LOOP
      l_to_drop_object := JSON_OBJECT_T(object_list.get(i));
      IF NOT check_if_object_exists_in_list(l_old_object_list, 
                                            l_to_drop_object) 
      THEN
        IF NOT FORCE THEN
          raise_application_error(-20000, 'Object ' || 
                l_to_drop_object.to_clob || 
                ' not found in current object list.');
        END IF;
      ELSE
        l_to_drop_index.put(i, l_to_drop_object);
      END IF;
    END LOOP;

    FOR i IN 0..object_list.get_size - 1 LOOP
      l_to_drop_object := JSON_OBJECT_T(object_list.get(i));
      unset_object(agent_team_name  => agent_team_name,
                   obj_name         => l_to_drop_object.get_string('name'),
                   obj_type         => l_to_drop_object.get_string('type'),
                   owner_name       => l_to_drop_object.get_string('owner'));
    END LOOP;
  END drop_inspect_object_list;


  ------------------------------------------------------------------------------------------------------------------
  ------------------------------------------------------------------------------------------------------------------
  ----------------------------                     AGENT TOOLS                          ----------------------------
  ------------------------------------------------------------------------------------------------------------------
  ------------------------------------------------------------------------------------------------------------------

  -----------------------------------------------------------------------------
  -- list_objects: returns a list of set database objects for the agent team. 
  -- The result set can be optionally filtered by object name, object type, 
  -- and/or object owner to narrow the scope of returned objects.
  -----------------------------------------------------------------------------
  FUNCTION list_objects(
    tool_name         IN VARCHAR2,
    object_name       IN VARCHAR2 DEFAULT NULL,
    object_type       IN VARCHAR2 DEFAULT NULL,
    object_owner      IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_agent_team_name DBMS_ID;
    l_cursor          SYS_REFCURSOR;
    l_stmt            CLOB;
    l_obj_name        DBMS_ID;
    l_obj_type        DBMS_ID;
    l_owner           DBMS_ID;
    l_params          CLOB;
    l_result          JSON_ARRAY_T := JSON_ARRAY_T('[]');
    l_obj_js          JSON_OBJECT_T;
    l_object_name     DBMS_ID := object_name;
    l_object_type     DBMS_ID;
    l_object_owner    DBMS_ID := object_owner;
  BEGIN
    l_agent_team_name := get_agent_team_name_from_tool(tool_name, 
                                                       TOOL_LIST_OBJECTS);

    IF object_type IS NOT NULL THEN
        l_object_type := UPPER(object_type);

        IF l_object_type NOT IN (OBJECT_TABLE, OBJECT_SCHEMA,
                                 OBJECT_PACKAGE, OBJECT_PACKAGE_BODY,
                                 OBJECT_PROCEDURE, OBJECT_FUNCTION, 
                                 OBJECT_TRIGGER, OBJECT_VIEW, OBJECT_TYPE)
        THEN
          raise_application_error(
            -20000, 'Invalid object type to filter - ' || object_type);
        END IF;
    END IF;

    l_stmt :=
        'SELECT object_name, object_type, owner '  ||
        '  FROM ' || INSPECT_OBJECTS ||
        ' WHERE (:1 IS NULL OR UPPER(object_name) = :1) ' ||
        '   AND UPPER(object_name) NOT LIKE ''DR$%'' ' ||
        '   AND UPPER(object_name) NOT LIKE ''VECTOR$%'' ' || 
        '   AND (:2 IS NULL OR object_type        = :2) ' ||
        '   AND (:3 IS NULL OR UPPER(owner)       = :3) ' ||
        '   AND agent_team_name = :4 ' ||
        ' ORDER BY UPPER(object_name), object_name, object_type, owner';

    OPEN l_cursor FOR l_stmt
        USING l_object_name, UPPER(l_object_name), 
              l_object_type, l_object_type, 
              l_object_owner, UPPER(l_object_owner),
              l_agent_team_name;

    LOOP
        FETCH l_cursor INTO l_obj_name, l_obj_type, l_owner;
        EXIT WHEN l_cursor%NOTFOUND;

        l_obj_js := JSON_OBJECT_T('{}');

        -- Same JSON shape as before
        l_obj_js.put('object_name', l_obj_name);
        l_obj_js.put('object_type',  l_obj_type);
        l_obj_js.put('object_owner', l_owner);
        l_result.append(l_obj_js);
    END LOOP;
    CLOSE l_cursor;

    -- Validate output length to avoid a known agent-side bug that can cause 
    -- buffer overflow issues.
    IF validate_tool_output_length(l_result.to_clob) THEN
      RETURN l_result.to_clob;
    ELSE
      raise_application_error(-20000, 
                              'The output of list_objects ' ||
                              'exceeds 200,000 characters. Please narrow ' ||
                              'the search scope and try again.');
    END IF;
  END list_objects; 


  -----------------------------------------------------------------------------
  -- list_incoming_dependencies: list objects that DEPEND ON or REFERENCE the 
  -- target object.
  -----------------------------------------------------------------------------
  FUNCTION list_incoming_dependencies(
    tool_name       IN VARCHAR2,
    object_name     IN VARCHAR2,
    object_type     IN VARCHAR2 DEFAULT NULL,
    object_owner    IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_ref_name         DBMS_ID := object_name;
    l_ref_type         DBMS_ID;
    l_ref_owner        DBMS_ID := object_owner;
    l_arr              JSON_ARRAY_T := JSON_ARRAY_T('[]');
    l_obj              JSON_OBJECT_T;
    l_sql              CLOB;
    l_cursor           SYS_REFCURSOR;
    l_owner            DBMS_ID;
    l_name             DBMS_ID;
    l_type             DBMS_ID;
    l_agent_team_name  DBMS_ID;
  BEGIN
    l_agent_team_name := get_agent_team_name_from_tool(
                            tool_name => tool_name, 
                            tool_type => TOOL_LIST_INCOMING_DEPENDENCIES);
    -- Schema is not supported for this tool
    IF object_type IS NOT NULL THEN
      l_ref_type := UPPER(object_type);
      IF l_ref_type NOT IN (OBJECT_TABLE, OBJECT_PACKAGE, 
                            OBJECT_PACKAGE_BODY, OBJECT_PROCEDURE, 
                            OBJECT_FUNCTION, OBJECT_TRIGGER, 
                            OBJECT_VIEW, OBJECT_TYPE)
      THEN
        raise_application_error(-20000, 'Invalid object type to track ' ||
                                'dependency - ' || object_type);
      END IF;
    END IF;

    IF l_ref_name IS NULL THEN
      RETURN l_arr.to_clob; -- []
    END IF;

    l_sql := 
      q'[
        SELECT r.referencing_object, r.referencing_type, r.owner FROM (
          WITH dep AS (
            SELECT
              d.owner,
              d.name               AS referencing_object,
              d.type               AS referencing_type,
              d.referenced_owner,
              d.referenced_name    AS referenced_object,
              d.referenced_type
            FROM all_dependencies d
            WHERE d.referenced_name  = NVL(:ref_name_dep , d.referenced_name)
              AND d.referenced_owner = NVL(:ref_owner_dep, d.referenced_owner)
              AND d.referenced_type  = NVL(:ref_type_dep , d.referenced_type)
            ),
            trg AS (
              SELECT
                t.owner,
                t.trigger_name        AS referencing_object,
                'TRIGGER'             AS referencing_type,
                t.table_owner         AS referenced_owner,
                t.table_name          AS referenced_object,
                'TABLE'               AS referenced_type
              FROM all_triggers t
              WHERE 'TABLE' = NVL(:ref_type_trg, 'TABLE')
                AND t.table_name  = NVL(:ref_name_trg , t.table_name)
                AND t.table_owner = NVL(:ref_owner_trg, t.table_owner)
            ),
            fk AS (
              SELECT
                c.owner,
                c.table_name          AS referencing_object,
                'TABLE'               AS referencing_type,
                r.owner               AS referenced_owner,
                r.table_name          AS referenced_object,
                'TABLE'               AS referenced_type
              FROM all_constraints c
              JOIN all_constraints r
                ON r.owner           = c.r_owner
              AND r.constraint_name = c.r_constraint_name
              WHERE 'TABLE' = NVL(:ref_type_fk, 'TABLE')
                AND c.constraint_type = 'R'
                AND r.constraint_type IN ('P','U')
                AND r.owner      = NVL(:ref_owner_fk, r.owner)
                AND r.table_name = NVL(:ref_name_fk , r.table_name)
            )
            SELECT * FROM dep
            UNION ALL
            SELECT * FROM trg
            UNION ALL
            SELECT * FROM fk
            ORDER BY referencing_type, owner, referencing_object) r, 
        ]';
    l_sql := l_sql || INSPECT_OBJECTS ||
      q'[ ro
          WHERE r.owner = ro.owner AND
                r.referencing_object = ro.object_name AND
                r.referencing_type = ro.object_type
                AND ro.agent_team_name = :agent_team_name
      ]';

    OPEN l_cursor FOR l_sql USING
          l_ref_name,  l_ref_owner, l_ref_type,
          l_ref_type,  l_ref_name,  l_ref_owner,
          l_ref_type,  l_ref_owner, l_ref_name,
          l_agent_team_name;
    LOOP
      FETCH l_cursor INTO l_name, l_type, l_owner;
      EXIT WHEN l_cursor%NOTFOUND;

      l_obj := JSON_OBJECT_T();
      l_obj.put('object_owner', l_owner);
      l_obj.put('object_name',  l_name);
      l_obj.put('object_type',  l_type);
      l_arr.append(l_obj);
    END LOOP;

    CLOSE l_cursor;
    RETURN l_arr.to_clob;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN l_arr.to_clob;
  END list_incoming_dependencies;


  -----------------------------------------------------------------------------
  -- list_outgoing_dependencies: list objects that the target object ITSELF 
  -- DEPENDS ON or REFERENCES.
  -----------------------------------------------------------------------------
  FUNCTION list_outgoing_dependencies(
    tool_name     IN VARCHAR2,
    object_name   IN VARCHAR2,
    object_type   IN VARCHAR2 DEFAULT NULL,
    object_owner  IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB
  IS
    l_ref_name          DBMS_ID := object_name;
    l_ref_type          DBMS_ID;
    l_ref_owner         DBMS_ID := object_owner;
    l_arr               JSON_ARRAY_T := JSON_ARRAY_T('[]');
    l_obj               JSON_OBJECT_T;
    l_sql               CLOB;
    l_cursor            SYS_REFCURSOR;
    l_owner             DBMS_ID;
    l_name              DBMS_ID;
    l_type              DBMS_ID;
    l_agent_team_name   DBMS_ID;
  BEGIN
    l_agent_team_name := get_agent_team_name_from_tool(
                            tool_name => tool_name, 
                            tool_type => TOOL_LIST_OUTGOING_DEPENDENCIES);
    -- Schema is not supported for this tool
    IF object_type IS NOT NULL THEN
      l_ref_type := UPPER(object_type);
      IF l_ref_type NOT IN (OBJECT_TABLE, OBJECT_PACKAGE,
                            OBJECT_PACKAGE_BODY, OBJECT_PROCEDURE,
                            OBJECT_FUNCTION, OBJECT_TRIGGER,
                            OBJECT_VIEW, OBJECT_TYPE)
      THEN
        raise_application_error(
          -20000,
          'Invalid object type to track referenced objects - ' || object_type
        );
      END IF;
    END IF;

    IF l_ref_name IS NULL THEN
      RETURN l_arr.to_clob; -- []
    END IF;

    /*
      For "outgoing" dependencies we treat the given object as the
      *referencing* object and list what it depends on:

        - ALL_DEPENDENCIES: owner/name/type = our object
                            referenced_*   = targets

        - Triggers (if the object itself is a TRIGGER): base table
        - Foreign keys (if the object is a TABLE): parent tables that
          this table references via FK (R -> P/U)

      As with list_incoming_dependencies, we filter results to only include
      objects within the object list for current agent$.
    */
    l_sql :=
      q'[
        SELECT r.referenced_object,
              r.referenced_type,
              r.referenced_owner
        FROM (
          WITH dep AS (
            SELECT
              d.owner,
              d.name             AS referencing_object,
              d.type             AS referencing_type,
              d.referenced_owner,
              d.referenced_name  AS referenced_object,
              d.referenced_type
            FROM all_dependencies d
            WHERE d.name  = NVL(:ref_name_dep , d.name)
              AND d.owner = NVL(:ref_owner_dep, d.owner)
              AND d.type  = NVL(:ref_type_dep , d.type)
          ),
          trg AS (
            -- If the object is a TRIGGER, it "references" its base table.
            SELECT
              t.owner               AS referencing_owner,
              t.trigger_name        AS referencing_object,
              'TRIGGER'             AS referencing_type,
              t.table_owner         AS referenced_owner,
              t.table_name          AS referenced_object,
              'TABLE'               AS referenced_type
            FROM all_triggers t
            WHERE 'TRIGGER' = NVL(:ref_type_trg, 'TRIGGER')
              AND t.trigger_name = NVL(:ref_name_trg , t.trigger_name)
              AND t.owner        = NVL(:ref_owner_trg, t.owner)
          ),
          fk AS (
            -- If the object is a TABLE, it may reference parent tables
            -- via foreign keys (R -> P/U). The parent is the referenced
            -- object from this table's point of view.
            SELECT
              c.owner              AS referencing_owner,
              c.table_name         AS referencing_object,
              'TABLE'              AS referencing_type,
              r.owner              AS referenced_owner,
              r.table_name         AS referenced_object,
              'TABLE'              AS referenced_type
            FROM all_constraints c
            JOIN all_constraints r
              ON r.owner           = c.r_owner
            AND r.constraint_name = c.r_constraint_name
            WHERE 'TABLE' = NVL(:ref_type_fk, 'TABLE')
              AND c.constraint_type = 'R'
              AND r.constraint_type IN ('P','U')
              AND c.owner      = NVL(:ref_owner_fk, c.owner)
              AND c.table_name = NVL(:ref_name_fk , c.table_name)
          )
          SELECT * FROM dep
          UNION ALL
          SELECT * FROM trg
          UNION ALL
          SELECT * FROM fk
        ) r,
      ]';
    l_sql := l_sql || INSPECT_OBJECTS ||
      q'[ ro 
        WHERE r.referenced_owner  = ro.owner
          AND r.referenced_object = ro.object_name
          AND r.referenced_type   = ro.object_type
          AND ro.agent_team_name = :agent_team_name
        ORDER BY r.referenced_type, r.referenced_owner, r.referenced_object
      ]';

    OPEN l_cursor FOR l_sql USING
          -- dep
          l_ref_name,  l_ref_owner, l_ref_type,
          -- trg
          l_ref_type,  l_ref_name,  l_ref_owner,
          -- fk
          l_ref_type,  l_ref_owner, l_ref_name,
          l_agent_team_name;

    LOOP
      FETCH l_cursor INTO l_name, l_type, l_owner;
      EXIT WHEN l_cursor%NOTFOUND;

      l_obj := JSON_OBJECT_T();
      l_obj.put('object_owner', l_owner);
      l_obj.put('object_name',  l_name);
      l_obj.put('object_type',  l_type);
      l_arr.append(l_obj);
    END LOOP;

    CLOSE l_cursor;
    RETURN l_arr.to_clob;

  EXCEPTION
    WHEN OTHERS THEN
      -- On any error, return empty array to keep the contract simple
      RETURN l_arr.to_clob;
  END list_outgoing_dependencies;


  -----------------------------------------------------------------------------
  -- retrieve_object_metadata: Retrieve the metadata for given object
  -----------------------------------------------------------------------------
  FUNCTION retrieve_object_metadata(
    object_name            IN VARCHAR2,
    object_type            IN VARCHAR2,
    object_owner           IN VARCHAR2
  ) RETURN CLOB
  IS
    l_metdata              CLOB;
    l_object_name          DBMS_ID := object_name;
    l_object_type          DBMS_ID;
    l_object_owner         DBMS_ID := object_owner;
  BEGIN
    IF object_type IS NOT NULL THEN
        l_object_type := UPPER(object_type);

        IF l_object_type NOT IN (OBJECT_TABLE,OBJECT_SCHEMA,
            OBJECT_PACKAGE,OBJECT_PACKAGE_BODY,OBJECT_PROCEDURE,
            OBJECT_FUNCTION,OBJECT_TRIGGER,OBJECT_VIEW,OBJECT_TYPE)
        THEN
          raise_application_error(
            -20000, 'Invalid object type to filter - ' || object_type);
        END IF;
    END IF;

    IF l_object_type != OBJECT_SCHEMA THEN
      l_metdata := DBMS_METADATA.GET_DDL(REPLACE(l_object_type, ' ', '_'), 
                                         l_object_name, l_object_owner);
    ELSE
      FOR m IN (
        SELECT ao.object_name, ao.object_type FROM all_objects ao
          WHERE ao.owner = l_object_owner AND 
                ao.object_type IN (OBJECT_TABLE, OBJECT_VIEW, OBJECT_TRIGGER,
                                   OBJECT_TYPE, OBJECT_FUNCTION, 
                                   OBJECT_PROCEDURE,
                                   OBJECT_PACKAGE, OBJECT_PACKAGE_BODY)
      ) LOOP
        BEGIN
          IF m.object_type IN (OBJECT_TABLE, OBJECT_VIEW, OBJECT_TRIGGER,
                                OBJECT_TYPE, OBJECT_FUNCTION, OBJECT_PROCEDURE,
                                OBJECT_PACKAGE, OBJECT_PACKAGE_BODY) 
          THEN
            l_metdata := l_metdata || '-- ' || m.object_type || ': ' || 
                         m.object_name || CHR(10) || 
                         DBMS_METADATA.GET_DDL(REPLACE(m.object_type, ' ', 
                                                       '_'),
                                               m.object_name, 
                                               l_object_owner) ||
                         CHR(10);
          END IF;
        EXCEPTION
          WHEN OTHERS THEN
            raise_application_error(-20000, 'Unable to get metadata for - ' ||
                                    m.object_name || CHR(10) || SQLERRM);
        END;
      END LOOP;
    END IF;
    RETURN l_metdata;
  END retrieve_object_metadata;


  -----------------------------------------------------------------------------
  -- retrieve_object_metadata_chunks: Get list of search results from the 
  -- vector table using either vector search or hybrid search (vector search + 
  -- text search).
  -----------------------------------------------------------------------------
  FUNCTION retrieve_object_metadata_chunks(
    tool_name           IN VARCHAR2,
    user_prompt         IN CLOB,
    keyword             IN CLOB DEFAULT NULL,
    object_list         IN CLOB DEFAULT NULL
  ) RETURN CLOB
  IS
    l_agent_team_name   DBMS_ID;
    l_embedding         CLOB;
    l_result            CLOB;
    l_profile_name      DBMS_ID;
  BEGIN
    l_agent_team_name := get_agent_team_name_from_tool(
                          tool_name => tool_name, 
                          tool_type => TOOL_RETRIEVE_OBJECT_METADATA_CHUNKS);
    l_profile_name := get_attribute(l_agent_team_name, 'profile_name');
  
    -- Get the embedding for the user_prompt
    l_embedding := DBMS_CLOUD_AI.generate(prompt        => user_prompt,
                                          profile_name  => l_profile_name,
                                          action        => 'embedding');
    
    -- If a keyword is provided, use hybrid search (text + vector); 
    -- otherwise, use vector search only
    IF keyword IS NULL THEN
      -- If object_list is provided, filter the search results by object_list
      IF object_list IS NULL THEN
        EXECUTE IMMEDIATE get_vector_sql(l_agent_team_name) INTO l_result 
            USING IN l_embedding;
      ELSE
        EXECUTE IMMEDIATE get_vector_sql(l_agent_team_name, TRUE) INTO l_result
            USING IN l_embedding, IN object_list;
      END IF;
    ELSE
      -- If object_list is provided, filter the search results by object_list
      IF object_list IS NULL THEN
        EXECUTE IMMEDIATE get_hybrid_sql(l_agent_team_name) INTO l_result 
            USING IN l_embedding, IN keyword;
      ELSE
        EXECUTE IMMEDIATE get_hybrid_sql(l_agent_team_name, TRUE) INTO l_result
            USING IN l_embedding, IN object_list, 
                  IN keyword,     IN object_list;
      END IF;
    END IF;

    RETURN l_result;
  END retrieve_object_metadata_chunks;


  -----------------------------------------------------------------------------
  -- expand_object_metadata_chunk: Returns a concatenated CLOB of 
  -- vectorized code snippets surrounding a specified content index for a given
  -- object.
  --
  -- The function retrieves snippets whose content_index falls within
  -- ± search_range of the provided content_index, ordered by content_index
  -- to preserve the original code sequence.
  -----------------------------------------------------------------------------
  FUNCTION expand_object_metadata_chunk(
    tool_name              IN VARCHAR2,
    object_name            IN VARCHAR2,
    object_type            IN VARCHAR2,
    object_owner           IN VARCHAR2,
    content_index          IN NUMBER,
    search_range           IN NUMBER DEFAULT 5
  ) RETURN CLOB
  IS
    l_stmt              CLOB;
    l_result            CLOB;
    l_obj_name          DBMS_ID := object_name;
    l_owner_name        DBMS_ID := object_owner;
    l_obj_type          DBMS_ID := UPPER(object_type);
    l_agent_team_name   DBMS_ID;
    l_vector_table_name DBMS_ID;
  BEGIN
    l_agent_team_name := get_agent_team_name_from_tool(
                          tool_name => tool_name, 
                          tool_type => TOOL_EXPAND_OBJECT_METADATA_CHUNK);
    l_vector_table_name := get_vecotr_table_name(l_agent_team_name);

    IF content_index <= 0 THEN
      raise_application_error(-20000, 'Invalid value for content_index - ' || 
                              content_index);
    END IF;

    -- Validate the object type
    IF l_obj_type NOT IN (OBJECT_TABLE, OBJECT_SCHEMA, OBJECT_PACKAGE, 
                          OBJECT_PACKAGE_BODY, OBJECT_PROCEDURE, 
                          OBJECT_FUNCTION, OBJECT_TRIGGER, 
                          OBJECT_VIEW, OBJECT_TYPE) 
    THEN
      raise_application_error(-20000, 'Invalid object type to register - ' || 
                              object_type);
    END IF;

    l_stmt := 
      q'[
        SELECT LISTAGG(content, '') 
            WITHIN GROUP (
              ORDER BY TO_NUMBER(JSON_VALUE(attributes, '$.content_index'))) 
            AS full_content
        FROM ]' || 
      l_vector_table_name ||
      q'[
      WHERE JSON_VALUE(attributes, '$.object_owner') = :1
        AND JSON_VALUE(attributes, '$.object_name') = :2
        AND JSON_VALUE(attributes, '$.object_type') = :3
        AND TO_NUMBER(JSON_VALUE(attributes, '$.content_index')) 
            BETWEEN :4 AND :5
      ]';

    EXECUTE IMMEDIATE l_stmt INTO l_result 
        USING IN l_owner_name, 
              IN l_obj_name, 
              IN l_obj_type, 
              IN content_index - search_range, 
              IN content_index + search_range;

    RETURN l_result;
  END expand_object_metadata_chunk;


  -----------------------------------------------------------------------------
  -- summarize_object: Summarizes a single object. Summarizing schema is not 
  -- supported
  -----------------------------------------------------------------------------
  FUNCTION summarize_object(
    tool_name         IN VARCHAR2,
    object_name       IN VARCHAR2,
    object_type       IN VARCHAR2,
    object_owner      IN VARCHAR2,
    user_prompt       IN CLOB     DEFAULT NULL
  ) RETURN CLOB
  IS
    l_name            DBMS_ID := object_name;
    l_owner           DBMS_ID := object_owner;
    l_type            DBMS_ID := UPPER(object_type);
    l_display_name    VARCHAR2(4000);
    l_code            CLOB;
    l_prompt          CLOB;
    l_result          CLOB;
    l_profile_name    DBMS_ID;
    l_agent_team_name DBMS_ID;
  BEGIN
    l_agent_team_name := get_agent_team_name_from_tool(
                            tool_name =>tool_name, 
                            tool_type => TOOL_SUMMARIZE_OBJECT);
    l_profile_name := get_attribute(l_agent_team_name, 'profile_name');

    -- Validate object type.
    -- Summarizing an entire schema can easily exceed the LLM context window, 
    -- so SCHEMA is explicitly not supported here.
    l_type := UPPER(object_type);
    IF l_type = OBJECT_SCHEMA THEN
      raise_application_error(-20000, 'plcode_summarizer does not support ' ||
                                      'summarizing an entire SCHEMA.');
    END IF;

    IF l_type NOT IN (OBJECT_TABLE, OBJECT_PACKAGE, OBJECT_PACKAGE_BODY, 
                      OBJECT_PROCEDURE, OBJECT_FUNCTION, OBJECT_TRIGGER,
                      OBJECT_VIEW, OBJECT_TYPE)
    THEN
      raise_application_error(-20000, 'Invalid object type for ' ||
                                      'plcode_summarizer - ' || object_type);
    END IF;

    IF l_name IS NULL THEN
      RETURN NULL;
    END IF;

    -- Build display name
    l_display_name := l_owner || '.' || l_name;

    -- Fetch object metadata / code
    l_code := retrieve_object_metadata(object_name  => l_name,
                                       object_type  => l_type,
                                       object_owner => l_owner);

    IF l_code IS NULL THEN
      RETURN NULL;
    END IF;

    -- Build concise summarizer prompt
    -- (format + summary requirement + user_prompt if provided)
    l_prompt :=
        'Given content is a pl/sql code block. Summarize the code '     ||
        'following this format: ' || CHR(10)                            ||
        '  * ' || l_type || ' ' || l_display_name                       || 
        ': <summary in one paragraph describing the main purpose and '  ||
        'behavior of this code bolck>.';

    IF user_prompt IS NOT NULL THEN
      l_prompt := l_prompt || ' Additional instructions: ' || user_prompt;
    END IF;

    -- Summarize the code using DBMS_CLOUD_AI.summarize API
    l_result := DBMS_CLOUD_AI.summarize(content       => l_code,
                                        user_prompt   => l_prompt,
                                        profile_name  => l_profile_name);
    RETURN l_result;
  EXCEPTION
    WHEN OTHERS THEN
      -- Suppress all errors; return NULL for tool safety
      RETURN NULL;
  END summarize_object;


  -----------------------------------------------------------------------------
  -- generate_pldoc: Generates a PLDoc/JavaDoc-style comment block (/** ... */)
  -- for a given object. Generating doc for schema object is not supported.
  -----------------------------------------------------------------------------
  FUNCTION generate_pldoc(
    tool_name         IN VARCHAR2,
    object_name       IN VARCHAR2,
    object_type       IN VARCHAR2,
    object_owner      IN VARCHAR2,
    user_prompt       IN CLOB DEFAULT NULL
  ) RETURN CLOB
  IS
    l_name            DBMS_ID := object_name;
    l_owner           DBMS_ID := object_owner;
    l_type            DBMS_ID;
    l_full_code       CLOB;
    l_code_for_llm    CLOB;
    l_prompt          CLOB;
    l_comment_block   CLOB;
    l_len             PLS_INTEGER;
    l_max_chars       PLS_INTEGER := 200000;  -- truncation limit
    l_profile_name    DBMS_ID;
    l_agent_team_name DBMS_ID;
  BEGIN
    l_agent_team_name := get_agent_team_name_from_tool(
                            tool_name =>tool_name, 
                            tool_type => TOOL_GENERATE_PLDOC);
    l_profile_name := get_attribute(l_agent_team_name, 'profile_name');
    l_type  := UPPER(object_type);

    -- Schema metadata can easily exceed the LLM context window, so it is 
    -- explicitly not supported here.
    IF l_type = OBJECT_SCHEMA THEN
      raise_application_error(-20000, 'pldoc_generate does not support ' ||
                                      'SCHEMA-level documentation.');
    END IF;

    IF l_name IS NULL OR l_owner IS NULL THEN
      raise_application_error(-20000, 'Error: Invalid object_name or ' ||
                                      'object_owner.');
    END IF;

    IF l_type NOT IN (OBJECT_TABLE, OBJECT_PACKAGE, OBJECT_PACKAGE_BODY, 
                      OBJECT_PROCEDURE, OBJECT_FUNCTION, OBJECT_TRIGGER, 
                      OBJECT_VIEW, OBJECT_TYPE) 
    THEN
      raise_application_error(-20000, 'Invalid object_type for ' ||
                                      'pldoc_generate - ' || object_type);
    END IF;

    -- Fetch full metadata / source
    l_full_code := retrieve_object_metadata(object_name  => l_name,
                                            object_type  => l_type,
                                            object_owner => l_owner);

    IF l_full_code IS NULL THEN
      raise_application_error(-20000, 'Error: metadata not found.');
    END IF;

    -- Truncate code for LLM (protect token limit). Doc generation doesn't 
    -- really need full code.
    l_len := LENGTH(l_full_code);

    IF l_len <= l_max_chars THEN
      l_code_for_llm := l_full_code;
    ELSE
      l_code_for_llm := SUBSTR(l_full_code, l_max_chars, 1);
    END IF;

    -- Build prompt: instructions + optional user instructions
    l_prompt :=
        'Generate a PLDoc-style JavaDoc comment block for the following ' ||
        'Oracle object. The PLDoc block must:' || CHR(10) ||
        '- Begin with "/**".' || CHR(10) ||
        '- Each line must begin with " *".' || CHR(10) ||
        '- End with " */".' || CHR(10) ||
        '- Provide a concise description of what the object does.' || 
        CHR(10) ||
        '- Include @param for each parameter (if any).' || CHR(10) ||
        '- Include @return for functions (if applicable).' || CHR(10) ||
        '- Include @throws or @exception if exceptions are identifiable.' || 
        CHR(10) ||
        'Output rules:' || CHR(10) ||
        '- Output ONLY the PLDoc block. Do not have any additional text.' || 
        CHR(10) ||
        '- Do NOT repeat or rewrite the code.' || CHR(10) ||
        '- No Markdown, no HTML, no backticks.' || CHR(10);

    IF user_prompt IS NOT NULL THEN
      l_prompt := l_prompt ||
                  'Additional user instructions: ' || user_prompt || CHR(10);
    END IF;

    -- Call the LLM
    l_comment_block := DBMS_CLOUD_AI.GENERATE(
                            prompt       => l_prompt || CHR(10) ||
                                            'Code snippet:' || CHR(10) ||
                                            l_code_for_llm,
                            profile_name => l_profile_name,
                            action       => 'CHAT');
    RETURN l_comment_block;
  END generate_pldoc;




  ------------------------------------------------------------------------------------------------------------------
  ------------------------------------------------------------------------------------------------------------------
  ----------------------------                   PUBLIC FUNCTIONS                       ----------------------------
  ------------------------------------------------------------------------------------------------------------------
  ------------------------------------------------------------------------------------------------------------------


  -----------------------------------------------------------------------------
  -- setup: create basic internal tables
  -----------------------------------------------------------------------------
  PROCEDURE setup
  IS
    l_count      NUMBER;
  BEGIN
    -- Create agent team table if not exists
    EXECUTE IMMEDIATE 
        'SELECT count(*) FROM user_tables ' || 
        'WHERE table_name = :1' 
      INTO l_count USING INSPECT_AGENT_TEAMS;
    IF l_count = 0 THEN
      EXECUTE IMMEDIATE 
        'CREATE TABLE ' || INSPECT_AGENT_TEAMS    || 
        '(id#               NUMBER GENERATED ALWAYS AS IDENTITY CACHE 2, ' ||
        ' agent_team_name   VARCHAR2(128)  NOT NULL)';
    END IF;

    -- Create agent team attributes table if not exists
    EXECUTE IMMEDIATE 
        'SELECT count(*) FROM user_tables ' || 
        'WHERE table_name = :1' 
      INTO l_count USING INSPECT_AGENT_TEAM_ATTRIBUTES;
    IF l_count = 0 THEN
      EXECUTE IMMEDIATE 
        'CREATE TABLE ' || INSPECT_AGENT_TEAM_ATTRIBUTES     || 
        '(agent_team_name      VARCHAR2(128)  NOT NULL,'     ||
        ' attribute_name       VARCHAR2(128)  NOT NULL,'     ||
        ' attribute_value      CLOB)';
    END IF;

    -- Create inspect objects table if not exists
    EXECUTE IMMEDIATE 
        'SELECT count(*) FROM user_tables ' || 
        'WHERE table_name = :1' 
      INTO l_count USING INSPECT_OBJECTS;
    IF l_count = 0 THEN
      EXECUTE IMMEDIATE 
        'CREATE TABLE ' || INSPECT_OBJECTS    || 
        '( ' ||
        '  agent_team_name      VARCHAR2(128) NOT NULL,'   ||
        '  object_name          VARCHAR2(128), '           ||
        '  object_type          VARCHAR2(30)  NOT NULL, '  ||
        '  owner                VARCHAR2(128) NOT NULL, '  ||
        '  params               CLOB)';
    END IF;
  END setup;


  -----------------------------------------------------------------------------
  -- cleanup: cleanup all internal tables and indexes
  -----------------------------------------------------------------------------
  PROCEDURE cleanup
  IS
    l_count             NUMBER;
    l_stmt              VARCHAR2(4000);
    l_cursor            SYS_REFCURSOR;
    l_agent_team_name   DBMS_ID;
  BEGIN
    -- Drop agents
    l_stmt := 'SELECT agent_team_name FROM ' || INSPECT_AGENT_TEAMS;
    OPEN l_cursor FOR l_stmt;
    LOOP
      FETCH l_cursor INTO l_agent_team_name;
      EXIT WHEN l_cursor%NOTFOUND;      
      drop_inspect_agent_team(l_agent_team_name);
    END LOOP;

    -- Drop agent team table if exists
    EXECUTE IMMEDIATE 
        'SELECT count(*) FROM user_tables ' || 
        'WHERE table_name = :1' 
      INTO l_count USING INSPECT_AGENT_TEAMS;
    IF l_count > 0 THEN
      EXECUTE IMMEDIATE 'DROP TABLE ' || INSPECT_AGENT_TEAMS || ' PURGE';
    END IF;

    -- Drop agent team attributes table if exists
    EXECUTE IMMEDIATE 
        'SELECT count(*) FROM user_tables ' || 
        'WHERE table_name = :1' 
      INTO l_count USING INSPECT_AGENT_TEAM_ATTRIBUTES;
    IF l_count > 0 THEN
      EXECUTE IMMEDIATE 'DROP TABLE ' || INSPECT_AGENT_TEAM_ATTRIBUTES || 
                        ' PURGE';
    END IF;

    -- Drop inspect objects table if exists
    EXECUTE IMMEDIATE 
        'SELECT count(*) FROM user_tables ' || 
        'WHERE table_name = :1' 
      INTO l_count USING INSPECT_OBJECTS;
    IF l_count > 0 THEN
      EXECUTE IMMEDIATE 'DROP TABLE ' || INSPECT_OBJECTS || ' PURGE';
    END IF;
  END cleanup;


  -----------------------------------------------------------------------------
  -- create_inspect_agent_team: create an agent team with given attributes
  -----------------------------------------------------------------------------
  PROCEDURE create_inspect_agent_team(
    agent_team_name   IN VARCHAR2,
    attributes        IN CLOB
  )
  IS
    -- ADD AUTO TRANS...
    l_attributes      JSON_OBJECT_T;
    l_object_list     JSON_ARRAY_T;
    l_curr_object     JSON_OBJECT_T;
    l_name            DBMS_ID;  
    l_owner           DBMS_ID;  
    l_type            DBMS_ID;
    l_attribute_keys  JSON_KEY_LIST;
    l_atribute_key    DBMS_ID;
    l_attribute_value CLOB;
    l_profile_name    DBMS_ID;
    l_team_name       DBMS_ID;
    l_count           NUMBER;  
  BEGIN
    -- Validate team_name and check if already exists
    l_team_name := validate_object_name(agent_team_name);
    IF check_team_exists(l_team_name) THEN
      raise_application_error(-20000, 'Agent team ' || agent_team_name || 
          ' already exists. Please choose a different name.');
    END IF;

    -- Validate attributes
    l_attributes := parse_attributes(attributes);

    -- profile_name and object_list must be provided in attributes
    l_profile_name := l_attributes.get_string('profile_name');
    IF l_profile_name IS NULL THEN
      raise_application_error(-20000, 'Attribute profile_name is required.');
    END IF;
    IF l_attributes.get('object_list') IS NULL THEN
      raise_application_error(-20000, 'Attribute object_list is required.');
    END IF;
    l_object_list := JSON_ARRAY_T(l_attributes.get('object_list'));

    BEGIN
      -- Record the agent team in agent table
      EXECUTE IMMEDIATE
          'INSERT INTO ' || INSPECT_AGENT_TEAMS ||
          ' (agent_team_name) VALUES (:1)'
          USING l_team_name;

      -- Record the agent team attributes in attribute table
      set_attributes(agent_team_name  => l_team_name,
                    attributes       => l_attributes);

      -- Create agent team
      create_agent_team(profile_name    =>  l_profile_name, 
                        agent_team_name =>  l_team_name);
  EXCEPTION
    WHEN OTHERS THEN
      drop_inspect_agent_team(l_team_name, true);
      RAISE;
    END;

    -- Create vector table and add object list for the agent team
    create_vector_table(
        agent_team_name => l_team_name,
        profile_name    => l_profile_name);
    add_inspect_object_list(
        agent_team_name => l_team_name, 
        object_list     => l_object_list);
  END create_inspect_agent_team;



  -----------------------------------------------------------------------------
  -- update_inspect_agent_team: update an existing agent team with given 
  -- attributes
  -----------------------------------------------------------------------------
  PROCEDURE update_inspect_agent_team(
    agent_team_name   IN VARCHAR2,
    attributes        IN CLOB
  )
  IS
    l_team_name                 DBMS_ID;
    l_attributes                JSON_OBJECT_T;
    l_profile_name              DBMS_ID;
    l_provider                  DBMS_ID;
    l_profile_attributes        JSON_OBJECT_T;
    l_new_profile_name          DBMS_ID;
    l_new_profile_attributes    JSON_OBJECT_T;
    l_new_provider              DBMS_ID;
    l_object_list               JSON_ARRAY_T;
    l_new_object_list           JSON_ARRAY_T;
    l_reset_object_list         BOOLEAN := FALSE;
    l_recreate_vector_table     BOOLEAN := FALSE;
  BEGIN
    -- Validate agent_team_name and check if already exists
    l_team_name := validate_object_name(agent_team_name);
    IF NOT check_team_exists(l_team_name) THEN
      raise_application_error(-20000, 'Agent team ' || agent_team_name || 
          ' does not exist.');
    END IF;

    -- Validate attributes
    l_attributes := parse_attributes(attributes);

    -- Get original profile_name and object_list
    l_profile_name := get_attribute(agent_team_name => l_team_name, 
                                    attribute_name => 'profile_name');
    l_object_list := JSON_ARRAY_T(
                      get_attribute(agent_team_name => l_team_name, 
                                    attribute_name => 'object_list'));

    -- If new profile name is provided, we need to check whether the provider 
    -- is changed. If provider is changed, we need to reset the object list 
    -- since the vector embedding may be different across different providers.
    -- If provider is not changed, we can keep the existing object list and 
    -- just update the vector table with new profile if needed.
    l_new_profile_name := l_attributes.get_string('profile_name');
    IF l_new_profile_name IS NOT NULL THEN
      -- get original provider
      l_profile_attributes := get_profile_attributes(l_profile_name);
      l_provider := LOWER(l_profile_attributes.get_string('provider'));

      -- get new provider
      l_new_profile_attributes := get_profile_attributes(l_new_profile_name);
      l_new_provider := LOWER(l_new_profile_attributes.get_string('provider'));

      IF l_new_provider != l_provider THEN
        l_reset_object_list := TRUE;
        l_recreate_vector_table := TRUE;
      END IF;
    END IF;

    -- IF new object_list is provided, we need to reset the object list 
    -- regardless whether the provider is changed or not, since the object 
    -- list is updated.
    IF l_attributes.get('object_list') IS NOT NULL THEN
      l_new_object_list := JSON_ARRAY_T(l_attributes.get('object_list'));
      l_reset_object_list := TRUE;
    END IF;

    -- Drop and recreate vector table for the agent team and add object list
    IF l_reset_object_list THEN
      drop_inspect_object_list(
                      agent_team_name => l_team_name, 
                      object_list     => l_object_list, 
                      force           => TRUE);

      IF l_recreate_vector_table THEN
        create_vector_table(agent_team_name => l_team_name,
                            profile_name    => l_new_profile_name);
      END IF;

      add_inspect_object_list(
                      agent_team_name => l_team_name, 
                      object_list     => NVL(l_new_object_list, l_object_list));
    END IF;

    set_attributes(agent_team_name  => l_team_name,
                    attributes       => l_attributes);
  END update_inspect_agent_team;


  -----------------------------------------------------------------------------
  -- drop_inspect_agent_team: drop an existing agent team and all related 
  -- information
  -----------------------------------------------------------------------------
  PROCEDURE drop_inspect_agent_team(
    agent_team_name   IN VARCHAR2,
    force             IN BOOLEAN DEFAULT FALSE
  )
  IS
    l_team_name         DBMS_ID;
    l_object_list_clob  CLOB;
    l_object_list       JSON_ARRAY_T;
  BEGIN
    -- Validate team_name and check if exists
    l_team_name := validate_object_name(agent_team_name);
    IF NOT check_team_exists(l_team_name) THEN
      IF force THEN
        RETURN;
      END IF;
      raise_application_error(-20000, 'Agent team ' || agent_team_name || 
                              ' does not exist.');
    END IF;

    -- Drop object list for the agent team
    l_object_list_clob := get_attribute(agent_team_name => l_team_name, 
                                        attribute_name => 'object_list');
    IF l_object_list_clob IS NOT NULL THEN
      l_object_list := JSON_ARRAY_T(l_object_list_clob);
      drop_inspect_object_list(agent_team_name => l_team_name, 
                               object_list     => l_object_list,
                               force           => TRUE);
    END IF;
    drop_vector_table(agent_team_name => l_team_name);

    -- Drop the agent
    drop_agent_team(l_team_name);

    -- Drop attributes set for the agent team
    drop_attributes(agent_team_name => l_team_name);

    -- Remove the agent team from agent table
    EXECUTE IMMEDIATE 'DELETE FROM ' || INSPECT_AGENT_TEAMS || 
                      ' WHERE agent_team_name = :1' 
                      USING l_team_name;
  END drop_inspect_agent_team;

BEGIN
  setup();
END database_inspect;
/

show errors;
PROMPT ======================================================
PROMPT DATABASE_INSPECT tools installation completed
PROMPT ======================================================

alter session set current_schema = ADMIN;
