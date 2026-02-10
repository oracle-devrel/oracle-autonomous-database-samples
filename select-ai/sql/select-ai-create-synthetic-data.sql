-- Copyright (c) 2025 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

/* PREREQUISITES
    Install the sample schema using script
        @data-create-sample-schema.sql
*/

-- config.sql contains the endpoints, resource groups and other settings required to connect to your Azure OpenAI deployment
@config.sql

-- Create your credential and Select AI Profile
@select-ai-create-profile.sql

drop table if exists activity cascade constraints;
drop table if exists customers cascade constraints;
drop table if exists award_winners cascade constraints;

-- Create a table containing award winning movies
CREATE TABLE award_winners AS
SELECT *
FROM movies
WHERE instr(awards, 'Academy') > 0;

SELECT title, awards
FROM AWARD_WINNERS;


/*
  Add PK constraints to existing tables. This will ensure that data generation for related tables will create valid values.
  For example, ACTIVITY data will be generated - and valid MOVIE_ID's will be generated for that table b/c of this primary key
*/
ALTER TABLE award_winners ADD CONSTRAINT pk_award_winners PRIMARY KEY (movie_id) ENABLE;

/* Create and generate customers */
CREATE TABLE customers (	
    cust_id NUMBER, 
    last_name VARCHAR2(100), 
    first_name VARCHAR2(100), 
    email VARCHAR2(200), 
    street_address VARCHAR2(4000), 
    postal_code VARCHAR2(10), 
    city VARCHAR2(100), 
    state_province VARCHAR2(100), 
    country VARCHAR2(400), 
    yrs_customer NUMBER, 
    age_range varchar2(4000), 
    gender VARCHAR2(4000), 
    household_size NUMBER, 
  
    CONSTRAINT pk_customers PRIMARY KEY (cust_id)
  )
;	

-- These comments will tell the AI model how to generate data for a column
COMMENT ON COLUMN customers.gender IS 'The value for gender should be either: Male, Female, Non-binary';
COMMENT ON COLUMN customers.YRS_CUSTOMER IS 'The value for YRS_CUSTOMER should be: number between 1 and 8';
COMMENT ON COLUMN customers.age_range IS 'The value for age_range should be either: Silent Generation, Baby Boomer, GenX, Millenials, GenZ';

-- Create customer activity. This will use the foreign keys to ensure that only valid values are created.
CREATE TABLE activity
   (
    day_id date, 
    movie_id NUMBER, 
    cust_id NUMBER, 
    app VARCHAR2(100), 
    device VARCHAR2(100), 
    list_price NUMBER(5,2), 
    discount_percent NUMBER(5,2), 
    amount NUMBER(5,2),  
    CONSTRAINT fk_activity_cust_id FOREIGN KEY (cust_id)
      REFERENCES customers (cust_id) ENABLE,
    CONSTRAINT fk_activity_movie_id FOREIGN KEY (movie_id)
      REFERENCES award_winners (movie_id) ENABLE
   );     

-- These comments will tell the AI model how to generate data for a column
COMMENT ON COLUMN activity.day_id IS 'Date between 01-JAN-2023 and 30-SEP-2024';
COMMENT ON COLUMN activity.device IS 'Possible values: laptop, roku, appletv';
COMMENT ON COLUMN activity.list_price IS 'Possible values: 0,1.99,3.99';
COMMENT ON COLUMN activity.discount_percent IS 'Fraction between 0 and 1. If list_price is 0, then 0';
COMMENT ON COLUMN activity.amount IS 'Value equals list_price * 1-discount';
COMMENT ON COLUMN activity.app IS 'When device is roku or appletv, then MovieStreamer. Otherwise, choose MovieStreamer or browser';

--
-- Generate data based on the rules in the comments. You can add additional rules to the generate function too.
-- The data will be generated based on the rules in the column contents
-- And, data integrity rules are applied for the primary->foreign key relationships
-- This will take a few minutes 
--
BEGIN
    DBMS_CLOUD_AI.GENERATE_SYNTHETIC_DATA(
        profile_name => '&AI_PROFILE_NAME',  
        object_list => '[                          
                          {"owner": "&USER_NAME", "name": "customers","record_count":20},
                          {"owner": "&USER_NAME", "name": "activity","record_count":500}
                        ]',
		params => '{
                "comments":true,
                "priority":"HIGH"
                }'
    );
END;
/

-- Query the new data sets!
SELECT * FROM award_winners;
SELECT * FROM activity;
