-- Copyright (c) 2025 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

/** Export data to cloud storage **/

/* PREREQUISITES
    Install the sample schema using script
        @data-create-sample-schema.sql
*/

@config.sql

-- Create a credential in order to connect to data lake storage
@credential-create.sql storage

-- List the files in that storage container
SELECT object_name, bytes 
FROM dbms_cloud.list_objects(
    credential_name => '&STORAGE_CREDENTIAL_NAME',
    location_uri => '&STORAGE_URL'
);

--
-- Export movie genre data to the data lake
--
-- Check out the data to be exported
SELECT *
FROM genre;

-- Export in CSV format
BEGIN
  DBMS_CLOUD.EXPORT_DATA(
    credential_name => '&STORAGE_CREDENTIAL_NAME',
    file_uri_list => '&STORAGE_URL/data/genre/genre',
    query => 'SELECT * FROM genre',
    format => JSON_OBJECT('type' VALUE 'csv', 'delimiter' VALUE ',')
  );
END;
/

-- Export in parquet format
BEGIN
  DBMS_CLOUD.EXPORT_DATA(
    credential_name => '&STORAGE_CREDENTIAL_NAME',
    file_uri_list => '&STORAGE_URL/data/customer/customer',
    query => 'SELECT * FROM genre',
    format => JSON_OBJECT('type' VALUE 'parquet')
  );
END;
/


-- List the files in that storage container. Notice the new genre data.
SELECT object_name, bytes 
FROM dbms_cloud.list_objects(
    credential_name => '&STORAGE_CREDENTIAL_NAME',
    location_uri => '&STORAGE_URL'
);