# Select AI - OCI Object Storage AI Agent & Tools

##  Overview

The **Select AI - OCI Object Storage AI Agent** enables natural-language–driven automation and advisory capabilities for **OCI Object Storage**, powered by **Select AI (DBMS_CLOUD_AI_AGENT)**.

This agent allows users to manage buckets, objects, lifecycle policies, retention rules, replication, multipart uploads, and work requests using **conversational instructions**, while enforcing **safety, confirmations, and clarity**.

The design follows a **Tools + Agent + Team** architecture, making it scalable, auditable, and easy to extend.

---

##  Why This Object Storage Agent Matters

Traditional Object Storage operations require:
- Deep knowledge of OCI APIs
- Correct sequencing of multiple steps
- Manual confirmation handling
- Error-prone scripting

This AI agent improves reliability by:
- Understanding user intent before acting
- Prompting only for missing inputs
- Confirming destructive operations explicitly
- Automatically deriving namespace and region context
- Presenting results in human-readable formats

---

##  Architecture Overview

```text
User Request
   ↓
OCI Object Storage Task
   ↓
Agent Reasoning & Validation
   ├── Discovery Tools (Regions, Compartments, Namespace)
   ├── Bucket Management Tools
   ├── Object Operations Tools
   ├── Lifecycle & Retention Tools
   ├── Replication & Encryption Tools
   └── Work Request Monitoring Tools
   ↓
Confirmed Operation + Result
```

---

##  Repository Contents

```text
.
├── oci_object_storage_tools.sql
│   ├── PL/SQL OCI Object Storage wrapper package
│   ├── Authentication & namespace resolution
│   ├── Bucket, object, lifecycle, replication APIs
│   └── AI tool registrations
│
├── oci_object_storage_agent.sql
│   ├── Task definition
│   ├── Agent creation
│   ├── Team creation
│   └── AI profile binding
│
└── README.md
```

---

##  Prerequisites

- Oracle Autonomous Database (23ai recommended)
- Select AI enabled
- OCI Object Storage access
- OCI credential or Resource Principal
- ADMIN or equivalent privileged user

---

##  Installation – Tools

Run as ADMIN (or privileged user):

```sql
sqlplus admin@db @oci_object_storage_tools.sql
```

> Configuration (credential, region, compartment) can be provided during install or later via `SELECTAI_AGENT_CONFIG`.

### What This Script Does

- Grants required `DBMS_CLOUD` and Select AI privileges
- Creates `OCI_OBJECT_STORAGE_AGENTS` PL/SQL package
- Registers all Object Storage AI tools
- Enables namespace discovery and secure OCI access

---

##  Available AI Tools (High-Level)

###  Discovery & Metadata
- List subscribed regions
- List compartments
- Derive Object Storage namespace
- List buckets
- Get bucket details

###  Bucket Management
- Create, update, delete buckets
- Enable/disable versioning
- Manage public access
- Re-encrypt buckets
- Configure lifecycle policies

###  Object Operations
- List, get, head, put, delete objects
- Rename and copy objects
- Restore archived objects
- Multipart upload (create, upload part, commit, abort)

###  Security & Access
- Pre-authenticated requests (create, list, delete)
- Retention rules (create, update, delete)
- Replication policies
- Namespace metadata updates

###  Work Requests & Monitoring
- List work requests
- Get work request details
- View logs and errors
- Cancel work requests

---

##  Installation – Agent & Team

Run:

```sql
sqlplus admin@db @oci_object_storage_agent.sql
```

### Prompts
- Target schema name
- AI Profile name

### Objects Created

| Object | Name |
|------|------|
| Task | OCI_OBJECTSTORE_TASKS |
| Agent | OCI_OBJECT_STORAGE_ADVISOR |
| Team | OCI_OBJECTSTORE_TEAM |

---

##  Task Intelligence Highlights

The task enforces:
- Intent detection before execution
- Clarifying questions for incomplete input
- Mandatory confirmation for destructive actions
- Automatic namespace resolution
- Human-readable formatting of outputs
- Safe automation of Object Storage operations

---

##  Extending & Generalizing the Agent

### Recommended Pattern

**Keep OCI logic inside tools.  
Define behavior in tasks.  
Bind permissions via AI profiles.**

### Example Extensions
- Read-only Object Storage audit agent
- Lifecycle and cost-optimization agent
- Cross-region replication advisor
- Security-focused retention enforcement agent

---

##  Safe Re-Execution

All scripts are **safe to re-run**:
- Tasks, agents, and teams are dropped and recreated
- No Object Storage resources are modified implicitly
- Destructive actions always require confirmation

---

##  Best Practices

- Always confirm bucket and object deletions
- Prefer Resource Principal in OCI environments
- Separate read-only and admin agents
- Use lifecycle rules instead of manual cleanup
- Monitor work requests for long-running operations

---

##  License

Universal Permissive License (UPL) 1.0  
https://oss.oracle.com/licenses/upl/

---

## ✨ Final Thought

This OCI Object Storage AI Agent transforms Object Storage from an API-driven service into a **guided, conversational automation platform**, combining safety, clarity, and power.

Designed for:
- Cloud platform teams
- DevOps automation
- Data lake operations
- Secure enterprise workflows
