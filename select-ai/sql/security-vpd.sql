-- Copyright (c) 2025 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

CREATE TABLE "MOVIESTREAM"."VGSALES" 
   (	"NAME" VARCHAR2(4000 BYTE) COLLATE "USING_NLS_COMP", 
	"PLATFORM" VARCHAR2(4000 BYTE) COLLATE "USING_NLS_COMP", 
	"YEAR_OF_RELEASE" NUMBER, 
	"GENRE" VARCHAR2(4000 BYTE) COLLATE "USING_NLS_COMP", 
	"PUBLISHER" VARCHAR2(4000 BYTE) COLLATE "USING_NLS_COMP", 
	"NA_SALES" NUMBER, 
	"EU_SALES" NUMBER, 
	"JP_SALES" NUMBER, 
	"OTHER_SALES" NUMBER, 
	"GLOBAL_SALES" NUMBER, 
	"CRITIC_SCORE" NUMBER, 
	"CRITIC_COUNT" NUMBER, 
	"USER_SCORE" NUMBER, 
	"USER_COUNT" NUMBER, 
	"DEVELOPER" VARCHAR2(4000 BYTE) COLLATE "USING_NLS_COMP", 
	"RATING" VARCHAR2(4000 BYTE) COLLATE "USING_NLS_COMP"
   )  DEFAULT COLLATION "USING_NLS_COMP" ;

CREATE OR REPLACE FUNCTION hide_eu (
 v_schema IN VARCHAR2, 
 v_objname IN VARCHAR2)

RETURN VARCHAR2 AS
con VARCHAR2 (200);

BEGIN
 con := 'Year_of_release=2009';
 RETURN (con);
END hide_eu;

BEGIN
    dbms_rls.drop_policy(object_schema => 'MOVIESTREAM',object_name=>'VGSALES',policy_name=>'hide_year');
end;

BEGIN
 DBMS_RLS.ADD_POLICY(
   object_schema         => 'MOVIESTREAM', 
   object_name           => 'VGSALES',
   policy_name           => 'hide_year', 
   policy_function       => 'hide_eu',
   sec_relevant_cols     =>'eu_sales',
   sec_relevant_cols_opt => dbms_rls.ALL_ROWS);
END;