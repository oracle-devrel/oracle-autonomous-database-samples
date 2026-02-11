/* Run natural language queries */

/* PREREQUISITES
    Install the sample schema using script
        @data-create-sample-schema.sql
*/

-- Run this script as the Autonomous Database database user that will be access Azure OpenAI */

-- config.sql contains the endpoints, resource groups and other settings required to connect to your Azure OpenAI deployment
@config.sql

-- Create your credential and Select AI Profile
@select-ai-create-profile.sql

-- Set that profile for this session. When using the SELECT AI command line, you need to set the current profile.
BEGIN
  dbms_cloud_ai.set_profile(
        profile_name => '&AI_PROFILE_NAME'
    );
END;
/

/**
Start asking questions!
Notice how the SQL language has been extended with new AI keywords
-- 1. chat    - general AI chat
-- 2. runsql  - [default] ask a question and get a structured result
-- 3. narrate - ask a question and get a conversational result
-- 4. showsql - SQL used to produce the result
-- 5. explainsql - explains the query and its processing
*/

-- simple chat
select ai chat what happened to the new england patriots;

-- use your data
select ai what are our total views;
select ai showsql what are our total views;

-- more sophisticated
select ai what are our total streams broken out by genre;
select ai explainsql what are our total streams broken out by genre;

select ai what are total streams by movie for tom hanks movies;

/**
There are also api's for using Select AI
*/
-- Ask another simple question
SELECT 
    DBMS_CLOUD_AI.GENERATE(
        PROMPT => 'What is Tom Hanks best known for',
        PROFILE_NAME => '&AI_PROFILE_NAME',
        ACTION       => 'chat'                     
    ) AS response
FROM dual; 




