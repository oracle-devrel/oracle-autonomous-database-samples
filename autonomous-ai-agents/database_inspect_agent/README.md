# Select AI Inspect - Database Inspection Tool Built Using Select AI Agent

## Overview

Select AI Inspect is an AI-powered inspection tool built using the **Select AI Agent** framework. It enables users to explore, understand, and interact with database objects and their metadata using natural language.

### Use Cases

Instead of manually reviewing tables, searching through PL/SQL files, or examining function and procedure metadata, users can simply ask the Select AI Inspect agent natural language questions such as:

* How are these tables related?
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
* Triggers
* Functions
* Procedures
* Packages
* Package Bodies
* Schema

Users may define the inspection scope either at the individual object level or at the schema level. When a schema is specified, all supported object types within that schema are included.

---

## Architecture Overview

Run `database_inspect_tool.sql` to install `DATABASE_INSPECT` package and tools
   ↓
Run `database_inspect_agent.sql` to configure and create the inspect agent team
   ↓
execute `DATABASE_INSPECT.create_inspect_agent_team(<inspect_agent_team>, <attributes_in_json_object>)` to create an Inspect agent;
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
│   └── Compiles package specification and body
│
├── database_inspect_agent.sql
│   ├── Installer and configuration script for DATABASE_INSPECT AI team
│   ├── Accepts target schema, AI profile, and optional team attributes
│   └── Recreates the inspect team using DATABASE_INSPECT package APIs
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
| profile_name   | AI profile name for the agent team. If provided, the exisiting profile_name value will be overwritten. If a different AI provider is specified, the `object_list` will be re-vectorized due to embedding dimension mismatches.                                                                       | N         |                                                                                                                         |
| object_list    | List of database objects the agent team is allowed to inspect.<br />Support "owner", "type" and optional "name" for the object. if "name" is not provided, we will set all objects in the schema.<br />If provided, the original object_list will be removed and the new object_list will be vectorized. | N         | e.g.<br />'[{"owner":"DEMO", "type":"schema"}]'<br />'[{"owner":"DEMO", "type":"package body", "name":"CHECKOUT_PKG"}]' |
| match_limit    | Specifies the maximum number of results to return in a hybrid/vector search query from RETRIEVE_OBJECT_METADATA agent tool.                                                                                                                                                                            | N         | default value is 10                                                                                                     |


---

## Agent Setup

An inspection agent is created when you call `DATABASE_INSPECT.create_inspect_agent_team`.

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
