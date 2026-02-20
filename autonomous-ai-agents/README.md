# Using Select AI Agent on Oracle Autonomous AI Database

## Overview

This repository provides a set of extensible AI agent templates built using Select AI Agent on Oracle Autonomous AI Database.

Select AI Agent enables natural language interactions with enterprise data by combining large language models (LLMs), database-resident tools, and orchestration logic directly inside your database. Agents can reason over user input, invoke tools, and return structured, explainable results while keeping data governance, security, and execution within the database.

The agents in this repository are templates that you can create and customize for enterprise use cases. While some examples interact with Oracle services, the Select AI Agent framework is not limited to a specific domain and can support many types of agents and workflows.

For product details, see:
https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/select-ai-agent.html

---

## What is a Select AI Agent?

Select AI Agent is part of Oracle Autonomous AI Database and extends core Select AI capabilities, including NL2SQL and RAG.

A Select AI Agent:

- Accepts natural language input from users or programs
- Uses an LLM to reason about the request
- Invokes built-in tools and custom tools (enabled using PL/SQL functions)
- Performs logic securely inside the database
- Returns agent responses

Key characteristics of the Select AI Agent framework include:

- Simple framework to build, deploy, and manage AI agents
- Native database integration to reduce infrastructure and orchestration overhead
- Support for preferred AI models and providers, including private endpoints
- Autoscaling in Oracle Autonomous AI Database
- Support for tools, tasks, agents, and teams
- Centralized governance and monitoring

---

## Simple Agent Execution Flow

```text
User -> Agent -> Task -> Tool (PL/SQL) -> Database -> Response
```

These concepts are represented as database-managed objects in the Select AI Agent framework.

| Concept | Definition |
|------|------------|
| Agent | An actor with a defined role that performs tasks using the LLM specified in the AI profile. |
| Task | A set of instructions that guides the LLM to use one or more tools to complete a step in a workflow. |
| Tool | A capability invoked by a task to perform actions, such as querying databases, calling web services, or sending notifications. |
| Agent Team | A group of agents with assigned tasks, serving as the unit for deploying and managing agent-based solutions. |

---

## Design Principles

### Two-Layer Architecture

Each agent implementation follows a two-layer model using separate SQL scripts.

| Layer | Script Pattern | Purpose |
|------|----------------|---------|
| Tools Layer | `*_tools.sql` | Installs core PL/SQL logic and registers Select AI tools |
| Agent Layer | `*_agent.sql` | Creates sample Task, Agent, and Team objects using those tools |

This design provides:

- Reusable tools across multiple agents
- Agent templates that can be customized for new domains and workflows
- Clear separation between infrastructure logic and agent behavior

---

## Repository Structure

The repository is organized to align with the Select AI Agent framework:

- Tools scripts define and register reusable PL/SQL functions
- Agent scripts compose tools into tasks, agents, and teams
- Additional agents can be created without modifying existing tools

---

## Common Prerequisites for All Agents

Before installing any agent in this repository, ensure the following baseline prerequisites are met:

- Oracle Autonomous AI Database is provisioned
- Select AI and `DBMS_CLOUD_AI_AGENT` are enabled
- You are using `ADMIN` or another user with required privileges to create packages, grants, and agent objects
- Required network access and credentials are available for any external integrations used by the agent
- A Select AI profile is created using `DBMS_CLOUD_AI.CREATE_PROFILE`

Each agent subfolder may include additional service-specific prerequisites.

---

## Creating a Select AI Profile

Before using Select AI Agent objects, create a Select AI profile with `DBMS_CLOUD_AI.CREATE_PROFILE`.

A Select AI profile is a configuration object that defines the AI provider and models (LLM and transformer) used by Select AI. It also stores provider metadata, credential references, and behavior settings used at runtime.

Profile management documentation:
https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/select-ai-manage-profiles.html#GUID-3721296F-14A1-428A-B464-7FA25E9EC8F3

Create a profile appropriate for your environment (OCI Generative AI, OpenAI, Azure OpenAI, and others). The profile name is provided later when creating agent objects from `*_agent.sql`.

---

## Agent Configuration (`SELECTAI_AGENT_CONFIG`)

### Overview

`SELECTAI_AGENT_CONFIG` is a shared configuration table used by agent installers and runtime code to store agent-specific parameters.

Each agent stores only the keys it needs (for example, credential names, feature flags, compartment names, or integration endpoints). Defaults can still be applied by tool logic when optional values are not present.

### Column Description

| Column | Description |
|------|------------|
| `ID` | System-generated unique identifier |
| `KEY` | Configuration parameter name |
| `VALUE` | Configuration value (stored as `CLOB`) |
| `AGENT` | Logical agent name used to scope configuration |

Configuration entries are uniquely identified by the combination of `KEY` and `AGENT`.

### Writing Configuration Entries

Configuration values are written during installation or setup.  
Only explicitly provided values are persisted.

### Example Configuration Entries

```sql
INSERT INTO SELECTAI_AGENT_CONFIG ("KEY", "VALUE", "AGENT")
VALUES ('ENABLE_RESOURCE_PRINCIPAL', 'YES', 'NL2SQL_DATA_RETRIEVAL_AGENT');

INSERT INTO SELECTAI_AGENT_CONFIG ("KEY", "VALUE", "AGENT")
VALUES ('CREDENTIAL_NAME', 'MY_DB_CREDENTIAL', 'NL2SQL_DATA_RETRIEVAL_AGENT');
```

### JSON-Based Configuration Input

Agent installers may also accept configuration as JSON input:

```json
{
  "use_resource_principal": true,
  "credential_name": "MY_DB_CREDENTIAL"
}
```

The installer parses the JSON and stores relevant values in `SELECTAI_AGENT_CONFIG`.

### Reading Configuration at Runtime

At runtime, agents read values from `SELECTAI_AGENT_CONFIG` and consume them as structured JSON. This allows configuration changes without modifying agent code.

---

## Supported Use Cases

This framework can be used to build Select AI Agent solutions for:

- Natural language to SQL (NL2SQL)
- Data retrieval and analytics
- Database administration and monitoring
- OCI and enterprise operational workflows
- Custom automation with database-native controls

---

## Compatibility and Release Support

Select AI capabilities vary by database release. For supported features across Autonomous Database and compatible non-Autonomous releases, see the Select AI Capability Matrix:

https://docs.oracle.com/en/database/oracle/oracle-database/26/saicm/select-ai-capability-matrix.pdf

---

## Getting Started

1. Run the Tools layer scripts to install and register Select AI tools.
2. Run the Agent layer scripts to create sample tasks, agents, and teams.
3. Validate with test prompts for your selected AI profile.
4. Customize existing templates or build new agents by composing available tools.

---

## Intended Audience

This repository is intended for:

- Database developers
- Data engineers
- Architects
- Platform teams
- AI practitioners working with Oracle Autonomous AI Database

---

## License

This project is licensed under the Universal Permissive License (UPL), Version 1.0.
See: https://oss.oracle.com/licenses/upl/
Copyright (c) 2026 Oracle and/or its affiliates.
