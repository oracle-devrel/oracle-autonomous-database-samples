# OCI Network Load Balancer AI Agent & Tools

## 🚀 Overview

The **OCI Network Load Balancer (NLB) AI Agent** enables safe, conversational management of **OCI Network Load Balancers** using **Select AI (DBMS_CLOUD_AI_AGENT)** in Oracle Autonomous Database.

It allows users to **list, create, update, and delete Network Load Balancers**, along with their **listeners, backend sets, and health status**, while enforcing **explicit confirmation for destructive operations**.

This agent follows the same **Tools + Agent + Team** architecture used across other OCI service agents in this repository.

---

## 🧠 Why an OCI Network Load Balancer AI Agent?

Managing Network Load Balancers typically requires:
- Deep understanding of OCI networking concepts
- Correct configuration of listeners and backend sets
- Careful handling of destructive operations
- Manual validation of regions, compartments, and health states

This AI agent improves safety and productivity by:
- Detecting **user intent** before execution
- Asking **clarifying questions** when requests are ambiguous
- Enforcing **confirmation for destructive actions**
- Presenting **human-readable summaries** instead of raw JSON
- Providing **guided workflows** for complex NLB operations

---

## 🧱 Architecture Overview

```text
User Request
   ↓
OCI Network Load Balancer Task
   ↓
Agent Reasoning & Validation
   ├── Region & Compartment Discovery
   ├── NLB Inventory & Inspection
   ├── Listener Management
   ├── Backend Set & Backend Inspection
   ├── Health & Policy Discovery
   └── Destructive Action Confirmation
   ↓
Confirmed NLB Operation + Result
```

---

## 📦 Repository Contents

```text
.
├── oci_network_load_balancer_agent.sql
│   ├── Task definition
│   ├── Agent creation
│   ├── Team creation
│   └── AI profile binding
│
├── oci_network_load_balancer_tools.sql   (if installed separately)
│   ├── PL/SQL OCI NLB wrappers
│   └── AI tool registrations
│
└── README.md
```

---

## 🛠 Prerequisites

- Oracle Autonomous Database (23ai recommended)
- Select AI enabled
- OCI Network Load Balancer permissions
- OCI credential or Resource Principal
- ADMIN or equivalent privileged user

---

## ⚙️ Installation – Agent & Team

Run as ADMIN (or privileged user):

```sql
sqlplus admin@db @oci_network_load_balancer_agent.sql
```

### Prompts
- Target schema name
- AI Profile name

### What the Installer Does

- Grants required `DBMS_CLOUD_AI_AGENT` and `DBMS_CLOUD` privileges
- Creates an installer procedure in the target schema
- Registers the **OCI Network Load Balancer task**
- Creates the **OCI Network Load Balancer agent**
- Creates the **OCI Network Load Balancer team**
- Binds the agent to the specified AI profile

---

## 🤖 Objects Created

| Object | Name |
|------|------|
| Task | OCI_NETWORK_LOAD_BALANCER_TASKS |
| Agent | OCI_NETWORK_LOAD_BALANCER_ADVISOR |
| Team | OCI_NETWORK_LOAD_BALANCER_TEAM |

---

## 🧩 Available AI Tools (High-Level)

### 🌍 Discovery
- List subscribed regions
- List compartments

### 📦 Network Load Balancer Management
- List Network Load Balancers
- Create Network Load Balancer
- Update Network Load Balancer
- Delete Network Load Balancer

### 🎧 Listener Management
- List listeners
- Get listener details
- Create listener
- Update listener
- Delete listener

### 🧰 Backend & Health
- Create backend sets
- List backend sets
- List backends
- Inspect health checks

### 📊 Metadata & Capabilities
- List supported NLB policies
- List supported protocols
- Review NLB health summaries

> ⚠️ All destructive operations require **explicit user confirmation**.

---

## 🧠 Task Intelligence Highlights

The Network Load Balancer task enforces:
- Intent detection before execution
- Mandatory confirmation for delete operations
- Human-readable formatting of lists and objects
- Safe sequencing of dependent operations
- Clear separation between discovery and mutation actions

---

## 🧱 Extending the NLB Agent

### Recommended Pattern

**Keep OCI API logic in tools.  
Define safety and flow rules in tasks.  
Bind permissions via AI profiles.**

### Example Extensions
- Read-only NLB inventory agent
- Health monitoring & diagnostics agent
- Automated NLB provisioning agent
- Multi-compartment governance agent

---

## 🔄 Safe Re-Execution

All scripts are **safe to re-run**:
- Tasks, agents, and teams are dropped and recreated
- No NLB resources are modified implicitly
- Destructive operations always require confirmation

---

## 📌 Best Practices

- Use Resource Principal whenever possible
- Separate read-only and admin NLB agents
- Validate regions and compartments before creation
- Review backend health before deleting listeners
- Use staged rollouts for listener updates

---

## 📜 License

Universal Permissive License (UPL) 1.0  
https://oss.oracle.com/licenses/upl/

---

## ✨ Final Thought

The OCI Network Load Balancer AI Agent transforms complex networking operations into a **guided, safe, and auditable conversational workflow**, reducing risk while accelerating infrastructure management.

Designed for:
- Platform & networking teams
- Cloud operations engineers
- Secure infrastructure automation
- Enterprise OCI environments
