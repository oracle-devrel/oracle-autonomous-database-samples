#  Select AI - OCI Network Load Balancer AI Agent & Tools 

## Overview

## OCI Network Load Balancer

OCI Network Load Balancer is a high-performance, layer-4 load balancing service in Oracle Cloud Infrastructure that distributes TCP and UDP traffic across backend servers while preserving source IP addresses. It is designed for ultra-low latency, high throughput, and scalability, making it ideal for mission-critical and network-intensive workloads.

The **Select AI - OCI Network Load Balancer (NLB) AI Agent** enables conversational management of **OCI Network Load Balancers** using **Select AI (DBMS_CLOUD_AI_AGENT)** in Oracle Autonomous Database.

It allows users to **list, create, update, and delete Network Load Balancers**, along with their **listeners, backend sets, and health status**, while enforcing **explicit confirmation for destructive operations**.

This agent follows the same **Tools + Agent + Team** architecture used across other OCI service agents in this repository.

---

##  Why an Select AI OCI Network Load Balancer AI Agent?

Managing Network Load Balancers typically requires:
- Deep understanding of OCI networking concepts
- Correct configuration of listeners and backend sets
- Careful handling of destructive operations
- Manual validation of regions, compartments, and health states

This AI agent improves productivity by:
- Detecting **user intent** before execution
- Asking **clarifying questions** when requests are ambiguous
- Enforcing **confirmation for destructive actions**
- Presenting **human-readable summaries** instead of raw JSON
- Providing **guided workflows** for complex NLB operations

---

##  Architecture Overview

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

##  Repository Contents

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

##  Prerequisites

- Oracle Autonomous Database 
- Select AI enabled
- OCI Network Load Balancer permissions
- OCI credential or Resource Principal
- ADMIN

---

##  Installation – Agent & Team

Run as ADMIN (or privileged user):

```sql
sqlplus admin@db @oci_network_load_balancer_agent.sql
```

### Input Parameters required to run.
- Target schema name (Schema where to the agent team needs to be installed)
- AI Profile name (Select AI Profile name that needs to be used with the Agent)

### What the Installer Does

- Grants required `DBMS_CLOUD_AI_AGENT` and `DBMS_CLOUD` privileges
- Creates an installer procedure in the target schema
- Registers the **OCI Network Load Balancer task**
- Creates the **OCI Network Load Balancer agent**
- Creates the **OCI Network Load Balancer team**
- Binds the agent to the specified AI profile

---

##  Objects Created

| Object | Name |
|------|------|
| Task | OCI_NETWORK_LOAD_BALANCER_TASKS |
| Agent | OCI_NETWORK_LOAD_BALANCER_ADVISOR |
| Team | OCI_NETWORK_LOAD_BALANCER_TEAM |

---

##  Available AI Tools (High-Level)

###  Discovery
- List subscribed regions
- List compartments

###  Network Load Balancer Management
- List Network Load Balancers
- Create Network Load Balancer
- Update Network Load Balancer
- Delete Network Load Balancer

###  Listener Management
- List listeners
- Get listener details
- Create listener
- Update listener
- Delete listener

###  Backend & Health
- Create backend sets
- List backend sets
- List backends
- Inspect health checks

###  Metadata & Capabilities
- List supported NLB policies
- List supported protocols
- Review NLB health summaries

>  All destructive operations require **explicit user confirmation**.

---

##  Task Intelligence Highlights

The Network Load Balancer task enforces:
- Intent detection before execution
- Mandatory confirmation for delete operations
- Human-readable formatting of lists and objects
- Clear separation between discovery and mutation actions

---

##  Extending the NLB Agent

### Recommended Pattern

**Keep OCI API logic in tools.  
Define flow rules in tasks.  
Bind permissions via AI profiles.**

### Example Extensions
- Read-only NLB inventory agent
- Health monitoring & diagnostics agent
- Automated NLB provisioning agent
- Multi-compartment governance agent

---

##  Best Practices

- Use Resource Principal whenever possible
- Separate read-only and admin NLB agents
- Validate regions and compartments before creation
- Review backend health before deleting listeners
- Use staged rollouts for listener updates

---

## Example Prompts

After creating the OCI Network Load Balancer AI Agent, users can interact with it using prompts such as:

### Discovery & Setup
- “List all OCI regions I am subscribed to.”
- “Show all compartments in my tenancy.”

### Network Load Balancer Provisioning
- “Create a public Network Load Balancer named `orders-nlb` in the `Finance` compartment in the Mumbai region with a TCP listener on port 443, a backend set using ROUND_ROBIN policy, and health checks enabled.”
- “Create a private Network Load Balancer in the `Finance` compartment with preserved source IP and IPv4 enabled.”

### Listing & Inspecting Network Load Balancers
- “List all Network Load Balancers in the `Finance` compartment in the Mumbai region.”
- “Get details of the Network Load Balancer with OCID `<nlb_ocid>`.”

### Listener Management
- “List all listeners for the Network Load Balancer `<nlb_ocid>`.”
- “Get details of the listener named `https-listener` on the Network Load Balancer `<nlb_ocid>`.”
- “Create a new TCP listener on port 80 for the Network Load Balancer `<nlb_ocid>`.”
- “Update the listener `https-listener` to use a different backend set.”
- “Delete the listener named `https-listener` from the Network Load Balancer `<nlb_ocid>`.”

### Backend Sets & Backends
- “List all backend sets for the Network Load Balancer `<nlb_ocid>`.”
- “Create a backend set named `orders-backend-set` with ROUND_ROBIN policy on port 8080.”
- “List all backends in the backend set `orders-backend-set` for the Network Load Balancer `<nlb_ocid>`.”

### Health, Policies & Protocols
- “Show health status of all Network Load Balancers in the `Finance` compartment.”
- “List all supported Network Load Balancer policies.”
- “List all supported Network Load Balancer protocols.”

### Updating Network Load Balancer
- “Update the display name and tags for the Network Load Balancer `<nlb_ocid>`.”
- “Enable source and destination preservation for the Network Load Balancer `<nlb_ocid>`.”

### Compartment Management
- “Move the Network Load Balancer `<nlb_ocid>` to a different compartment.”

### Deleting Resources
- “Delete the Network Load Balancer with OCID `<nlb_ocid>`.”


## License

Universal Permissive License (UPL) 1.0  
https://oss.oracle.com/licenses/upl/

---

## ✨ Final Thought

The OCI Network Load Balancer AI Agent transforms complex networking operations into a **guided, and auditable conversational workflow**, reducing risk while accelerating infrastructure management.

Designed for:
- Platform & networking teams
- Cloud operations engineers
- Secure infrastructure automation
- Enterprise OCI environments
