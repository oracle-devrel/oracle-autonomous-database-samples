-- Copyright (c) 2025 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

--
-- Use the Oracle LiveLabs has utilities for setting up sample data and schemas. Use this script to set up data
-- used by the samples
--
-- run the config script to set up variables
@config.sql

-- add a database user that will own the sample data
prompt Adding database user &USER_NAME
-- USER SQL
CREATE USER &USER_NAME IDENTIFIED BY &USER_PASSWORD;

-- ADD ROLES
GRANT CONNECT TO &USER_NAME;
GRANT CONSOLE_DEVELOPER TO &USER_NAME;
GRANT DWROLE TO &USER_NAME;
GRANT GRAPH_DEVELOPER TO &USER_NAME;
GRANT OML_DEVELOPER TO &USER_NAME;
GRANT RESOURCE TO &USER_NAME;
GRANT SODA_APP TO &USER_NAME;
ALTER USER &USER_NAME DEFAULT ROLE CONSOLE_DEVELOPER,DWROLE,GRAPH_DEVELOPER,OML_DEVELOPER;
ALTER USER &USER_NAME GRANT CONNECT THROUGH GRAPH$PROXY_USER;
ALTER USER &USER_NAME GRANT CONNECT THROUGH OML$PROXY;
ALTER USER &USER_NAME QUOTA UNLIMITED ON DATA;
grant execute on dbms_cloud_ai to &USER_NAME;
grant execute on dbms_cloud_repo to &USER_NAME;

-- REST ENABLE
BEGIN
    ORDS_ADMIN.ENABLE_SCHEMA(
        p_enabled => TRUE,
        p_schema => '&USER_NAME',
        p_url_mapping_type => 'BASE_PATH',
        p_url_mapping_pattern => '&USER_NAME',
        p_auto_rest_auth=> TRUE
    );
    -- ENABLE DATA SHARING
    C##ADP$SERVICE.DBMS_SHARE.ENABLE_SCHEMA(
            SCHEMA_NAME => '&USER_NAME',
            ENABLED => TRUE
    );
    commit;
END;
/

--
-- Add sample data set
--
-- install the utilities
prompt Installing workshop utilities
set timing on

declare 
    l_uri varchar2(500) := 'https://objectstorage.us-ashburn-1.oraclecloud.com/n/c4u04/b/building_blocks_utilities/o/setup/workshop-setup.sql';
begin
    dbms_cloud_repo.install_sql(
        content => to_clob(dbms_cloud.get_object(object_uri => l_uri))
    );
end;
/

prompt Connecting as database user &USER_NAME
conn &USER_NAME/&USER_PASSWORD@&CONN

prompt Adding data sets. This will take a few minutes
exec workshop.add_dataset(tag => 'gen-ai')

prompt Done.



