# Autonomous AI Agents for Oracle Autonomous Database

## Overview

This repository provides a **modular, extensible framework** for building **OCI AI Agents** using **Oracle Autonomous Database** and **`DBMS_CLOUD_AI_AGENT` (Select AI)**.

Each OCI service (Vault, Object Storage, Autonomous Database, Network Load Balancer, etc.) is implemented using a **two-layer model**:

- **Tools Layer**
  - Installs reusable PL/SQL functions
  - Registers them as AI tools
- **Agent Layer**
  - Creates sample tasks, agents, and teams
  - Consumes the tools created in the Tools layer

### Benefits of This Design

- Reuse tools across multiple agents
- Allow end users to create custom agents and tasks
- Clear separation of:
  - Infrastructure logic
  - AI orchestration logic

---

## Design Principles

### 1. Two-Layer Architecture

Each OCI service is implemented using **two SQL scripts**:

| Layer | Script Pattern | Purpose |
|------|---------------|---------|
| Tools Layer | `*_tools.sql` | Installs core PL/SQL logic and registers AI tools |
| Agent Layer | `*_agent.sql` | Creates a sample Task, Agent, and Team using those tools |

This design ensures:
- Tools are reusable across multiple agents
- Agent behavior remains customizable

---

## Tools Scripts (`*_tools.sql`)

### Purpose

Tools scripts are responsible for **infrastructure and capability enablement**.

**Example:**
- `oci_vault_tools.sql`

---

### What a Tools Script Does

A tools script typically performs the following steps:

#### 1. Grant Required Privileges

- Grants access to:
  - `DBMS_CLOUD`
  - `DBMS_CLOUD_AI`
  - `DBMS_CLOUD_AI_AGENT`
  - Relevant OCI typed API packages
- Privileges are scoped to the **target schema**

---

#### 2. Create Configuration Table

Creates a generic configuration table:

```sql
OCI_AGENT_CONFIG
```

**Stores configuration such as:**
- Credential name
- Compartment name / OCID
- Resource principal enablement

> Configuration is **agent-specific** and persisted for runtime use.

---

#### 3. Initialize Configuration

- Parses optional JSON configuration input
- Enables resource principal authentication if requested
- Persists configuration values

---

#### 4. Create PL/SQL Package

**Example package:**

```sql
oci_vault_agents
```

**Package responsibilities:**
- Implements core OCI API logic
- Calls OCI APIs using `DBMS_CLOUD_OCI_*`
- Each function:
  - Returns **CLOB JSON**
  - Includes:
    - Status codes
    - Headers
    - Response payloads

---

#### 5. Register AI Tools

- Uses `DBMS_CLOUD_AI_AGENT.CREATE_TOOL`
- Maps each PL/SQL function to an AI tool
- Adds rich instructions describing:
  - When to use the tool
  - Safety rules (e.g. no secret exposure)
  - Expected behavior

---

### Key Characteristics of Tools

- Service-specific but **agent-agnostic**
- Reusable by any task or agent
- Safe to re-run (drop & recreate logic)
- Designed for **human-readable AI responses**

---

## Agent Scripts (`*_agent.sql`)

### Purpose

Agent scripts create **example AI agents** demonstrating how to use the tools.

**Example:**
- `oci_vault_agent.sql`

---

### What an Agent Script Does

#### 1. Interactive Execution

Prompts for:
- Target schema name
- AI Profile name

This makes scripts **portable across environments**.

---

#### 2. Grant Required Privileges

Grants:
- `DBMS_CLOUD_AI_AGENT`
- `DBMS_CLOUD`

To the target schema.

---

#### 3. Create Installer Procedure

- Creates an installer procedure in the target schema
- Keeps all agent logic **schema-local**

---

#### 4. Create AI Task

Defines:
- User intent detection
- Allowed tools
- Safety rules
- Formatting expectations

Enforces:
- Confirmation for destructive actions
- Human-readable output

---

#### 5. Create AI Agent

- Binds the agent to the specified AI Profile
- Defines the agent’s role and behavior

---

#### 6. Create AI Team

- Links the agent and task
- Uses **sequential execution**

---

#### 7. Execute Installer

- Runs the installer procedure
- Completes agent setup

---

### Key Characteristics of Agents

- Agents are **examples**, not hard dependencies
- End users can:
  - Modify tasks
  - Create new agents
  - Create multiple teams
- Tools remain unchanged and reusable

---

## Example: OCI Vault

### Files

| File | Description |
|-----|------------|
| `oci_vault_tools.sql` | Installs Vault PL/SQL package, config table, and AI tools |
| `oci_vault_agent.sql` | Creates a sample Vault task, agent, and team |

---

### Supported Capabilities

The Vault tools support:

- List secrets
- Get secret metadata
- Create secrets
- Update secrets / rotate versions
- List secret versions
- Get specific secret versions
- Schedule and cancel deletions
- Change secret compartment

**All operations:**
- Use persisted configuration
- Require confirmation for destructive actions
- Never expose secret payloads unintentionally

---

## Installation Order (Recommended)

For each OCI service:

1. Run `*_tools.sql`
2. Run `*_agent.sql` (optional, for sample agent)

### Example (OCI Vault)

```sql
-- Step 1: Install tools
sqlplus admin@db @oci_vault_tools.sql <INSTALL_SCHEMA>

-- Step 2: Install sample agent
sqlplus admin@db @oci_vault_agent.sql
```

---

## Customization & Extension

- Create your own tasks, agents, and teams
- Tools remain stable and reusable
- Multiple agents can share the same tools
- Configuration can be updated in:

```sql
OCI_AGENT_CONFIG
```

---

## Error Handling & Safety

- Scripts exit immediately on SQL errors
- All destructive OCI operations require confirmation
- Tools return structured JSON containing:
  - Status
  - Headers
  - Payload
- Fully re-runnable with safe drop-and-create logic

---

## License

This project is licensed under the **Universal Permissive License (UPL), Version 1.0**.

See:
https://oss.oracle.com/licenses/upl/
