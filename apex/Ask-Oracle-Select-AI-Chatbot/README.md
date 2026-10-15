# Ask Oracle Select AI 5.0.0.1

Ask Oracle Select AI is an Oracle APEX application that provides a low-code interface to Oracle Select AI on Oracle AI Database and Autonomous AI Database. It brings conversational AI, natural-language-to-SQL (NL2SQL), Retrieval-Augmented Generation (RAG), and agent experiences into one application that you can inspect, customize, and extend.

Release 5.0 evolves the original conversational interface into a low-code application platform for configuring, governing, and deploying Select AI-powered experiences.
This app is compatible with Apex 24 and Apex 26 versions.

## What's new in Release 5.0.0.1

- Visual Agent Builder for Oracle Select AI Agent Framework agents and teams
- Agent Team Map for inspecting agent, task, and tool relationships
- Prebuilt Oracle Select AI agents that can be installed and configured in the application
- AI Profile lifecycle management for NL2SQL, RAG, and agents
- Centralized governance, defaults, branding, and button-level access controls

## Why use Release 5.0.0.1?

Release 5.0 helps teams move from asking questions to building governed AI applications. Use it to configure NL2SQL and RAG profiles, build and validate agent teams visually, and control the capabilities available to different users.

## Key capabilities

- **Chat** — converse directly with the LLM configured in an AI Profile.
- **NL2SQL** — query Oracle AI Database using natural language and explain generated SQL.
- **RAG** — ground responses in trusted text content using Retrieval-Augmented Generation and Oracle AI Vector Search.
- **Agents and teams** — run Oracle Select AI Agent Framework agents and agent teams.
- **Visual Agent Builder** — generate an initial team from natural language, then refine its teams, agents, tasks, and tools in one visual workflow before validating it.
- **Agent Team Map** — view routing and relationships among teams, agents, tasks, and tools.
- **Prebuilt agents** — install a provided agent through the application, then configure its required credentials, parameters, tools, and target resources, plus data access.
- **Profiles and governance** — create, edit, validate, and reuse AI Profiles; configure application defaults, branding, and feature access.

## User Interface

![Agent Builder showing an agent team with its agents, tasks, and assigned tools](../../images/agent_builder.png)

**Figure 1:** Visual Agent Builder for creating and refining an agent team, including its agents, tasks, and assigned tools.

<br>
<br>
<br>
<br>

![Agent Team Map showing relationships among teams, agents, tasks, and tools](../../images/agent_team_map.png)

**Figure 2:** Agent Team Map for reviewing the relationships among teams, agents, tasks, and tools.

<br>
<br>

![AI Profile management screen for configuring an NL2SQL profile](../../images/nl2sql_profile.png)

**Figure 3:** AI Profile management for configuring and validating an NL2SQL profile.

## Repository contents

| Path | Purpose |
| --- | --- |
| [`ADB-AskOracle-Chatbot-2026-07-23.sql`](ADB-AskOracle-Chatbot-2026-08-06.sql) | Oracle APEX application export for Ask Oracle Select AI Release 5.0.0.1 It includes supporting objects. |
| [Ask Oracle App Installation Steps.pdf](https://github.com/sandeepkhot/oracle-autonomous-database-samples/blob/main/apex/Ask-Oracle-Select-AI-Chatbot/Ask%20Oracle%20App%20Installation%20Steps.pdf) | Installation guide. |
| `README.md` | This overview, setup guidance, and troubleshooting notes. |

Prebuilt agent definitions are included with the application export and become available in the **Prebuilt Agents** interface after import. Installing an agent is only the first step: configure its credentials, parameters, tools, and target resources, plus least-privilege data access, before using it. This version does not include standalone prebuilt-agent definition files outside the application export.

## Prerequisites and compatibility

Use a supported Oracle AI Database or Autonomous AI Database deployment where Oracle APEX and Oracle Select AI are available. The export was generated with Oracle APEX **24.2.17**; import it into a compatible APEX environment. Agent capabilities additionally require a deployment that supports the Oracle Select AI Agent Framework. Confirm feature availability, supported providers, and version requirements for your target database service before deployment.

### App installation prerequisites

#### Base application permissions

The following package permissions are required for the application install schema. Replace `<APP_INSTALL_SCHEMA>` with the schema used to install and run the application:

```sql
grant execute on dbms_cloud to <APP_INSTALL_SCHEMA>;
grant execute on dbms_cloud_ai to <APP_INSTALL_SCHEMA>;
```

The install schema also needs an AI provider credential and access to the provider endpoint. For providers outside OCI Generative AI, a DBA may need to grant network ACL access for the applicable provider host. Create or make available the credential and AI Profile before testing the application.

#### Optional feature permissions

Grant only the permissions needed for enabled features:

```sql
-- Required for Agent Framework and prebuilt agents
grant execute on dbms_cloud_ai_agent to <APP_INSTALL_SCHEMA>;
```

#### DBA-only schema provisioning

The following are DBA-run provisioning steps for a new application install schema. They are not commands the application parsing schema should execute. Use only the specific object privileges and tablespace quota required by your environment; do not grant `CONNECT` or `RESOURCE` as the baseline.

```sql
create user <APP_INSTALL_SCHEMA> identified by <STRONG_PASSWORD>;

grant create session, create table, create sequence, create procedure, create view to <APP_INSTALL_SCHEMA>;
grant read on directory data_pump_dir to <APP_INSTALL_SCHEMA>;
alter user <APP_INSTALL_SCHEMA> quota <QUOTA> on <TABLESPACE>;
```

### Minimum setup: Chat and NL2SQL

- An APEX workspace and parsing schema. Import as that schema, or use a database account with `APEX_ADMINISTRATOR_ROLE`.
- A Select AI provider credential, a supported model, and an AI Profile that the parsing schema can use.

### Optional setup: RAG

- A RAG AI Profile and trusted content indexed through Select AI or the Ask Oracle application interface.
- An Oracle AI Vector Search vector index created for that RAG configuration. When the selected provider supplies a default embedding model, explicit embedding-model configuration may not be required.

### Optional setup: Agent Framework and prebuilt agents

- Oracle Select AI Agent Framework available and configured in the target database service.
- An agent team selected in the application for agent conversations.
- For each prebuilt agent, configuration of its required credentials, parameters, tools, and target resources, plus data access. Do not assume an installed agent is ready for use without this environment-specific setup.

> **Safety note:** Test the application, RAG indexes, and agent teams in a non-production environment first. Apply least privilege to the parsing schema and to every credential, tool, and data source used by the application.

## Installation

1. Download or clone this repository and locate [`ADB-AskOracle-Chatbot-2026-07-23.sql`](ADB-AskOracle-Chatbot-2026-07-23.sql).
2. Sign in to the target Oracle APEX workspace as a workspace administrator or developer with permission to import applications.
3. Open **App Builder**, select **Import**, choose the SQL export, and complete the import wizard. Choose the target parsing schema when prompted.
4. Review the supporting-object installation during the import. The application export includes supporting objects; allow the import to install them when appropriate for your environment.
5. Open the imported application and configure its Select AI Profiles, conversation defaults, and access controls. Configure RAG profiles and vector indexes only if you plan to use RAG; configure an agent team only if you plan to use agents.
6. Run the application and complete the validation checks below.

For an illustrated import procedure, see the [installation guide](https://github.com/sandeepkhot/oracle-autonomous-database-samples/blob/main/apex/Ask-Oracle-Select-AI-Chatbot/Ask%20Oracle%20App%20Installation%20Steps.pdf) or [watch the installation video on YouTube](https://youtu.be/kjeQ2AC3TFo). The local [MP4 copy](https://github.com/sandeepkhot/oracle-autonomous-database-samples/blob/main/apex/images/Ask%20Oracle%20App%20Installation%20video.mp4) is provided for download; GitHub does not reliably provide in-page MP4 playback for repository README content.

## Configuration

Configure the application before making it available to end users:

- **AI Profiles:** Create or select the profiles for Chat, NL2SQL, RAG, and agents. Validate the provider credential, model, and profile settings.
- **Conversation defaults:** Choose the default conversation mode and the default NL2SQL Profile, RAG Profile, and optional Agent Team.
- **RAG:** Select the RAG AI Profile, Oracle AI Vector Search vector index, and retrieval settings. Use the provider default embedding model where applicable, then load and index trusted content before testing retrieval.
- **Agents:** Use Agent Builder to create or refine teams, agents, tasks, and tools; validate the team before assigning it as a default. For a prebuilt agent, complete its required environment-specific configuration before validation.
- **Governance:** Set application name, logo, branding, navigation, and permissions for actions such as SQL Editor, exports, deletion, conversation timer, and agent reasoning.

## Quick start and validation

After configuration, verify each enabled capability with a prompt appropriate for your data:

| Capability | Example validation |
| --- | --- |
| Chat | Ask a general question supported by the configured model. |
| NL2SQL | Ask a question about a table the parsing schema can query, such as “How many orders were created this month?” |
| RAG | Ask a question answered by content you have loaded into the configured vector index. |
| Agents | Select an agent team and ask it to complete a task that uses its configured tools. |

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| No AI Profile is available | Create or grant access to a Select AI Profile for the parsing schema, then select it in the application defaults. |
| Provider, credential, or model error | Verify the provider credential, model name and availability, network policy, and the profile configuration. |
| NL2SQL cannot query data | Verify grants and synonyms for the parsing schema, and confirm the profile is configured for the intended schemas and objects. |
| RAG returns no relevant results | Confirm the correct embedding model, vector index, indexed content, and retrieval settings are configured. |
| Agent option is unavailable or fails | Confirm Agent Framework configuration, validate the agent team, and select the team in the conversation settings. |
| A prebuilt agent cannot run | Complete the agent's required credential, parameter, tool, target-resource, and data-access configuration, then validate it before use. |
| A button or feature is missing | Review the application's action controls and button-level access settings for the current user. |

## Resources

- [Oracle Autonomous AI Database Select AI](https://www.oracle.com/autonomous-database/select-ai/)
- [Getting started with Select AI](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/select-ai-get-started.html)
- [Manage AI Profiles](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/select-ai-manage-profiles.html)
- [Oracle Select AI Agent Framework](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/select-ai-agent.html)
- [Oracle APEX](https://apex.oracle.com/)
- [Oracle APEX in Autonomous AI Database](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/application-express-autonomous-database.html)

## License

Copyright (c) 2026 Oracle and/or its affiliates.

Licensed under the [Universal Permissive License (UPL), Version 1.0](https://oss.oracle.com/licenses/upl/).
