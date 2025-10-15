
--
-- NAME:
--   list_compartments - Retrieve compartments for a tenancy
--
-- DESCRIPTION:
--   This function queries the OCI Identity service to list all compartments
--   in the current tenancy using the provided credential. It dynamically builds
--   the API endpoint based on the PDB metadata, sends a GET request, and
--   returns compartment details as a structured JSON response (CLOB).
--
-- PARAMETERS:
--   credential_name   (IN)  - Name of the stored credential (for DBMS_CLOUD)
--
-- RETURNS:
--   CLOB containing JSON object with keys:
--     - status             : 'success' or 'error'
--     - message            : Status message
--     - total_compartments : Count of compartments retrieved (if successful)
--     - compartments       : JSON array of compartment objects, each with:
--                              * name
--                              * id
--                              * description
--                              * lifecycle_state
--                              * time_created
--
-- EXAMPLE:
--   SELECT list_compartments('OCI_CRED')
--     FROM dual;
--
-- NOTES:
--   - Only includes compartments named 'COMP_STABLE' or 'COMP_PUBLIC'
--     (renamed to 'COMP_AI_AGENT' and 'COMP_DB' respectively in the output).
--   - Returns an error JSON if no compartments are found or if request fails.
--   - Uses DBMS_CLOUD.send_request and JSON parsing APIs.
--



create or replace FUNCTION list_compartments(credential_name VARCHAR2)
RETURN CLOB
IS
    l_response        CLOB;
    l_endpoint        VARCHAR2(1000);
    l_result_json     JSON_OBJECT_T := JSON_OBJECT_T();
    l_compartments    JSON_ARRAY_T := JSON_ARRAY_T();
    l_comp_data       JSON_ARRAY_T;
    l_comp_obj        JSON_OBJECT_T;
    l_name            VARCHAR2(200);
    l_ocid            VARCHAR2(200);
    l_description     VARCHAR2(500);
    l_lifecycle_state VARCHAR2(50);
    l_time_created    VARCHAR2(100);
    tenancy_id        VARCHAR2(128);
    l_region          VARCHAR2(128);

BEGIN

    SELECT
      JSON_VALUE(cloud_identity, '$.TENANT_OCID') AS tenant_ocid,
      JSON_VALUE(cloud_identity, '$.REGION') AS region
    into tenancy_id,l_region
    FROM v$pdbs;

    -- Construct endpoint to list compartments in tenancy
    l_endpoint := 'https://identity.'||l_region||'.oci.oraclecloud.com/20160918/compartments?compartmentId='
                  || tenancy_id ;

    BEGIN
        -- Call OCI REST API
        l_response := DBMS_CLOUD.get_response_text(
            DBMS_CLOUD.send_request(
                credential_name => credential_name,
                uri             => l_endpoint,
                method          => DBMS_CLOUD.METHOD_GET
            )
        );

        -- Parse response JSON as array
        l_comp_data := JSON_ARRAY_T.parse(l_response);

        IF l_comp_data.get_size() > 0 THEN
            FOR i IN 0 .. l_comp_data.get_size() - 1 LOOP
                l_comp_obj := JSON_OBJECT_T(l_comp_data.get(i));
                l_name := l_comp_obj.get_string('name');
                l_ocid := l_comp_obj.get_string('id');
                l_description := l_comp_obj.get_string('description');
                l_lifecycle_state := l_comp_obj.get_string('lifecycleState');
                l_time_created := l_comp_obj.get_string('timeCreated');

                l_compartments.append(
                    JSON_OBJECT(
                        'name' VALUE l_name,
                        'id' VALUE l_ocid,
                        'description' VALUE l_description,
                        'lifecycle_state' VALUE l_lifecycle_state,
                        'time_created' VALUE l_time_created
                    )
                );

            END LOOP;

            l_result_json.put('status', 'success');
            l_result_json.put('message', 'Successfully retrieved compartments');
            l_result_json.put('total_compartments', l_compartments.get_size());
            l_result_json.put('compartments', l_compartments);
        ELSE
            l_result_json.put('status', 'error');
            l_result_json.put('message', 'No compartments found in response');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            l_result_json.put('status', 'error');
            l_result_json.put('message', 'Failed to retrieve compartments: ' || SQLERRM);
            l_result_json.put('endpoint_used', l_endpoint);
    END;

    RETURN l_result_json.to_clob();
END list_compartments;
/





--Drop tool if exists

DECLARE
    l_tool_count NUMBER;
BEGIN
    -- Check if the tool exists
    SELECT COUNT(*)
    INTO l_tool_count
    FROM USER_AI_AGENT_TOOLS
    WHERE TOOL_NAME = 'LIST_COMPARTMENTS_TOOL';

    -- Drop only if it exists
    IF l_tool_count > 0 THEN
        DBMS_CLOUD_AI_AGENT.DROP_TOOL('LIST_COMPARTMENTS_TOOL');
    END IF;
END;
/

--Create tool 

BEGIN
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name => 'LIST_COMPARTMENTS_TOOL',
        attributes => '{"instruction": "This tool lists all the compartments in the tenancy. Ask your credentials",
                        "function" : "list_compartments"}',
        description => 'Tool for listing compartments'
    );
END;
/



