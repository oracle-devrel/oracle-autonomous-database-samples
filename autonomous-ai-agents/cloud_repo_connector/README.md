# Select AI - Cloud Repo Connector Agent (DBMS_CLOUD_REPO)

## Overview

Cloud Repo Connector turns `DBMS_CLOUD_REPO` capabilities into Select AI tools so users can run repository operations conversationally from Oracle Autonomous AI Database.

It supports GitHub, AWS CodeCommit, and Azure Repos through one common toolset and one runtime configuration model.

Core runtime objects:
- Task: `CLOUD_REPO_TASKS`
- Agent: `CLOUD_REPO_CONNECTOR`
- Team: `CLOUD_REPO_CONNECTOR_TEAM`

How this works:
- `cloud_repo_connector_tools.sql` installs packages and registers all AI tools.
- `cloud_repo_connector_agent.sql` creates task/agent/team and binds the AI profile.
- Tools resolve provider/repo context from `SELECTAI_AGENT_CONFIG` first, so repeated prompts for owner/repo/credential/branch are avoided.
- Users can still override repo context in prompts when needed.

For definitions of **Tool**, **Task**, **Agent**, and **Agent Team**, see the top-level guide: [README](../README.md#simple-agent-execution-flow).

---

## Architecture Overview

```text
User Request
   ↓
CLOUD_REPO_TASKS
   ↓
CLOUD_REPO_CONNECTOR Reasoning & Tool Selection
   ├── Initialization tools (INIT_*_REPO_TOOL)
   ├── Repository lifecycle tools
   ├── Branch tools
   ├── File tools
   ├── Metadata export tools
   └── SQL install tools
   ↓
Formatted Repository/SQL Operation Response
```

---

## Feature Areas

The implementation maps directly to `DBMS_CLOUD_REPO` feature areas:

1. Repository initialization
- Generic repository handle: `INIT_REPO`
- GitHub handle: `INIT_GITHUB_REPO`
- AWS CodeCommit handle: `INIT_AWS_REPO`
- Azure Repos handle: `INIT_AZURE_REPO`

2. Repository management
- Create repository
- Update repository
- List repositories
- Delete repository

3. Repository file management
- Upload file from Oracle Database
- Download file to Oracle Database
- Delete file
- List files

4. Database object export
- Export object metadata/DDL to repository files (`EXPORT_OBJECT`)

---

## Repository Contents

```text
.
├── cloud_repo_connector_tools.sql
│   ├── Configuration bootstrap (SELECTAI_AGENT_CONFIG)
│   ├── DBMS_CLOUD_REPO wrapper package (github_repo_selectai)
│   ├── Agent package (select_ai_github_connector)
│   └── Tool registrations
│
├── cloud_repo_connector_agent.sql
│   ├── Task definition (CLOUD_REPO_TASKS)
│   ├── Agent creation (CLOUD_REPO_CONNECTOR)
│   ├── Team creation (CLOUD_REPO_CONNECTOR_TEAM)
│   └── AI profile binding
│
└── README.md
```

---

## Prerequisites

- Oracle Autonomous AI Database (26ai recommended)
- Select AI / `DBMS_CLOUD_AI_AGENT` enabled
- `DBMS_CLOUD_REPO` available in your database version
- `ADMIN` (or equivalent privileged user) for installation
- Required credentials for GitHub/AWS/Azure repo access

---

## Installation - Tools

From `autonomous-ai-agents/cloud_repo_connector`:

```sql
sqlplus admin@<adb_connect_string> @cloud_repo_connector_tools.sql
```

### Optional Configuration JSON

```json
{
  "credential_name": "GITHUB_CRED",
  "provider": "GITHUB",
  "default_owner": "your-org",
  "default_repo": "your-repo",
  "default_branch": "main",
  "aws_region": "us-east-1",
  "azure_organization": "your-org",
  "azure_project": "your-project"
}
```

Supported config keys in `SELECTAI_AGENT_CONFIG` for `AGENT='CLOUD_REPO_CONNECTOR'`:
- `CREDENTIAL_NAME`
- `PROVIDER`
- `DEFAULT_REPO`
- `DEFAULT_OWNER`
- `DEFAULT_BRANCH`
- `AWS_REGION`
- `AZURE_ORGANIZATION`
- `AZURE_PROJECT`

Backward compatibility:
- Legacy config rows for `AGENT='GITHUB_CONNECTOR'` and `AGENT='GITHUB'` are still read as fallback.

---

## Installation - Agent & Team

```sql
sqlplus admin@<adb_connect_string> @cloud_repo_connector_agent.sql
```

Objects created:
- Task: `CLOUD_REPO_TASKS`
- Agent: `CLOUD_REPO_CONNECTOR`
- Team: `CLOUD_REPO_CONNECTOR_TEAM`

---

## Available AI Tools (Complete)

Registered by `initialize_cloud_repo_tools` in `cloud_repo_connector_tools.sql`: **22 tools**.

Initialization:
- `INIT_GENERIC_REPO_TOOL`
- `INIT_GITHUB_REPO_TOOL`
- `INIT_AWS_REPO_TOOL`
- `INIT_AZURE_REPO_TOOL`

Repository management:
- `CREATE_REPOSITORY_TOOL`
- `UPDATE_REPOSITORY_TOOL`
- `LIST_REPOSITORIES_TOOL`
- `GET_REPOSITORY_TOOL`
- `DELETE_REPOSITORY_TOOL`

Branch management:
- `CREATE_BRANCH_TOOL`
- `DELETE_BRANCH_TOOL`
- `LIST_BRANCHES_TOOL`
- `LIST_COMMITS_TOOL`
- `MERGE_BRANCH_TOOL`

File management:
- `PUT_REPO_FILE_TOOL`
- `GET_REPO_FILE_TOOL`
- `LIST_REPO_FILES_TOOL`
- `DELETE_REPO_FILE_TOOL`

Export:
- `EXPORT_DB_OBJECT_REPO_TOOL`
- `EXPORT_SCHEMA_REPO_TOOL`

SQL install operations:
- `INSTALL_REPO_FILE_TOOL`
- `INSTALL_SQL_BUFFER_TOOL`

### Tool-to-Function Mapping (from `cloud_repo_connector_tools.sql`)

| Tool | Function | Purpose |
|------|----------|---------|
| `INIT_GENERIC_REPO_TOOL` | `select_ai_github_connector.init_repo` | Initialize generic repository handle |
| `INIT_GITHUB_REPO_TOOL` | `select_ai_github_connector.init_github_repo` | Initialize GitHub repository handle |
| `INIT_AWS_REPO_TOOL` | `select_ai_github_connector.init_aws_repo` | Initialize AWS CodeCommit repository handle |
| `INIT_AZURE_REPO_TOOL` | `select_ai_github_connector.init_azure_repo` | Initialize Azure Repos repository handle |
| `CREATE_REPOSITORY_TOOL` | `select_ai_github_connector.create_repository` | Create repository |
| `UPDATE_REPOSITORY_TOOL` | `select_ai_github_connector.update_repository` | Update repository |
| `LIST_REPOSITORIES_TOOL` | `select_ai_github_connector.list_repositories` | List repositories |
| `GET_REPOSITORY_TOOL` | `select_ai_github_connector.get_repository` | Get repository metadata |
| `DELETE_REPOSITORY_TOOL` | `select_ai_github_connector.delete_repository` | Delete repository |
| `CREATE_BRANCH_TOOL` | `select_ai_github_connector.create_branch` | Create repository branch |
| `DELETE_BRANCH_TOOL` | `select_ai_github_connector.delete_branch` | Delete repository branch |
| `LIST_BRANCHES_TOOL` | `select_ai_github_connector.list_branches` | List repository branches |
| `LIST_COMMITS_TOOL` | `select_ai_github_connector.list_commits` | List repository commits |
| `MERGE_BRANCH_TOOL` | `select_ai_github_connector.merge_branch` | Merge repository branches |
| `PUT_REPO_FILE_TOOL` | `select_ai_github_connector.put_file` | Upload repository file |
| `GET_REPO_FILE_TOOL` | `select_ai_github_connector.get_file` | Download repository file |
| `LIST_REPO_FILES_TOOL` | `select_ai_github_connector.list_files` | List repository files |
| `DELETE_REPO_FILE_TOOL` | `select_ai_github_connector.delete_file` | Delete repository file |
| `EXPORT_DB_OBJECT_REPO_TOOL` | `select_ai_github_connector.export_object` | Export DB object metadata to repository |
| `EXPORT_SCHEMA_REPO_TOOL` | `select_ai_github_connector.export_schema` | Export schema metadata to repository |
| `INSTALL_REPO_FILE_TOOL` | `select_ai_github_connector.install_file` | Install SQL from repository file |
| `INSTALL_SQL_BUFFER_TOOL` | `select_ai_github_connector.install_sql` | Install SQL from buffer |

---

## Example Prompts

Initialization:
- "Initialize GitHub repo handle for repo `my-repo` owner `my-org`."
- "Initialize AWS CodeCommit repo handle for `app-repo` in `us-east-1`."

Repository management:
- "Create repository using defaults with description `Demo repo`."
- "List repositories."
- "Delete repository `old-repo`."

Branch management:
- "Create branch `feature/checkout-v2` from `main`."
- "List branches for the configured repository."
- "List commits for branch `feature/checkout-v2`."
- "Merge `feature/checkout-v2` into `main`."
- "Delete branch `feature/checkout-v2`."

File management:
- "Upload `docs/readme.md` with this content and commit message `add docs`."
- "List files under `src/` on branch `main`."
- "Get file `src/app.sql` from branch `main`."
- "Delete file `tmp/test.sql` with commit message `cleanup`."

Export metadata:
- "Export package `HR.EMP_PKG` to `ddl/hr/emp_pkg.sql`."
- "Export table `SALES.ORDERS` to `ddl/sales/orders.sql` on branch `main`."

SQL install operations:
- "Export schema `HR` metadata to `ddl/hr/schema.sql`."
- "Install SQL from repository file `install/release_2026_02.sql` on branch `main`."
- "Install this SQL buffer: `CREATE TABLE demo_t(id NUMBER); /`"

---

## Notes

- `LIST_REPOSITORIES` still needs a repository handle context; set `DEFAULT_REPO` for no-arg usage.
- For GitHub provider, `owner` is required (directly or via `DEFAULT_OWNER`).
- For AWS provider, `region` is required.
- For Azure provider, `organization` and `project` are required.

---

## License

Universal Permissive License (UPL) 1.0
https://oss.oracle.com/licenses/upl/
