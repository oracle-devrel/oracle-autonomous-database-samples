# Select AI - Data Quality Check Agent for Oracle Autonomous Database

## Release Metadata

- Release Version: `1.1`
- Release Date: `19-May-2026`

## Overview

The **Data Quality Check Agent** provides schema-aware data quality assessment for Oracle Autonomous Database tables using Select AI Agent tools.

It supports:

- Table profiling
- Null/duplicate/outlier detection
- Quality score computation with history tracking
- Drift detection based on recent vs baseline score windows
- Issue listing with severity and remediation guidance
- Safe remediation preview and controlled apply mode
- OML Services monitoring setup and run trigger hooks

For definitions of **Tool**, **Task**, **Agent**, and **Agent Team**, see the top-level guide: [README](../README.md#simple-agent-execution-flow).

---

## Repository Contents

```text
.
├── database_quality_check_tools.sql
│   ├── Installer bootstrap and grants
│   ├── DATABASE_QUALITY package (core DQ logic)
│   ├── SELECT_AI_DATA_QUALITY_AGENT package (tool wrappers)
│   └── Tool registration
│
├── database_quality_check_agent.sql
│   ├── Task definition (DATA_QUALITY_TASKS)
│   ├── Agent creation (DATA_QUALITY_ADVISOR)
│   ├── Team creation (DATA_QUALITY_TEAM)
│   └── Default target schema behavior (DQ_TARGET_SCHEMA)
│
└── README.md
```

---

## Architecture Overview

```text
User Request
   ↓
DATA_QUALITY_TASKS
   ↓
DATA_QUALITY_ADVISOR Reasoning
   ├── PROFILE_TABLE_TOOL
   ├── DETECT_NULLS_TOOL
   ├── DETECT_DUPLICATES_TOOL
   ├── DETECT_OUTLIERS_TOOL
   ├── DETECT_DRIFT_TOOL
   ├── GENERATE_QUALITY_RULES_TOOL
   ├── EVALUATE_QUALITY_SCORE_TOOL
   ├── LIST_QUALITY_ISSUES_TOOL
   ├── SUGGEST_REMEDIATION_TOOL
   ├── APPLY_REMEDIATION_TOOL
   ├── SETUP_OML_DATA_MONITORING_TOOL
   └── RUN_OML_DATA_MONITORING_TOOL
   ↓
Issue Summary + Severity + Quality Score + Next Action
```

---

## Prerequisites

- Oracle Autonomous AI Database (26ai recommended)
- Select AI and `DBMS_CLOUD_AI_AGENT` enabled
- `ADMIN` (or equivalent privileged user) for installation
- A valid AI profile (`DBMS_CLOUD_AI.CREATE_PROFILE`)
- Object privileges from install schema to target data schema tables (for cross-schema checks)

For OML monitoring tools:

- `SELECTAI_AGENT_CONFIG` entries for `AGENT='DATA_QUALITY'`:
  - `OML_MONITORING_ENDPOINT`
  - `OML_MONITORING_CREDENTIAL`

For controlled remediation apply:

- `SELECTAI_AGENT_CONFIG` entry for `AGENT='DATA_QUALITY'`:
  - `REMEDIATION_APPROVAL_CODE`

---

## Installation

Run as `ADMIN` (or privileged user) from this folder:

```sql
sqlplus admin@<adb_connect_string> @database_quality_check_tools.sql
sqlplus admin@<adb_connect_string> @database_quality_check_agent.sql
```

Prompts in tools script:

- `SCHEMA_NAME` (schema where package/tools are installed)

Prompts in agent script:

- `SCHEMA_NAME` (same install schema)
- `AI_PROFILE_NAME`
- `DQ_TARGET_SCHEMA` (default schema for DQ checks; if blank uses `SCHEMA_NAME`)

Important:

- Re-run `database_quality_check_agent.sql` whenever task instructions are changed.

---

## Internal Tables

Created in install schema (if missing):

- `DQ_RUN_HISTORY$`:
  - score history per table/run
  - stores score component metrics and worst severity
- `DQ_FINDINGS$`:
  - issue registry with severity, recommendation, and optional fix SQL
- `DQ_OML_MONITORS$`:
  - registered OML monitor metadata and last run response

---

## Tool-to-Function Mapping

| Tool | Function | Purpose |
|---|---|---|
| `PROFILE_TABLE_TOOL` | `select_ai_data_quality_agent.profile_table` | Baseline profile |
| `DETECT_NULLS_TOOL` | `select_ai_data_quality_agent.detect_nulls` | Null issue detection |
| `DETECT_DUPLICATES_TOOL` | `select_ai_data_quality_agent.detect_duplicates` | Duplicate detection |
| `DETECT_OUTLIERS_TOOL` | `select_ai_data_quality_agent.detect_outliers` | Outlier detection |
| `DETECT_DRIFT_TOOL` | `select_ai_data_quality_agent.detect_drift` | Drift analysis |
| `GENERATE_QUALITY_RULES_TOOL` | `select_ai_data_quality_agent.generate_quality_rules` | Rule suggestions |
| `EVALUATE_QUALITY_SCORE_TOOL` | `select_ai_data_quality_agent.evaluate_quality_score` | Score + persistence |
| `LIST_QUALITY_ISSUES_TOOL` | `select_ai_data_quality_agent.list_quality_issues` | Issue review |
| `SUGGEST_REMEDIATION_TOOL` | `select_ai_data_quality_agent.suggest_remediation` | SQL guidance |
| `APPLY_REMEDIATION_TOOL` | `select_ai_data_quality_agent.apply_remediation` | Preview/apply fix SQL |
| `SETUP_OML_DATA_MONITORING_TOOL` | `select_ai_data_quality_agent.setup_oml_data_monitoring` | Register OML monitor |
| `RUN_OML_DATA_MONITORING_TOOL` | `select_ai_data_quality_agent.run_oml_data_monitoring` | Trigger OML monitor run |

---

## Operational Behavior

- If `owner_name` is omitted, agent defaults to `DQ_TARGET_SCHEMA`.
- For schema-wide requests (for example, “all tables”), task instruction is configured to auto-discover tables and not ask user to list table names.
- `APPLY_REMEDIATION_TOOL`:
  - default mode is `PREVIEW`
  - `APPLY` requires matching `approval_code`
  - SQL safety checks block unsafe statements

---

## Example Prompts

- `Check null issues in SALES and show columns with null_count, null_rate_pct, and severity.`
- `Detect duplicates in SALES using all columns and show duplicate_row_count, duplicate_rate_pct, and severity.`
- `Find numeric outliers in SALES using z-score threshold 3 and rank by severity.`
- `Evaluate quality score for SALES and explain null, duplicate, outlier, and drift components.`
- `Evaluate quality score for every table in the default target schema and return table-wise summary.`
- `List open HIGH severity quality issues for SALES with recommendation and generated_fix_sql.`
- `Preview remediation for issue_id 1 on SALES.`
- `Apply remediation for issue_id 1 on SALES with execute_mode APPLY and approval_code <code>.`

OML examples:

- `Set up OML data monitoring for SH.SALES with monitor name SH_SALES_DQ_MON, baseline query "<baseline_sql>", and new-data query "<new_sql>".`
- `Run OML data monitoring for monitor SH_SALES_DQ_MON and return the job response.`

---

## Troubleshooting

- `ORA-00942` during package compilation:
  - Re-run `database_quality_check_tools.sql`; it pre-creates `DQ_*` tables.
- Agent asks for table list during “all tables” request:
  - Re-run `database_quality_check_agent.sql` to recreate task with latest instructions.
- OML monitoring tool errors with missing config:
  - Insert required keys in `SELECTAI_AGENT_CONFIG` for `AGENT='DATA_QUALITY'`.
- Apply remediation blocked:
  - Ensure `REMEDIATION_APPROVAL_CODE` is configured and supplied as `approval_code`.
