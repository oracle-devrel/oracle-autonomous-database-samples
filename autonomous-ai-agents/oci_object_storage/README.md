# Select AI - OCI Object Storage AI Agent and Tools

##  Overview

## OCI Object Storage

OCI Object Storage is a highly scalable and durable storage service in Oracle Cloud Infrastructure that enables you to securely store and retrieve unstructured data such as files, backups, logs, and media. It offers high availability, strong security with encryption, lifecycle management, and seamless integration with OCI services and applications.

The **Select AI - OCI Object Storage AI Agent** enables natural-language–driven automation and advisory capabilities for **OCI Object Storage**, powered by **Select AI (DBMS_CLOUD_AI_AGENT)**.

This agent allows users to manage buckets, objects, lifecycle policies, retention rules, replication, multipart uploads, and work requests using **conversational instructions**, while enforcing ** confirmations, and clarity**.

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
Agent Reasoning and Validation
   ├── Discovery Tools (Regions, Compartments, Namespace)
   ├── Bucket Management Tools
   ├── Object Operations Tools
   ├── Lifecycle and Retention Tools
   ├── Replication and Encryption Tools
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
│   ├── Authentication and namespace resolution
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

### Input Parameters required to run
- Target schema name (Schema where to the agent team needs to be installed)
- Cloud Config Parameters.
  - OCI Credentials - Required to access to Object Storage buckets.
  - Compartment Name 

> Configuration (credential, region, compartment) can be provided during install or later via `SELECTAI_AGENT_CONFIG`.

### What This Script Does

- Grants required `DBMS_CLOUD` and Select AI privileges
- Creates `OCI_OBJECT_STORAGE_AGENTS` PL/SQL package
- Registers all Object Storage AI tools
- Enables namespace discovery and secure OCI access

---

##  Available AI Tools (High-Level)

###  Discovery and Metadata
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

###  Security and Access
- Pre-authenticated requests (create, list, delete)
- Retention rules (create, update, delete)
- Replication policies
- Namespace metadata updates

###  Work Requests and Monitoring
- List work requests
- Get work request details
- View logs and errors
- Cancel work requests

---

##  Installation – Agent and Team

Run:

```sql
sqlplus admin@db @oci_object_storage_agent.sql
```

### Input Parameters required to run
- Target schema name (Schema where to the agent team needs to be installed)
- AI Profile name (Select AI Profile name that needs to be used with the Agent)

### Objects Created

| Object | Name |
|--------|------|
| Task   | OCI_OBJECTSTORE_TASKS |
| Agent  | OCI_OBJECT_STORAGE_ADVISOR |
| Team   | OCI_OBJECTSTORE_TEAM |

---

##  Task Intelligence Highlights

The task enforces:
- Intent detection before execution
- Clarifying questions for incomplete input
- Mandatory confirmation for destructive actions
- Automatic namespace resolution
- Human-readable formatting of outputs

---

##  Extending and Generalizing the Agent

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

##  Best Practices

- Always confirm bucket and object deletions
- Use lifecycle rules instead of manual cleanup
- Monitor work requests for long-running operations

---

## Example Prompts

After creating the OCI Object Storage AI Agent, users can interact with it using prompts such as:

### Buckets and Namespace
- “List all Object Storage buckets in the Mumbai region.”
- “Get details of the bucket named `finance-reports` in the Mumbai region.”
- “Check whether the bucket `finance-reports` exists in the Mumbai region.”
- “Get the Object Storage namespace for the Mumbai region.”
- “Create a new bucket named `archive-bucket` in the Mumbai region.”
- “Delete the bucket named `archive-bucket` in the Mumbai region.”

### Objects
- “List all objects in the bucket `finance-reports` in the Mumbai region.”
- “Get the object `q1-report.pdf` from the bucket `finance-reports`.”
- “Upload an object named `summary.json` to the bucket `finance-reports` with content type `application/json`.”
- “Delete the object `old-report.pdf` from the bucket `finance-reports`.”
- “Rename the object `draft.txt` to `final.txt` in the bucket `finance-reports`.”
- “Copy the object `q1-report.pdf` from the bucket `finance-reports` to the bucket `finance-archive` in the Hyderabad region.”

### Object Metadata and Versions
- “Get metadata for the object `q1-report.pdf` in the bucket `finance-reports`.”
- “List all versions of objects in the bucket `finance-reports`.”

### Multipart Uploads
- “Create a multipart upload for the object `large-video.mp4` in the bucket `media-files`.”
- “List all active multipart uploads in the bucket `media-files`.”
- “List uploaded parts for multipart upload ID `<upload_id>` of object `large-video.mp4`.”

### Bucket Configuration
- “Enable versioning and object events for the bucket `finance-reports`.”
- “Make the bucket `finance-reports` writable.”
- “Apply a lifecycle policy to delete objects older than 30 days in the bucket `finance-reports`.”
- “Delete the lifecycle policy for the bucket `finance-reports`.”

### Retention Rules
- “List all retention rules for the bucket `finance-reports`.”
- “Create a retention rule to retain objects for 7 days in the bucket `finance-reports`.”
- “Get details of retention rule with ID `<retention_rule_id>`.”
- “Update the retention rule `<retention_rule_id>` to retain objects for 14 days.”
- “Delete the retention rule `<retention_rule_id>`.”

### Pre-Authenticated Requests (PAR)
- “List all pre-authenticated requests for the bucket `finance-reports`.”
- “Get details of the pre-authenticated request with ID `<par_id>`.”
- “Delete the pre-authenticated request with ID `<par_id>`.”

### Replication
- “List all replication policies for the bucket `finance-reports`.”
- “Create a replication policy to replicate the bucket `finance-reports` to `finance-reports-dr` in the Hyderabad region.”
- “Get details of replication policy with ID `<replication_id>`.”
- “Delete the replication policy with ID `<replication_id>`.”
- “List all replication source buckets for the bucket `finance-reports`.”

### Encryption and Security
- “Re-encrypt the bucket `finance-reports`.”
- “Re-encrypt the object `q1-report.pdf` in the bucket `finance-reports` using a new KMS key.”

### Object Restore
- “Restore the object `archived-report.pdf` from Archive Storage for 24 hours.”
- “Restore version `<version_id>` of the object `archived-report.pdf`.”

### Work Requests and Operations
- “List all Object Storage work requests in the Mumbai region.”
- “Get details of the work request with ID `<work_request_id>`.”


##  License

Universal Permissive License (UPL) 1.0  
https://oss.oracle.com/licenses/upl/

---

## ✨ Final Thoughts

This OCI Object Storage AI Agent transforms Object Storage from an API-driven service into a **guided, conversational automation platform**, combining  clarity, and power.

Designed for:
- Cloud platform teams
- DevOps automation
- Data lake operations
- Secure enterprise workflows
