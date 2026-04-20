# Oracle AI Database Agent

## Overview

The **Oracle AI Database Agent** enables natural-language data analysis workflows by combining NL2SQL generation, metadata inspection, query correction, and chart generation inside Oracle Autonomous AI Database.

For definitions of **Tool**, **Task**, **Agent**, and **Agent Team**, see the top-level guide: [README](../README.md#simple-agent-execution-flow).

## How the NL2SQL agent improves upon Select AI NL2SQL

Oracle Select AI already provides Natural Language to SQL (NL2SQL), but **real-world data retrieval often fails** due to:

- Ambiguous column values  
- Unknown or incorrect value ranges (dates, numbers)  
- Invalid predicates leading to zero-row results  
- Lack of visualization support  

This **Oracle AI Database Agent** addresses these limitations by combining:

- Database introspection  
- Fail-safe retries  
- Distinct and range value discovery  
- Chart and visualization generation  

into a **single autonomous agent workflow**.

---

##  Architecture Overview

```text
User Query
   ↓
NL2SQL Task
   ↓
Agent Reasoning
   ├── SQL_TOOL
   ├── DISTINCT_VALUES_CHECK
   ├── RANGE_VALUES_CHECK
   └── GENERATE_CHART
   ↓
Final Verified Answer + Sources
```

The agent dynamically selects tools, retries intelligently, and produces **explainable outputs**.

---

##  Repository Contents

```text
.
├── oracle_ai_database_agent_tool.sql
│   ├── PL/SQL utility functions
│   ├── Database-native analysis helpers
│   └── AI tool registration
│
├── oracle_ai_database_agent.sql
│   ├── Task definition
│   ├── Agent creation
│   ├── Team orchestration
│   └── AI profile binding
│
└── README.md
```

---

##  Prerequisites

- Oracle Autonomous AI Database (26ai recommended)
- Select AI enabled
- Run as ADMIN 

---

##  Installation – Tools

Before running installation commands:

1. Clone or download this repository.
2. Open a terminal and change directory to `google-gemini-marketplace-agents`.
3. Choose one execution mode:
   - SQL*Plus/SQLcl: run script files directly with `@script_name`.
   - SQL Worksheet (Database Actions or other SQL IDE): open the `.sql` file and run/paste its contents.
4. Uploading scripts to `DATA_PUMP_DIR` is not required for these methods.

Run as `ADMIN` (or another privileged user):

```sql
sqlplus admin@<adb_connect_string> @oracle_ai_database_agent_tool.sql
```
### Input Parameters required to run
- Target schema name (Schema where to the agent team needs to be installed)

### What This Script Does

- Grants required Select AI privileges  
- Creates `SELECTAI_AGENT_CONFIG`  
- Installs `ORACLE_AI_DATA_RETRIEVAL_FUNCTIONS`  
- Registers all AI agent tools.

---

##  Installed Tools Explained

### 1️⃣ SQL_TOOL
**Purpose:** Generate SQL from natural language and run it safely.

**Fail-safe behavior:**
- SQL generation failure → feedback returned to the LLM  
- Zero rows → agent retries using range or distinct tools  

---

### 2️⃣ DISTINCT_VALUES_CHECK
**Purpose:** Discover valid categorical values before filtering.

**Use cases:**
- Status columns  
- Country or region names  
- Product categories  

**Matching modes:** `fuzzy` (default), `exact`, `regex`

---

### 3️⃣ RANGE_VALUES_CHECK
**Purpose:** Determine minimum and maximum values for numeric, DATE, or TIMESTAMP columns.

**Use cases:**
- Time-series analysis  
- Salary or revenue ranges  
- Boundary detection  

---

### 4️⃣ GENERATE_CHART
**Purpose:** Generate **Chart.js-compatible JSON** for visualizations.

**Supported chart types:**
- bar, line, pie, doughnut  
- radar, scatter, bubble, polarArea  

---

##  Installation – Agent and Team

From `google-gemini-marketplace-agents`, run:

```sql
sqlplus admin@<adb_connect_string> @oracle_ai_database_agent.sql
```

You can also execute the contents of `oracle_ai_database_agent.sql` in SQL Worksheet.

### Input Parameters required to run.
- Target schema name (Schema where to the agent team needs to be installed)
- AI Profile name (Select AI Profile name that needs to be used with the Agent)


### Objects Created

| Object | Name |
|-------|------|
| Task  | ORACLE_AI_DATABASE_TASK  |
| Agent | ORACLE_AI_DATABASE_AGENT |
| Team  | ORACLE_AI_DATABASE_TEAM  |

---

##  Task Intelligence Highlights

The task definition enforces:
- Tool-based reasoning  
- Mandatory source attribution  
- Structured, readable responses  
- Explicit chart generation flow  
- Retry logic for SQL failures  
- Metadata-aware querying  

---

##  Generalizing Teams Using Tools

### Recommended Design Pattern
**Keep tools generic.  
Specialize agents using tasks.**

### Example Team Strategies

| Team | Tools Used | Purpose |
|----|-----------|--------|
| Data Retrieval Team | All tools | General analytics |
| Finance Analytics Team | SQL + RANGE | Financial reporting |
| Visualization Team | SQL + CHART | Dashboards and insights |

### Why This Scales Well
- Tools are reusable  
- Tasks define behavior  
- Agents bind AI profiles  
- Teams orchestrate workflows  

### Example prompts
After creating the Oracle AI Database Agent team, you can interact with it using prompts such as:

- “How can you help?”
- Ask questions related to the database tables associated with the selected profile.
- To generate visualizations, explicitly mention the chart type, for example:
  “Generate a bar chart for the result.” (any supported chart type can be used)

---

##  Best Practices

- Use `DISTINCT_VALUES_CHECK` before filtering text columns  
- Use `RANGE_VALUES_CHECK` for DATE and NUMBER columns    
- Maintain separate AI profiles per environment   

---

##  License

Universal Permissive License (UPL) 1.0  
https://oss.oracle.com/licenses/upl/
Copyright (c) 2026 Oracle and/or its affiliates.

---

## ✨ Final Thoughts

This Oracle AI Database Agent elevates Select AI from a **SQL generator** to a **true autonomous data analyst** — capable of reasoning, validating, retrying, and visualizing data with confidence.

Designed for:
- Domain-specific agents  
- Multi-team orchestration  
- UI / APEX integrations  
- Autonomous dashboards  
