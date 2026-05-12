---
name: adb-mcp-server-setup
description: Create or update a Codex MCP server entry for Oracle Autonomous Database, refresh ADB bearer token, and optionally bootstrap default DB tools (LIST_SCHEMAS, LIST_OBJECTS, GET_OBJECT_DETAILS, EXECUTE_SQL).
---

# ADB MCP Server Setup

Two-stage flow:
- **Stage 1 (mandatory):** create/update `mcp_servers.<name>` in `~/.codex/config.toml` and refresh token env setup.
- **Stage 2 (optional):** bootstrap default DB tools via generated SQL (`DBMS_CLOUD_AI_AGENT.CREATE_TOOL` pattern) and optionally execute that SQL with SQLPlus. Do not use a SQLPlus MCP server in this flow.


## Tone Guidelines

**Voice:** Direct, clear, and conversational. Address the reader as "you."

**Formality level:** Casual-professional. Write as a knowledgeable colleague explaining something to a peer, not as a consultant writing a report.


## Prerequisites

1. Before setup, target ADB must have an OCI free-form tag. In OCI Console, set Namespace to `None`:
- `adb$feature={"name":"mcp_server","enable":true}`

2. If using OCI Secrets and Vault, one should have authenticated using OCI session

```bash
oci session authenticate --region <region> --profile-name DEFAULT
```
- Do not ask the user to edit/add `user` in OCI config as part of this skill flow.
- Optional sanity check before Stage 1 (Vault path):

```bash
oci --profile DEFAULT --auth security_token secrets secret-bundle get --secret-id <secret_ocid>
```

## Stage 1 Inputs

Required inputs:
- `server_config_name`
- `adb_ocid`
- `region`
- Choose one credential path:
- Direct DB credentials:
  - `db_username`
  - `db_password`
  - Leave `db_password` empty to let the CLI prompt securely
- Vault-backed credentials:
  - `db_username_secret_ocid`
  - `db_password_secret_ocid`
  - `oci_profile` (optional)

OCI commands usage:
- Use `--auth security_token` for session-auth profiles, with fallback to default OCI CLI auth.


## Interaction Rules (Strict)

- Always start by collecting Stage 1 details for MCP config creation.
- Stage 1 must complete before any Stage 2 question.
- Emit exactly one Stage 1 intake/follow-up prompt per turn.
- If Stage 1 inputs are incomplete, end the turn after that single prompt and wait for user input.
- The initial Stage 1 intake prompt must use short labeled sections and one item per line.
- Do not collapse prerequisites and requested inputs into a single paragraph.
- Follow-ups must ask only missing/invalid fields; never re-ask confirmed values.
- Determine credential path dynamically:
  - if Vault secret OCIDs are provided, do not ask for `db_username` or `db_password`
  - if direct DB credentials are used, do not ask for Vault secret OCIDs
  - if direct DB credentials are used and `db_password` is not supplied, allow the secure CLI prompt at runtime instead of re-asking later
- Run Stage 1 directly by default once required inputs are available.
- Only provide local-run command when user explicitly asks to run locally.
- Do not ask for `auto_approve` unless user explicitly wants to override defaults.


## Canonical Flow

1. Collect Stage 1 required fields and credential path.
2. If Vault secret OCIDs are used, ensure OCI CLI session is valid first.
3. Run Stage 1 immediately.
4. On Stage 1 success, print the required Stage 1 completion block exactly, then ask the Stage 2 decision in the same response.
5. Do not wait for the user to ask about Stage 2 after Stage 1 completes.
6. If Stage 2 yes, collect only required SQLPlus input (`db_service_name` or a full connect string) when needed.
7. Reuse the Stage 1 DB credentials for SQLPlus execution. Do not re-ask for DB credentials when Vault is used.
8. On Stage 2 success, print required Stage 2 completion block.

## Required Initial Stage-1 Intake Message

Use this structure for the first Stage 1 message when starting setup or when most Stage 1 fields are still missing:

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

Rules for this message:
- Keep each prerequisite on its own line.
- Keep each requested input on its own line.
- Use the `**Prerequisites:**` and `**Inputs:**` labels exactly.
- Keep the credential-path choices visually distinct so the user can tell they must choose one path.
- Do not merge the credential-path explanation into a paragraph.
- For follow-ups, keep the same line-by-line format but ask only for missing fields.

## Command Templates

Use these only when the user explicitly asks to run the setup locally.

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

--------------------------------------------------
**Stage 1 completed successfully.**

**Server created:** <server_config_name>
**Config updated:** <config_path>
**Backup created:** <backup_path>
**Token env var set:** <token_env_var> (<platform_persistence_note>)

--------------------------------------------------
**Do you want to run Stage 2 bootstrap of default DB tools (LIST_SCHEMAS, LIST_OBJECTS, GET_OBJECT_DETAILS, EXECUTE_SQL)?**
**Recommended:** Say **Yes** if this database has not been bootstrapped previously.

**If yes, choose one:**

1. Generate SQL only
2. Generate and execute via SQLPlus (not MCP server). I’ll need `db_service_name` or an optional full connect string
3. No (skip Stage 2 for now)

Platform persistence note values:
- macOS GUI app: `via launchctl`
- macOS/Linux terminal launch: `via shell startup file when available`
- Windows VS Code extension: `via setx for future VS Code processes`
- Unknown/manual environment: `set in the Codex process environment before launch`

## Required Post-Stage-2 Message

Use this exact structure:

--------------------------------------------------
**Stage 2 completed successfully.**

**Bootstrap mode:** <sql_only_or_sqlplus_executed>
**Bootstrap SQL path:** <bootstrap_sql_path>
**Default DB tools bootstrapped:** LIST_SCHEMAS, LIST_OBJECTS, GET_OBJECT_DETAILS, EXECUTE_SQL
**SUCCESS:** The default database MCP tools are now registered and ready to use.
You can run verification/tool calls after reloading Codex.


**Next step:** Restart Codex now so updated MCP config/token env are loaded before verification/tool calls. On Windows with the VS Code extension, restart VS Code.

## Runtime Notes

- ADB bearer tokens expire after about 1 hour. If verification later fails with `401 ADB-00015` or an invalid credential error after Stage 1 previously succeeded, re-run Stage 1 to refresh the token and then restart Codex or VS Code.
- The ADB MCP server may expose database tools with generated suffixes such as `LIST_OBJECTS_15`. Use the tool names discovered in the active MCP session instead of assuming the unsuffixed database tool name is callable directly.
- For first verification, prefer `LIST_OBJECTS` against a known schema over `LIST_SCHEMAS`; `LIST_SCHEMAS` can be less reliable when the client exposes suffixed tool names.
- `EXECUTE_SQL` must use the Oracle sample input name `query`, not `query_text`.

## Reference

- `references/oracle-adb-mcp.md`
