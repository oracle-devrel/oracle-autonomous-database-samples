# Select AI - OCI Autonomous Database AI Agent and Tools

##  Overview

The **Select AI - OCI Autonomous Database AI Agent** enables natural-language–driven provisioning, management, and advisory operations for **Oracle Autonomous Databases on OCI**, powered by **Select AI (DBMS_CLOUD_AI_AGENT)**.

With this agent, users can provision databases, run lifecycle and scaling operations, inspect configuration and backups, and perform guided administrative workflows using natural-language instructions.

Unlike traditional scripts or consoles, this agent allows users to:
- Provision and manage Autonomous Databases conversationally
- Run lifecycle operations with confirmations
- Discover OCI resources dynamically (regions, compartments, databases)
- Automate complex OCI workflows through reusable AI tools

For definitions of **Tool**, **Task**, **Agent**, and **Agent Team**, see the top-level guide: [README](../README.md#simple-agent-execution-flow).

---

##  Why This Agent Is Powerful

Compared to manual OCI operations or simple chat-based automation, this agent:

- Understands **user intent** before acting
- Prompts for **missing or ambiguous inputs**
- Requires **explicit confirmation for destructive actions**
- Uses **OCI-native APIs** through PL/SQL wrappers
- Produces **human-readable outputs**, not raw JSON dumps

---

##  Architecture Overview

```text
User Request
   ↓
OCI Autonomous Database Task
   ↓
Agent Reasoning and Validation
   ├── Discovery Tools (Regions, Compartments, Databases)
   ├── Provisioning Tools
   ├── Lifecycle Management Tools
   ├── Configuration and Scaling Tools
   └── Maintenance and Backup Tools
   ↓
Confirmed OCI Operation + Result
```

---

##  Repository Contents

```text
.
├── oci_autonomous_database_tools.sql
│   ├── PL/SQL OCI wrapper package
│   ├── OCI authentication and config handling
│   ├── Autonomous Database lifecycle functions
│   └── AI tool registrations
│
├── oci_autonomous_database_agent.sql
│   ├── Task definition
│   ├── Agent creation
│   ├── Team creation
│   └── AI profile binding
│
└── README.md
```

---

##  Prerequisites

- Oracle Autonomous AI Database (26ai recommended)
- Select AI enabled
- OCI credential or Resource Principal
- Access to OCI compartments with ADB permissions
- ADMIN user

---

##  Installation – Tools

Before running installation commands:

1. Clone or download this repository.
2. Open a terminal and change directory to `autonomous-ai-agents/oci_autonomous_database`.
3. Choose one execution mode:
   - SQL*Plus/SQLcl: run script files directly with `@script_name`.
   - SQL Worksheet (Database Actions or other SQL IDE): open the `.sql` file and run/paste its contents.
4. Uploading scripts to `DATA_PUMP_DIR` is not required for these methods.

Run as `ADMIN` (or another privileged user):

```sql
sqlplus admin@<adb_connect_string> @oci_autonomous_database_tools.sql
```

### Input Parameters required to run
- Target schema name (Schema where to the agent team needs to be installed)
- Cloud Config Parameters.
  - OCI Credentials - Required to access to Object Storage buckets.
  - Compartment Name 
  
### Optional Configuration JSON

```json
{
  "use_resource_principal": true,
  "credential_name": "OCI_CRED",
  "compartment_name": "MY_COMPARTMENT"
}
```

> Configuration can also be updated later in `SELECTAI_AGENT_CONFIG`.

### What This Script Does

- Grants required DBMS_CLOUD privileges
- Creates `OCI_AUTONOMOUS_DATABASE_AGENTS` package
- Registers OCI Autonomous Database AI tools
- Stores OCI configuration securely

---

##  Available AI Tools (High Level)

### 🔍 Discovery and Metadata
- List subscribed regions
- List compartments
- Resolve compartment OCID by name
- List Autonomous Databases
- Get Autonomous Database details

###  Provisioning and Lifecycle
- Provision Autonomous Database
- Start / Stop / Restart database
- Scale CPU and storage
- Enable / manage autoscaling
- Shrink database
- Delete Autonomous Database (confirmed)

###  Configuration and Updates
- Update database attributes
- Manage power model
- Modify workload and edition
- Update network and security settings
- Manage tags

###  Maintenance and Backup
- List maintenance run history
- List Autonomous Database backups
- List DB homes
- List key stores
- Delete key stores

---

##  Installation – Agent and Team

From `autonomous-ai-agents/oci_autonomous_database`, run:

```sql
sqlplus admin@<adb_connect_string> @oci_autonomous_database_agent.sql
```

You can also execute the contents of `oci_autonomous_database_agent.sql` in SQL Worksheet.

### Input Parameters required to run.
- Target schema name (Schema where to the agent team needs to be installed)
- AI Profile name (Select AI Profile name that needs to be used with the Agent)

### Objects Created

| Object | Name |
|------|------|
| Task | OCI_AUTONOMOUS_DATABASE_TASKS |
| Agent| OCI_AUTONOMOUS_DATABASE_ADVISOR |
| Team | OCI_AUTONOMOUS_DATABASE_TEAM |

---

##  Task Intelligence Highlights

The task enforces:

- Intent detection before execution
- Clarifying questions for incomplete input
- Mandatory confirmation for destructive actions
- Human-readable formatting of OCI outputs

---

##  Extending and Generalizing the Agent

### Recommended Pattern

**Keep OCI logic in tools.  
Use tasks to define behavior.  
Bind profiles at agent level.**

### Example Extensions
- Separate agents for **Provisioning**, **Operations**, and **Cost Optimization**
- Read-only advisory agent
- Policy-enforced enterprise agent
- Multi-region orchestration teams

---

##  Best Practices

- Always use confirmation for destructive actions
- Prefer Resource Principal in OCI environments
- Keep provisioning and advisory agents separate
- Use compartment scoping to enforce boundaries
- Review AI profile permissions carefully

---

## Example Prompts

After creating the Oracle Autonomous Database AI Agent, users can interact with it using prompts such as:

### Discovery and Setup
- “List all OCI regions I am subscribed to.”
- “Show all compartments in my tenancy.”

### Provisioning Autonomous Databases
- “Help me to Provision a new Autonomous Transaction Processing database"

### Listing and Inspecting Databases
- “List all Autonomous Databases in the `Finance` compartment in the Mumbai region.”
- “Get detailed information for the Autonomous Database with OCID `<db_ocid>`.”

### Power and Lifecycle Management
- “Start the Autonomous Database with OCID `<db_ocid>` in the Mumbai region.”
- “Stop the Autonomous Database with OCID `<db_ocid>`.”
- “Restart the Autonomous Database with OCID `<db_ocid>`.”

### Scaling and Resource Management
- “Increase the CPU count of the Autonomous Database `<db_ocid>` to 8 cores.”
- “Update the storage size of the Autonomous Database `<db_ocid>` to 2 TB.”
- “Shrink the Autonomous Database `<db_ocid>` to optimize storage usage.”

### Configuration Updates
- “Enable auto-scaling and update the display name for the Autonomous Database `<db_ocid>`.”
- “Update backup retention to 30 days for the Autonomous Database `<db_ocid>`.”

### Maintenance and Backups
- “Show maintenance run history for maintenance run ID `<maintenance_id>`.”
- “List all backups for the Autonomous Database `<db_ocid>` in the `Finance` compartment.”

### Supporting Resources
- “List all key stores in the `Finance` compartment.”
- “List all DB homes in the `Finance` compartment.”



##  License

Universal Permissive License (UPL) 1.0  
https://oss.oracle.com/licenses/upl/
Copyright (c) 2026 Oracle and/or its affiliates.

---

## ✨ Final Thoughts

This OCI Autonomous Database AI Agent turns OCI operations into a **guided, conversational**, blending human judgment with automation.

It is designed for:
- Platform teams
- Cloud DBAs
- DevOps automation
- Autonomous cloud operations
