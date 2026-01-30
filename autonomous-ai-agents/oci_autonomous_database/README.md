# OCI Autonomous Database AI Agent & Tools

## 🚀 Overview

The **OCI Autonomous Database AI Agent** enables natural-language–driven provisioning, management, and advisory operations for **Oracle Autonomous Databases on OCI**, powered by **Select AI (DBMS_CLOUD_AI_AGENT)**.

Unlike traditional scripts or consoles, this agent allows users to:
- Provision and manage Autonomous Databases conversationally
- Safely execute lifecycle operations with confirmations
- Discover OCI resources dynamically (regions, compartments, databases)
- Automate complex OCI workflows through reusable AI tools

This repository provides a **clean separation between Tools and Agent orchestration**, making it easy to extend, customize, and reuse.

---

## 🧠 Why This Agent Is Powerful

Compared to manual OCI operations or simple chat-based automation, this agent:

- Understands **user intent** before acting
- Prompts for **missing or ambiguous inputs**
- Requires **explicit confirmation for destructive actions**
- Uses **OCI-native APIs** through PL/SQL wrappers
- Produces **human-readable outputs**, not raw JSON dumps
- Is **idempotent and safe to re-run**

---

## 🧱 Architecture Overview

```text
User Request
   ↓
OCI Autonomous Database Task
   ↓
Agent Reasoning & Validation
   ├── Discovery Tools (Regions, Compartments, Databases)
   ├── Provisioning Tools
   ├── Lifecycle Management Tools
   ├── Configuration & Scaling Tools
   └── Maintenance & Backup Tools
   ↓
Confirmed OCI Operation + Result
```

---

## 📦 Repository Contents

```text
.
├── oci_autonomous_database_tools.sql
│   ├── PL/SQL OCI wrapper package
│   ├── OCI authentication & config handling
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

## 🛠 Prerequisites

- Oracle Autonomous Database (23ai recommended)
- Select AI enabled
- OCI credential or Resource Principal
- Access to OCI compartments with ADB permissions
- ADMIN or equivalent privileged user

---

## ⚙️ Installation – Tools

Run as ADMIN (or privileged user):

```sql
sqlplus admin@db @oci_autonomous_database_tools.sql
```

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

## 🧩 Available AI Tools (High Level)

### 🔍 Discovery & Metadata
- List subscribed regions
- List compartments
- Resolve compartment OCID by name
- List Autonomous Databases
- Get Autonomous Database details

### 🚀 Provisioning & Lifecycle
- Provision Autonomous Database
- Start / Stop / Restart database
- Scale CPU and storage
- Enable / manage autoscaling
- Shrink database
- Delete Autonomous Database (confirmed)

### 🛠 Configuration & Updates
- Update database attributes
- Manage power model
- Modify workload and edition
- Update network and security settings
- Manage tags

### 🧰 Maintenance & Backup
- List maintenance run history
- List Autonomous Database backups
- List DB homes
- List key stores
- Delete key stores

---

## 🤖 Installation – Agent & Team

Run:

```sql
sqlplus admin@db @oci_autonomous_database_agent.sql
```

### Prompts
- Target schema name
- AI Profile name

### Objects Created

| Object | Name |
|------|------|
| Task | OCI_AUTONOMOUS_DATABASE_TASKS |
| Agent | OCI_AUTONOMOUS_DATABASE_ADVISOR |
| Team | OCI_AUTONOMOUS_DATABASE_TEAM |

---

## 🧠 Task Intelligence Highlights

The task enforces:

- Intent detection before execution
- Clarifying questions for incomplete input
- Mandatory confirmation for destructive actions
- Human-readable formatting of OCI outputs
- Safe automation of OCI operations

---

## 🧱 Extending & Generalizing the Agent

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

## 🔄 Safe Re-Execution

All scripts are **safe to re-run**:
- Tasks, agents, and teams are dropped and recreated
- OCI configuration is preserved
- No duplicate OCI resources are created accidentally

---

## 📌 Best Practices

- Always use confirmation for destructive actions
- Prefer Resource Principal in OCI environments
- Keep provisioning and advisory agents separate
- Use compartment scoping to enforce boundaries
- Review AI profile permissions carefully

---

## 📜 License

Universal Permissive License (UPL) 1.0  
https://oss.oracle.com/licenses/upl/

---

## ✨ Final Thought

This OCI Autonomous Database AI Agent turns OCI operations into a **guided, conversational, and safe experience**, blending human judgment with automation.

It is designed for:
- Platform teams
- Cloud DBAs
- DevOps automation
- Autonomous cloud operations
