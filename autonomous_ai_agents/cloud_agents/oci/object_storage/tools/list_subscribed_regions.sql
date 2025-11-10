--
-- NAME:
--   list_subscribed_regions - Retrieve subscribed OCI regions for a tenancy
--
-- DESCRIPTION:
--   This function queries the OCI Identity service to list all subscribed
--   regions for the current tenancy using the provided credential. It builds
--   the Identity API endpoint dynamically from the PDB metadata, sends a GET
--   request to fetch subscribed region details, and returns the results as a
--   structured JSON response (CLOB).
--
-- PARAMETERS:
--   credential_name   (IN)  - Name of the stored credential (for DBMS_CLOUD)
--
-- RETURNS:
--   CLOB containing JSON object with keys:
--     - status          : 'success' or 'error'
--     - message         : Status message
--     - total_regions   : Count of regions retrieved (if successful)
--     - regions         : JSON array of region objects, each with:
--                           * region_name
--                           * is_home_region (Yes/No)
--
-- EXAMPLE:
--   SELECT list_subscribed_regions('OCI_CRED') 
--     FROM dual;
--
-- NOTES:
--   - Only includes 'us-ashburn-1' and 'us-phoenix-1' regions in the response.
--   - Returns an error JSON if no regions are found or if request fails.
--   - Uses DBMS_CLOUD.send_request and JSON parsing APIs.
--

create or replace FUNCTION list_subscribed_regions(credential_name IN VARCHAR2)
RETURN CLOB
IS
    l_response      CLOB;
    l_endpoint      VARCHAR2(500);
    l_result_json   JSON_OBJECT_T := JSON_OBJECT_T();
    l_regions_array JSON_ARRAY_T := JSON_ARRAY_T();
    l_regions_data  JSON_ARRAY_T;
    l_region_obj    JSON_OBJECT_T;
    l_region_name   VARCHAR2(100);
    l_region_key    VARCHAR2(50);
    l_status        VARCHAR2(50);
    l_is_home       VARCHAR2(10);
    tenancy_id      VARCHAR2(128);
    l_region        VARCHAR2(128); 
BEGIN


    SELECT
      JSON_VALUE(cloud_identity, '$.TENANT_OCID') AS tenant_ocid,
      JSON_VALUE(cloud_identity, '$.REGION') AS region
    into tenancy_id,l_region
    FROM v$pdbs;

    -- Build the OCI endpoint URL
    l_endpoint := 'https://identity.'||l_region||'.oci.oraclecloud.com/20160918/tenancies/' ||
                  tenancy_id || '/regionSubscriptions';

    BEGIN
        -- Send GET request to OCI Identity API
        l_response := DBMS_CLOUD.get_response_text(
            DBMS_CLOUD.send_request(
                credential_name => credential_name,
                uri => l_endpoint,
                method => DBMS_CLOUD.METHOD_GET
            )
        );

        -- Debug print: see raw API response
        -- DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(l_response, 4000, 1));

        -- Parse the response as JSON array
        l_regions_data := JSON_ARRAY_T.parse(l_response);

        IF l_regions_data.get_size() > 0 THEN
            -- Process each region
            FOR i IN 0 .. l_regions_data.get_size() - 1 LOOP
                l_region_obj := JSON_OBJECT_T(l_regions_data.get(i));
                l_region_name := l_region_obj.get_string('regionName');
                l_region_key := l_region_obj.get_string('regionKey');
                l_status := l_region_obj.get_string('status');
                l_is_home := CASE WHEN l_region_obj.get_boolean('isHomeRegion') THEN 'Yes' ELSE 'No' END;

            END LOOP;

            -- Build success response
            l_result_json.put('status', 'success');
            l_result_json.put('message', 'Successfully retrieved subscribed regions');
            l_result_json.put('total_regions', l_regions_array.get_size());
            l_result_json.put('regions', l_regions_array);
        ELSE
            l_result_json.put('status', 'error');
            l_result_json.put('message', 'No regions data found in response');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            l_result_json.put('status', 'error');
            l_result_json.put('message', 'Failed to retrieve subscribed regions: ' || SQLERRM);
            l_result_json.put('endpoint_used', l_endpoint);
    END;

    RETURN l_result_json.to_clob();
END list_subscribed_regions;
/


DECLARE
    l_tool_count NUMBER;
BEGIN
    -- Check if the tool exists
    SELECT COUNT(*)
    INTO l_tool_count
    FROM USER_AI_AGENT_TOOLS
    WHERE TOOL_NAME = 'LIST_SUBSCRIBED_REGIONS_TOOL';

    -- Drop only if it exists
    IF l_tool_count > 0 THEN
        DBMS_CLOUD_AI_AGENT.DROP_TOOL('LIST_SUBSCRIBED_REGIONS_TOOL');
    END IF;
END;
/


BEGIN
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name => 'LIST_SUBSCRIBED_REGIONS_TOOL',
        attributes => '{"instruction": "This tool lists all Oracle Cloud regions that are subscribed by current user tenancy. ' ||
                                       'It helps users choose which region to deploy their Autonomous Database. ",
            "function" : "list_subscribed_regions"}',
        description => 'Tool for listing Oracle Cloud subscribed regions'
    );
END;
/

