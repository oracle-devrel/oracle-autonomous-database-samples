# Select AI - AI Agent & Tools for JIRA

## Release Metadata

- Release Version: `1.1`
- Release Date: `14-May-2026`

## Overview

## Jira Integration

Jira integration in this project connects Oracle Autonomous AI Database to Atlassian Jira Cloud APIs through `DBMS_CLOUD`, then exposes those operations as Select AI tools via `DBMS_CLOUD_AI_AGENT`.

The **Select AI Insight agent for Jira** enables conversational Jira operations such as issue search, issue insight generation, assignee lookup, comments/changelog/worklog retrieval, project lookup, user lookup, and board discovery.

Runtime connection settings are stored in `SELECTAI_AGENT_CONFIG` under agent key `JIRA`, so credentials and Jira Cloud ID are centrally managed and not passed as user inputs on every tool call.

For definitions of **Tool**, **Task**, **Agent**, and **Agent Team**, see the top-level guide: [README](../README.md#simple-agent-execution-flow).

---

## Why a Select AI Jira Agent?

Jira API usage usually requires:
- API endpoint familiarity
- Correct query/JQL construction
- Repeated handling of auth and cloud identifiers
- Multi-step workflows for assignee and issue analysis

This agent streamlines those steps into guided conversational workflows while preserving clear tool boundaries and auditable behavior.

---

## Architecture Overview

```text
User Request
   ↓
JIRA_TASKS
   ↓
JIRA_ADVISOR Reasoning & Validation
   ├── SEARCH_JIRA_TOOL
   ├── GET_JIRA_TOOL
   ├── LIST_JIRA_PROJECTS_TOOL
   ├── GET_ASSIGNEE_ACCOUNT_ID_TOOL
   ├── GET_CURRENT_ATLASSIAN_USER_TOOL
   ├── GET_JIRA_ASSIGNED_ISSUES_TOOL
   ├── GET_JIRA_PROJECT_ISSUES_TOOL
   ├── GET_JIRA_COMMENTS_TOOL
   ├── GET_JIRA_CHANGELOG_TOOL
   ├── GET_JIRA_WORKLOG_TOOL
   ├── GET_JIRA_PROJECT_TOOL
   ├── GET_ATLASSIAN_USER_TOOL
   ├── GET_JIRA_BOARDS_TOOL
   └── UPDATE_JIRA_COMMENT_TOOL
   ↓
Formatted Jira/Atlassian Response
```

---

## Repository Contents

```text
.
├── insight_jira_tools.sql
│   ├── Configuration bootstrap (SELECTAI_AGENT_CONFIG)
│   ├── Jira API wrapper package (jira_selectai)
│   ├── Agent package (select_ai_jira_agent)
│   └── Jira AI tool registrations
│
├── insight_jira_agent.sql
│   ├── Task definition (JIRA_TASKS)
│   ├── Agent creation (JIRA_ADVISOR)
│   ├── Team creation (JIRA_INSIGHT_TEAM)
│   └── AI profile binding
│
└── README.md
```

---

## Prerequisites

- Oracle Autonomous AI Database (26ai recommended)
- Select AI / `DBMS_CLOUD_AI_AGENT` enabled
- Jira Cloud access
- Atlassian credential created in database (`DBMS_CLOUD` credential)
- Jira Cloud ID
- ADMIN (or equivalent privileged user) for installation

---

## Atlassian Jira Credential Setup

Use these steps to create OAuth client credentials for Jira Cloud and obtain the Jira Cloud ID required by this project.

### 1. Open Atlassian Admin

1. Sign in to Atlassian Admin:
   - `https://admin.atlassian.com`
2. Select the organization and Jira site you want this integration to access.

### 2. Create a Service Account

1. In Atlassian Admin, open **Directory** from the left navigation.
2. Create a dedicated service account for this integration.
3. Assign appropriate product access to Jira for that service account.

### 3. Create OAuth 2.0 Client Credentials

1. In Atlassian developer/admin app settings, create a new **OAuth 2.0 (Client Credentials)** app.
2. Select product as **Jira**.
3. Configure scopes.

### 4. Configure Jira Scopes

1. Use **Classic scopes**.
2. Select Jira actions your agent needs (for example: read, write, create, delete as required by your use case).
3. If prompted for roles/permissions, select the required classic roles according to least-privilege policy.

### 5. Capture Client Credentials

Copy and save:
- `client_id`
- `client_secret`

You will use these values to generate a bearer token.

### 6. Generate an Access Token

Run:

```bash
curl --request POST \
  --url https://auth.atlassian.com/oauth/token \
  --header 'Content-Type: application/json' \
  --data '{
    "grant_type": "client_credentials",
    "client_id": "<client_id>",
    "client_secret": "<client_secret>",
    "audience": "api.atlassian.com"
  }'
```

Copy the `access_token` from the response.

### 7. Fetch Accessible Jira Resources (Cloud ID)

Run:

```bash
curl --request GET \
  --url https://api.atlassian.com/oauth/token/accessible-resources \
  --header "Authorization: Bearer <access_token>"
```

From the response:
- Use the Jira resource `id` as your Jira **id** value.
- Keep the associated resource URL/name for validation.

### 8. Create DBMS_CLOUD Credential in Oracle Database

Run as `ADMIN` (or privileged user), replacing placeholders:

```sql
BEGIN
  DBMS_CLOUD.CREATE_CREDENTIAL(
    credential_name => 'ATLASSIAN_CRED',
    username        => '<client_id>',
    password        => '<client_secret>'
  );
END;
/
```

### 9. Provide Config During Tool Installation

When `insight_jira_tools.sql` prompts for `CONFIG_JSON`, provide:

```json
{
  "credential_name": "ATLASSIAN_CRED",
  "cloud_id": "<id>"
}
```

### 10. Validate Before Running the Agent

Confirm:
- Credential exists in DB.
- `SELECTAI_AGENT_CONFIG` contains:
  - `CREDENTIAL_NAME` for `AGENT='JIRA'`
  - `CLOUD_ID` for `AGENT='JIRA'`
- Network ACL allows outbound HTTPS to:
  - `auth.atlassian.com`
  - `api.atlassian.com`
  - `atlassian.com`

---

## Installation – Tools

Before running installation commands:

1. Clone or download this repository.
2. Open a terminal and change directory to `autonomous-ai-agents/jira_insight`.
3. Choose one execution mode:
   - SQL*Plus/SQLcl: run script files directly with `@script_name`.
   - SQL Worksheet (Database Actions or other SQL IDE): open the `.sql` file and run/paste its contents.
4. Uploading scripts to `DATA_PUMP_DIR` is not required for these methods.

Run as `ADMIN` (or another privileged user):

```sql
sqlplus admin@<adb_connect_string> @insight_jira_tools.sql
```

### Optional Configuration JSON

```json
{
  "credential_name": "ATLASSIAN_CRED",
  "id": "your-jira-id"
}
```

> Configuration is stored in `SELECTAI_AGENT_CONFIG` for `AGENT='JIRA'`.

### What This Script Does

- Grants required package privileges
- Creates/updates `SELECTAI_AGENT_CONFIG`
- Persists `CREDENTIAL_NAME` and `CLOUD_ID` for `JIRA`
- Creates package `jira_selectai`
- Creates package `select_ai_jira_agent`
- Registers all Jira AI tools

---

## Available AI Tools (Complete)

### Issue Search & Retrieval
- `SEARCH_JIRA_TOOL`
- `GET_JIRA_TOOL`

### Assignee Workflows
- `GET_ASSIGNEE_ACCOUNT_ID_TOOL`
- `GET_CURRENT_ATLASSIAN_USER_TOOL`
- `GET_JIRA_ASSIGNED_ISSUES_TOOL`

### Issue Activity
- `GET_JIRA_COMMENTS_TOOL`
- `GET_JIRA_CHANGELOG_TOOL`
- `GET_JIRA_WORKLOG_TOOL`

### Project, User, and Boards
- `LIST_JIRA_PROJECTS_TOOL`
- `GET_JIRA_PROJECT_TOOL`
- `GET_JIRA_PROJECT_ISSUES_TOOL`
- `GET_ATLASSIAN_USER_TOOL`
- `GET_JIRA_BOARDS_TOOL`

### Comment Updates
- `UPDATE_JIRA_COMMENT_TOOL`

### Tool-to-Function Mapping (from `insight_jira_tools.sql`)

| Tool | Function | Purpose |
|------|----------|---------|
| `SEARCH_JIRA_TOOL` | `select_ai_jira_agent.search_jira` | Search Jira issues by keyword |
| `GET_JIRA_TOOL` | `select_ai_jira_agent.get_jira` | Get Jira issue details by key |
| `GET_ASSIGNEE_ACCOUNT_ID_TOOL` | `select_ai_jira_agent.get_assignee_account_id` | Resolve assignee account ID |
| `GET_JIRA_ASSIGNED_ISSUES_TOOL` | `select_ai_jira_agent.get_jira_assigned_issues` | List issues assigned to an account |
| `GET_JIRA_PROJECT_ISSUES_TOOL` | `select_ai_jira_agent.get_jira_project_issues` | List issues for a specific project key |
| `GET_JIRA_COMMENTS_TOOL` | `select_ai_jira_agent.get_jira_comments` | Get issue comments |
| `GET_JIRA_CHANGELOG_TOOL` | `select_ai_jira_agent.get_jira_changelog` | Get issue changelog/history |
| `GET_JIRA_WORKLOG_TOOL` | `select_ai_jira_agent.get_jira_worklog` | Get issue worklogs |
| `GET_JIRA_PROJECT_TOOL` | `select_ai_jira_agent.get_jira_project` | Get project metadata |
| `LIST_JIRA_PROJECTS_TOOL` | `select_ai_jira_agent.list_jira_projects` | List projects and resolve project names to keys |
| `GET_ATLASSIAN_USER_TOOL` | `select_ai_jira_agent.get_atlassian_user` | Get Atlassian user profile |
| `GET_CURRENT_ATLASSIAN_USER_TOOL` | `select_ai_jira_agent.get_current_atlassian_user` | Get current Jira user profile |
| `GET_JIRA_BOARDS_TOOL` | `select_ai_jira_agent.get_jira_boards` | List Jira boards (optional project filter) |
| `UPDATE_JIRA_COMMENT_TOOL` | `select_ai_jira_agent.update_jira_comment` | Update Jira comment text |

---

## Installation – Agent & Team

From `autonomous-ai-agents/jira_insight`, run after tools installation:

```sql
sqlplus admin@<adb_connect_string> @insight_jira_agent.sql
```

You can also execute the contents of `insight_jira_agent.sql` in SQL Worksheet.

### Prompts

- Target schema name
- AI profile name

### Objects Created

| Object | Name |
|--------|------|
| Task   | `JIRA_TASKS` |
| Agent  | `JIRA_ADVISOR` |
| Team   | `JIRA_INSIGHT_TEAM` |

---

## Task Intelligence Highlights

The Jira task is configured to:
- Interpret intent and pick the right Jira tool
- Ask for only missing business inputs
- Use human tool escalation when required
- Return human-readable output summaries

---

## Example Prompts

### Issue Search & Details
- "Search Jira issues for `payment timeout`."
- "Get details for issue `FIN-123`."

### Assignee Analysis
- "Find Jira account ID for assignee `john.doe@company.com`."
- "List issues assigned to account ID `<account_id>`."

### Activity History
- "Get comments for `FIN-123`."
- "Get changelog for `FIN-123`."
- "Get worklog for `FIN-123`."

### Project/User/Boards
- "Get project details for `FIN`."
- "Get Atlassian user details for `<account_id>`."
- "List Jira boards for project `FIN`."

### Comment Update
- "Update Jira comment `<comment_id>` in project `FIN` with: `Please prioritize this issue for release.`"

---

## Best Practices

- Keep Jira credentials scoped with least privilege
- Store only required runtime values in `SELECTAI_AGENT_CONFIG`
- Separate read-only and operational agents when needed
- Validate assignee identity before assignment-based reporting

---

## Troubleshooting

- If tools return config errors, verify `SELECTAI_AGENT_CONFIG` contains:
  - `CREDENTIAL_NAME` for `AGENT='JIRA'`
  - `CLOUD_ID` for `AGENT='JIRA'`
- If API calls fail, verify:
  - Credential validity/token freshness
  - Jira Cloud ID correctness
  - Jira permission scope for the calling identity

---

## License

Universal Permissive License (UPL) 1.0  
https://oss.oracle.com/licenses/upl/
Copyright (c) 2026 Oracle and/or its affiliates.

---

## Final Thoughts

The Jira AI Agent provides a clean operational bridge between Select AI and Jira APIs, making issue intelligence workflows faster and easier to standardize across teams.

---

## Jira Credential & ACL Setup (ADMIN)

Run the following as `ADMIN` before using Jira tools.

### 1. Create Jira Credential

```sql
BEGIN
  DBMS_CLOUD.CREATE_CREDENTIAL (
    credential_name => '<JIRA_OAUTH2_CRED_NAME>',
    params          => JSON_OBJECT(
                         'oauth2' VALUE JSON_OBJECT(
                           'client_id'     VALUE '<client_id>',
                           'client_secret' VALUE ',client_secret>',
                           'endpoint' VALUE 'https://auth.atlassian.com/oauth/token',
                           'grant_type' VALUE 'client_credentials'
                         )
                       )
  );
END;
/
```

### 2. Grant Network ACL for Jira Hosts

Grant HTTP access to the target install schema (the schema where the Jira agent is installed) for each host below:
- `atlassian.com`
- `api.atlassian.com`

Replace the <SCHEMA_NAME> in below code and run as admin.

```sql
begin
dbms_network_acl_admin.append_host_ace(
  host =>'atlassian.com',
  lower_port => 443,
  upper_port => 443,
  ace => xs$ace_type(
    privilege_list => xs$name_list('http'),
    principal_name => '<SCHEMA_NAME>',
    principal_type => xs_acl.ptype_db));
end;
/

begin
dbms_network_acl_admin.append_host_ace(
  host =>'api.atlassian.com',
  lower_port => 443,
  upper_port => 443,
  ace => xs$ace_type(
    privilege_list => xs$name_list('http'),
    principal_name => '<SCHEMA_NAME>',
    principal_type => xs_acl.ptype_db));
end;
/
```
