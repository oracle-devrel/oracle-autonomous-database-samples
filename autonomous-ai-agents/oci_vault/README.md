# OCI Vault AI Agent & Tools

## 🚀 Overview

The **OCI Vault AI Agent** enables secure, conversational management of **OCI Vault secrets and secret versions** using **Select AI (DBMS_CLOUD_AI_AGENT)** within Oracle Autonomous Database.

This agent is designed for **security‑critical workflows**, allowing users to safely create, inspect, rotate, move, and schedule deletion of secrets while enforcing **explicit confirmations, least‑privilege access, and human‑readable responses**.

It follows the same **Tools + Agent + Team** architecture used across other OCI service agents in this repository.

---

## 🧠 Why an OCI Vault AI Agent?

OCI Vault operations are sensitive and traditionally require:
- Deep familiarity with OCI APIs
- Correct handling of secret versions and stages
- Careful scheduling of deletions
- Manual guardrails for destructive actions

This AI agent improves safety and usability by:
- Detecting **user intent** before acting
- Asking **clarifying questions** for ambiguous requests
- Enforcing **confirmation for destructive operations**
- Never exposing secret payloads in responses
- Returning **auditable, structured metadata**

---

## 🧱 Architecture Overview

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

## 📦 Repository Contents

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

## 🛠 Prerequisites

- Oracle Autonomous Database (23ai recommended)
- Select AI enabled
- OCI Vault access
- OCI credential or Resource Principal
- ADMIN or equivalent privileged user

---

## ⚙️ Installation – Tools

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

> Configuration is stored securely in `SELECTAI_AGENT_CONFIG`  
> and can be updated post‑installation.

### What This Script Does

- Grants required OCI Vault–related DBMS_CLOUD privileges
- Creates the `OCI_VAULT_AGENTS` PL/SQL package
- Initializes `SELECTAI_AGENT_CONFIG`
- Enables Resource Principal (by default)
- Registers all OCI Vault AI tools

---

## 🧩 Available AI Tools (High‑Level)

### 🔍 Discovery & Inventory
- List subscribed regions
- List compartments
- Resolve compartment OCID
- List secrets (metadata only)

### 🔐 Secret & Version Inspection
- Get secret metadata
- List secret versions
- Get specific secret version details

### 🔄 Creation & Rotation
- Create new secrets
- Rotate secrets (new CURRENT version)
- Update metadata, tags, and rules

### 🗑 Deletion & Recovery Control
- Schedule secret deletion
- Schedule secret version deletion
- Cancel scheduled deletions

### 📦 Organization & Governance
- Change secret compartment
- Inspect agent configuration

> ⚠️ Secret payloads are **never returned** by any tool.

---

## 🤖 Installation – Agent & Team

Run:

```sql
sqlplus admin@db @oci_vault_agent.sql
```

### Prompts
- Target schema name
- AI Profile name

### Objects Created

| Object | Name |
|------|------|
| Task | OCI_VAULT_TASKS |
| Agent | OCI_VAULT_ADVISOR |
| Team | OCI_VAULT_TEAM |

---

## 🧠 Task Intelligence Highlights

The Vault task enforces:
- Intent detection before execution
- Mandatory confirmation for destructive actions
- Human‑readable formatting of responses
- Safe sequencing of Vault operations
- Strict separation of metadata vs secret material

---

## 🧱 Extending the Vault Agent

### Recommended Pattern

**Keep Vault API logic inside tools.  
Define safety rules in tasks.  
Bind permissions via AI profiles.**

### Example Extensions
- Read‑only secrets audit agent
- Automated secret rotation agent
- Compliance & lifecycle enforcement agent
- Multi‑compartment governance agent

---

## 🔄 Safe Re‑Execution

All scripts are **safe to re‑run**:
- Tasks, agents, and teams are dropped and recreated
- Secrets are never modified implicitly
- Destructive operations always require confirmation

---

## 📌 Best Practices

- Use Resource Principal whenever possible
- Separate read‑only and admin Vault agents
- Prefer scheduled deletion over immediate removal
- Rotate secrets regularly using versioning
- Audit secret metadata instead of values

---

## 📜 License

Universal Permissive License (UPL) 1.0  
https://oss.oracle.com/licenses/upl/

---

## ✨ Final Thought

The OCI Vault AI Agent turns secret management into a **guided, auditable, and safe conversational workflow**, ensuring that security‑critical operations remain controlled while still benefiting from automation.

Designed for:
- Security & platform teams
- Compliance automation
- Enterprise secret governance
- Safe cloud operations
