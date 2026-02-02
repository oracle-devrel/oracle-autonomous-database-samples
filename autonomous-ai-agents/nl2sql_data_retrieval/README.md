# Select AI - NL2SQL Data Retrieval Agent for Oracle Autonomous AI Database

## How the NL2SQL agent improves upon Select AI NL2SQL

Oracle Select AI already provides Natural Language to SQL (NL2SQL), but **real-world data retrieval often fails** due to:

- Ambiguous column values  
- Unknown or incorrect value ranges (dates, numbers)  
- Invalid predicates leading to zero-row results  
- Missing external or contextual knowledge  
- Lack of visualization support  

This **NL2SQL Data Retrieval Agent** addresses these limitations by combining:

- Database introspection  
- Fail-safe retries  
- Distinct and range value discovery  
- Secure web intelligence  
- Chart and visualization generation  

into a **single autonomous agent workflow**.

###  Key Advantages Over Plain NL2SQL

| Capability | Plain Select AI NL2SQL | This Agent |
|----------|------------------------|------------|
| SQL generation | ✅ | ✅ |
| Automatic retry on failure | ❌ | ✅ |
| Distinct value discovery | ❌ | ✅ |
| Range discovery (DATE / NUMBER) | ❌ | ✅ |
| Predicate refinement | ❌ | ✅ |
| External web search | ❌ | ✅ |
| URL content validation | ❌ | ✅ |
| Chart generation | ❌ | ✅ |
| Config-driven and extensible | ❌ | ✅ |

> **Result:** Higher accuracy, fewer hallucinations, accurate SQL, and richer analytical answers.

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
   ├── WEBSEARCH
   ├── GET_URL_CONTENT
   └── GENERATE_CHART
   ↓
Final Verified Answer + Sources
```

The agent dynamically selects tools, retries intelligently, and produces **explainable outputs**.

---

##  Repository Contents

```text
.
├── nl2sql_data_retrieval_tools.sql
│   ├── PL/SQL utility functions
│   ├── OCI Vault integration for Websearch credentials
│   ├── Web search enablement
│   └── AI tool registration
│
├── nl2sql_data_retrieval_agent.sql
│   ├── Task definition
│   ├── Agent creation
│   ├── Team orchestration
│   └── AI profile binding
│
└── README.md
```

---

##  Prerequisites

- Oracle Autonomous AI Database
- Select AI enabled
- OCI Vault configured (Optional for websearch)
- Google Custom Search API enabled (Optional for websearch)
- Run as ADMIN 

---

##  Web Search Configuration (Google Custom Search)

The agent **never stores secrets in database tables**.  
All credentials are resolved **securely at runtime from OCI Vault**.

### Step 1: Create Google Cloud Project
- https://console.cloud.google.com

### Step 2: Enable Custom Search API
- APIs and Services → Library → **Custom Search API**

### Step 3: Create API Key
- APIs and Services → Credentials → **Create API Key**

### Step 4: Create Custom Search Engine (CX)
- https://programmablesearchengine.google.com  
- Enable **Search the entire web**  
- Capture the **Search Engine ID (CX)**

### Step 5: Store Secrets in OCI Vault
Create **two secrets**:
- Google API Key  
- Google CX ID  

Note the **Vault Secret OCIDs**.

---

##  Installation – Tools

Run as ADMIN (or privileged user):

```sql
sqlplus admin@db @nl2sql_data_retrieval_tools.sql
```
### Input Parameters required to run
- Target schema name (Schema where to the agent team needs to be installed)
- Cloud Config Parameters required for Websearch (This is mandatory to enable Websearch)
  - Google Search API Keys needs to be stored in OCI Vault
  - Vault Secret OCID's.
  - OCI Region name where Vault is created.

### Example Configuration JSON

```json
{
  "credential_name": "OCI_CRED",
  "vault_region": "eu-frankfurt-1",
  "api_key_vault_secret_ocid": "ocid1.vaultsecret.oc1..aaaa",
  "cxid_vault_secret_ocid": "ocid1.vaultsecret.oc1..bbbb"
}
```

### What This Script Does

- Grants required DBMS_CLOUD and Select AI privileges  
- Creates `SELECTAI_AGENT_CONFIG`  
- Installs `NL2SQL_DATA_RETRIEVAL_FUNCTIONS`  
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

### 4️⃣ WEBSEARCH
**Purpose:** Retrieve secure, real-world external information.

**Returns:** title, URL, snippet

---

### 5️⃣ GET_URL_CONTENT
**Purpose:** Fetch and validate full content from a URL.

**Used when:**
- Snippets are insufficient  
- Source verification is required  

---

### 6️⃣ GENERATE_CHART
**Purpose:** Generate **Chart.js-compatible JSON** for visualizations.

**Supported chart types:**
- bar, line, pie, doughnut  
- radar, scatter, bubble, polarArea  

---

##  Installation – Agent and Team

Run:

```sql
sqlplus admin@db @nl2sql_data_retrieval_agent.sql
```

### Input Parameters required to run.
- Target schema name (Schema where to the agent team needs to be installed)
- AI Profile name (Select AI Profile name that needs to be used with the Agent)


### Objects Created

| Object | Name |
|-------|------|
| Task  | NL2SQL_DATA_RETRIEVAL_TASK  |
| Agent | NL2SQL_DATA_RETRIEVAL_AGENT |
| Team  | NL2SQL_DATA_RETRIEVAL_TEAM  |

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
| Research Agent Team | WEBSEARCH | External intelligence |
| Visualization Team | SQL + CHART | Dashboards and insights |

### Why This Scales Well
- Tools are reusable  
- Tasks define behavior  
- Agents bind AI profiles  
- Teams orchestrate workflows  

### Example prompts
After creating the NL2SQL Data Retrieval Agent team, you can interact with it using prompts such as:

- “How can you help?”
- Ask questions related to the database tables associated with the selected profile.
- To generate visualizations, explicitly mention the chart type, for example:
  “Generate a bar chart for the result.” (any supported chart type can be used)
- To perform a web search, ask relevant questions after configuring the required credentials.

---

##  Best Practices

- Use `DISTINCT_VALUES_CHECK` before filtering text columns  
- Use `RANGE_VALUES_CHECK` for DATE and NUMBER columns    
- Maintain separate AI profiles per environment   

---

##  License

Universal Permissive License (UPL) 1.0  
https://oss.oracle.com/licenses/upl/

---

## ✨ Final Thoughts

This NL2SQL Data Retrieval Agent elevates Select AI from a **SQL generator** to a **true autonomous data analyst** — capable of reasoning, validating, retrying, enriching, and visualizing data with confidence.

Designed for:
- Domain-specific agents  
- Multi-team orchestration  
- UI / APEX integrations  
- Autonomous dashboards  
