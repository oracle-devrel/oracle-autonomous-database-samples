
# Select AI Agents on Oracle Autonomous Database

## Overview

This repository provides a **generic, extensible framework for building Select AI Agents on Oracle Autonomous Database** using the **Select AI Agent framework**.

Select AI Agents enable natural language interactions with enterprise data by combining large language models (LLMs), database-resident tools, and orchestration logic directly inside Oracle Database. Agents can reason over user input, invoke tools, and return structured, explainable results — all while keeping data governance, security, and execution within the database.

The agents in this repository are **generic Select AI agents**. While some examples may interact with Oracle services, the framework itself is not limited to any specific domain or platform and can support many different types of agents and workflows.

---

## What is a Select AI Agent?

Select AI Agents are part of the Oracle Autonomous Database Select AI framework. A Select AI Agent:

- Accepts natural language input from users
- Uses an LLM to reason about the request
- Invokes database-resident tools (PL/SQL functions)
- Executes logic securely inside the database
- Returns structured and auditable responses

Key characteristics of the Select AI Agent framework include:

- Native integration with Oracle Database
- Tool execution through PL/SQL
- Support for tasks, agents, and teams
- Centralized governance and auditing
- Flexibility to build domain-specific or generic agents

For full details, refer to the official documentation:
https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/select-ai-agent.html

---

## Design Principles

### 1. Two-Layer Architecture

Each agent implementation follows a two-layer model using separate SQL scripts.

| Layer        | Script Pattern   | Purpose |
|--------------|-----------------|---------|
| Tools Layer  | `*_tools.sql`   | Installs core PL/SQL logic and registers Select AI tools |
| Agent Layer  | `*_agent.sql`   | Creates a sample Task, Agent, and Team using those tools |

This design provides:

- **Tools** that are reusable across multiple agents  
- **Agents** as examples for customizable behavior

The clear separation between tools and agents allows infrastructure logic to remain stable while agent behavior can be easily adapted or extended.

---

## Repository Structure

The repository is organized to align with the Select AI Agent framework:

- Tools scripts define and register reusable PL/SQL functions
- Agent scripts demonstrate how those tools are composed into tasks, agents, and teams
- Additional agents can be created without modifying existing tools

---

## Supported Use Cases

This framework can be used to build Select AI agents for:

- Natural language to SQL (NL2SQL)
- Data retrieval and analytics
- Database administration and monitoring
- Operational workflows
- Custom enterprise automation

Agents can target database-only workflows, service integrations, or mixed enterprise use cases.

---

## Compatibility and Release Support

Select AI capabilities vary by database release. For details on supported features across Autonomous Database and compatible non-Autonomous Database releases, refer to the official Select AI Capability Matrix:

https://docs.oracle.com/en/database/oracle/oracle-database/26/saicm/select-ai-capability-matrix.pdf

---

## Getting Started

1. Run the Tools layer scripts to install and register Select AI tools.
2. Run the Agent layer scripts to create sample tasks, agents, and teams.
3. Customize existing agents or create new ones by composing available tools.
4. Extend the framework by adding new tools and agent definitions.

---

## Intended Audience

This repository is intended for:

- Database developers
- Data engineers
- Architects
- Platform teams
- AI practitioners working with Oracle Database

Anyone looking to build secure, database-native AI agents using Select AI can use this repository as a starting point.

---

## License

This project is licensed under the **Universal Permissive License (UPL), Version 1.0**.

See: https://oss.oracle.com/licenses/upl/
