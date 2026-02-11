-- Copyright (c) 2025 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

/* Run this script as the Autonomous Database ADMIN user */
/* You must enable network access to Azure OpenAI for the database user that will be accessing the service */

-- config.sql contains the endpoints, resource groups and other settings required to connect to your Azure OpenAI deployment
@config.sql

-- view current network access privileges
SELECT dna.host, dnp.principal, dnp.privilege, dna.acl
FROM dba_network_acls dna, dba_network_acl_privileges dnp 
WHERE dna.acl = dnp.acl
ORDER BY host, lower_port, upper_port;


BEGIN                                                                          
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(                                      
       host => '&AI_ENDPOINT',
       ace  => xs$ace_type(privilege_list => xs$name_list('http'),             
                           principal_name => '&USER_NAME',                          
                           principal_type => xs_acl.ptype_db)                  
 );                                                                            
END;                                                                           
/  