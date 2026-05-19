# Select AI - DBMS Scheduler Monitoring Agent

## Release Metadata

- Release Version: `1.0`
- Release Date: `19-May-2026`

## Overview

The **Scheduler Monitoring Agent** is a production-style Select AI agent for Oracle `DBMS_SCHEDULER` activity, job history, and CPU/load diagnostics.

It supports:

- Running/scheduled/completed/failed/disabled/broken job visibility
- Historical interval analysis (counts, success/failure, p95 elapsed/CPU)
- Per-job detail and metadata (program/schedule/class/arguments)
- Full local-schema job inventory listing
- CPU and load trend analysis
- Hotspot and recurring-failure detection
- Chart-ready and export-table payload generation
- Executive summary + diagnostics + recommendations format

---

## Repository Contents

```text
.
├── dbms_scheduler_jobs.sql                 (legacy draft script)
├── dbms_scheduler_monitor_tools.sql        (tools layer)
├── dbms_scheduler_monitor_agent.sql        (agent layer)
└── README.md
```

---

## Architecture Pattern

This implementation follows the same two-layer pattern as other agents:

1. **Tools layer** (`dbms_scheduler_monitor_tools.sql`)
- Installs `SCHEDULER_MONITORING` core package
- Installs `SELECT_AI_SCHEDULER_MONITOR` wrapper package
- Registers all Select AI tools

2. **Agent layer** (`dbms_scheduler_monitor_agent.sql`)
- Creates task (`SCHEDULER_MONITOR_TASKS`)
- Creates agent (`SCHEDULER_MONITOR_ADVISOR`)
- Creates team (`DBMS_SCHEDULER_MONITOR_TEAM`)

---

## Tools Implemented

- `GET_DATABASE_CURRENT_TIME_TOOL`
- `LIST_ALL_JOBS_TOOL`
- `LIST_RUNNING_JOBS_TOOL`
- `LIST_JOB_HISTORY_TOOL`
- `GET_JOB_DETAILS_TOOL`
- `ANALYZE_CPU_BY_JOB_TOOL`
- `ANALYZE_LOAD_BY_JOB_TOOL`
- `COMPARE_JOBS_TOOL`
- `IDENTIFY_HOTSPOTS_TOOL`
- `DETECT_FAILURES_TOOL`
- `SUMMARIZE_SCHEDULER_HEALTH_TOOL`
- `GENERATE_CHARTS_TOOL`
- `EXPORT_TABLES_TOOL`

---

## Primary Data Sources

The package is designed around local-schema scheduler views:

- `USER_SCHEDULER_JOBS`
- `USER_SCHEDULER_RUNNING_JOBS`
- `USER_SCHEDULER_JOB_RUN_DETAILS`
- `USER_SCHEDULER_JOB_ARGS`

It returns explicit error/proxy messaging when specific sources are unavailable.

Important scope note:

- This agent is intentionally **local-schema scoped** via `USER_SCHEDULER_*`.
- If a user mentions another schema name, the agent should clarify scope and continue with current schema data.

---

## Installation

Run as `ADMIN` (or equivalent privileged user):

```sql
sqlplus admin@<adb_connect_string> @dbms_scheduler_monitor_tools.sql
sqlplus admin@<adb_connect_string> @dbms_scheduler_monitor_agent.sql
```

Prompts:

- Tools script:
  - `SCHEMA_NAME`
- Agent script:
  - `SCHEMA_NAME`
  - `AI_PROFILE_NAME`
- `SCHED_TARGET_OWNER` (default owner label for responses; data remains local schema scope)

---

## Output Contract

Task instructions enforce output sections:

- Executive summary
- Detailed tables
- Chart section
- Diagnostics section
- Recommendations section

For correlations:

- label as `exact` or `inferred`
- include confidence
- avoid strong attribution when confidence is weak
- relative date requests (today/yesterday/previous day) must be resolved from database `SYSTIMESTAMP` via `GET_DATABASE_CURRENT_TIME_TOOL`

For full-list requests:

- Use `LIST_ALL_JOBS_TOOL` first.
- Do not infer total jobs from history/running jobs.
- Do not return sample-only output unless explicitly requested.
- Do not use ellipsis placeholders; if needed, paginate deterministically (`Page 1`, `Page 2`, ...).

---

## Sample Prompts

1. `Show currently running scheduler jobs with session id, elapsed time, and cpu used.`
1. `Give me full list of all scheduler jobs in table format.`
2. `Show scheduler run history for last 7 days with success/failure breakdown and p95 elapsed time.`
3. `Get detailed diagnostics for job <OWNER>.<JOB_NAME>.`
4. `Analyze top CPU-consuming jobs in last 3 days.`
5. `Identify scheduler hotspots with minimum elapsed 600 seconds and minimum cpu 120 seconds.`
6. `Detect recurring scheduler failures in last 14 days and show common error patterns.`
7. `Compare jobs JOB_A and JOB_B for last 30 days.`
8. `Generate chart datasets for scheduler health trends by hour for last 2 days.`
9. `Export tables for running jobs, history, cpu analysis, and failures for last 24 hours.`
10. `Give scheduler health overview for last 7 days with recommendations.`

---

## Notes

- Time filters accept timestamp text; if timezone is supplied it is preserved.
- Aggregations are bounded with `top_n` caps to avoid oversized payloads.
- Logging table `SCHED_MONITOR_LOG$` captures operation duration and failures.
- `list_all_jobs` returns:
  - `summary` (total/enabled/disabled/running/failed/broken)
  - `returned_rows`
  - `truncated` (`true`/`false`)
  - `rows` (detailed job list)
- Legacy draft script (`dbms_scheduler_jobs.sql`) is retained for reference.

---

## Troubleshooting

1. `ORA-20051: Task attributes are not in valid JSON format`
- Cause: unescaped double quotes inside task instruction text.
- Fix: avoid embedded `"` in free text within `attributes` JSON.

2. `ORA-40478` during large JSON payloads
- Cause: JSON result exceeds default `VARCHAR2` JSON return size.
- Fix: use `RETURNING CLOB` on outer JSON constructors (already applied).

3. Package compilation errors in `SCHEDULER_MONITORING`
- Re-run tools script after edits:
  - `@dbms_scheduler_monitor_tools.sql`
- Then recreate task/agent:
  - `@dbms_scheduler_monitor_agent.sql`
