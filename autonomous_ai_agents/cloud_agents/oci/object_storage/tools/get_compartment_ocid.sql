--
-- NAME:
--   get_compartment_ocid - Retrieve the OCID of a given compartment
--
-- DESCRIPTION:
--   This function retrieves the OCID (Oracle Cloud Identifier) for a specific
--   compartment by name within a tenancy. It internally calls the
--   list_compartments function to fetch all available compartments, then
--   searches for the compartment with the given name. The result is returned
--   as a structured JSON object (CLOB).
--
-- PARAMETERS:
--   credential_name   (IN)  - Name of the stored credential (for DBMS_CLOUD)
--   compartment_name  (IN)  - Name of the compartment to search for
--
-- RETURNS:
--   CLOB containing JSON object with keys:
--     - status            : 'success' or 'error'
--     - compartment_name  : Name of the matched compartment (if success)
--     - compartment_ocid  : OCID of the matched compartment (if success)
--     - message           : Error message if compartment not found or request fails
--
-- EXAMPLE:
--   SELECT get_compartment_ocid('OCI_CRED', 'COMP_DB')
--     FROM dual;
--
-- NOTES:
--   - Relies on the list_compartments function to fetch compartment details.
--   - Returns an error JSON if the compartment name is not found or if an
--     unexpected error occurs.
--   - Uses DBMS_CLOUD.send_request and JSON parsing APIs.
--


create or replace FUNCTION get_compartment_ocid(
    credential_name  IN VARCHAR2,
    compartment_name IN VARCHAR2
) RETURN CLOB
IS
    l_comp_json_clob CLOB;
    l_result_json    JSON_OBJECT_T := JSON_OBJECT_T();
    l_compartments   JSON_ARRAY_T;
    l_comp_obj       JSON_OBJECT_T;
    l_name           VARCHAR2(200);
    l_ocid           VARCHAR2(200);
    found            BOOLEAN := FALSE;
    l_compartment_name VARCHAR2(256);
BEGIN
    
    -- Call existing list_compartments function
    l_comp_json_clob := list_compartments(credential_name);

    -- Parse returned JSON object
    l_result_json := JSON_OBJECT_T.parse(l_comp_json_clob);

    IF l_result_json.get('status').to_string() = '"success"' THEN
        -- Extract compartments array
        l_compartments := l_result_json.get_Array('compartments');

        -- Loop through compartments to find matching name
        FOR i IN 0 .. l_compartments.get_size() - 1 LOOP
            l_comp_obj := JSON_OBJECT_T(l_compartments.get(i));
            l_name := l_comp_obj.get_string('name');

            IF l_name = compartment_name THEN
                l_ocid := l_comp_obj.get_string('id');
                found := TRUE;
                EXIT;
            END IF;
        END LOOP;

        IF found THEN
            l_result_json := JSON_OBJECT_T();
            l_result_json.put('status', 'success');
            l_result_json.put('compartment_name', compartment_name);
            l_result_json.put('compartment_ocid', l_ocid);
        ELSE
            l_result_json := JSON_OBJECT_T();
            l_result_json.put('status', 'error');
            l_result_json.put('message', 'Compartment name "' || compartment_name || '" not found');
        END IF;

    ELSE
        -- Forward error from list_compartments function
        RETURN l_comp_json_clob;
    END IF;

    RETURN l_result_json.to_clob();

EXCEPTION
    WHEN OTHERS THEN
        l_result_json := JSON_OBJECT_T();
        l_result_json.put('status', 'error');
        l_result_json.put('message', 'Unexpected error: ' || SQLERRM);
        RETURN l_result_json.to_clob();
END get_compartment_ocid;
/

--Drop tool if exists

DECLARE
    l_tool_count NUMBER;
BEGIN
    -- Check if the tool exists
    SELECT COUNT(*)
    INTO l_tool_count
    FROM USER_AI_AGENT_TOOLS
    WHERE TOOL_NAME = 'GET_COMPARTMENT_OCID_TOOL';

    -- Drop only if it exists
    IF l_tool_count > 0 THEN
        DBMS_CLOUD_AI_AGENT.DROP_TOOL('GET_COMPARTMENT_OCID_TOOL');
    END IF;
END;
/

--Create tool

BEGIN
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name => 'GET_COMPARTMENT_OCID_TOOL',
        attributes => '{
            "instruction": "This tool accepts OCI credentials and a compartment name, and returns the OCID of that compartment.",
            "function": "get_compartment_ocid"
        }',
        description => 'Tool to get compartment OCID by name'
    );
END;
/
