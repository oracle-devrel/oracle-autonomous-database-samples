-- Copyright (c) 2025 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

/* Apply AI SQL function to your data to summarize information, derive sentiment, key phrases, extract fields from text */

-- Run this script as the Autonomous Database database user that will be accesssing your AI service

-- config.sql contains the configuration properties, like endpoints, credentials, AI providers and more
@config.sql

-- Create your credential and Select AI Profile
@select-ai-create-profile.sql

/*
    Parse the various components of an address
*/
with example as (
    select ('38 Newbury St, Office #3, Boston, MA 02116') as address
    from dual
),
json_string as (
select 
    dbms_cloud_ai.generate (
        action => 'chat',
        profile_name => '&AI_PROFILE_NAME',
        prompt => 'Parse the given address without any comments. Only return valid JSON - no other text.' 
            || 'The result should be 1) a json object for that address and 2) be simple text, not markdown. '
            || 'Here are the required JSON object fields: {addressNumber, streetName, unitNumber, city, state, zip}. '
            || 'Apply to the following address: ' || address
    ) as address_json
from example
)
select 
    json_value(address_json, '$.addressNumber') as address_number,
    json_value(address_json, '$.streetName') as street,
    json_value(address_json, '$.unitNumber') as unit,
    json_value(address_json, '$.city') as city,
    json_value(address_json, '$.state') as state,
    json_value(address_json, '$.zip') as zip
from json_string j;

/*
Do the same as above, but ths time, batch up numerous addresses
*/
-- Create the table containing addresses
drop table if exists temp_address;
CREATE TABLE temp_address (
    address VARCHAR2(200)
);

INSERT INTO temp_address (address) VALUES
('123 Main St, Apt 3, Springfield, IL 62701'),
('456 Elm Ave, #9, Rivertown, CA 90210'),
('789 Oak Rd, Lakeside, NY 10001'),
('101 Pine Ln, Mountain View, CO 80301'),
('202 Maple Dr, Seaside, FL 33139'),
('303 Cedar Blvd, Forest Hills, OR 97034'),
('404 Birch St, Hilltown, TX 75001'),
('505 Willow Way, Meadowville, WA 98101'),
('606 Spruce Ct, Sunnydale, AZ 85001'),
('707 Redwood Rd, Greenfield, MA 01301');

commit;

-- Do this in batches. Here, we'll do all the addresses b/c there are 10 of them
-- First, turn the rows into a json array 
-- Send that to the model to transform - returning an array of json objects
-- Turn that array of json objects into a tabular result
WITH json_address_array AS (
    SELECT JSON_ARRAYAGG(
        JSON_OBJECT('address' VALUE address) RETURNING CLOB) AS addresses
    FROM temp_address
),
json_address_with_fields AS (
SELECT
    dbms_cloud_ai.generate (
        action => 'chat',
        profile_name => '&AI_PROFILE_NAME',
        prompt => 'Parse the given address list without any comments. Only return valid JSON - no other text.' 
            || 'The result should be 1) a json array with an json object for each address and 2) be simple text, not markdown. '
            || 'Here are the required JSON object fields: {addressNumber, streetName, unitNumber, city, state, zip}. '
            || 'Apply to the following list of address: ' || addresses
    ) as address_json
FROM json_address_array)
SELECT jt.*
FROM json_address_with_fields,
     JSON_TABLE(address_json, '$[*]'
       COLUMNS (
         addressNumber VARCHAR2(10) PATH '$.addressNumber',
         streetName VARCHAR2(100) PATH '$.streetName',
         unitNumber VARCHAR2(10) PATH '$.unitNumber',
         city VARCHAR2(150) PATH '$.city',
         state VARCHAR2(10) PATH '$.state',
         zip VARCHAR2(10) PATH '$.zip'
       )
     ) jt
;


/*
Derive the address from free-form text
*/
with example as (
    select ('I live in Brookline MA. ' 
            || 'Why don''t you come by at 10. Walk over to 1785 Beacon Street. Get ready to walk up some stairs' 
            || ' - I''m in apartment is 6f.') as text
    from dual
)
select 
    dbms_cloud_ai.generate (
        action => 'chat',
        profile_name => '&AI_PROFILE_NAME',
        prompt => 'Parse the given text and extract the street address without any comments. '  
            || 'The result should simple text, not markdown and in the following format: '
            || 'street, apartment, city, state, country, zip code. Here is an example formatted result: ' 
            || '1 Main St, Westfield, NJ USA 07090. Apply these rules to the following text: '
            || text  
    ) as address
from example;


/* Summarize a support chat and derive the support rep, key phrases and sentiment */

with example as (
    select 'I was so frustrated trying to resolve my billing issue. I spoke with Marty, who seemed completely uninterested in helping and kept transferring me to different departments. I feel like I wasted an hour of my time and still don''t have a solution.' as support_chat
),
summarize_json as (
select 
    dbms_cloud_ai.generate (
        action => 'chat',
        profile_name => '&AI_PROFILE_NAME',
        prompt => 'Summarize the support chat into the following json values without any comments - only return valid JSON - no other text: {summary, keyPhrases, sentiment, supportRep}. content: '
            || support_chat || '.  The result should 1) be a valid json document that can be validated against a json schema, 2) begin with { and end with }, 3) be simple text, not markdown. ' 
            || 'Apply these rules to determine the values: ' 
            || 'supportRep: the name of the customer service representative, '
            || 'summary: a 2 sentence summary of the support conversation,'
            || 'keyPhrases: Extract 2 of the most important keywords and phrases from the conversation. Focus on terms that capture the main topics, key ideas, and significant points discussed,'
            || 'sentiment:  return one value - Positive or Negative'
    ) as chat_info
from example
)
select 
    json_value(chat_info, '$.supportRep') as support_rep,
    json_query(chat_info, '$.keyPhrases') as key_phrases,
    json_value(chat_info, '$.sentiment') as sentiment,
    json_value(chat_info, '$.summary') as summary,
    chat_info
from summarize_json;


