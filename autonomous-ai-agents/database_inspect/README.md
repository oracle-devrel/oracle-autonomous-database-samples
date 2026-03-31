# Select AI Inspect - Database Inspection Tool Built Using Select AI Agent

## Overview

Select AI Inspect is an AI-powered database inspection tool built using the **Select AI Agent** framework. It enables users to explore, understand, and interact with database objects and their metadata using natural language.
This agent is supported only on Oracle Database **26ai**.

For definitions of **Tool**, **Task**, **Agent**, and **Agent Team**, see the top-level guide: [README](../README.md#simple-agent-execution-flow).

### Use Cases

Instead of manually reviewing tables, searching through PL/SQL files, or examining function and procedure metadata, users can simply ask the Select AI Inspect agent natural language questions such as:

* Which objects reference this table?
* Why am I receiving this error from a function call?
* What is this function used for?
* What objects will be impacted if I modify this package?

Common use cases for Select AI Inspect include:

* **Code inspection and debugging** , particularly for unfamiliar or legacy code.
* **Dependency analysis** , such as identifying which tables, functions, or packages would be affected by a change.
* **Test case generation** for functions or procedures.
* **Automatic documentation generation** based on source code and object metadata.

### Implementation

Select AI Inspect is delivered as the `DATABASE_INSPECT` PL/SQL package. It provides a set of APIs that allow users to create and configure AI agents to handle inspection and analysis tasks.

Users can create multiple agents, each scoped to a specific set of database objects. This enables flexible configuration for different environments, projects, or teams.

### Supported Object Types

Select AI Inspect supports the following database object types:

* Tables
* Views
* Types
* Type Bodies
* Triggers
* Functions
* Procedures
* Packages
* Package Bodies
* Schema

Users may define the inspection scope either at the individual object level or at the schema level. When a schema is specified, all supported object types within that schema are included.

---

## Prerequisites

- Oracle Autonomous AI Database (26ai)
- Select AI and `DBMS_CLOUD_AI_AGENT` enabled
- `ADMIN` or equivalent privileged user for installation
- A Select AI profile created with `DBMS_CLOUD_AI.CREATE_PROFILE`
- The Select AI profile used for inspection must include an `embedding_model` attribute
- If the Select AI profile uses an OCI Generative AI model/provider, it must also include `oci_compartment_id`

---

## Installation

Before running installation commands:

1. Clone or download this repository.
2. Open a terminal and change directory to `autonomous-ai-agents/database_inspect`.
3. Choose one execution mode:
   - SQL*Plus/SQLcl: run script files directly with `@script_name`.
   - SQL Developer or another SQL IDE: run the file in script mode so interactive prompts are shown.
4. Uploading scripts to `DATA_PUMP_DIR` is not required for these methods.

Run as `ADMIN` (or another privileged user):

```sql
sqlplus admin@<adb_connect_string> @database_inspect_tool.sql
sqlplus admin@<adb_connect_string> @database_inspect_agent.sql
```

`database_inspect_agent.sql` uses interactive prompts, so run it as a script instead of copy/pasting individual statements into a worksheet.

### Step 1: Install `DATABASE_INSPECT` Package and Tool Framework

Run `database_inspect_tool.sql` first.

The script prompts for:

- `SCHEMA_NAME`: target schema where `DATABASE_INSPECT` is compiled

What the tools installer does:

- Grants required execute privileges to the target schema
- Switches `CURRENT_SCHEMA` to the target schema
- Compiles the `DATABASE_INSPECT` package specification and body inline
- Is safe to rerun

Notes:

- The tools installer no longer executes `DATABASE_INSPECT.setup` directly from an `ADMIN` anonymous block. This avoids `ORA-06598` when the package is `AUTHID CURRENT_USER`.
- Internal `DATABASE_INSPECT` tables are initialized from the target-schema execution path when the package is invoked by the agent installer or by direct package usage in the target schema.

### Step 2: Create or Recreate the Inspect Agent Team

Run `database_inspect_agent.sql` after the package is installed.

The script prompts for:

- `INSTALL_SCHEMA_NAME`: schema where the team is created
- `AI_PROFILE_NAME`: profile used for reasoning and embeddings
- `AGENT_TEAM_NAME`: team name to create
- `RECREATE_EXISTING`: `Y` to drop and recreate an existing team, otherwise `N`
- `SCOPE_MODE`: guided scope mode; supported values are `SCHEMA`, `TABLE`, `PACKAGE`, and `JSON`
- `SCOPE_OWNERS`: use this for `SCHEMA` mode; enter one or more schema owners separated by commas, or leave blank to use `INSTALL_SCHEMA_NAME`
- `OBJECT_OWNER`: use this for `TABLE` or `PACKAGE` mode; enter the owner/schema of the listed objects, or leave blank to use `INSTALL_SCHEMA_NAME`
- `OBJECT_NAMES`: use this for `TABLE` or `PACKAGE` mode; enter one or more object names separated by commas
- `MATCH_LIMIT`: optional
- `TEAM_ATTRIBUTES_JSON`: use this for `JSON` mode

The script now shows one simple input section for these values. Enter only the fields that apply to the selected `SCOPE_MODE` and leave the others blank.

Guided input examples:

- Single schema scope:
  `SCOPE_MODE = SCHEMA`
  `SCOPE_OWNERS = <INSTALL_SCHEMA_NAME>`
- Multiple schema owners:
  `SCOPE_MODE = SCHEMA`
  `SCOPE_OWNERS = SH,HR`
- Multiple tables in one schema:
  `SCOPE_MODE = TABLE`
  `OBJECT_OWNER = SH`
  `OBJECT_NAMES = SALES,CUSTOMERS,PRODUCTS`
- Multiple packages in one schema:
  `SCOPE_MODE = PACKAGE`
  `OBJECT_OWNER = HR`
  `OBJECT_NAMES = EMP_PKG,PAYROLL_PKG`

Advanced `TEAM_ATTRIBUTES_JSON` example for JSON mode:

```json
{"object_list":[
  {"owner":"SH","type":"TABLE","name":"SALES"},
  {"owner":"SH","type":"TABLE","name":"CUSTOMERS"},
  {"owner":"SH","type":"TABLE","name":"PRODUCTS"}
]}
```

What the agent installer does:

- Grants required privileges for agent creation and background jobs, including `CREATE JOB`, `CREATE SEQUENCE`, `CREATE PROCEDURE`, and `CREATE VIEW`
- Creates `DATABASE_INSPECT_AGENT_JOB_LOG$` in the target schema
- Creates submitter and worker procedures in the target schema
- Validates that `AI_PROFILE_NAME` has a non-null `embedding_model`
- Requires `AI_PROFILE_NAME` to include `oci_compartment_id` when the profile uses an OCI Generative AI model/provider
- Enforces `AI_PROFILE_NAME` as `profile_name`, even if `TEAM_ATTRIBUTES_JSON` includes a different value
- Converts common installation failures into user-friendly log messages, including missing OCI compartment id, tablespace quota errors, and embedding-dimension mismatch errors
- Verifies that the expected agent tools were recreated successfully

`RECREATE_EXISTING = Y` behavior:

- Cleans up any existing Select AI team, agent, and task objects for the requested team name
- Drops the existing team metadata and vectorized object state
- Recreates the team using the resolved attributes

### Monitoring Background Installation

Each submission writes one row to `DATABASE_INSPECT_AGENT_JOB_LOG$`.

Use a query like this to monitor progress:

```sql
SELECT *
FROM <INSTALL_SCHEMA_NAME>.DATABASE_INSPECT_AGENT_JOB_LOG$
ORDER BY run_id DESC;
```

Typical statuses include `PRECHECK`, `QUEUED`, `RUNNING`, `SUCCEEDED`, `FAILED`, `TEAM_EXISTS`, and `FAILED_TO_QUEUE`.

---

## Architecture Overview

Run `database_inspect_tool.sql` to install the `DATABASE_INSPECT` package and prerequisites
   ↓
Run `database_inspect_agent.sql` to validate inputs and queue background installation
   ↓
`DATABASE_INSPECT_AGENT_WORKER`
   ├── Ensures `DATABASE_INSPECT.setup` completed
   ├── Validates profile and attributes
   ├── Optionally drops and recreates existing team state
   └── Creates tools, task, team, and vectorized object metadata
   ↓
User query
   ↓
<inspect_agent_team>
   ↓
Agent Reasoning
   ├── LIST_OBJECTS
   ├── LIST_INCOMING_DEPENDENCIES
   ├── LIST_OUTGOING_DEPENDENCIES
   ├── RETRIEVE_OBJECT_METADATA
   ├── RETRIEVE_OBJECT_METADATA_CHUNKS
   ├── EXPAND_OBJECT_METADATA_CHUNK
   ├── SUMMARIZE_OBJECT
   └── GENERATE_PLDOC
   ↓
Final Verified Answer

---

## Repository Contents

```text
.
├── database_inspect_tool.sql
│   ├── Installer script for DATABASE_INSPECT package and tool framework
│   ├── Grants required privileges to the target schema
│   ├── Compiles package specification and body
│   └── Leaves internal table setup to target-schema execution
│
├── database_inspect_agent.sql
│   ├── Installer and configuration script for DATABASE_INSPECT AI team
│   ├── Accepts target schema, AI profile, team name, recreate flag, and optional team attributes
│   ├── Logs asynchronous installation progress to DATABASE_INSPECT_AGENT_JOB_LOG$
│   └── Creates or recreates the inspect team using background job execution
│
├── README.md
└── README_nl2sql.md
```

---

## Supported APIs

##### create_inspect_agent_team

Creates an inspect agent team using the provided `attributes` such as `profile_name` and `object_list`.

```
DATABASE_INSPECT.create_inspect_agent_team(
	agent_team_name		IN VARCHAR2,
	attributes		IN CLOB);
```

**Syntax**

|    argument    | Description                   | Mandatory | value format                                                                                                 |
| :-------------: | ----------------------------- | --------- | ------------------------------------------------------------------------------------------------------------ |
| agent_team_name | Name of the agent team        | Y         |                                                                                                              |
|   attributes   | Team configuration attributes | Y         | JSON object CLOB, e.g.`{"profile_name":"openai_profile","object_list":[{"owner":"DEMO","type":"schema"}]}` |

**Attributes**

| attribute name | description                                                                                                                                                                                       | Mandatory | attribute value format                                                                                                  |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- | ----------------------------------------------------------------------------------------------------------------------- |
| profile_name   | AI profile name for the agent team.                                                                                                                                                              | Y         |                                                                                                                         |
| object_list    | List of database objects the agent team is allowed to inspect.<br />Support "owner", "type" and optional "name" for the object. if "name" is not provided, we will set all objects in the schema. | Y         | e.g.<br />'[{"owner":"DEMO", "type":"schema"}]'<br />'[{"owner":"DEMO", "type":"package body", "name":"CHECKOUT_PKG"}]' |
| match_limit    | Specifies the maximum number of results to return in a hybrid/vector search query from RETRIEVE_OBJECT_METADATA agent tool.                                                                     | N         | default value is 10                                                                                                     |

##### drop_inspect_agent_team

Drop the specified inspect agent team.

```
DATABASE_INSPECT.drop_inspect_agent_team(
	agent_team_name		IN VARCHAR2,
	force		        IN BOOLEAN DEFAULT FALSE);
```

**Syntax**

|    argument    | Description                          | Mandatory | value format |
| :-------------: | ------------------------------------ | --------- | ------------ |
| agent_team_name | Name of the agent team               | Y         |              |
|      force      | If `TRUE`, skip errors during drop | N         | TRUE, FALSE  |

##### update_inspect_agent_team

Update an inspect agent team’s attributes.

```
DATABASE_INSPECT.update_inspect_agent_team(
	agent_team_name		IN VARCHAR2,
	attributes		IN CLOB);
```

**Syntax**

|    argument    | Description                   | Mandatory | value format                                                                                                 |
| :-------------: | ----------------------------- | --------- | ------------------------------------------------------------------------------------------------------------ |
| agent_team_name | Name of the agent team        | Y         |                                                                                                              |
|   attributes   | Team configuration attributes | Y         | JSON object CLOB, e.g.`{"profile_name":"openai_profile","object_list":[{"owner":"DEMO","type":"schema"}]}` |

**Attributes**

| attribute name | description                                                                                                                                                                                                                                                                                              | Mandatory | attribute value format                                                                                                  |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- | ----------------------------------------------------------------------------------------------------------------------- |
| profile_name   | AI profile name for the agent team. If provided, the exisiting profile_name value will be overwritten. Any profile change triggers re-vectorization of the `object_list`, because embedding dimensions or similarity semantics can change even within the same provider.                                | N         |                                                                                                                         |
| object_list    | List of database objects the agent team is allowed to inspect.<br />Support "owner", "type" and optional "name" for the object. if "name" is not provided, we will set all objects in the schema.<br />If provided, the original object_list will be removed and the new object_list will be vectorized. | N         | e.g.<br />'[{"owner":"DEMO", "type":"schema"}]'<br />'[{"owner":"DEMO", "type":"package body", "name":"CHECKOUT_PKG"}]' |
| match_limit    | Specifies the maximum number of results to return in a hybrid/vector search query from RETRIEVE_OBJECT_METADATA agent tool.                                                                                                                                                                            | N         | default value is 10                                                                                                     |

---

## Agent Setup

An inspection agent can be created directly by calling `DATABASE_INSPECT.create_inspect_agent_team`, but the recommended installation path is to use `database_inspect_agent.sql` so that setup, validation, logging, and background execution are handled for you.

### Supported Tools

* **list_objects**: List all available objects for the agent
* **list_incoming_dependencies**: List objects that depend on or reference the given object
* **list_outgoing_dependencies**: List objects that the given object itself depends on or references
* **retrieve_object_metadata**: Retrieve the full metadata for the given object
* **retrieve_object_metadata_chunks**: Retrieve a list of metadata chunks by performing hybrid search (vector search + Oracle Text search) to answer user’s query
* **expand_object_metadata_chunk**: Given a selected result from the retrieve_object_metadata_chunks tool, returns an expanded metadata segment around the specified chunk to provide additional context
* **generate_pldoc**: Generates a PLDoc/JavaDoc-style comment block (/** ... */) for a given object
* **summarize_object**: Summarize the definition, purpose or behavior of the given object

---

## Example Prompts

We use a small but realistic product purchase order schema and some example prompts to show how you can use Selec AI Inspect agent to interact with your database.

This schema includes more than 10 tables, such as customers, products, orders, and tax rates, 3 standalone functions, including a tax-calculation function, and one package that contains the main checkout logic.

**Prompts**:

1. Show me all database objects available for us to inspect.
2. Show me the column definitions for the PRODUCTS table, and list all database objects that reference or depend on it.
3. If I rename the active_flag column in the PRODUCTS table to is_active, where do I need to update the code?
4. Explain what the CHECKOUT_PKG.reprice_order procedure is used for, including its purpose, parameters and business rules.
5. Can you write and run a test script for the calc_tax_amount function to verify the results and check for any bugs?
6. When I call the calc_tax_amount function, for state_code = 'CA' (rate 0.0825), calc_tax_amount(10.01, 'CA') returns 0.82, but it should return 0.83. Please debug the function and show me the exact code that needs to be fixed.
7. Summarize the CHECKOUT_PKG package body in one paragraph.
8. Generate PLDoc comments for the calc_tax_amount function.
9. Which packages and procedures will be impacted if I modify the ORDERS table?
10.Get me a list of tables available for inspection.

---

## License

Universal Permissive License (UPL) 1.0
https://oss.oracle.com/licenses/upl/
Copyright (c) 2026 Oracle and/or its affiliates.
