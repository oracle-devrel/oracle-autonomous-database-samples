# adb-mcp-server-setup

End-user guide for creating an MCP server config in Codex for Oracle Autonomous Database (ADW/ATP).

This skill handles the repetitive setup work needed before Codex can use the managed Autonomous AI Database MCP server: it writes the Codex MCP config, refreshes the ADB bearer token, and can generate the default database-side tools for schema/object inspection and read-only SQL.

GitHub location: https://github.com/oracle-devrel/oracle-autonomous-database-samples/tree/main/mcp-server/codex-skills/adb-mcp-server-setup

Two-stage flow:
- Stage 1 (mandatory): create/update `mcp_servers.<config_name>` in `~/.codex/config.toml` and refresh token env setup.
- Stage 2 (optional): bootstrap default DB tools via generated SQL (`DBMS_CLOUD_AI_AGENT.CREATE_TOOL` pattern) and optionally execute that SQL with SQLPlus. Do not use a SQLPlus MCP server in this flow. In VSCode, it may run in the Codex tab.

## Before You Start

Nothing in this skill will work until these prerequisites are met.

1. Enable MCP server on the target Autonomous AI Database (mandatory).
- In OCI Console, add this free-form tag on the database. Set Namespace to `None`:
  - Tag Name: `adb$feature`
  - Tag Value: `{"name":"mcp_server","enable":true}`

2. Have the Stage 1 setup inputs ready.
- `server_config_name` (example: `my_adw_prod`; maps to script flag `--server-name`)
- `adb_ocid`
- `region` (example: `us-phoenix-1`)
- Choose one credential path:
  - Direct DB credentials:
    - `db_username`
    - `db_password`
    - Leave `db_password` empty to let the CLI prompt securely
  - Vault-backed credentials:
    - `db_username_secret_ocid`
    - `db_password_secret_ocid`
    - optional `oci_profile`

OCI Vault secret option (recommended for automation):
- `db_username_secret_ocid` (optional): Vault Secret OCID containing the DB username
- `db_password_secret_ocid` (optional): Vault Secret OCID containing the DB password
- `oci_profile` (optional): OCI CLI profile name used to fetch secrets (if omitted, use `DEFAULT`)
- OCI CLI must be installed and a valid OCI CLI session/profile must exist on the machine that runs the script
- If needed, authenticate first with:

```bash
oci session authenticate --region <region> --profile-name DEFAULT
```
- Optional sanity check (Vault path):

```bash
oci --profile DEFAULT --auth security_token secrets secret-bundle get --secret-id <secret_ocid>
```
- Vault secret fetch auto-tries `--auth security_token` for session-authenticated profiles, with fallback to default OCI CLI auth mode.
- This skill flow does not require you to manually edit/add `user` in OCI config.
- OCI CLI usage in this flow prefers `--auth security_token` for session-auth profiles, with fallback to default OCI CLI auth.

3. Run Stage 1 first. Only after Stage 1 completes, decide whether you also want Stage 2 tool bootstrap.
- Do not ask for Stage 2 confirmation during initial Stage 1 input collection
- Stage 2 is optional and creates the default database MCP tools used for schema listing, object inspection, and read-only SQL queries
- If you want Stage 2, then decide whether you want SQL generated only or generated and executed via SQLPlus
- This Stage 2 flow does not use a SQLPlus MCP server
- If you want SQLPlus execution, then provide `db_service_name` or a full connect string
- SQLPlus execution reuses the same DB credentials resolved in Stage 1
- If Vault secrets are used, do not ask again for direct DB credentials
- Initial tool/function creation should use an admin/elevated database user.
- The setup user must have `EXECUTE` on `DBMS_CLOUD_AI_AGENT`
- After bootstrap is complete, you can re-run with different credentials for token/config updates
- If using automatic bootstrap, SQLPlus must be available in PATH as `sqlplus`, or passed via `--sqlplus-command`
- If SQLPlus is unavailable, run Stage 1 first and then use manual bootstrap SQL with SQL Developer, SQL Worksheet, SQLcl, or SQLPlus

4. Advanced overrides (optional).
- `auto_approve` if the user wants to change the default approved tool list
- `shell_path` for non-default shell startup-file handling during token persistence

## Expected Initial Intake Format

The first skill response for Stage 1 should be formatted like this:

```text
Using adb-mcp-server-setup to create the MCP config.

**Prerequisites:**
- Confirm the target ADB has free-form tag `adb$feature={"name":"mcp_server","enable":true}`.
- In OCI Console, use a free-form tag with Namespace set to `None`.
- If you want to use Vault secrets, authenticate OCI CLI first:
  `oci session authenticate --region <region> --profile-name DEFAULT`

**Inputs:** Provide all inputs at once or step-by-step.
- `server_config_name`: Name for this MCP server configuration (e.g., `my_adw_prod`)
- `adb_ocid`
- `region`: OCI region of the database
- Choose one credential path:
  - Direct DB credentials:
    - `db_username`
    - `db_password`
    - Leave `db_password` empty to use the secure CLI prompt, or provide it directly if needed.
  - Or Vault-backed credentials:
    - `db_username_secret_ocid`
    - `db_password_secret_ocid`
    - `oci_profile` (optional)
```

Do not collapse prerequisites and inputs into one paragraph. Keep one item per line.

## Command Templates

Stage 1 (secure prompt):

```bash
python3 scripts/setup_adb_mcp_server.py \
  --server-name <server_config_name> \
  --adb-ocid <adb_ocid> \
  --region <region> \
  --db-username <db_username> \
  --backup
```

Stage 1 (Vault):

```bash
python3 scripts/setup_adb_mcp_server.py \
  --server-name <server_config_name> \
  --adb-ocid <adb_ocid> \
  --region <region> \
  --db-username-secret-ocid <vault_secret_ocid_for_username> \
  --db-password-secret-ocid <vault_secret_ocid_for_password> \
  --oci-profile <optional_profile_name> \
  --backup
```

Stage 2 SQL only (direct credentials):

```bash
python3 scripts/setup_adb_mcp_server.py \
  --server-name <server_config_name> \
  --adb-ocid <adb_ocid> \
  --region <region> \
  --db-username <db_username> \
  --bootstrap-tools \
  --backup
```

Stage 2 SQL only (Vault credentials):

```bash
python3 scripts/setup_adb_mcp_server.py \
  --server-name <server_config_name> \
  --adb-ocid <adb_ocid> \
  --region <region> \
  --db-username-secret-ocid <vault_secret_ocid_for_username> \
  --db-password-secret-ocid <vault_secret_ocid_for_password> \
  --oci-profile <optional_profile_name> \
  --bootstrap-tools \
  --backup
```

Stage 2 SQLPlus execution (direct credentials):

```bash
python3 scripts/setup_adb_mcp_server.py \
  --server-name <server_config_name> \
  --adb-ocid <adb_ocid> \
  --region <region> \
  --db-username <db_username> \
  --bootstrap-tools \
  --run-bootstrap-tools \
  --db-service-name '<db_service_name>' \
  --backup
```

Stage 2 SQLPlus execution (Vault credentials):

```bash
python3 scripts/setup_adb_mcp_server.py \
  --server-name <server_config_name> \
  --adb-ocid <adb_ocid> \
  --region <region> \
  --db-username-secret-ocid <vault_secret_ocid_for_username> \
  --db-password-secret-ocid <vault_secret_ocid_for_password> \
  --oci-profile <optional_profile_name> \
  --bootstrap-tools \
  --run-bootstrap-tools \
  --db-service-name '<db_service_name>' \
  --backup
```

## Required Post-Stage-1 Message

Use this exact structure before any Stage 2 question:

```text
--------------------------------------------------
Stage 1 completed successfully.

**Server created:** <server_config_name>
**Config updated:** <config_path>
**Backup created:** <backup_path>
**Token env var set:** <token_env_var> (<platform_persistence_note>)

--------------------------------------------------
**Do you want to run Stage 2 bootstrap of default DB tools (LIST_SCHEMAS, LIST_OBJECTS, GET_OBJECT_DETAILS, EXECUTE_SQL)?**
**Recommended:** Say **Yes** if this database has not been bootstrapped previously.

If yes, choose one:

1. Generate SQL only
2. Generate and execute via SQLPlus (not MCP server). I’ll need `db_service_name` or an optional full connect string
3. No (skip Stage 2 for now)
```

Use the platform note that matches where Codex runs:
- macOS GUI app: `via launchctl`
- macOS/Linux terminal launch: `via shell startup file when available`
- Windows VS Code extension: `via setx for future VS Code processes`
- Unknown/manual environment: `set in the Codex process environment before launch`

## Required Post-Stage-2 Message

Use this exact structure:

```text
--------------------------------------------------
Stage 2 completed successfully.

**Bootstrap mode:** <sql_only_or_sqlplus_executed>
**Bootstrap SQL path:** <bootstrap_sql_path>
**Default DB tools bootstrapped:** LIST_SCHEMAS, LIST_OBJECTS, GET_OBJECT_DETAILS, EXECUTE_SQL
**SUCCESS:** The default database MCP tools are now registered and ready to use.
You can run verification/tool calls after reloading Codex.


**Next step:** Restart Codex now so updated MCP config/token env are loaded before verification/tool calls. On Windows with the VS Code extension, restart VS Code.
```

## What The Database Tools Are

In this skill, a "tool" is a database-side MCP action backed by a SQL/PLSQL function in the target Autonomous Database and registered via `DBMS_CLOUD_AI_AGENT.CREATE_TOOL`.

The default tool set is:
- `LIST_SCHEMAS` to list schemas visible to the current user
- `LIST_OBJECTS` to list objects in a schema
- `GET_OBJECT_DETAILS` to return object DDL/details
- `EXECUTE_SQL` to run read-only SQL and return JSON rows

These tools are what let Codex inspect and query the database through MCP. Bootstrapping them is usually a one-time Stage 2 setup step for a new database environment. If the database already has the tools you need, you can skip Stage 2 and only complete Stage 1 MCP client setup plus token refresh.

## Install Skill

Install this skill into your local Codex skills folder, then restart Codex. On Windows with the VS Code extension, restart VS Code.

Target folder:
- macOS/Linux: `~/.codex/skills/adb-mcp-server-setup`
- Windows: `%USERPROFILE%\.codex\skills\adb-mcp-server-setup`

### Recommended: ZIP install

#### macOS/Linux

```bash
mkdir -p ~/.codex/skills
unzip -o adb-mcp-server-setup.zip -d ~/.codex/skills
ls ~/.codex/skills/adb-mcp-server-setup/SKILL.md
```

#### Windows

Use File Explorer "Extract All..." and extract `adb-mcp-server-setup.zip` into:
`%USERPROFILE%\.codex\skills\`

Then confirm this file exists:
`%USERPROFILE%\.codex\skills\adb-mcp-server-setup\SKILL.md`

Windows ZIP warning: File Explorer may create a nested folder like:
`%USERPROFILE%\.codex\skills\adb-mcp-server-setup\adb-mcp-server-setup\`

Open and install from the inner folder, the one that directly contains `README.md` and `SKILL.md`. If the outer folder is opened in VS Code, the project can look empty and install commands may fail.

## Use in Codex

Use this exact prompt:

```text
Use $adb-mcp-server-setup to create an MCP server for my ADW
```

Happy-path checklist:
1. Install the skill.
2. Restart Codex. On Windows with the VS Code extension, restart VS Code.
3. Run the prompt above.
4. Complete Stage 1 setup, then decide whether you also want Stage 2 one-time tool bootstrap.

VS Code extension note:
- Use the Codex Chat tab to start the skill and collect Stage 1 inputs.
- If you continue in the Codex tab for Stage 2 or verification, keep the same server name and restart VS Code after token/config changes so the extension sees the new environment.

## What the Skill Does

Stage 1:
1. Updates `~/.codex/config.toml` with a new `mcp_servers.<server_config_name>` entry.
   The default server shape is native `streamable-http` with `url` and `bearer_token_env_var`.
2. Fetches a fresh ADB auth token and persists it into the OS process environment.
   For `streamable-http`, do not place the token under `[mcp_servers.<name>.env]`.
   Token env var is derived from `server_config_name` (for example `MY_ADW_PROD_ADB_TOKEN`).
   ADB bearer tokens expire after about 1 hour. Re-run Stage 1 to refresh the token when needed.

Stage 2:
3. Optionally bootstraps default tools in the target database:
- `LIST_SCHEMAS`
- `LIST_OBJECTS`
- `GET_OBJECT_DETAILS`
- `EXECUTE_SQL`
4. Optionally executes the generated bootstrap SQL with SQLPlus, reusing the Stage 1 DB credentials.
   This does not create or use a SQLPlus MCP server.
   If SQLPlus is unavailable, Codex reports the generated SQL path. Copy the SQL from the temp folder to a durable location before manual execution because temp files can be deleted.
   For manual execution, use the Autonomous AI Database `ADMIN` user in SQL Developer, SQL Worksheet, SQLcl, or SQLPlus unless your DBA has explicitly granted another setup user the required privileges.
   You can create other tools later with the Select AI Agent framework SDK.

## Verify

After setup:

1. Fast check: run `LIST_OBJECTS` against a known schema, then `GET_OBJECT_DETAILS` for a known object. `LIST_SCHEMAS` is still useful, but can be less reliable as a first check when the MCP client exposes suffixed tool names.

The ADB MCP server may expose database tools with generated suffixes such as `LIST_OBJECTS_15`. Use the tool names discovered in the active MCP session instead of assuming the unsuffixed database tool name is callable directly.

2. Optional deep check in DB:

```sql
SELECT tool_name, status
FROM user_ai_agent_tools
WHERE tool_name IN ('LIST_SCHEMAS', 'LIST_OBJECTS', 'GET_OBJECT_DETAILS', 'EXECUTE_SQL')
ORDER BY tool_name;
-- or
SELECT tool_name, status
FROM user_cloud_ai_agent_tools
WHERE tool_name IN ('LIST_SCHEMAS', 'LIST_OBJECTS', 'GET_OBJECT_DETAILS', 'EXECUTE_SQL')
ORDER BY tool_name;
```

## Troubleshooting

- `invalid_grant` during token request:
  - Verify `db_username`/`db_password`
  - Confirm `adb_ocid` and `region` match the target database
  - Confirm account is usable for ADB token auth

- `401 ADB-00015` or invalid credential after setup previously worked:
  - The ADB bearer token may have expired; tokens last about 1 hour
  - Re-run Stage 1 to refresh the token
  - Restart Codex, or restart VS Code on Windows, so the new token environment is loaded

- MCP startup fails in Codex:
  - Use native `streamable-http` server shape for Oracle ADB MCP servers
  - In Codex CLI terms, that means `codex mcp add <name> --url <endpoint> --bearer-token-env-var <ENV_VAR>`
  - Ensure the token env var exists in the Codex process environment before launch/restart

- Codex rejects `env` inside a `streamable-http` server block:
  - Do not place the bearer token under `[mcp_servers.<name>.env]`
  - The token must be available in the Codex process environment
  - On macOS, this skill uses `launchctl setenv` by default so the Codex app can see the token after restart
  - On Windows, this skill uses `setx` so future VS Code processes can see the token after restart
  - For repeated CLI calls, prefer `MY_SERVER_ADB_TOKEN=... <command>` over `source ~/.zshrc && <command>` once the token is already known

- SQLPlus bootstrap fails:
  - Confirm SQLPlus is available in PATH (`sqlplus`) or pass `--sqlplus-command`
  - Confirm connect target (`db_service_name` or a full connect string)
  - Prefer a full service name for walletless mode (for example `<dbid>_<name>_medium.adb.oraclecloud.com`)
  - If fallback uses TNS alias, ensure `TNS_ADMIN` points to the wallet directory containing `tnsnames.ora`
  - Use the Autonomous AI Database `ADMIN` user for initial tool creation unless your DBA has explicitly prepared another setup user
  - Ensure the setup user has `EXECUTE` on `DBMS_CLOUD_AI_AGENT`
  - Re-run via Codex without SQLPlus bootstrap and request manual bootstrap SQL
  - Copy generated SQL out of the system temp folder before running it manually

## Platform Behavior

- ADB MCP config is native `streamable-http`.
- `sqlplus` is resolved from PATH by default when needed.
- If your environment differs, ask Codex to set `--sqlplus-command` or `--shell-path`.

## Model Compatibility

This skill is designed to work across Codex-capable models because execution logic lives in the Python script.

To keep outcomes consistent:
- Use the same invocation prompt.
- Provide the same input values.
- Run the same verification checks.

## Advanced: Internal Distribution

### Install with git clone (internal)

#### macOS/Linux

```bash
mkdir -p ~/.codex/skills
git clone <internal_repo_url> /tmp/skills-repo
cp -R /tmp/skills-repo/skills/adb-mcp-server-setup ~/.codex/skills/
ls ~/.codex/skills/adb-mcp-server-setup/SKILL.md
```

#### Windows

Clone the repo with your preferred git client, then copy:
`skills/adb-mcp-server-setup`
into:
`%USERPROFILE%\.codex\skills\`

### Install from GitHub (when published)

- Replace `<github_repo_url>` with your published repository URL.
- Use the same clone/copy pattern as internal distribution.

## Related Docs

- `SKILL.md`
- `references/oracle-adb-mcp.md`
