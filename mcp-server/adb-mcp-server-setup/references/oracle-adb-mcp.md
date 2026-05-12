# Oracle ADB MCP Reference

Source:
- https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/use-mcp-server.html

## Endpoint Patterns

- Data access host:
  - `https://dataaccess.adb.<region>.oraclecloudapps.com`
- Database MCP endpoint:
  - `https://dataaccess.adb.<region>.oraclecloudapps.com/adb/mcp/v1/databases/<adb_ocid>`
- Token endpoint:
  - `https://dataaccess.adb.<region>.oraclecloudapps.com/adb/auth/v1/databases/<adb_ocid>/token`

## Token Request Pattern

- Method: `POST`
- Headers:
  - `Content-Type: application/json`
  - `Accept: application/json`
- Body fields:
  - `grant_type=password`
  - `username`
  - `password`
- Response: `access_token`

## Sample Custom Tools (Database Side)

Oracle page includes Sample Custom Tools using `DBMS_CLOUD_AI_AGENT.CREATE_TOOL`.
Typical tool set:
- `LIST_SCHEMAS`
- `LIST_OBJECTS`
- `GET_OBJECT_DETAILS`
- `EXECUTE_SQL`

These tools must exist in the database before Codex can call them from the MCP server.

For `EXECUTE_SQL`, follow Oracle's sample input name: the PL/SQL function parameter and `tool_inputs` entry should be `query`. Using a different input name such as `query_text` can register the database tool but make it unreachable or unusable from the MCP client.

## SQLPlus Branching Guidance

- If SQLPlus is available, bootstrap tools automatically by executing generated SQL.
- This branch uses SQLPlus only. Do not introduce or depend on a SQLPlus MCP server.
- SQLPlus execution can reuse the same database credentials already resolved in Stage 1.
- If Vault secrets are used for Stage 1, do not ask again for direct DB credentials during Stage 2.
- If SQLPlus is not available, provide generated SQL and a manual run command for SQL Developer, SQL Worksheet, SQLcl, or SQLPlus.
- Generated SQL may be written to the system temp folder unless `--bootstrap-sql-out` is provided. Tell users to copy it somewhere durable before manual execution.
- Initial tool creation should normally be run as the Autonomous AI Database `ADMIN` user unless another setup user has the required privileges.
- Verify tool registration after bootstrap using one of:
  - `SELECT tool_name, status FROM user_ai_agent_tools WHERE tool_name IN ('LIST_SCHEMAS', 'LIST_OBJECTS', 'GET_OBJECT_DETAILS', 'EXECUTE_SQL') ORDER BY tool_name;`
  - `SELECT tool_name, status FROM user_cloud_ai_agent_tools WHERE tool_name IN ('LIST_SCHEMAS', 'LIST_OBJECTS', 'GET_OBJECT_DETAILS', 'EXECUTE_SQL') ORDER BY tool_name;`

## Token Behavior

- ADB bearer tokens expire after about 1 hour.
- If a previously working setup fails with `401 ADB-00015` or invalid credential errors, re-run Stage 1 to refresh the token and restart Codex or VS Code.
- macOS GUI sessions use `launchctl`; Windows VS Code extension sessions use `setx` for future processes.

## Codex Client Guidance

Prefer native streamable HTTP MCP config in Codex for Oracle ADB:
- `url = "https://dataaccess.adb.<region>.oraclecloudapps.com/adb/mcp/v1/databases/<adb_ocid>"`
- `bearer_token_env_var = "<TOKEN_ENV_VAR>"`
- `transport = "streamable-http"`
- Do not add `[mcp_servers.<name>.env]` for this transport; Codex expects the bearer token in its process environment.

For Codex, keep the server in native authenticated streamable HTTP mode and provide the token through process environment variables.

The MCP server may expose registered database tools with generated suffixes such as `LIST_OBJECTS_15`. During verification, use the tool names discovered in the active MCP session. Prefer `LIST_OBJECTS` against a known schema as the first smoke test; `LIST_SCHEMAS` can be less reliable when the client exposes suffixed names.
