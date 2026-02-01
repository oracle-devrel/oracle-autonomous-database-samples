# Select AI - OCI Vault AI Agent & Tools

##  Overview

## OCI Vaults

OCI Vaults is a secure key and secrets management service in Oracle Cloud Infrastructure that helps you centrally store, manage, and control access to sensitive data such as encryption keys, secrets, certificates, and passwords. It supports customer-managed encryption keys backed by Hardware Security Modules (HSMs), enabling strong security, compliance, key rotation, and fine-grained access control for OCI resources and applications.

The ** Select AI OCI Vault AI Agent** enables secure, conversational management of **OCI Vault secrets and secret versions** using **Select AI (DBMS_CLOUD_AI_AGENT)** within Oracle Autonomous AI Database.

This agent is designed for **security‑critical workflows**, allowing users to create, inspect, rotate, move, and schedule deletion of secrets while enforcing **explicit confirmations, least‑privilege access, and human‑readable responses**.

It follows the same **Tools + Agent + Team** architecture used across other OCI service agents in this repository.

---

##  Why an Select AI OCI Vault AI Agent?

OCI Vault operations are sensitive and traditionally require:
- Deep familiarity with OCI APIs
- Correct handling of secret versions and stages
- Careful scheduling of deletions
- Manual guardrails for destructive actions

---

##  Architecture Overview

```text
User Request
   ↓
OCI Vault Task
   ↓
Agent Reasoning & Validation
   ├── Discovery Tools (Regions, Compartments, Namespace)
   ├── Secret Inventory Tools
   ├── Secret & Version Inspection Tools
   ├── Secret Creation & Rotation Tools
   ├── Deletion Scheduling & Cancellation Tools
   └── Compartment Management Tools
   ↓
Confirmed Vault Operation + Result
```

---

##  Repository Contents

```text
.
├── oci_vault_tools.sql
│   ├── PL/SQL OCI Vault wrapper package
│   ├── Secure configuration & credential handling
│   ├── Secret & version management functions
│   └── AI tool registrations
│
├── oci_vault_agent.sql
│   ├── Task definition
│   ├── Agent creation
│   ├── Team creation
│   └── AI profile binding
│
└── README.md
```

---

## Prerequisites

- Oracle Autonomous AI Database
- Select AI enabled
- OCI Vault access
- OCI credential or Resource Principal
- ADMIN or equivalent privileged user

---

##  Installation – Tools

Run as ADMIN (or privileged user):

```sql
sqlplus admin@db @oci_vault_tools.sql
```

### Optional Configuration JSON

```json
{ 
  "credential_name": "OCI_CRED",
  "compartment_name": "MY_COMPARTMENT"
}
```

> Configuration is stored securely in table `SELECTAI_AGENT_CONFIG`  
> and can be updated post‑installation.

### What This Script Does

- Grants required OCI Vault–related DBMS_CLOUD privileges
- Creates the `OCI_VAULT_AGENTS` PL/SQL package
- Initializes `SELECTAI_AGENT_CONFIG`
- Enables Resource Principal (by default)
- Registers all OCI Vault AI tools

---

##  Available AI Tools (High‑Level)

###  Discovery & Inventory
- List subscribed regions
- List compartments
- Resolve compartment OCID
- List secrets (metadata only)

###  Secret & Version Inspection
- Get secret metadata
- List secret versions
- Get specific secret version details

###  Creation & Rotation
- Create new secrets
- Rotate secrets (new CURRENT version)
- Update metadata, tags, and rules

###  Deletion & Recovery Control
- Schedule secret deletion
- Schedule secret version deletion
- Cancel scheduled deletions

###  Organization & Governance
- Change secret compartment
- Inspect agent configuration

>  Secret payloads are **never returned** by any tool.

---

##  Installation – Agent & Team

Run:

```sql
sqlplus admin@db @oci_vault_agent.sql
```

### Prompts
- Target schema name
- AI Profile name

### Objects Created

| Object | Name |
|--------|------|
| Task   | OCI_VAULT_TASKS |
| Agent  | OCI_VAULT_ADVISOR |
| Team   | OCI_VAULT_TEAM |

---

##  Task Intelligence Highlights

The Vault task enforces:
- Intent detection before execution
- Mandatory confirmation for destructive actions
- Human‑readable formatting of responses
- Strict separation of metadata vs secret material

---

##  Extending the Vault Agent

### Recommended Pattern

**Keep Vault API logic inside tools.  
Define rules in tasks.  
Bind permissions via AI profiles.**

### Example Extensions
- Read‑only secrets audit agent
- Automated secret rotation agent
- Compliance & lifecycle enforcement agent

---

##  Best Practices

- Separate read‑only and admin Vault agents
- Prefer scheduled deletion over immediate removal
- Rotate secrets regularly using versioning

---

## Example Prompts

After creating the OCI Vault AI Agent, users can interact with it using prompts such as:

### Discovery & Metadata
- “Get the Object Storage namespace for the Mumbai region.”
- “Resolve Vault namespace and compartment metadata for the Mumbai region.”
- “Get the OCID for the compartment named `Security`.”
- “List all compartments available for Vault operations.”

### Secrets Management
- “Create a secret named `db-password` in vault `<vault_ocid>` using key `<key_ocid>` in the Mumbai region.”
- “Create a secret named `api-token` with description `API access token` in the Mumbai region.”
- “Get details of the secret with OCID `<secret_ocid>`.”
- “List all secrets in the Mumbai region.”

### Secret Versions
- “List all versions of the secret `<secret_ocid>` in the Mumbai region.”
- “Get version 2 of the secret `<secret_ocid>`.”
- “Update the secret `<secret_ocid>` with a new value.”
- “Update the description of the secret `<secret_ocid>`.”

### Secret Deletion & Recovery
- “Schedule deletion of the secret `<secret_ocid>` after 7 days.”
- “Schedule deletion of version 1 of the secret `<secret_ocid>`.”
- “Cancel the scheduled deletion of the secret `<secret_ocid>`.”
- “Cancel the scheduled deletion of version 1 of the secret `<secret_ocid>`.”

### Compartment Management
- “Move the secret `<secret_ocid>` to a different compartment.”

### Agent Configuration
- “Get the AI agent configuration for schema `ADMIN`, table `AGENT_CONFIG`, and agent name `vault-agent`.”


##  License

Universal Permissive License (UPL) 1.0  
https://oss.oracle.com/licenses/upl/

---

## ✨ Final Thoughts

The OCI Vault AI Agent turns secret management into a **guided conversational workflow**, ensuring that security‑critical operations remain controlled while still benefiting from automation.

Designed for:
- Security & platform teams
- Compliance automation
- Enterprise secret governance
