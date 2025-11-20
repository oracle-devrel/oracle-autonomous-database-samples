# Autonomous AI Agents — Quick Install Guide (OCI Object Storage + OCI Vault)

This guide shows how to install and use the two SQL installer scripts:
- oci_object_storage_agent_install.sql
- oci_vault_agent_install.sql

What gets installed
- A config table in your target schema: OCI_AGENT_CONFIG
- A PL/SQL package with ready-to-use functions
- AI Agent tools (DBMS_CLOUD_AI_AGENT) mapped to those functions

Important
- INSTALL_SCHEMA is mandatory. Always set it.

Prerequisites
- A DBMS_CLOUD credential with OCI permissions for the target compartment(s)
- The target schema name (INSTALL_SCHEMA) where packages/tools/config will live

1) Create or identify a DBMS_CLOUD credential
Example (if needed):
```
BEGIN
  DBMS_CLOUD.CREATE_CREDENTIAL(
    credential_name => 'MY_CRED',
    username        => '<oci_user_or_principal>',
    password        => '<oci_auth_token_or_secret>'
  );
END;
/
```

2) Install — set variables and run the scripts
Use SQL*Plus q'(...)' quoting for JSON so you don't need to escape quotes.

Connect:
```
sqlplus admin@<tns_alias>
```

Set variables (mandatory INSTALL_SCHEMA, optional INSTALL_CONFIG_JSON):
```
DEFINE INSTALL_SCHEMA = 'YOUR_APP_SCHEMA';
DEFINE INSTALL_CONFIG_JSON = q'({"credential_name": "MY_CRED", "compartment_name": "MY_COMP"})';
```

Run one or both installers:
```
@autonomous_ai_agents/oci_object_storage_agent_install.sql
@autonomous_ai_agents/oci_vault_agent_install.sql
```

Notes
- INSTALL_CONFIG_JSON is optional (defaults to NULL).
- Recommended keys to include if you pass JSON:
  - credential_name: your DBMS_CLOUD credential name
  - compartment_name: name of the compartment

3) If you didn’t pass INSTALL_CONFIG_JSON, you can still configure the 
agent after installation by adding rows to YOUR_APP_SCHEMA.OCI_AGENT_CONFIG.
Each agent has its own AGENT value
- For object storage use OCI_OBJECT_STORAGE
- For vault use OCI_VAULT

Examples (Object Storage)

Set credential name for Object Storage operations:
```
INSERT INTO YOUR_APP_SCHEMA.OCI_AGENT_CONFIG ("KEY","VALUE","AGENT")
VALUES ('CREDENTIAL_NAME', 'MY_CRED', 'OCI_OBJECT_STORAGE');
```

Set compartment name for Vault
```
INSERT INTO YOUR_APP_SCHEMA.OCI_AGENT_CONFIG ("KEY","VALUE","AGENT")
VALUES ('COMPARTMENT_NAME', 'MY_COMP', 'OCI_VAULT');
```

