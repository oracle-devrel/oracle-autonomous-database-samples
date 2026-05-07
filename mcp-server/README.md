# Autonomous AI Database MCP Tools

This repository contains SQL/PLSQL definitions for custom MCP tools that you can register in Oracle Autonomous AI Database using Select AI Agent.

## What This Repository Provides

The script creates:
1. Backend PL/SQL functions that return JSON output.
2. MCP tool registrations using `DBMS_CLOUD_AI_AGENT.CREATE_TOOL`.

The tools are intended for schema discovery and read-oriented SQL exploration from MCP-compatible clients.

## Prerequisites

Before running the script:
1. You have an Oracle Autonomous AI Database environment with Select AI Agent support.
2. The database user running the script can create functions/procedures in its schema.
3. The database user has `EXECUTE` on `DBMS_CLOUD_AI_AGENT` (required).

Example grant (run as admin user):

```sql
GRANT EXECUTE ON DBMS_CLOUD_AI_AGENT TO <db_user>;
```

## Installation

1. Connect to your target schema/user in Autonomous AI Database.
2. Run the SQL script:

```sql
@common-db-tools.sql
```

3. Verify that tools were created (for example, by listing tools through Select AI Agent views or your MCP setup flow).
4. Configure your MCP client/server to use the Autonomous Database MCP endpoint.

## Tool Summary

The following tools are created by `common-db-tools.sql`:

### `LIST_SCHEMAS`
- Function: `LIST_SCHEMAS(offset, limit)`
- Purpose: Returns schema names visible to the current user.
- Inputs:
1. `offset`: Pagination offset (skip rows).
2. `limit`: Pagination size (max rows to return).

### `LIST_OBJECTS`
- Function: `LIST_OBJECTS(schema_name, offset, limit)`
- Purpose: Returns objects in a schema (table/view/synonym/function/procedure/trigger).
- Inputs:
1. `schema_name`: Database schema name.
2. `offset`: Pagination offset.
3. `limit`: Pagination size.

### `GET_OBJECT_DETAILS`
- Function: `GET_OBJECT_DETAILS(owner_name, obj_name)`
- Purpose: Returns metadata sections for an object, including object info, indexes, columns, and constraints.
- Inputs:
1. `owner_name`: Database schema name.
2. `obj_name`: Object name (for example, table or view).

### `EXECUTE_SQL`
- Function: `EXECUTE_SQL(query, offset, limit)`
- Purpose: Executes a provided query and returns JSON rows with pagination applied.
- Inputs:
1. `query`: `SELECT` statement without trailing semicolon.
2. `offset`: Pagination offset.
3. `limit`: Pagination size.

## Notes

1. `offset` and `limit` are used to control page size and response volume.
2. Tool instructions in the script explicitly indicate tool output should not be treated as LLM instructions.
3. Use read-only SQL for `EXECUTE_SQL` in MCP workflows.

## Documentation Links

1. MCP Server documentation:  
   https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/mcp-server.html
2. Use MCP Server (includes setup flow and examples):  
   https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/use-mcp-server.html
3. Create Select AI Agent Tools (`DBMS_CLOUD_AI_AGENT.CREATE_TOOL`):  
   https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/use-mcp-server.html
4. `DBMS_CLOUD_AI_AGENT` package reference:  
   https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/dbms-cloud-ai-agent-package.html
