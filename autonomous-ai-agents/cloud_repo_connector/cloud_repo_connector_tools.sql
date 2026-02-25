rem ============================================================================
rem LICENSE
rem   Copyright (c) 2026 Oracle and/or its affiliates.
rem   Licensed under the Universal Permissive License (UPL), Version 1.0
rem   https://oss.oracle.com/licenses/upl/
rem
rem NAME
rem   cloud_repo_connector_tools.sql
rem
rem DESCRIPTION
rem   Installer script for Cloud Repo Connector Select AI tools
rem   implemented with DBMS_CLOUD_REPO.
rem
rem   This script installs PL/SQL packages and registers
rem   AI Agent tools for:
rem     - Repository initialization
rem     - Repository management
rem     - Repository file management
rem     - SQL export/install operations
rem
rem RELEASE VERSION
rem   1.1
rem
rem RELEASE DATE
rem   24-Feb-2026
rem
rem ============================================================================

SET SERVEROUTPUT ON
SET VERIFY OFF

VAR v_schema VARCHAR2(128)
EXEC :v_schema := '&SCHEMA_NAME';

PROMPT
PROMPT Enter Cloud Repo connector configuration values in JSON format.
PROMPT Optional keys:
PROMPT   credential_name, provider, default_repo, default_owner, default_branch,
PROMPT   aws_region, azure_organization, azure_project
PROMPT
PROMPT Backward-compatible key accepted: repository_name (mapped to default_repo)
PROMPT
PROMPT Example:
PROMPT {"credential_name":"GITHUB_CRED","provider":"GITHUB","default_owner":"my-org","default_repo":"my-repo","default_branch":"main"}
PROMPT
PROMPT Press ENTER to skip this step.
PROMPT

VAR v_config VARCHAR2(4000)
EXEC :v_config := '&CONFIG_JSON';

CREATE OR REPLACE PROCEDURE initialize_cloud_repo_agent(
  p_install_schema_name IN VARCHAR2,
  p_config_json         IN CLOB
)
IS
  l_schema_name        VARCHAR2(128);
  l_credential_name    VARCHAR2(4000);
  l_provider           VARCHAR2(4000);
  l_default_repo       VARCHAR2(4000);
  l_default_owner      VARCHAR2(4000);
  l_default_branch     VARCHAR2(4000);
  l_aws_region         VARCHAR2(4000);
  l_azure_organization VARCHAR2(4000);
  l_azure_project      VARCHAR2(4000);

  c_cloud_repo_agent CONSTANT VARCHAR2(64) := 'CLOUD_REPO_CONNECTOR';

  TYPE priv_list_t IS VARRAY(20) OF VARCHAR2(4000);
  l_priv_list CONSTANT priv_list_t := priv_list_t(
    'DBMS_CLOUD',
    'DBMS_CLOUD_AI',
    'DBMS_CLOUD_AI_AGENT',
    'DBMS_CLOUD_TYPES',
    'DBMS_CLOUD_REPO'
  );

  PROCEDURE execute_grants(p_schema IN VARCHAR2, p_objects IN priv_list_t) IS
  BEGIN
    FOR i IN 1 .. p_objects.COUNT LOOP
      BEGIN
        EXECUTE IMMEDIATE 'GRANT EXECUTE ON ' || p_objects(i) || ' TO ' || p_schema;
      EXCEPTION
        WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('Warning: failed to grant ' || p_objects(i) ||
                               ' to ' || p_schema || ' - ' || SQLERRM);
      END;
    END LOOP;
  END execute_grants;

  PROCEDURE get_config(
    p_json               IN  CLOB,
    o_credential_name    OUT VARCHAR2,
    o_provider           OUT VARCHAR2,
    o_default_repo       OUT VARCHAR2,
    o_default_owner      OUT VARCHAR2,
    o_default_branch     OUT VARCHAR2,
    o_aws_region         OUT VARCHAR2,
    o_azure_organization OUT VARCHAR2,
    o_azure_project      OUT VARCHAR2
  ) IS
    l_cfg JSON_OBJECT_T := NULL;
  BEGIN
    o_credential_name := NULL;
    o_provider := NULL;
    o_default_repo := NULL;
    o_default_owner := NULL;
    o_default_branch := NULL;
    o_aws_region := NULL;
    o_azure_organization := NULL;
    o_azure_project := NULL;

    IF p_json IS NOT NULL AND TRIM(p_json) IS NOT NULL THEN
      BEGIN
        l_cfg := JSON_OBJECT_T.parse(p_json);

        IF l_cfg.has('credential_name') THEN
          o_credential_name := l_cfg.get_string('credential_name');
        END IF;

        IF l_cfg.has('provider') THEN
          o_provider := UPPER(l_cfg.get_string('provider'));
        END IF;

        IF l_cfg.has('default_repo') THEN
          o_default_repo := l_cfg.get_string('default_repo');
        ELSIF l_cfg.has('repository_name') THEN
          o_default_repo := l_cfg.get_string('repository_name');
        END IF;

        IF l_cfg.has('default_owner') THEN
          o_default_owner := l_cfg.get_string('default_owner');
        END IF;

        IF l_cfg.has('default_branch') THEN
          o_default_branch := l_cfg.get_string('default_branch');
        END IF;

        IF l_cfg.has('aws_region') THEN
          o_aws_region := l_cfg.get_string('aws_region');
        END IF;

        IF l_cfg.has('azure_organization') THEN
          o_azure_organization := l_cfg.get_string('azure_organization');
        END IF;

        IF l_cfg.has('azure_project') THEN
          o_azure_project := l_cfg.get_string('azure_project');
        END IF;
      EXCEPTION
        WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('Config JSON parse failed: ' || SQLERRM);
      END;
    ELSE
      DBMS_OUTPUT.PUT_LINE('No config JSON provided, using existing table values.');
    END IF;
  END get_config;

  PROCEDURE merge_config_key(
    p_schema IN VARCHAR2,
    p_key    IN VARCHAR2,
    p_val    IN CLOB,
    p_agent  IN VARCHAR2
  ) IS
    l_sql CLOB;
  BEGIN
    l_sql :=
      'MERGE INTO ' || p_schema || '.SELECTAI_AGENT_CONFIG c
         USING (SELECT :k AS "KEY", :v AS "VALUE", :a AS "AGENT" FROM DUAL) src
           ON (c."KEY" = src."KEY" AND c."AGENT" = src."AGENT")
       WHEN MATCHED THEN
         UPDATE SET c."VALUE" = src."VALUE"
       WHEN NOT MATCHED THEN
         INSERT ("KEY", "VALUE", "AGENT") VALUES (src."KEY", src."VALUE", src."AGENT")';

    EXECUTE IMMEDIATE l_sql USING p_key, p_val, p_agent;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Warning: failed to persist ' || p_key || ' config: ' || SQLERRM);
  END merge_config_key;
BEGIN
  l_schema_name := DBMS_ASSERT.SIMPLE_SQL_NAME(p_install_schema_name);

  execute_grants(l_schema_name, l_priv_list);

  get_config(
    p_json               => p_config_json,
    o_credential_name    => l_credential_name,
    o_provider           => l_provider,
    o_default_repo       => l_default_repo,
    o_default_owner      => l_default_owner,
    o_default_branch     => l_default_branch,
    o_aws_region         => l_aws_region,
    o_azure_organization => l_azure_organization,
    o_azure_project      => l_azure_project
  );

  BEGIN
    EXECUTE IMMEDIATE
      'CREATE TABLE ' || l_schema_name || '.SELECTAI_AGENT_CONFIG (
         "ID"     NUMBER GENERATED BY DEFAULT AS IDENTITY,
         "KEY"    VARCHAR2(200) NOT NULL,
         "VALUE"  CLOB,
         "AGENT"  VARCHAR2(128) NOT NULL,
         CONSTRAINT SELECTAI_AGENT_CONFIG_PK PRIMARY KEY ("ID"),
         CONSTRAINT SELECTAI_AGENT_CONFIG_UK UNIQUE ("KEY","AGENT")
       )';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -955 THEN
        NULL;
      ELSE
        RAISE;
      END IF;
  END;

  IF l_credential_name IS NOT NULL THEN
    merge_config_key(l_schema_name, 'CREDENTIAL_NAME', l_credential_name, c_cloud_repo_agent);
  END IF;

  IF l_provider IS NOT NULL THEN
    merge_config_key(l_schema_name, 'PROVIDER', l_provider, c_cloud_repo_agent);
  END IF;

  IF l_default_repo IS NOT NULL THEN
    merge_config_key(l_schema_name, 'DEFAULT_REPO', l_default_repo, c_cloud_repo_agent);
  END IF;

  IF l_default_owner IS NOT NULL THEN
    merge_config_key(l_schema_name, 'DEFAULT_OWNER', l_default_owner, c_cloud_repo_agent);
  END IF;

  IF l_default_branch IS NOT NULL THEN
    merge_config_key(l_schema_name, 'DEFAULT_BRANCH', l_default_branch, c_cloud_repo_agent);
  END IF;

  IF l_aws_region IS NOT NULL THEN
    merge_config_key(l_schema_name, 'AWS_REGION', l_aws_region, c_cloud_repo_agent);
  END IF;

  IF l_azure_organization IS NOT NULL THEN
    merge_config_key(l_schema_name, 'AZURE_ORGANIZATION', l_azure_organization, c_cloud_repo_agent);
  END IF;

  IF l_azure_project IS NOT NULL THEN
    merge_config_key(l_schema_name, 'AZURE_PROJECT', l_azure_project, c_cloud_repo_agent);
  END IF;

  DBMS_OUTPUT.PUT_LINE('initialize_cloud_repo_agent completed for schema ' || l_schema_name);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Fatal error in initialize_cloud_repo_agent: ' || SQLERRM);
    RAISE;
END initialize_cloud_repo_agent;
/

BEGIN
  initialize_cloud_repo_agent(
    p_install_schema_name => :v_schema,
    p_config_json         => :v_config
  );
END;
/

BEGIN
  EXECUTE IMMEDIATE 'ALTER SESSION SET CURRENT_SCHEMA = ' || :v_schema;
END;
/

CREATE OR REPLACE PACKAGE github_repo_selectai AS
  -- Function: init_repo_handle
  -- Purpose: Build and return a DBMS_CLOUD_REPO repository handle.
  -- Inputs:
  --   provider: GITHUB | AWS | AZURE (ignored when params_json is provided).
  --   repo_name/owner/region/organization/project/credential_name: provider-specific context.
  --   params_json: full INIT_REPO JSON payload for generic handle initialization.
  -- Returns: repository handle CLOB used by all DBMS_CLOUD_REPO operations.
  FUNCTION init_repo_handle(
    provider        VARCHAR2 DEFAULT 'GITHUB',
    repo_name       VARCHAR2 DEFAULT NULL,
    owner           VARCHAR2 DEFAULT NULL,
    credential_name VARCHAR2 DEFAULT NULL,
    region          VARCHAR2 DEFAULT NULL,
    organization    VARCHAR2 DEFAULT NULL,
    project         VARCHAR2 DEFAULT NULL,
    params_json     CLOB DEFAULT NULL
  ) RETURN CLOB;

  -- Function: build_commit_details
  -- Purpose: Build commit metadata JSON accepted by DBMS_CLOUD_REPO write operations.
  -- Inputs: commit message, author name, and author email.
  -- Returns: commit_details JSON CLOB or NULL when all inputs are NULL.
  FUNCTION build_commit_details(
    message_txt  VARCHAR2 DEFAULT NULL,
    author_name  VARCHAR2 DEFAULT NULL,
    author_email VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: create_repository
  -- Purpose: Create a repository for the given repository handle.
  -- Inputs:
  --   repo_handle: initialized handle.
  --   description: repository description.
  --   private_flag: 1/0 mapped to TRUE/FALSE visibility.
  -- Returns: success/error JSON response CLOB.
  FUNCTION create_repository(
    repo_handle  CLOB,
    description  VARCHAR2 DEFAULT NULL,
    private_flag NUMBER DEFAULT 1
  ) RETURN CLOB;

  -- Function: update_repository
  -- Purpose: Update repository name/description/visibility for an existing repository.
  -- Inputs: repo_handle and optional new_name/description/private_flag.
  -- Returns: success/error JSON response CLOB (includes updated handle when applicable).
  FUNCTION update_repository(
    repo_handle  CLOB,
    new_name     VARCHAR2 DEFAULT NULL,
    description  VARCHAR2 DEFAULT NULL,
    private_flag NUMBER DEFAULT NULL
  ) RETURN CLOB;

  -- Function: list_repositories
  -- Purpose: List repositories visible from the supplied repository handle context.
  -- Inputs: repo_handle and optional owner_filter.
  -- Returns: JSON CLOB containing repository array with metadata.
  FUNCTION list_repositories(
    repo_handle   CLOB,
    owner_filter  VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: get_repository
  -- Purpose: Find a single repository by name (and optional owner) from handle context.
  -- Inputs: repo_handle, repo_name, optional owner filter.
  -- Returns: JSON CLOB with repository metadata or not_found status.
  FUNCTION get_repository(
    repo_handle CLOB,
    repo_name   VARCHAR2,
    owner       VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: delete_repository
  -- Purpose: Delete repository represented by the supplied repository handle.
  -- Inputs: repo_handle.
  -- Returns: success/error JSON response CLOB.
  FUNCTION delete_repository(
    repo_handle CLOB
  ) RETURN CLOB;

  -- Function: create_branch
  -- Purpose: Create a repository branch from an optional source branch/commit.
  -- Inputs: repo_handle, branch_name and optional source_branch/source_commit_id.
  -- Returns: success/error JSON response CLOB.
  FUNCTION create_branch(
    repo_handle       CLOB,
    branch_name       VARCHAR2,
    source_branch     VARCHAR2 DEFAULT NULL,
    source_commit_id  VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: delete_branch
  -- Purpose: Delete a repository branch.
  -- Inputs: repo_handle and branch_name.
  -- Returns: success/error JSON response CLOB.
  FUNCTION delete_branch(
    repo_handle CLOB,
    branch_name VARCHAR2
  ) RETURN CLOB;

  -- Function: list_branches
  -- Purpose: List repository branches.
  -- Inputs: repo_handle.
  -- Returns: JSON CLOB with branches array.
  FUNCTION list_branches(
    repo_handle CLOB
  ) RETURN CLOB;

  -- Function: list_commits
  -- Purpose: List commits for a repository (optionally scoped to branch).
  -- Inputs: repo_handle and optional branch_name.
  -- Returns: JSON CLOB with commits array.
  FUNCTION list_commits(
    repo_handle CLOB,
    branch_name VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: merge_branch
  -- Purpose: Merge source_branch into target_branch.
  -- Inputs: repo_handle, source_branch, target_branch and optional commit_details.
  -- Returns: success/error JSON response CLOB.
  FUNCTION merge_branch(
    repo_handle     CLOB,
    source_branch   VARCHAR2,
    target_branch   VARCHAR2,
    commit_details  CLOB DEFAULT NULL
  ) RETURN CLOB;

  -- Function: put_file
  -- Purpose: Upload/create/update a repository file from database text content.
  -- Inputs:
  --   repo_handle/file_path/file_content are required.
  --   branch_name and commit_details are optional.
  -- Returns: success/error JSON response CLOB.
  FUNCTION put_file(
    repo_handle     CLOB,
    file_path       VARCHAR2,
    file_content    CLOB,
    branch_name     VARCHAR2 DEFAULT NULL,
    commit_details  CLOB DEFAULT NULL
  ) RETURN CLOB;

  -- Function: get_file
  -- Purpose: Download repository file content.
  -- Inputs: repo_handle, file_path and optional branch/tag/commit selectors.
  -- Returns: JSON CLOB containing file content and metadata.
  FUNCTION get_file(
    repo_handle   CLOB,
    file_path     VARCHAR2,
    branch_name   VARCHAR2 DEFAULT NULL,
    tag_name      VARCHAR2 DEFAULT NULL,
    commit_name   VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: list_files
  -- Purpose: List files under a repository path using optional branch/tag/commit context.
  -- Inputs: repo_handle and optional path/branch_name/tag_name/commit_id.
  -- Returns: JSON CLOB with file listing entries.
  FUNCTION list_files(
    repo_handle   CLOB,
    path          VARCHAR2 DEFAULT NULL,
    branch_name   VARCHAR2 DEFAULT NULL,
    tag_name      VARCHAR2 DEFAULT NULL,
    commit_id     VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: delete_file
  -- Purpose: Delete a file from repository and optionally attach commit metadata.
  -- Inputs: repo_handle, file_path, optional branch_name/commit_details.
  -- Returns: success/error JSON response CLOB.
  FUNCTION delete_file(
    repo_handle     CLOB,
    file_path       VARCHAR2,
    branch_name     VARCHAR2 DEFAULT NULL,
    commit_details  CLOB DEFAULT NULL
  ) RETURN CLOB;

  -- Function: export_object
  -- Purpose: Export DB object metadata/DDL to a repository file via DBMS_CLOUD_REPO.EXPORT_OBJECT.
  -- Inputs:
  --   repo_handle/file_path/object_type are required.
  --   object_name/object_schema narrow export scope.
  --   branch_name/commit_details/append_flag control commit behavior.
  -- Returns: success/error JSON response CLOB.
  FUNCTION export_object(
    repo_handle      CLOB,
    file_path        VARCHAR2,
    object_type      VARCHAR2,
    object_name      VARCHAR2 DEFAULT NULL,
    object_schema    VARCHAR2 DEFAULT NULL,
    branch_name      VARCHAR2 DEFAULT NULL,
    commit_details   CLOB DEFAULT NULL,
    append_flag      NUMBER DEFAULT 0
  ) RETURN CLOB;

  -- Function: export_schema
  -- Purpose: Export all schema metadata DDL (optionally filtered) to a repository file.
  -- Inputs:
  --   repo_handle/file_path/schema_name are required.
  --   filter_list is optional JSON array CLOB for include/exclude filtering.
  --   branch_name/commit_details are optional commit context values.
  -- Returns: success/error JSON response CLOB.
  FUNCTION export_schema(
    repo_handle      CLOB,
    file_path        VARCHAR2,
    schema_name      VARCHAR2,
    filter_list      CLOB DEFAULT NULL,
    branch_name      VARCHAR2 DEFAULT NULL,
    commit_details   CLOB DEFAULT NULL
  ) RETURN CLOB;

  -- Function: install_file
  -- Purpose: Install SQL from a repository file into the current schema.
  -- Inputs:
  --   repo_handle/file_path are required.
  --   branch_name/tag_name/commit_name select repository revision context.
  --   stop_on_error controls whether execution stops on first SQL error (1/0).
  -- Returns: success/error JSON response CLOB.
  FUNCTION install_file(
    repo_handle      CLOB,
    file_path        VARCHAR2,
    branch_name      VARCHAR2 DEFAULT NULL,
    tag_name         VARCHAR2 DEFAULT NULL,
    commit_name      VARCHAR2 DEFAULT NULL,
    stop_on_error    NUMBER DEFAULT 1
  ) RETURN CLOB;

  -- Function: install_sql
  -- Purpose: Install SQL statements provided directly in a CLOB buffer.
  -- Inputs: sql_content CLOB and stop_on_error flag (1/0).
  -- Returns: success/error JSON response CLOB.
  FUNCTION install_sql(
    sql_content      CLOB,
    stop_on_error    NUMBER DEFAULT 1
  ) RETURN CLOB;
END github_repo_selectai;
/

CREATE OR REPLACE PACKAGE BODY github_repo_selectai AS
  -- Implements function: bool from number.
  FUNCTION bool_from_number(
    p_value        IN NUMBER,
    p_default_true IN BOOLEAN DEFAULT TRUE
  ) RETURN BOOLEAN IS
  BEGIN
    IF p_value IS NULL THEN
      RETURN p_default_true;
    ELSIF p_value = 0 THEN
      RETURN FALSE;
    ELSE
      RETURN TRUE;
    END IF;
  END bool_from_number;

  -- Implements function: clob to blob.
  FUNCTION clob_to_blob(p_content CLOB) RETURN BLOB IS
    l_blob         BLOB;
    l_dest_offset  INTEGER := 1;
    l_src_offset   INTEGER := 1;
    l_lang_context INTEGER := DBMS_LOB.DEFAULT_LANG_CTX;
    l_warning      INTEGER;
  BEGIN
    DBMS_LOB.CREATETEMPORARY(l_blob, TRUE);

    IF p_content IS NOT NULL THEN
      DBMS_LOB.CONVERTTOBLOB(
        dest_lob     => l_blob,
        src_clob     => p_content,
        amount       => DBMS_LOB.LOBMAXSIZE,
        dest_offset  => l_dest_offset,
        src_offset   => l_src_offset,
        blob_csid    => DBMS_LOB.DEFAULT_CSID,
        lang_context => l_lang_context,
        warning      => l_warning
      );
    END IF;

    RETURN l_blob;
  END clob_to_blob;

  -- Implements function: normalize provider.
  FUNCTION normalize_provider(p_provider VARCHAR2) RETURN VARCHAR2 IS
    l_provider VARCHAR2(30) := UPPER(TRIM(NVL(p_provider, 'GITHUB')));
  BEGIN
    IF l_provider NOT IN ('GITHUB', 'AWS', 'AZURE') THEN
      RAISE_APPLICATION_ERROR(-20010, 'Unsupported provider: ' || l_provider || '. Expected GITHUB, AWS, or AZURE.');
    END IF;
    RETURN l_provider;
  END normalize_provider;

  -- Converts a dynamic SELECT resultset into JSON array without compile-time rowtype dependency.
  FUNCTION query_to_json_array(
    p_sql        IN VARCHAR2,
    p_bind_repo  IN CLOB,
    p_bind_arg2  IN VARCHAR2 DEFAULT NULL
  ) RETURN JSON_ARRAY_T IS
    l_cur           INTEGER := NULL;
    l_rowcount      INTEGER;
    l_col_count     INTEGER;
    l_desc_tab      DBMS_SQL.DESC_TAB2;
    l_val           VARCHAR2(32767);
    l_arr           JSON_ARRAY_T := JSON_ARRAY_T();
    l_row           JSON_OBJECT_T;
  BEGIN
    l_cur := DBMS_SQL.OPEN_CURSOR;
    DBMS_SQL.PARSE(l_cur, p_sql, DBMS_SQL.NATIVE);

    DBMS_SQL.BIND_VARIABLE(l_cur, ':b1', p_bind_repo);
    IF p_bind_arg2 IS NOT NULL THEN
      DBMS_SQL.BIND_VARIABLE(l_cur, ':b2', p_bind_arg2);
    END IF;

    DBMS_SQL.DESCRIBE_COLUMNS2(l_cur, l_col_count, l_desc_tab);
    FOR i IN 1 .. l_col_count LOOP
      DBMS_SQL.DEFINE_COLUMN(l_cur, i, l_val, 32767);
    END LOOP;

    l_rowcount := DBMS_SQL.EXECUTE(l_cur);
    LOOP
      EXIT WHEN DBMS_SQL.FETCH_ROWS(l_cur) = 0;
      l_row := JSON_OBJECT_T();
      FOR i IN 1 .. l_col_count LOOP
        DBMS_SQL.COLUMN_VALUE(l_cur, i, l_val);
        l_row.put(LOWER(l_desc_tab(i).col_name), l_val);
      END LOOP;
      l_arr.append(l_row);
    END LOOP;

    DBMS_SQL.CLOSE_CURSOR(l_cur);
    RETURN l_arr;
  EXCEPTION
    WHEN OTHERS THEN
      IF l_cur IS NOT NULL AND DBMS_SQL.IS_OPEN(l_cur) THEN
        DBMS_SQL.CLOSE_CURSOR(l_cur);
      END IF;
      RAISE;
  END query_to_json_array;

  -- Implements function: init repo handle.
  FUNCTION init_repo_handle(
    provider        VARCHAR2 DEFAULT 'GITHUB',
    repo_name       VARCHAR2 DEFAULT NULL,
    owner           VARCHAR2 DEFAULT NULL,
    credential_name VARCHAR2 DEFAULT NULL,
    region          VARCHAR2 DEFAULT NULL,
    organization    VARCHAR2 DEFAULT NULL,
    project         VARCHAR2 DEFAULT NULL,
    params_json     CLOB DEFAULT NULL
  ) RETURN CLOB IS
    l_provider VARCHAR2(30);
    l_repo     CLOB;
  BEGIN
    IF params_json IS NOT NULL AND TRIM(params_json) IS NOT NULL THEN
      l_repo := DBMS_CLOUD_REPO.INIT_REPO(params => params_json);
      RETURN l_repo;
    END IF;

    l_provider := normalize_provider(provider);

    IF l_provider = 'GITHUB' THEN
      IF repo_name IS NULL OR owner IS NULL THEN
        RAISE_APPLICATION_ERROR(-20011, 'repo_name and owner are required for provider GITHUB.');
      END IF;
      l_repo := DBMS_CLOUD_REPO.INIT_GITHUB_REPO(
        credential_name => credential_name,
        repo_name       => repo_name,
        owner           => owner
      );
    ELSIF l_provider = 'AWS' THEN
      IF repo_name IS NULL OR region IS NULL THEN
        RAISE_APPLICATION_ERROR(-20012, 'repo_name and region are required for provider AWS.');
      END IF;
      l_repo := DBMS_CLOUD_REPO.INIT_AWS_REPO(
        credential_name => credential_name,
        repo_name       => repo_name,
        region          => region
      );
    ELSE
      IF repo_name IS NULL OR organization IS NULL OR project IS NULL THEN
        RAISE_APPLICATION_ERROR(-20013, 'repo_name, organization, and project are required for provider AZURE.');
      END IF;
      l_repo := DBMS_CLOUD_REPO.INIT_AZURE_REPO(
        credential_name => credential_name,
        repo_name       => repo_name,
        organization    => organization,
        project         => project
      );
    END IF;

    RETURN l_repo;
  END init_repo_handle;

  -- Implements function: build commit details.
  FUNCTION build_commit_details(
    message_txt  VARCHAR2 DEFAULT NULL,
    author_name  VARCHAR2 DEFAULT NULL,
    author_email VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_commit JSON_OBJECT_T := JSON_OBJECT_T();
    l_author JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    IF message_txt IS NULL AND author_name IS NULL AND author_email IS NULL THEN
      RETURN NULL;
    END IF;

    IF message_txt IS NOT NULL THEN
      l_commit.put('message', message_txt);
    END IF;

    IF author_name IS NOT NULL OR author_email IS NOT NULL THEN
      IF author_name IS NOT NULL THEN
        l_author.put('name', author_name);
      END IF;
      IF author_email IS NOT NULL THEN
        l_author.put('email', author_email);
      END IF;
      l_commit.put('author', l_author);
    END IF;

    RETURN l_commit.to_clob();
  END build_commit_details;

  -- Implements function: create repository.
  FUNCTION create_repository(
    repo_handle  CLOB,
    description  VARCHAR2 DEFAULT NULL,
    private_flag NUMBER DEFAULT 1
  ) RETURN CLOB IS
    l_result JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    DBMS_CLOUD_REPO.CREATE_REPOSITORY(
      repo        => repo_handle,
      description => description,
      private     => bool_from_number(private_flag, TRUE)
    );

    l_result.put('status', 'success');
    l_result.put('message', 'Repository created successfully.');
    RETURN l_result.to_clob();
  END create_repository;

  -- Implements function: update repository.
  FUNCTION update_repository(
    repo_handle  CLOB,
    new_name     VARCHAR2 DEFAULT NULL,
    description  VARCHAR2 DEFAULT NULL,
    private_flag NUMBER DEFAULT NULL
  ) RETURN CLOB IS
    l_result JSON_OBJECT_T := JSON_OBJECT_T();
    l_repo   CLOB := repo_handle;
    l_priv   BOOLEAN;
  BEGIN
    IF private_flag IS NULL THEN
      l_priv := NULL;
    ELSIF private_flag = 0 THEN
      l_priv := FALSE;
    ELSE
      l_priv := TRUE;
    END IF;

    DBMS_CLOUD_REPO.UPDATE_REPOSITORY(
      repo        => l_repo,
      new_name    => new_name,
      description => description,
      private     => l_priv
    );

    l_result.put('status', 'success');
    l_result.put('message', 'Repository updated successfully.');
    l_result.put('repo_handle', l_repo);
    RETURN l_result.to_clob();
  END update_repository;

  -- Implements function: list repositories.
  FUNCTION list_repositories(
    repo_handle   CLOB,
    owner_filter  VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_result JSON_OBJECT_T := JSON_OBJECT_T();
    l_items  JSON_ARRAY_T := JSON_ARRAY_T();
    l_item   JSON_OBJECT_T;
  BEGIN
    FOR r IN (
      SELECT name, owner, description, url, bytes, created, last_modified
      FROM TABLE(DBMS_CLOUD_REPO.LIST_REPOSITORIES(repo => repo_handle))
    ) LOOP
      IF owner_filter IS NULL
         OR UPPER(NVL(r.owner, '')) = UPPER(NVL(owner_filter, ''))
      THEN
        l_item := JSON_OBJECT_T();
        l_item.put('name', r.name);
        l_item.put('owner', r.owner);
        l_item.put('description', r.description);
        l_item.put('url', r.url);
        l_item.put('bytes', r.bytes);
        IF r.created IS NOT NULL THEN
          l_item.put('created', TO_CHAR(r.created, 'YYYY-MM-DD"T"HH24:MI:SS'));
        END IF;
        IF r.last_modified IS NOT NULL THEN
          l_item.put('last_modified', TO_CHAR(r.last_modified, 'YYYY-MM-DD"T"HH24:MI:SS'));
        END IF;
        l_items.append(l_item);
      END IF;
    END LOOP;

    l_result.put('status', 'success');
    l_result.put('repositories', l_items);
    RETURN l_result.to_clob();
  END list_repositories;

  -- Implements function: get repository.
  FUNCTION get_repository(
    repo_handle CLOB,
    repo_name   VARCHAR2,
    owner       VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_result JSON_OBJECT_T := JSON_OBJECT_T();
    l_item   JSON_OBJECT_T;
  BEGIN
    FOR r IN (
      SELECT name, owner, description, url, bytes, created, last_modified
      FROM TABLE(DBMS_CLOUD_REPO.LIST_REPOSITORIES(repo => repo_handle))
    ) LOOP
      IF UPPER(r.name) = UPPER(repo_name)
         AND (owner IS NULL OR UPPER(NVL(r.owner, '')) = UPPER(NVL(owner, '')))
      THEN
        l_item := JSON_OBJECT_T();
        l_item.put('name', r.name);
        l_item.put('owner', r.owner);
        l_item.put('description', r.description);
        l_item.put('url', r.url);
        l_item.put('bytes', r.bytes);
        IF r.created IS NOT NULL THEN
          l_item.put('created', TO_CHAR(r.created, 'YYYY-MM-DD"T"HH24:MI:SS'));
        END IF;
        IF r.last_modified IS NOT NULL THEN
          l_item.put('last_modified', TO_CHAR(r.last_modified, 'YYYY-MM-DD"T"HH24:MI:SS'));
        END IF;

        l_result.put('status', 'success');
        l_result.put('repository', l_item);
        RETURN l_result.to_clob();
      END IF;
    END LOOP;

    l_result.put('status', 'not_found');
    l_result.put('message', 'Repository not found.');
    l_result.put('repo_name', repo_name);
    IF owner IS NOT NULL THEN
      l_result.put('owner', owner);
    END IF;
    RETURN l_result.to_clob();
  END get_repository;

  -- Implements function: delete repository.
  FUNCTION delete_repository(
    repo_handle CLOB
  ) RETURN CLOB IS
    l_result JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    DBMS_CLOUD_REPO.DELETE_REPOSITORY(repo => repo_handle);

    l_result.put('status', 'success');
    l_result.put('message', 'Repository deleted successfully.');
    RETURN l_result.to_clob();
  END delete_repository;

  -- Implements function: create branch.
  FUNCTION create_branch(
    repo_handle       CLOB,
    branch_name       VARCHAR2,
    source_branch     VARCHAR2 DEFAULT NULL,
    source_commit_id  VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_result    JSON_OBJECT_T := JSON_OBJECT_T();
    l_err_main  VARCHAR2(4000);
  BEGIN
    BEGIN
      EXECUTE IMMEDIATE q'[
        BEGIN
          DBMS_CLOUD_REPO.CREATE_BRANCH(:1, :2, :3, :4);
        END;
      ]'
      USING repo_handle, branch_name, source_branch, source_commit_id;
    EXCEPTION
      WHEN OTHERS THEN
        l_err_main := SQLERRM;
        BEGIN
          EXECUTE IMMEDIATE q'[
            BEGIN
              DBMS_CLOUD_REPO.CREATE_BRANCH(:1, :2, :3);
            END;
          ]'
          USING repo_handle, branch_name, source_branch;
        EXCEPTION
          WHEN OTHERS THEN
            BEGIN
              EXECUTE IMMEDIATE q'[
                BEGIN
                  DBMS_CLOUD_REPO.CREATE_BRANCH(:1, :2);
                END;
              ]'
              USING repo_handle, branch_name;
            EXCEPTION
              WHEN OTHERS THEN
                RAISE_APPLICATION_ERROR(
                  -20030,
                  'CREATE_BRANCH failed. First attempt: ' || l_err_main || '; second/third attempt: ' || SQLERRM
                );
            END;
        END;
    END;

    l_result.put('status', 'success');
    l_result.put('message', 'Branch created successfully.');
    l_result.put('branch_name', branch_name);
    RETURN l_result.to_clob();
  END create_branch;

  -- Implements function: delete branch.
  FUNCTION delete_branch(
    repo_handle CLOB,
    branch_name VARCHAR2
  ) RETURN CLOB IS
    l_result JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    EXECUTE IMMEDIATE q'[
      BEGIN
        DBMS_CLOUD_REPO.DELETE_BRANCH(:1, :2);
      END;
    ]'
    USING repo_handle, branch_name;

    l_result.put('status', 'success');
    l_result.put('message', 'Branch deleted successfully.');
    l_result.put('branch_name', branch_name);
    RETURN l_result.to_clob();
  END delete_branch;

  -- Implements function: list branches.
  FUNCTION list_branches(
    repo_handle CLOB
  ) RETURN CLOB IS
    l_result JSON_OBJECT_T := JSON_OBJECT_T();
    l_rows   JSON_ARRAY_T;
  BEGIN
    l_rows := query_to_json_array(
      p_sql       => 'SELECT * FROM TABLE(DBMS_CLOUD_REPO.LIST_BRANCHES(:b1))',
      p_bind_repo => repo_handle
    );

    l_result.put('status', 'success');
    l_result.put('branches', l_rows);
    RETURN l_result.to_clob();
  END list_branches;

  -- Implements function: list commits.
  FUNCTION list_commits(
    repo_handle CLOB,
    branch_name VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_result JSON_OBJECT_T := JSON_OBJECT_T();
    l_rows   JSON_ARRAY_T;
  BEGIN
    IF branch_name IS NULL THEN
      l_rows := query_to_json_array(
        p_sql       => 'SELECT * FROM TABLE(DBMS_CLOUD_REPO.LIST_COMMITS(:b1))',
        p_bind_repo => repo_handle
      );
    ELSE
      l_rows := query_to_json_array(
        p_sql       => 'SELECT * FROM TABLE(DBMS_CLOUD_REPO.LIST_COMMITS(:b1, :b2))',
        p_bind_repo => repo_handle,
        p_bind_arg2 => branch_name
      );
    END IF;

    l_result.put('status', 'success');
    IF branch_name IS NOT NULL THEN
      l_result.put('branch_name', branch_name);
    END IF;
    l_result.put('commits', l_rows);
    RETURN l_result.to_clob();
  END list_commits;

  -- Implements function: merge branch.
  FUNCTION merge_branch(
    repo_handle     CLOB,
    source_branch   VARCHAR2,
    target_branch   VARCHAR2,
    commit_details  CLOB DEFAULT NULL
  ) RETURN CLOB IS
    l_result   JSON_OBJECT_T := JSON_OBJECT_T();
    l_err_main VARCHAR2(4000);
  BEGIN
    BEGIN
      EXECUTE IMMEDIATE q'[
        BEGIN
          DBMS_CLOUD_REPO.MERGE_BRANCH(:1, :2, :3, :4);
        END;
      ]'
      USING repo_handle, source_branch, target_branch, commit_details;
    EXCEPTION
      WHEN OTHERS THEN
        l_err_main := SQLERRM;
        BEGIN
          EXECUTE IMMEDIATE q'[
            BEGIN
              DBMS_CLOUD_REPO.MERGE_BRANCH(:1, :2, :3);
            END;
          ]'
          USING repo_handle, source_branch, target_branch;
        EXCEPTION
          WHEN OTHERS THEN
            RAISE_APPLICATION_ERROR(
              -20031,
              'MERGE_BRANCH failed. First attempt: ' || l_err_main || '; second attempt: ' || SQLERRM
            );
        END;
    END;

    l_result.put('status', 'success');
    l_result.put('message', 'Branch merged successfully.');
    l_result.put('source_branch', source_branch);
    l_result.put('target_branch', target_branch);
    RETURN l_result.to_clob();
  END merge_branch;

  -- Implements function: put file.
  FUNCTION put_file(
    repo_handle     CLOB,
    file_path       VARCHAR2,
    file_content    CLOB,
    branch_name     VARCHAR2 DEFAULT NULL,
    commit_details  CLOB DEFAULT NULL
  ) RETURN CLOB IS
    l_result JSON_OBJECT_T := JSON_OBJECT_T();
    l_blob   BLOB;
  BEGIN
    l_blob := clob_to_blob(file_content);

    DBMS_CLOUD_REPO.PUT_FILE(
      repo           => repo_handle,
      file_path      => file_path,
      contents       => l_blob,
      branch_name    => branch_name,
      commit_details => commit_details
    );

    l_result.put('status', 'success');
    l_result.put('message', 'File uploaded successfully.');
    l_result.put('file_path', file_path);
    IF branch_name IS NOT NULL THEN
      l_result.put('branch_name', branch_name);
    END IF;
    RETURN l_result.to_clob();
  END put_file;

  -- Implements function: get file.
  FUNCTION get_file(
    repo_handle   CLOB,
    file_path     VARCHAR2,
    branch_name   VARCHAR2 DEFAULT NULL,
    tag_name      VARCHAR2 DEFAULT NULL,
    commit_name   VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_result  JSON_OBJECT_T := JSON_OBJECT_T();
    l_content CLOB;
  BEGIN
    l_content := DBMS_CLOUD_REPO.GET_FILE(
      repo        => repo_handle,
      file_path   => file_path,
      branch_name => branch_name,
      tag_name    => tag_name,
      commit_id   => commit_name
    );

    l_result.put('status', 'success');
    l_result.put('file_path', file_path);
    l_result.put('content', l_content);
    RETURN l_result.to_clob();
  END get_file;

  -- Implements function: list files.
  FUNCTION list_files(
    repo_handle   CLOB,
    path          VARCHAR2 DEFAULT NULL,
    branch_name   VARCHAR2 DEFAULT NULL,
    tag_name      VARCHAR2 DEFAULT NULL,
    commit_id     VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_result JSON_OBJECT_T := JSON_OBJECT_T();
    l_items  JSON_ARRAY_T := JSON_ARRAY_T();
    l_item   JSON_OBJECT_T;
  BEGIN
    FOR r IN (
      SELECT id, name, url, bytes
      FROM TABLE(
        DBMS_CLOUD_REPO.LIST_FILES(
          repo        => repo_handle,
          path        => path,
          branch_name => branch_name,
          tag_name    => tag_name,
          commit_id   => commit_id
        )
      )
    ) LOOP
      l_item := JSON_OBJECT_T();
      l_item.put('id', r.id);
      l_item.put('name', r.name);
      l_item.put('url', r.url);
      l_item.put('bytes', r.bytes);
      l_items.append(l_item);
    END LOOP;

    l_result.put('status', 'success');
    l_result.put('files', l_items);
    RETURN l_result.to_clob();
  END list_files;

  -- Implements function: delete file.
  FUNCTION delete_file(
    repo_handle     CLOB,
    file_path       VARCHAR2,
    branch_name     VARCHAR2 DEFAULT NULL,
    commit_details  CLOB DEFAULT NULL
  ) RETURN CLOB IS
    l_result JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    DBMS_CLOUD_REPO.DELETE_FILE(
      repo           => repo_handle,
      file_path      => file_path,
      branch_name    => branch_name,
      commit_details => commit_details
    );

    l_result.put('status', 'success');
    l_result.put('message', 'File deleted successfully.');
    l_result.put('file_path', file_path);
    RETURN l_result.to_clob();
  END delete_file;

  -- Implements function: export object.
  FUNCTION export_object(
    repo_handle      CLOB,
    file_path        VARCHAR2,
    object_type      VARCHAR2,
    object_name      VARCHAR2 DEFAULT NULL,
    object_schema    VARCHAR2 DEFAULT NULL,
    branch_name      VARCHAR2 DEFAULT NULL,
    commit_details   CLOB DEFAULT NULL,
    append_flag      NUMBER DEFAULT 0
  ) RETURN CLOB IS
    l_result JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    DBMS_CLOUD_REPO.EXPORT_OBJECT(
      repo           => repo_handle,
      file_path      => file_path,
      object_type    => object_type,
      object_name    => object_name,
      object_schema  => object_schema,
      branch_name    => branch_name,
      commit_details => commit_details,
      append         => bool_from_number(append_flag, FALSE)
    );

    l_result.put('status', 'success');
    l_result.put('message', 'Object metadata exported successfully.');
    l_result.put('file_path', file_path);
    RETURN l_result.to_clob();
  END export_object;

  -- Implements function: export schema.
  FUNCTION export_schema(
    repo_handle      CLOB,
    file_path        VARCHAR2,
    schema_name      VARCHAR2,
    filter_list      CLOB DEFAULT NULL,
    branch_name      VARCHAR2 DEFAULT NULL,
    commit_details   CLOB DEFAULT NULL
  ) RETURN CLOB IS
    l_result JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    DBMS_CLOUD_REPO.EXPORT_SCHEMA(
      repo           => repo_handle,
      file_path      => file_path,
      schema_name    => schema_name,
      filter_list    => filter_list,
      branch_name    => branch_name,
      commit_details => commit_details
    );

    l_result.put('status', 'success');
    l_result.put('message', 'Schema metadata exported successfully.');
    l_result.put('file_path', file_path);
    l_result.put('schema_name', schema_name);
    RETURN l_result.to_clob();
  END export_schema;

  -- Implements function: install file.
  FUNCTION install_file(
    repo_handle      CLOB,
    file_path        VARCHAR2,
    branch_name      VARCHAR2 DEFAULT NULL,
    tag_name         VARCHAR2 DEFAULT NULL,
    commit_name      VARCHAR2 DEFAULT NULL,
    stop_on_error    NUMBER DEFAULT 1
  ) RETURN CLOB IS
    l_result       JSON_OBJECT_T := JSON_OBJECT_T();
    l_stop_literal VARCHAR2(5);
    l_err_main     VARCHAR2(4000);
  BEGIN
    l_stop_literal := CASE
                        WHEN bool_from_number(stop_on_error, TRUE) THEN 'TRUE'
                        ELSE 'FALSE'
                      END;

    BEGIN
      EXECUTE IMMEDIATE
        'BEGIN
           DBMS_CLOUD_REPO.INSTALL_FILE(
             repo          => :1,
             file_path     => :2,
             branch_name   => :3,
             tag_name      => :4,
             commit_name   => :5,
             stop_on_error => ' || l_stop_literal || '
           );
         END;'
      USING repo_handle, file_path, branch_name, tag_name, commit_name;
    EXCEPTION
      WHEN OTHERS THEN
        l_err_main := SQLERRM;
        BEGIN
          EXECUTE IMMEDIATE q'[
            BEGIN
              DBMS_CLOUD_REPO.INSTALL_FILE(
                repo        => :1,
                file_path   => :2,
                branch_name => :3,
                tag_name    => :4,
                commit_name => :5
              );
            END;
          ]'
          USING repo_handle, file_path, branch_name, tag_name, commit_name;
        EXCEPTION
          WHEN OTHERS THEN
            BEGIN
              EXECUTE IMMEDIATE
                'BEGIN
                   DBMS_CLOUD_REPO.INSTALL_FILE(
                     repo          => :1,
                     file_path     => :2,
                     branch_name   => :3,
                     stop_on_error => ' || l_stop_literal || '
                   );
                 END;'
              USING repo_handle, file_path, branch_name;
            EXCEPTION
              WHEN OTHERS THEN
                BEGIN
                  EXECUTE IMMEDIATE q'[
                    BEGIN
                      DBMS_CLOUD_REPO.INSTALL_FILE(
                        repo        => :1,
                        file_path   => :2,
                        branch_name => :3
                      );
                    END;
                  ]'
                  USING repo_handle, file_path, branch_name;
                EXCEPTION
                  WHEN OTHERS THEN
                    BEGIN
                      EXECUTE IMMEDIATE
                        'BEGIN
                           DBMS_CLOUD_REPO.INSTALL_FILE(
                             repo          => :1,
                             file_path     => :2,
                             stop_on_error => ' || l_stop_literal || '
                           );
                         END;'
                      USING repo_handle, file_path;
                    EXCEPTION
                      WHEN OTHERS THEN
                        BEGIN
                          EXECUTE IMMEDIATE q'[
                            BEGIN
                              DBMS_CLOUD_REPO.INSTALL_FILE(
                                repo      => :1,
                                file_path => :2
                              );
                            END;
                          ]'
                          USING repo_handle, file_path;
                        EXCEPTION
                          WHEN OTHERS THEN
                            RAISE_APPLICATION_ERROR(
                              -20034,
                              'INSTALL_FILE failed. First attempt: ' || l_err_main || '; final attempt: ' || SQLERRM
                            );
                        END;
                    END;
                END;
            END;
        END;
    END;

    l_result.put('status', 'success');
    l_result.put('message', 'SQL installed from repository file successfully.');
    l_result.put('file_path', file_path);
    RETURN l_result.to_clob();
  END install_file;

  -- Implements function: install sql.
  FUNCTION install_sql(
    sql_content      CLOB,
    stop_on_error    NUMBER DEFAULT 1
  ) RETURN CLOB IS
    l_result       JSON_OBJECT_T := JSON_OBJECT_T();
    l_stop_literal VARCHAR2(5);
    l_err_main     VARCHAR2(4000);
  BEGIN
    l_stop_literal := CASE
                        WHEN bool_from_number(stop_on_error, TRUE) THEN 'TRUE'
                        ELSE 'FALSE'
                      END;

    BEGIN
      EXECUTE IMMEDIATE
        'BEGIN
           DBMS_CLOUD_REPO.INSTALL_SQL(
             content       => :1,
             stop_on_error => ' || l_stop_literal || '
           );
         END;'
      USING sql_content;
    EXCEPTION
      WHEN OTHERS THEN
        l_err_main := SQLERRM;
        BEGIN
          EXECUTE IMMEDIATE q'[
            BEGIN
              DBMS_CLOUD_REPO.INSTALL_SQL(
                content => :1
              );
            END;
          ]'
          USING sql_content;
        EXCEPTION
          WHEN OTHERS THEN
            BEGIN
              EXECUTE IMMEDIATE
                'BEGIN
                   DBMS_CLOUD_REPO.INSTALL_SQL(
                     sql_content   => :1,
                     stop_on_error => ' || l_stop_literal || '
                   );
                 END;'
              USING sql_content;
            EXCEPTION
              WHEN OTHERS THEN
                BEGIN
                  EXECUTE IMMEDIATE q'[
                    BEGIN
                      DBMS_CLOUD_REPO.INSTALL_SQL(
                        sql_content => :1
                      );
                    END;
                  ]'
                  USING sql_content;
                EXCEPTION
                  WHEN OTHERS THEN
                    BEGIN
                      EXECUTE IMMEDIATE q'[
                        BEGIN
                          DBMS_CLOUD_REPO.INSTALL_SQL(:1);
                        END;
                      ]'
                      USING sql_content;
                    EXCEPTION
                      WHEN OTHERS THEN
                        RAISE_APPLICATION_ERROR(
                          -20035,
                          'INSTALL_SQL failed. First attempt: ' || l_err_main || '; final attempt: ' || SQLERRM
                        );
                    END;
                END;
            END;
        END;
    END;

    l_result.put('status', 'success');
    l_result.put('message', 'SQL buffer installed successfully.');
    RETURN l_result.to_clob();
  END install_sql;
END github_repo_selectai;
/

CREATE OR REPLACE PACKAGE select_ai_github_connector AS
  -- Function: init_repo
  -- Purpose: Initialize repository handle from full INIT_REPO JSON input.
  -- Input: params_json (provider-specific repository JSON).
  -- Return: JSON CLOB containing repo_handle or error details.
  FUNCTION init_repo(
    params_json IN CLOB
  ) RETURN CLOB;

  -- Function: init_github_repo
  -- Purpose: Initialize GitHub repository handle using explicit or default config values.
  -- Inputs: repo_name, owner, credential_name (each optional when defaults exist).
  -- Return: JSON CLOB containing repo_handle.
  FUNCTION init_github_repo(
    repo_name       IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: init_aws_repo
  -- Purpose: Initialize AWS CodeCommit repository handle.
  -- Inputs: repo_name, region, credential_name (uses defaults when available).
  -- Return: JSON CLOB containing repo_handle.
  FUNCTION init_aws_repo(
    repo_name       IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: init_azure_repo
  -- Purpose: Initialize Azure Repos repository handle.
  -- Inputs: repo_name, organization, project, credential_name.
  -- Return: JSON CLOB containing repo_handle.
  FUNCTION init_azure_repo(
    repo_name       IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: create_repository
  -- Purpose: Resolve provider/repository context then create repository.
  -- Inputs: description/private_flag plus optional provider context overrides.
  -- Return: success/error JSON response CLOB.
  FUNCTION create_repository(
    description     IN VARCHAR2 DEFAULT NULL,
    private_flag    IN NUMBER DEFAULT 1,
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: update_repository
  -- Purpose: Resolve context and update repository metadata/visibility.
  -- Inputs: new_name/description/private_flag plus optional context overrides.
  -- Return: success/error JSON response CLOB.
  FUNCTION update_repository(
    new_name        IN VARCHAR2 DEFAULT NULL,
    description     IN VARCHAR2 DEFAULT NULL,
    private_flag    IN NUMBER DEFAULT NULL,
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: list_repositories
  -- Purpose: Resolve context and list repositories via DBMS_CLOUD_REPO.
  -- Inputs: optional repo/provider/owner/credential/region/organization/project.
  -- Return: JSON CLOB containing repository array.
  FUNCTION list_repositories(
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: get_repository
  -- Purpose: Resolve context and fetch one repository by name.
  -- Inputs: repo_name and optional context overrides.
  -- Return: JSON CLOB with repository metadata or not_found status.
  FUNCTION get_repository(
    repo_name       IN VARCHAR2,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: delete_repository
  -- Purpose: Resolve context and delete target repository.
  -- Inputs: optional repo/provider/owner/credential/region/organization/project.
  -- Return: success/error JSON response CLOB.
  FUNCTION delete_repository(
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: create_branch
  -- Purpose: Resolve context and create a branch in repository.
  -- Inputs: branch_name required; optional source_branch/source_commit_id and context overrides.
  -- Return: success/error JSON response CLOB.
  FUNCTION create_branch(
    branch_name      IN VARCHAR2,
    source_branch    IN VARCHAR2 DEFAULT NULL,
    source_commit_id IN VARCHAR2 DEFAULT NULL,
    repo_name        IN VARCHAR2 DEFAULT NULL,
    provider         IN VARCHAR2 DEFAULT NULL,
    owner            IN VARCHAR2 DEFAULT NULL,
    credential_name  IN VARCHAR2 DEFAULT NULL,
    region           IN VARCHAR2 DEFAULT NULL,
    organization     IN VARCHAR2 DEFAULT NULL,
    project          IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: delete_branch
  -- Purpose: Resolve context and delete a branch in repository.
  -- Inputs: branch_name required plus optional context overrides.
  -- Return: success/error JSON response CLOB.
  FUNCTION delete_branch(
    branch_name      IN VARCHAR2,
    repo_name        IN VARCHAR2 DEFAULT NULL,
    provider         IN VARCHAR2 DEFAULT NULL,
    owner            IN VARCHAR2 DEFAULT NULL,
    credential_name  IN VARCHAR2 DEFAULT NULL,
    region           IN VARCHAR2 DEFAULT NULL,
    organization     IN VARCHAR2 DEFAULT NULL,
    project          IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: list_branches
  -- Purpose: Resolve context and list repository branches.
  -- Inputs: optional repository/provider context.
  -- Return: JSON CLOB with branches array.
  FUNCTION list_branches(
    repo_name        IN VARCHAR2 DEFAULT NULL,
    provider         IN VARCHAR2 DEFAULT NULL,
    owner            IN VARCHAR2 DEFAULT NULL,
    credential_name  IN VARCHAR2 DEFAULT NULL,
    region           IN VARCHAR2 DEFAULT NULL,
    organization     IN VARCHAR2 DEFAULT NULL,
    project          IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: list_commits
  -- Purpose: Resolve context and list commits (optionally by branch).
  -- Inputs: optional branch_name and repository/provider context.
  -- Return: JSON CLOB with commits array.
  FUNCTION list_commits(
    branch_name      IN VARCHAR2 DEFAULT NULL,
    repo_name        IN VARCHAR2 DEFAULT NULL,
    provider         IN VARCHAR2 DEFAULT NULL,
    owner            IN VARCHAR2 DEFAULT NULL,
    credential_name  IN VARCHAR2 DEFAULT NULL,
    region           IN VARCHAR2 DEFAULT NULL,
    organization     IN VARCHAR2 DEFAULT NULL,
    project          IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: merge_branch
  -- Purpose: Resolve context and merge source branch into target branch.
  -- Inputs:
  --   source_branch/target_branch required.
  --   commit metadata optional.
  --   provider context optional with defaults.
  -- Return: success/error JSON response CLOB.
  FUNCTION merge_branch(
    source_branch    IN VARCHAR2,
    target_branch    IN VARCHAR2,
    commit_message   IN VARCHAR2 DEFAULT NULL,
    author_name      IN VARCHAR2 DEFAULT NULL,
    author_email     IN VARCHAR2 DEFAULT NULL,
    repo_name        IN VARCHAR2 DEFAULT NULL,
    provider         IN VARCHAR2 DEFAULT NULL,
    owner            IN VARCHAR2 DEFAULT NULL,
    credential_name  IN VARCHAR2 DEFAULT NULL,
    region           IN VARCHAR2 DEFAULT NULL,
    organization     IN VARCHAR2 DEFAULT NULL,
    project          IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: put_file
  -- Purpose: Resolve context and upload/update repository file with optional commit metadata.
  -- Inputs:
  --   file_path/file_content required.
  --   branch_name/commit_message/author_name/author_email optional.
  --   provider context can be passed explicitly or sourced from defaults.
  -- Return: success/error JSON response CLOB.
  FUNCTION put_file(
    file_path       IN VARCHAR2,
    file_content    IN CLOB,
    branch_name     IN VARCHAR2 DEFAULT NULL,
    commit_message  IN VARCHAR2 DEFAULT NULL,
    author_name     IN VARCHAR2 DEFAULT NULL,
    author_email    IN VARCHAR2 DEFAULT NULL,
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: get_file
  -- Purpose: Resolve context and download a file by path.
  -- Inputs: file_path and optional branch_name/tag_name/commit_name selectors.
  -- Return: JSON CLOB containing file content and metadata.
  FUNCTION get_file(
    file_path       IN VARCHAR2,
    branch_name     IN VARCHAR2 DEFAULT NULL,
    tag_name        IN VARCHAR2 DEFAULT NULL,
    commit_name     IN VARCHAR2 DEFAULT NULL,
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: list_files
  -- Purpose: Resolve context and list files under optional path and revision context.
  -- Inputs: path and optional branch_name/tag_name/commit_id plus context overrides.
  -- Return: JSON CLOB containing file listing array.
  FUNCTION list_files(
    path            IN VARCHAR2 DEFAULT NULL,
    branch_name     IN VARCHAR2 DEFAULT NULL,
    tag_name        IN VARCHAR2 DEFAULT NULL,
    commit_id       IN VARCHAR2 DEFAULT NULL,
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: delete_file
  -- Purpose: Resolve context and delete a repository file with optional commit metadata.
  -- Inputs: file_path required; optional branch_name/commit details and context overrides.
  -- Return: success/error JSON response CLOB.
  FUNCTION delete_file(
    file_path       IN VARCHAR2,
    branch_name     IN VARCHAR2 DEFAULT NULL,
    commit_message  IN VARCHAR2 DEFAULT NULL,
    author_name     IN VARCHAR2 DEFAULT NULL,
    author_email    IN VARCHAR2 DEFAULT NULL,
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: export_object
  -- Purpose: Resolve context and export database object metadata/DDL to repository file.
  -- Inputs:
  --   file_path/object_type required.
  --   object_name/object_schema optional object scope.
  --   branch_name/commit details/append_flag optional export behavior.
  --   provider context supports GITHUB/AWS/AZURE.
  -- Return: success/error JSON response CLOB.
  FUNCTION export_object(
    file_path       IN VARCHAR2,
    object_type     IN VARCHAR2,
    object_name     IN VARCHAR2 DEFAULT NULL,
    object_schema   IN VARCHAR2 DEFAULT NULL,
    branch_name     IN VARCHAR2 DEFAULT NULL,
    commit_message  IN VARCHAR2 DEFAULT NULL,
    author_name     IN VARCHAR2 DEFAULT NULL,
    author_email    IN VARCHAR2 DEFAULT NULL,
    append_flag     IN NUMBER DEFAULT 0,
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: export_schema
  -- Purpose: Resolve context and export schema metadata/DDL to a repository file.
  -- Inputs:
  --   file_path/schema_name required.
  --   filter_list optional JSON array CLOB for include/exclude object filters.
  --   branch_name/commit metadata optional.
  --   provider context supports GITHUB/AWS/AZURE.
  -- Return: success/error JSON response CLOB.
  FUNCTION export_schema(
    file_path       IN VARCHAR2,
    schema_name     IN VARCHAR2,
    filter_list     IN CLOB DEFAULT NULL,
    branch_name     IN VARCHAR2 DEFAULT NULL,
    commit_message  IN VARCHAR2 DEFAULT NULL,
    author_name     IN VARCHAR2 DEFAULT NULL,
    author_email    IN VARCHAR2 DEFAULT NULL,
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: install_file
  -- Purpose: Resolve context and install SQL from a repository file.
  -- Inputs:
  --   file_path required.
  --   branch_name/tag_name/commit_name optional revision selectors.
  --   stop_on_error controls behavior on statement failure (1 stop / 0 continue).
  --   provider context supports GITHUB/AWS/AZURE.
  -- Return: success/error JSON response CLOB.
  FUNCTION install_file(
    file_path       IN VARCHAR2,
    branch_name     IN VARCHAR2 DEFAULT NULL,
    tag_name        IN VARCHAR2 DEFAULT NULL,
    commit_name     IN VARCHAR2 DEFAULT NULL,
    stop_on_error   IN NUMBER DEFAULT 1,
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB;

  -- Function: install_sql
  -- Purpose: Install SQL statements directly from a provided CLOB buffer.
  -- Inputs: sql_content required and stop_on_error optional (1 stop / 0 continue).
  -- Return: success/error JSON response CLOB.
  FUNCTION install_sql(
    sql_content    IN CLOB,
    stop_on_error  IN NUMBER DEFAULT 1
  ) RETURN CLOB;

  -- Function: get_agent_config
  -- Purpose: Read configuration rows for an agent from SELECTAI_AGENT_CONFIG.
  -- Inputs: schema_name, table_name, agent_name.
  -- Return: JSON CLOB with status and config_params key/value object.
  FUNCTION get_agent_config(
    schema_name IN VARCHAR2,
    table_name  IN VARCHAR2,
    agent_name  IN VARCHAR2
  ) RETURN CLOB;
END select_ai_github_connector;
/

CREATE OR REPLACE PACKAGE BODY select_ai_github_connector AS
  c_agent_name CONSTANT VARCHAR2(64) := 'CLOUD_REPO_CONNECTOR';

  -- Implements function: build error response.
  FUNCTION build_error_response(
    action_name IN VARCHAR2,
    message_txt IN VARCHAR2
  ) RETURN CLOB IS
    l_result_json JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    l_result_json.put('status', 'error');
    l_result_json.put('message', action_name || ' failed: ' || message_txt);
    RETURN l_result_json.to_clob();
  END build_error_response;

  -- Implements function: get agent config.
  FUNCTION get_agent_config(
    schema_name IN VARCHAR2,
    table_name  IN VARCHAR2,
    agent_name  IN VARCHAR2
  ) RETURN CLOB
  IS
    l_sql          VARCHAR2(4000);
    l_cursor       SYS_REFCURSOR;
    l_config_json  JSON_OBJECT_T := JSON_OBJECT_T();
    l_key          VARCHAR2(200);
    l_value        CLOB;
    l_result_json  JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    l_sql := 'SELECT "KEY", "VALUE" FROM ' || schema_name || '.' || table_name ||
             ' WHERE "AGENT" = :agent';

    OPEN l_cursor FOR l_sql USING agent_name;
    LOOP
      FETCH l_cursor INTO l_key, l_value;
      EXIT WHEN l_cursor%NOTFOUND;
      l_config_json.put(l_key, l_value);
    END LOOP;
    CLOSE l_cursor;

    l_result_json.put('status', 'success');
    l_result_json.put('config_params', l_config_json);
    RETURN l_result_json.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      IF l_cursor%ISOPEN THEN
        CLOSE l_cursor;
      END IF;
      l_result_json := JSON_OBJECT_T();
      l_result_json.put('status', 'error');
      l_result_json.put('message', 'Error: ' || SQLERRM);
      RETURN l_result_json.to_clob();
  END get_agent_config;

  PROCEDURE get_runtime_config(
    o_credential_name    OUT VARCHAR2,
    o_provider           OUT VARCHAR2,
    o_default_repo       OUT VARCHAR2,
    o_default_owner      OUT VARCHAR2,
    o_default_branch     OUT VARCHAR2,
    o_aws_region         OUT VARCHAR2,
    o_azure_organization OUT VARCHAR2,
    o_azure_project      OUT VARCHAR2
  ) IS
    l_sql           VARCHAR2(4000);
    l_cursor        SYS_REFCURSOR;
    l_key           VARCHAR2(200);
    l_value         CLOB;
    l_val_vc        VARCHAR2(4000);

    PROCEDURE close_cursor_if_open IS
    BEGIN
      IF l_cursor%ISOPEN THEN
        CLOSE l_cursor;
      END IF;
    EXCEPTION
      WHEN OTHERS THEN
        NULL;
    END close_cursor_if_open;

    PROCEDURE apply_config_from(
      p_table_name IN VARCHAR2,
      p_agent_name IN VARCHAR2
    ) IS
    BEGIN
      -- Read from local schema objects to avoid CURRENT_USER/CURRENT_SCHEMA drift in agent runtime.
      l_sql := 'SELECT "KEY", "VALUE" FROM ' || p_table_name ||
               ' WHERE UPPER(TRIM("AGENT")) = UPPER(TRIM(:agent))';

      OPEN l_cursor FOR l_sql USING p_agent_name;
      LOOP
        FETCH l_cursor INTO l_key, l_value;
        EXIT WHEN l_cursor%NOTFOUND;

        l_val_vc := CASE
                      WHEN l_value IS NULL THEN NULL
                      ELSE DBMS_LOB.SUBSTR(l_value, 4000, 1)
                    END;

        CASE UPPER(TRIM(l_key))
          WHEN 'CREDENTIAL_NAME' THEN
            IF o_credential_name IS NULL THEN
              o_credential_name := l_val_vc;
            END IF;
          WHEN 'PROVIDER' THEN
            IF o_provider IS NULL THEN
              o_provider := UPPER(l_val_vc);
            END IF;
          WHEN 'DEFAULT_REPO' THEN
            IF o_default_repo IS NULL THEN
              o_default_repo := l_val_vc;
            END IF;
          WHEN 'REPOSITORY_NAME' THEN
            -- Legacy key fallback used by earlier connector versions.
            IF o_default_repo IS NULL THEN
              o_default_repo := l_val_vc;
            END IF;
          WHEN 'DEFAULT_OWNER' THEN
            IF o_default_owner IS NULL THEN
              o_default_owner := l_val_vc;
            END IF;
          WHEN 'DEFAULT_BRANCH' THEN
            IF o_default_branch IS NULL THEN
              o_default_branch := l_val_vc;
            END IF;
          WHEN 'AWS_REGION' THEN
            IF o_aws_region IS NULL THEN
              o_aws_region := l_val_vc;
            END IF;
          WHEN 'AZURE_ORGANIZATION' THEN
            IF o_azure_organization IS NULL THEN
              o_azure_organization := l_val_vc;
            END IF;
          WHEN 'AZURE_PROJECT' THEN
            IF o_azure_project IS NULL THEN
              o_azure_project := l_val_vc;
            END IF;
          ELSE
            NULL;
        END CASE;
      END LOOP;

      close_cursor_if_open;
    EXCEPTION
      WHEN OTHERS THEN
        close_cursor_if_open;
        -- -942 means table/view does not exist; continue with next fallback.
        IF SQLCODE = -942 THEN
          NULL;
        ELSE
          RAISE;
        END IF;
    END apply_config_from;
  BEGIN
    o_credential_name := NULL;
    o_provider := NULL;
    o_default_repo := NULL;
    o_default_owner := NULL;
    o_default_branch := NULL;
    o_aws_region := NULL;
    o_azure_organization := NULL;
    o_azure_project := NULL;

    -- Preferred table/key path used by this connector.
    apply_config_from('SELECTAI_AGENT_CONFIG', c_agent_name);
    -- Backward-compatible agent name fallbacks.
    apply_config_from('SELECTAI_AGENT_CONFIG', 'GITHUB_CONNECTOR');
    apply_config_from('SELECTAI_AGENT_CONFIG', 'GITHUB');
    -- Backward compatibility for table name variant without underscore.
    apply_config_from('SELECTAIAGENT_CONFIG', c_agent_name);
    apply_config_from('SELECTAIAGENT_CONFIG', 'GITHUB_CONNECTOR');
    apply_config_from('SELECTAIAGENT_CONFIG', 'GITHUB');

    IF o_provider IS NULL THEN
      o_provider := 'GITHUB';
    END IF;

    IF o_credential_name IS NULL THEN
      RAISE_APPLICATION_ERROR(
        -20001,
        'Missing CREDENTIAL_NAME in SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG for AGENT=CLOUD_REPO_CONNECTOR, GITHUB_CONNECTOR, or GITHUB'
      );
    END IF;
  END get_runtime_config;

  PROCEDURE resolve_repo_context(
    p_repo_name          IN VARCHAR2,
    p_provider           IN VARCHAR2,
    p_owner              IN VARCHAR2,
    p_credential_name    IN VARCHAR2,
    p_region             IN VARCHAR2,
    p_organization       IN VARCHAR2,
    p_project            IN VARCHAR2,
    p_default_repo       IN VARCHAR2,
    p_default_provider   IN VARCHAR2,
    p_default_owner      IN VARCHAR2,
    p_default_credential IN VARCHAR2,
    p_default_region     IN VARCHAR2,
    p_default_org        IN VARCHAR2,
    p_default_project    IN VARCHAR2,
    o_repo_name          OUT VARCHAR2,
    o_provider           OUT VARCHAR2,
    o_owner              OUT VARCHAR2,
    o_credential_name    OUT VARCHAR2,
    o_region             OUT VARCHAR2,
    o_organization       OUT VARCHAR2,
    o_project            OUT VARCHAR2
  ) IS
    FUNCTION normalize_input(p_value IN VARCHAR2) RETURN VARCHAR2 IS
      l_val VARCHAR2(4000) := TRIM(p_value);
    BEGIN
      IF l_val IS NULL THEN
        RETURN NULL;
      END IF;

      -- Ignore common placeholder literals that the LLM may emit.
      IF UPPER(l_val) IN (
        'DEFAULT_REPO',
        'DEFAULT_OWNER',
        'DEFAULT_CREDENTIAL',
        'DEFAULT_CREDENTIAL_NAME',
        'DEFAULT_PROVIDER',
        'DEFAULT_REGION',
        'DEFAULT_ORGANIZATION',
        'DEFAULT_PROJECT',
        'REPO_NAME',
        'OWNER',
        'CREDENTIAL_NAME',
        'PROVIDER',
        'REGION',
        'ORGANIZATION',
        'PROJECT',
        'NULL',
        '<REPO_NAME>',
        '<OWNER>',
        '<CREDENTIAL_NAME>',
        '<PROVIDER>',
        '<REGION>',
        '<ORGANIZATION>',
        '<PROJECT>'
      ) THEN
        RETURN NULL;
      END IF;

      RETURN l_val;
    END normalize_input;
  BEGIN
    o_repo_name := NVL(normalize_input(p_repo_name), TRIM(p_default_repo));
    o_provider := UPPER(NVL(normalize_input(p_provider), TRIM(p_default_provider)));
    o_owner := NVL(normalize_input(p_owner), TRIM(p_default_owner));
    o_credential_name := NVL(normalize_input(p_credential_name), TRIM(p_default_credential));
    o_region := NVL(normalize_input(p_region), TRIM(p_default_region));
    o_organization := NVL(normalize_input(p_organization), TRIM(p_default_org));
    o_project := NVL(normalize_input(p_project), TRIM(p_default_project));

    IF o_provider IS NULL THEN
      o_provider := 'GITHUB';
    END IF;

    IF o_provider NOT IN ('GITHUB', 'AWS', 'AZURE') THEN
      RAISE_APPLICATION_ERROR(-20020, 'Unsupported provider ' || o_provider || '. Use GITHUB, AWS, or AZURE.');
    END IF;

    IF o_repo_name IS NULL THEN
      RAISE_APPLICATION_ERROR(-20021,
        'repo_name is required. Provide repo_name input or set DEFAULT_REPO in SELECTAI_AGENT_CONFIG.');
    END IF;

    IF o_provider = 'GITHUB' AND o_owner IS NULL THEN
      RAISE_APPLICATION_ERROR(-20022,
        'owner is required for provider GITHUB. Provide owner input or set DEFAULT_OWNER in SELECTAI_AGENT_CONFIG.');
    END IF;

    IF o_provider = 'AWS' AND o_region IS NULL THEN
      RAISE_APPLICATION_ERROR(-20023,
        'region is required for provider AWS. Provide region input or set AWS_REGION in SELECTAI_AGENT_CONFIG.');
    END IF;

    IF o_provider = 'AZURE' AND (o_organization IS NULL OR o_project IS NULL) THEN
      RAISE_APPLICATION_ERROR(-20024,
        'organization and project are required for provider AZURE. Provide inputs or set AZURE_ORGANIZATION and AZURE_PROJECT in SELECTAI_AGENT_CONFIG.');
    END IF;
  END resolve_repo_context;

  PROCEDURE resolve_and_init_repo_handle(
    p_repo_name       IN VARCHAR2,
    p_provider        IN VARCHAR2,
    p_owner           IN VARCHAR2,
    p_credential_name IN VARCHAR2,
    p_region          IN VARCHAR2,
    p_organization    IN VARCHAR2,
    p_project         IN VARCHAR2,
    o_repo_handle     OUT CLOB,
    o_default_branch  OUT VARCHAR2
  ) IS
    l_def_credential_name VARCHAR2(4000);
    l_def_provider        VARCHAR2(4000);
    l_def_repo            VARCHAR2(4000);
    l_def_owner           VARCHAR2(4000);
    l_def_branch          VARCHAR2(4000);
    l_def_region          VARCHAR2(4000);
    l_def_org             VARCHAR2(4000);
    l_def_project         VARCHAR2(4000);
    l_repo_name           VARCHAR2(4000);
    l_provider            VARCHAR2(4000);
    l_owner               VARCHAR2(4000);
    l_credential_name     VARCHAR2(4000);
    l_region              VARCHAR2(4000);
    l_organization        VARCHAR2(4000);
    l_project             VARCHAR2(4000);
  BEGIN
    get_runtime_config(
      o_credential_name    => l_def_credential_name,
      o_provider           => l_def_provider,
      o_default_repo       => l_def_repo,
      o_default_owner      => l_def_owner,
      o_default_branch     => l_def_branch,
      o_aws_region         => l_def_region,
      o_azure_organization => l_def_org,
      o_azure_project      => l_def_project
    );

    resolve_repo_context(
      p_repo_name          => p_repo_name,
      p_provider           => p_provider,
      p_owner              => p_owner,
      p_credential_name    => p_credential_name,
      p_region             => p_region,
      p_organization       => p_organization,
      p_project            => p_project,
      p_default_repo       => l_def_repo,
      p_default_provider   => l_def_provider,
      p_default_owner      => l_def_owner,
      p_default_credential => l_def_credential_name,
      p_default_region     => l_def_region,
      p_default_org        => l_def_org,
      p_default_project    => l_def_project,
      o_repo_name          => l_repo_name,
      o_provider           => l_provider,
      o_owner              => l_owner,
      o_credential_name    => l_credential_name,
      o_region             => l_region,
      o_organization       => l_organization,
      o_project            => l_project
    );

    o_default_branch := l_def_branch;
    o_repo_handle := github_repo_selectai.init_repo_handle(
      provider        => l_provider,
      repo_name       => l_repo_name,
      owner           => l_owner,
      credential_name => l_credential_name,
      region          => l_region,
      organization    => l_organization,
      project         => l_project
    );
  END resolve_and_init_repo_handle;

  -- Implements function: init repo.
  FUNCTION init_repo(
    params_json IN CLOB
  ) RETURN CLOB IS
    l_repo_handle CLOB;
    l_result      JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    l_repo_handle := github_repo_selectai.init_repo_handle(params_json => params_json);
    l_result.put('status', 'success');
    l_result.put('repo_handle', l_repo_handle);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('init_repo', SQLERRM);
  END init_repo;

  -- Implements function: init github repo.
  FUNCTION init_github_repo(
    repo_name       IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_repo_handle         CLOB;
    l_result              JSON_OBJECT_T := JSON_OBJECT_T();
    l_def_credential_name VARCHAR2(4000);
    l_def_provider        VARCHAR2(4000);
    l_def_repo            VARCHAR2(4000);
    l_def_owner           VARCHAR2(4000);
    l_def_branch          VARCHAR2(4000);
    l_def_region          VARCHAR2(4000);
    l_def_org             VARCHAR2(4000);
    l_def_project         VARCHAR2(4000);
  BEGIN
    get_runtime_config(
      o_credential_name    => l_def_credential_name,
      o_provider           => l_def_provider,
      o_default_repo       => l_def_repo,
      o_default_owner      => l_def_owner,
      o_default_branch     => l_def_branch,
      o_aws_region         => l_def_region,
      o_azure_organization => l_def_org,
      o_azure_project      => l_def_project
    );

    l_repo_handle := github_repo_selectai.init_repo_handle(
      provider        => 'GITHUB',
      repo_name       => NVL(repo_name, l_def_repo),
      owner           => NVL(owner, l_def_owner),
      credential_name => NVL(credential_name, l_def_credential_name)
    );

    l_result.put('status', 'success');
    l_result.put('repo_handle', l_repo_handle);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('init_github_repo', SQLERRM);
  END init_github_repo;

  -- Implements function: init aws repo.
  FUNCTION init_aws_repo(
    repo_name       IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_repo_handle         CLOB;
    l_result              JSON_OBJECT_T := JSON_OBJECT_T();
    l_def_credential_name VARCHAR2(4000);
    l_def_provider        VARCHAR2(4000);
    l_def_repo            VARCHAR2(4000);
    l_def_owner           VARCHAR2(4000);
    l_def_branch          VARCHAR2(4000);
    l_def_region          VARCHAR2(4000);
    l_def_org             VARCHAR2(4000);
    l_def_project         VARCHAR2(4000);
  BEGIN
    get_runtime_config(
      o_credential_name    => l_def_credential_name,
      o_provider           => l_def_provider,
      o_default_repo       => l_def_repo,
      o_default_owner      => l_def_owner,
      o_default_branch     => l_def_branch,
      o_aws_region         => l_def_region,
      o_azure_organization => l_def_org,
      o_azure_project      => l_def_project
    );

    l_repo_handle := github_repo_selectai.init_repo_handle(
      provider        => 'AWS',
      repo_name       => NVL(repo_name, l_def_repo),
      region          => NVL(region, l_def_region),
      credential_name => NVL(credential_name, l_def_credential_name)
    );

    l_result.put('status', 'success');
    l_result.put('repo_handle', l_repo_handle);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('init_aws_repo', SQLERRM);
  END init_aws_repo;

  -- Implements function: init azure repo.
  FUNCTION init_azure_repo(
    repo_name       IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_repo_handle         CLOB;
    l_result              JSON_OBJECT_T := JSON_OBJECT_T();
    l_def_credential_name VARCHAR2(4000);
    l_def_provider        VARCHAR2(4000);
    l_def_repo            VARCHAR2(4000);
    l_def_owner           VARCHAR2(4000);
    l_def_branch          VARCHAR2(4000);
    l_def_region          VARCHAR2(4000);
    l_def_org             VARCHAR2(4000);
    l_def_project         VARCHAR2(4000);
  BEGIN
    get_runtime_config(
      o_credential_name    => l_def_credential_name,
      o_provider           => l_def_provider,
      o_default_repo       => l_def_repo,
      o_default_owner      => l_def_owner,
      o_default_branch     => l_def_branch,
      o_aws_region         => l_def_region,
      o_azure_organization => l_def_org,
      o_azure_project      => l_def_project
    );

    l_repo_handle := github_repo_selectai.init_repo_handle(
      provider        => 'AZURE',
      repo_name       => NVL(repo_name, l_def_repo),
      organization    => NVL(organization, l_def_org),
      project         => NVL(project, l_def_project),
      credential_name => NVL(credential_name, l_def_credential_name)
    );

    l_result.put('status', 'success');
    l_result.put('repo_handle', l_repo_handle);
    RETURN l_result.to_clob();
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('init_azure_repo', SQLERRM);
  END init_azure_repo;

  -- Implements function: create repository.
  FUNCTION create_repository(
    description     IN VARCHAR2 DEFAULT NULL,
    private_flag    IN NUMBER DEFAULT 1,
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_repo_handle         CLOB;
    l_def_credential_name VARCHAR2(4000);
    l_def_provider        VARCHAR2(4000);
    l_def_repo            VARCHAR2(4000);
    l_def_owner           VARCHAR2(4000);
    l_def_branch          VARCHAR2(4000);
    l_def_region          VARCHAR2(4000);
    l_def_org             VARCHAR2(4000);
    l_def_project         VARCHAR2(4000);
    l_repo_name           VARCHAR2(4000);
    l_provider            VARCHAR2(4000);
    l_owner               VARCHAR2(4000);
    l_credential_name     VARCHAR2(4000);
    l_region              VARCHAR2(4000);
    l_organization        VARCHAR2(4000);
    l_project             VARCHAR2(4000);
  BEGIN
    get_runtime_config(
      o_credential_name    => l_def_credential_name,
      o_provider           => l_def_provider,
      o_default_repo       => l_def_repo,
      o_default_owner      => l_def_owner,
      o_default_branch     => l_def_branch,
      o_aws_region         => l_def_region,
      o_azure_organization => l_def_org,
      o_azure_project      => l_def_project
    );

    resolve_repo_context(
      p_repo_name          => repo_name,
      p_provider           => provider,
      p_owner              => owner,
      p_credential_name    => credential_name,
      p_region             => region,
      p_organization       => organization,
      p_project            => project,
      p_default_repo       => l_def_repo,
      p_default_provider   => l_def_provider,
      p_default_owner      => l_def_owner,
      p_default_credential => l_def_credential_name,
      p_default_region     => l_def_region,
      p_default_org        => l_def_org,
      p_default_project    => l_def_project,
      o_repo_name          => l_repo_name,
      o_provider           => l_provider,
      o_owner              => l_owner,
      o_credential_name    => l_credential_name,
      o_region             => l_region,
      o_organization       => l_organization,
      o_project            => l_project
    );

    l_repo_handle := github_repo_selectai.init_repo_handle(
      provider        => l_provider,
      repo_name       => l_repo_name,
      owner           => l_owner,
      credential_name => l_credential_name,
      region          => l_region,
      organization    => l_organization,
      project         => l_project
    );

    RETURN github_repo_selectai.create_repository(
      repo_handle  => l_repo_handle,
      description  => description,
      private_flag => private_flag
    );
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('create_repository', SQLERRM);
  END create_repository;

  -- Implements function: update repository.
  FUNCTION update_repository(
    new_name        IN VARCHAR2 DEFAULT NULL,
    description     IN VARCHAR2 DEFAULT NULL,
    private_flag    IN NUMBER DEFAULT NULL,
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_repo_handle         CLOB;
    l_def_credential_name VARCHAR2(4000);
    l_def_provider        VARCHAR2(4000);
    l_def_repo            VARCHAR2(4000);
    l_def_owner           VARCHAR2(4000);
    l_def_branch          VARCHAR2(4000);
    l_def_region          VARCHAR2(4000);
    l_def_org             VARCHAR2(4000);
    l_def_project         VARCHAR2(4000);
    l_repo_name           VARCHAR2(4000);
    l_provider            VARCHAR2(4000);
    l_owner               VARCHAR2(4000);
    l_credential_name     VARCHAR2(4000);
    l_region              VARCHAR2(4000);
    l_organization        VARCHAR2(4000);
    l_project             VARCHAR2(4000);
  BEGIN
    get_runtime_config(
      o_credential_name    => l_def_credential_name,
      o_provider           => l_def_provider,
      o_default_repo       => l_def_repo,
      o_default_owner      => l_def_owner,
      o_default_branch     => l_def_branch,
      o_aws_region         => l_def_region,
      o_azure_organization => l_def_org,
      o_azure_project      => l_def_project
    );

    resolve_repo_context(
      p_repo_name          => repo_name,
      p_provider           => provider,
      p_owner              => owner,
      p_credential_name    => credential_name,
      p_region             => region,
      p_organization       => organization,
      p_project            => project,
      p_default_repo       => l_def_repo,
      p_default_provider   => l_def_provider,
      p_default_owner      => l_def_owner,
      p_default_credential => l_def_credential_name,
      p_default_region     => l_def_region,
      p_default_org        => l_def_org,
      p_default_project    => l_def_project,
      o_repo_name          => l_repo_name,
      o_provider           => l_provider,
      o_owner              => l_owner,
      o_credential_name    => l_credential_name,
      o_region             => l_region,
      o_organization       => l_organization,
      o_project            => l_project
    );

    l_repo_handle := github_repo_selectai.init_repo_handle(
      provider        => l_provider,
      repo_name       => l_repo_name,
      owner           => l_owner,
      credential_name => l_credential_name,
      region          => l_region,
      organization    => l_organization,
      project         => l_project
    );

    RETURN github_repo_selectai.update_repository(
      repo_handle  => l_repo_handle,
      new_name     => new_name,
      description  => description,
      private_flag => private_flag
    );
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('update_repository', SQLERRM);
  END update_repository;

  -- Implements function: list repositories.
  FUNCTION list_repositories(
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_repo_handle         CLOB;
    l_def_credential_name VARCHAR2(4000);
    l_def_provider        VARCHAR2(4000);
    l_def_repo            VARCHAR2(4000);
    l_def_owner           VARCHAR2(4000);
    l_def_branch          VARCHAR2(4000);
    l_def_region          VARCHAR2(4000);
    l_def_org             VARCHAR2(4000);
    l_def_project         VARCHAR2(4000);
    l_repo_name           VARCHAR2(4000);
    l_provider            VARCHAR2(4000);
    l_owner               VARCHAR2(4000);
    l_credential_name     VARCHAR2(4000);
    l_region              VARCHAR2(4000);
    l_organization        VARCHAR2(4000);
    l_project             VARCHAR2(4000);
  BEGIN
    get_runtime_config(
      o_credential_name    => l_def_credential_name,
      o_provider           => l_def_provider,
      o_default_repo       => l_def_repo,
      o_default_owner      => l_def_owner,
      o_default_branch     => l_def_branch,
      o_aws_region         => l_def_region,
      o_azure_organization => l_def_org,
      o_azure_project      => l_def_project
    );

    resolve_repo_context(
      p_repo_name          => repo_name,
      p_provider           => provider,
      -- For list_repositories, prefer configured DEFAULT_OWNER from config table.
      p_owner              => NULL,
      p_credential_name    => credential_name,
      p_region             => region,
      p_organization       => organization,
      p_project            => project,
      p_default_repo       => l_def_repo,
      p_default_provider   => l_def_provider,
      p_default_owner      => l_def_owner,
      p_default_credential => l_def_credential_name,
      p_default_region     => l_def_region,
      p_default_org        => l_def_org,
      p_default_project    => l_def_project,
      o_repo_name          => l_repo_name,
      o_provider           => l_provider,
      o_owner              => l_owner,
      o_credential_name    => l_credential_name,
      o_region             => l_region,
      o_organization       => l_organization,
      o_project            => l_project
    );

    l_repo_handle := github_repo_selectai.init_repo_handle(
      provider        => l_provider,
      repo_name       => l_repo_name,
      owner           => l_owner,
      credential_name => l_credential_name,
      region          => l_region,
      organization    => l_organization,
      project         => l_project
    );

    RETURN github_repo_selectai.list_repositories(
      repo_handle  => l_repo_handle,
      owner_filter => l_owner
    );
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('list_repositories', SQLERRM);
  END list_repositories;

  -- Implements function: get repository.
  FUNCTION get_repository(
    repo_name       IN VARCHAR2,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_repo_handle         CLOB;
    l_def_credential_name VARCHAR2(4000);
    l_def_provider        VARCHAR2(4000);
    l_def_repo            VARCHAR2(4000);
    l_def_owner           VARCHAR2(4000);
    l_def_branch          VARCHAR2(4000);
    l_def_region          VARCHAR2(4000);
    l_def_org             VARCHAR2(4000);
    l_def_project         VARCHAR2(4000);
    l_repo_name           VARCHAR2(4000);
    l_provider            VARCHAR2(4000);
    l_owner               VARCHAR2(4000);
    l_credential_name     VARCHAR2(4000);
    l_region              VARCHAR2(4000);
    l_organization        VARCHAR2(4000);
    l_project             VARCHAR2(4000);
  BEGIN
    get_runtime_config(
      o_credential_name    => l_def_credential_name,
      o_provider           => l_def_provider,
      o_default_repo       => l_def_repo,
      o_default_owner      => l_def_owner,
      o_default_branch     => l_def_branch,
      o_aws_region         => l_def_region,
      o_azure_organization => l_def_org,
      o_azure_project      => l_def_project
    );

    resolve_repo_context(
      p_repo_name          => repo_name,
      p_provider           => provider,
      p_owner              => owner,
      p_credential_name    => credential_name,
      p_region             => region,
      p_organization       => organization,
      p_project            => project,
      p_default_repo       => l_def_repo,
      p_default_provider   => l_def_provider,
      p_default_owner      => l_def_owner,
      p_default_credential => l_def_credential_name,
      p_default_region     => l_def_region,
      p_default_org        => l_def_org,
      p_default_project    => l_def_project,
      o_repo_name          => l_repo_name,
      o_provider           => l_provider,
      o_owner              => l_owner,
      o_credential_name    => l_credential_name,
      o_region             => l_region,
      o_organization       => l_organization,
      o_project            => l_project
    );

    l_repo_handle := github_repo_selectai.init_repo_handle(
      provider        => l_provider,
      repo_name       => l_repo_name,
      owner           => l_owner,
      credential_name => l_credential_name,
      region          => l_region,
      organization    => l_organization,
      project         => l_project
    );

    RETURN github_repo_selectai.get_repository(
      repo_handle => l_repo_handle,
      repo_name   => l_repo_name,
      owner       => l_owner
    );
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('get_repository', SQLERRM);
  END get_repository;

  -- Implements function: delete repository.
  FUNCTION delete_repository(
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_repo_handle         CLOB;
    l_def_credential_name VARCHAR2(4000);
    l_def_provider        VARCHAR2(4000);
    l_def_repo            VARCHAR2(4000);
    l_def_owner           VARCHAR2(4000);
    l_def_branch          VARCHAR2(4000);
    l_def_region          VARCHAR2(4000);
    l_def_org             VARCHAR2(4000);
    l_def_project         VARCHAR2(4000);
    l_repo_name           VARCHAR2(4000);
    l_provider            VARCHAR2(4000);
    l_owner               VARCHAR2(4000);
    l_credential_name     VARCHAR2(4000);
    l_region              VARCHAR2(4000);
    l_organization        VARCHAR2(4000);
    l_project             VARCHAR2(4000);
  BEGIN
    get_runtime_config(
      o_credential_name    => l_def_credential_name,
      o_provider           => l_def_provider,
      o_default_repo       => l_def_repo,
      o_default_owner      => l_def_owner,
      o_default_branch     => l_def_branch,
      o_aws_region         => l_def_region,
      o_azure_organization => l_def_org,
      o_azure_project      => l_def_project
    );

    resolve_repo_context(
      p_repo_name          => repo_name,
      p_provider           => provider,
      p_owner              => owner,
      p_credential_name    => credential_name,
      p_region             => region,
      p_organization       => organization,
      p_project            => project,
      p_default_repo       => l_def_repo,
      p_default_provider   => l_def_provider,
      p_default_owner      => l_def_owner,
      p_default_credential => l_def_credential_name,
      p_default_region     => l_def_region,
      p_default_org        => l_def_org,
      p_default_project    => l_def_project,
      o_repo_name          => l_repo_name,
      o_provider           => l_provider,
      o_owner              => l_owner,
      o_credential_name    => l_credential_name,
      o_region             => l_region,
      o_organization       => l_organization,
      o_project            => l_project
    );

    l_repo_handle := github_repo_selectai.init_repo_handle(
      provider        => l_provider,
      repo_name       => l_repo_name,
      owner           => l_owner,
      credential_name => l_credential_name,
      region          => l_region,
      organization    => l_organization,
      project         => l_project
    );

    RETURN github_repo_selectai.delete_repository(l_repo_handle);
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('delete_repository', SQLERRM);
  END delete_repository;

  -- Implements function: create branch.
  FUNCTION create_branch(
    branch_name      IN VARCHAR2,
    source_branch    IN VARCHAR2 DEFAULT NULL,
    source_commit_id IN VARCHAR2 DEFAULT NULL,
    repo_name        IN VARCHAR2 DEFAULT NULL,
    provider         IN VARCHAR2 DEFAULT NULL,
    owner            IN VARCHAR2 DEFAULT NULL,
    credential_name  IN VARCHAR2 DEFAULT NULL,
    region           IN VARCHAR2 DEFAULT NULL,
    organization     IN VARCHAR2 DEFAULT NULL,
    project          IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_repo_handle      CLOB;
    l_default_branch   VARCHAR2(4000);
    l_effective_source VARCHAR2(4000);
  BEGIN
    resolve_and_init_repo_handle(
      p_repo_name       => repo_name,
      p_provider        => provider,
      p_owner           => owner,
      p_credential_name => credential_name,
      p_region          => region,
      p_organization    => organization,
      p_project         => project,
      o_repo_handle     => l_repo_handle,
      o_default_branch  => l_default_branch
    );

    l_effective_source := NVL(TRIM(source_branch), l_default_branch);
    RETURN github_repo_selectai.create_branch(
      repo_handle      => l_repo_handle,
      branch_name      => branch_name,
      source_branch    => l_effective_source,
      source_commit_id => source_commit_id
    );
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('create_branch', SQLERRM);
  END create_branch;

  -- Implements function: delete branch.
  FUNCTION delete_branch(
    branch_name      IN VARCHAR2,
    repo_name        IN VARCHAR2 DEFAULT NULL,
    provider         IN VARCHAR2 DEFAULT NULL,
    owner            IN VARCHAR2 DEFAULT NULL,
    credential_name  IN VARCHAR2 DEFAULT NULL,
    region           IN VARCHAR2 DEFAULT NULL,
    organization     IN VARCHAR2 DEFAULT NULL,
    project          IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_repo_handle    CLOB;
    l_default_branch VARCHAR2(4000);
  BEGIN
    resolve_and_init_repo_handle(
      p_repo_name       => repo_name,
      p_provider        => provider,
      p_owner           => owner,
      p_credential_name => credential_name,
      p_region          => region,
      p_organization    => organization,
      p_project         => project,
      o_repo_handle     => l_repo_handle,
      o_default_branch  => l_default_branch
    );

    RETURN github_repo_selectai.delete_branch(
      repo_handle => l_repo_handle,
      branch_name => branch_name
    );
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('delete_branch', SQLERRM);
  END delete_branch;

  -- Implements function: list branches.
  FUNCTION list_branches(
    repo_name        IN VARCHAR2 DEFAULT NULL,
    provider         IN VARCHAR2 DEFAULT NULL,
    owner            IN VARCHAR2 DEFAULT NULL,
    credential_name  IN VARCHAR2 DEFAULT NULL,
    region           IN VARCHAR2 DEFAULT NULL,
    organization     IN VARCHAR2 DEFAULT NULL,
    project          IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_repo_handle    CLOB;
    l_default_branch VARCHAR2(4000);
  BEGIN
    resolve_and_init_repo_handle(
      p_repo_name       => repo_name,
      p_provider        => provider,
      p_owner           => owner,
      p_credential_name => credential_name,
      p_region          => region,
      p_organization    => organization,
      p_project         => project,
      o_repo_handle     => l_repo_handle,
      o_default_branch  => l_default_branch
    );

    RETURN github_repo_selectai.list_branches(
      repo_handle => l_repo_handle
    );
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('list_branches', SQLERRM);
  END list_branches;

  -- Implements function: list commits.
  FUNCTION list_commits(
    branch_name      IN VARCHAR2 DEFAULT NULL,
    repo_name        IN VARCHAR2 DEFAULT NULL,
    provider         IN VARCHAR2 DEFAULT NULL,
    owner            IN VARCHAR2 DEFAULT NULL,
    credential_name  IN VARCHAR2 DEFAULT NULL,
    region           IN VARCHAR2 DEFAULT NULL,
    organization     IN VARCHAR2 DEFAULT NULL,
    project          IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_repo_handle      CLOB;
    l_default_branch   VARCHAR2(4000);
    l_effective_branch VARCHAR2(4000);
  BEGIN
    resolve_and_init_repo_handle(
      p_repo_name       => repo_name,
      p_provider        => provider,
      p_owner           => owner,
      p_credential_name => credential_name,
      p_region          => region,
      p_organization    => organization,
      p_project         => project,
      o_repo_handle     => l_repo_handle,
      o_default_branch  => l_default_branch
    );

    l_effective_branch := NVL(TRIM(branch_name), l_default_branch);

    RETURN github_repo_selectai.list_commits(
      repo_handle => l_repo_handle,
      branch_name => l_effective_branch
    );
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('list_commits', SQLERRM);
  END list_commits;

  -- Implements function: merge branch.
  FUNCTION merge_branch(
    source_branch    IN VARCHAR2,
    target_branch    IN VARCHAR2,
    commit_message   IN VARCHAR2 DEFAULT NULL,
    author_name      IN VARCHAR2 DEFAULT NULL,
    author_email     IN VARCHAR2 DEFAULT NULL,
    repo_name        IN VARCHAR2 DEFAULT NULL,
    provider         IN VARCHAR2 DEFAULT NULL,
    owner            IN VARCHAR2 DEFAULT NULL,
    credential_name  IN VARCHAR2 DEFAULT NULL,
    region           IN VARCHAR2 DEFAULT NULL,
    organization     IN VARCHAR2 DEFAULT NULL,
    project          IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_repo_handle    CLOB;
    l_default_branch VARCHAR2(4000);
    l_commit_details CLOB;
  BEGIN
    resolve_and_init_repo_handle(
      p_repo_name       => repo_name,
      p_provider        => provider,
      p_owner           => owner,
      p_credential_name => credential_name,
      p_region          => region,
      p_organization    => organization,
      p_project         => project,
      o_repo_handle     => l_repo_handle,
      o_default_branch  => l_default_branch
    );

    l_commit_details := github_repo_selectai.build_commit_details(
      message_txt  => commit_message,
      author_name  => author_name,
      author_email => author_email
    );

    RETURN github_repo_selectai.merge_branch(
      repo_handle    => l_repo_handle,
      source_branch  => source_branch,
      target_branch  => target_branch,
      commit_details => l_commit_details
    );
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('merge_branch', SQLERRM);
  END merge_branch;

  -- Implements function: put file.
  FUNCTION put_file(
    file_path       IN VARCHAR2,
    file_content    IN CLOB,
    branch_name     IN VARCHAR2 DEFAULT NULL,
    commit_message  IN VARCHAR2 DEFAULT NULL,
    author_name     IN VARCHAR2 DEFAULT NULL,
    author_email    IN VARCHAR2 DEFAULT NULL,
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_repo_handle         CLOB;
    l_commit_details      CLOB;
    l_effective_branch    VARCHAR2(4000);
    l_def_credential_name VARCHAR2(4000);
    l_def_provider        VARCHAR2(4000);
    l_def_repo            VARCHAR2(4000);
    l_def_owner           VARCHAR2(4000);
    l_def_branch          VARCHAR2(4000);
    l_def_region          VARCHAR2(4000);
    l_def_org             VARCHAR2(4000);
    l_def_project         VARCHAR2(4000);
    l_repo_name           VARCHAR2(4000);
    l_provider            VARCHAR2(4000);
    l_owner               VARCHAR2(4000);
    l_credential_name     VARCHAR2(4000);
    l_region              VARCHAR2(4000);
    l_organization        VARCHAR2(4000);
    l_project             VARCHAR2(4000);
  BEGIN
    get_runtime_config(
      o_credential_name    => l_def_credential_name,
      o_provider           => l_def_provider,
      o_default_repo       => l_def_repo,
      o_default_owner      => l_def_owner,
      o_default_branch     => l_def_branch,
      o_aws_region         => l_def_region,
      o_azure_organization => l_def_org,
      o_azure_project      => l_def_project
    );

    resolve_repo_context(
      p_repo_name          => repo_name,
      p_provider           => provider,
      p_owner              => owner,
      p_credential_name    => credential_name,
      p_region             => region,
      p_organization       => organization,
      p_project            => project,
      p_default_repo       => l_def_repo,
      p_default_provider   => l_def_provider,
      p_default_owner      => l_def_owner,
      p_default_credential => l_def_credential_name,
      p_default_region     => l_def_region,
      p_default_org        => l_def_org,
      p_default_project    => l_def_project,
      o_repo_name          => l_repo_name,
      o_provider           => l_provider,
      o_owner              => l_owner,
      o_credential_name    => l_credential_name,
      o_region             => l_region,
      o_organization       => l_organization,
      o_project            => l_project
    );

    l_repo_handle := github_repo_selectai.init_repo_handle(
      provider        => l_provider,
      repo_name       => l_repo_name,
      owner           => l_owner,
      credential_name => l_credential_name,
      region          => l_region,
      organization    => l_organization,
      project         => l_project
    );

    l_effective_branch := NVL(TRIM(branch_name), l_def_branch);

    l_commit_details := github_repo_selectai.build_commit_details(
      message_txt  => commit_message,
      author_name  => author_name,
      author_email => author_email
    );

    RETURN github_repo_selectai.put_file(
      repo_handle    => l_repo_handle,
      file_path      => file_path,
      file_content   => file_content,
      branch_name    => l_effective_branch,
      commit_details => l_commit_details
    );
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('put_file', SQLERRM);
  END put_file;

  -- Implements function: get file.
  FUNCTION get_file(
    file_path       IN VARCHAR2,
    branch_name     IN VARCHAR2 DEFAULT NULL,
    tag_name        IN VARCHAR2 DEFAULT NULL,
    commit_name     IN VARCHAR2 DEFAULT NULL,
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_repo_handle         CLOB;
    l_effective_branch    VARCHAR2(4000);
    l_def_credential_name VARCHAR2(4000);
    l_def_provider        VARCHAR2(4000);
    l_def_repo            VARCHAR2(4000);
    l_def_owner           VARCHAR2(4000);
    l_def_branch          VARCHAR2(4000);
    l_def_region          VARCHAR2(4000);
    l_def_org             VARCHAR2(4000);
    l_def_project         VARCHAR2(4000);
    l_repo_name           VARCHAR2(4000);
    l_provider            VARCHAR2(4000);
    l_owner               VARCHAR2(4000);
    l_credential_name     VARCHAR2(4000);
    l_region              VARCHAR2(4000);
    l_organization        VARCHAR2(4000);
    l_project             VARCHAR2(4000);
  BEGIN
    get_runtime_config(
      o_credential_name    => l_def_credential_name,
      o_provider           => l_def_provider,
      o_default_repo       => l_def_repo,
      o_default_owner      => l_def_owner,
      o_default_branch     => l_def_branch,
      o_aws_region         => l_def_region,
      o_azure_organization => l_def_org,
      o_azure_project      => l_def_project
    );

    resolve_repo_context(
      p_repo_name          => repo_name,
      p_provider           => provider,
      p_owner              => owner,
      p_credential_name    => credential_name,
      p_region             => region,
      p_organization       => organization,
      p_project            => project,
      p_default_repo       => l_def_repo,
      p_default_provider   => l_def_provider,
      p_default_owner      => l_def_owner,
      p_default_credential => l_def_credential_name,
      p_default_region     => l_def_region,
      p_default_org        => l_def_org,
      p_default_project    => l_def_project,
      o_repo_name          => l_repo_name,
      o_provider           => l_provider,
      o_owner              => l_owner,
      o_credential_name    => l_credential_name,
      o_region             => l_region,
      o_organization       => l_organization,
      o_project            => l_project
    );

    l_repo_handle := github_repo_selectai.init_repo_handle(
      provider        => l_provider,
      repo_name       => l_repo_name,
      owner           => l_owner,
      credential_name => l_credential_name,
      region          => l_region,
      organization    => l_organization,
      project         => l_project
    );

    l_effective_branch := NVL(TRIM(branch_name), l_def_branch);

    RETURN github_repo_selectai.get_file(
      repo_handle  => l_repo_handle,
      file_path    => file_path,
      branch_name  => l_effective_branch,
      tag_name     => tag_name,
      commit_name  => commit_name
    );
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('get_file', SQLERRM);
  END get_file;

  -- Implements function: list files.
  FUNCTION list_files(
    path            IN VARCHAR2 DEFAULT NULL,
    branch_name     IN VARCHAR2 DEFAULT NULL,
    tag_name        IN VARCHAR2 DEFAULT NULL,
    commit_id       IN VARCHAR2 DEFAULT NULL,
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_repo_handle      CLOB;
    l_default_branch   VARCHAR2(4000);
    l_effective_branch VARCHAR2(4000);
  BEGIN
    resolve_and_init_repo_handle(
      p_repo_name          => repo_name,
      p_provider           => provider,
      p_owner              => owner,
      -- Always source credential from SELECTAI_AGENT_CONFIG for list_files.
      -- This avoids LLM-injected placeholder credentials (for example DEFAULT_CREDENTIAL).
      p_credential_name    => NULL,
      p_region             => region,
      p_organization       => organization,
      p_project            => project,
      o_repo_handle        => l_repo_handle,
      o_default_branch     => l_default_branch
    );

    l_effective_branch := NVL(TRIM(branch_name), l_default_branch);

    RETURN github_repo_selectai.list_files(
      repo_handle  => l_repo_handle,
      path         => path,
      branch_name  => l_effective_branch,
      tag_name     => tag_name,
      commit_id    => commit_id
    );
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('list_files', SQLERRM);
  END list_files;

  -- Implements function: delete file.
  FUNCTION delete_file(
    file_path       IN VARCHAR2,
    branch_name     IN VARCHAR2 DEFAULT NULL,
    commit_message  IN VARCHAR2 DEFAULT NULL,
    author_name     IN VARCHAR2 DEFAULT NULL,
    author_email    IN VARCHAR2 DEFAULT NULL,
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_repo_handle         CLOB;
    l_commit_details      CLOB;
    l_effective_branch    VARCHAR2(4000);
    l_def_credential_name VARCHAR2(4000);
    l_def_provider        VARCHAR2(4000);
    l_def_repo            VARCHAR2(4000);
    l_def_owner           VARCHAR2(4000);
    l_def_branch          VARCHAR2(4000);
    l_def_region          VARCHAR2(4000);
    l_def_org             VARCHAR2(4000);
    l_def_project         VARCHAR2(4000);
    l_repo_name           VARCHAR2(4000);
    l_provider            VARCHAR2(4000);
    l_owner               VARCHAR2(4000);
    l_credential_name     VARCHAR2(4000);
    l_region              VARCHAR2(4000);
    l_organization        VARCHAR2(4000);
    l_project             VARCHAR2(4000);
  BEGIN
    get_runtime_config(
      o_credential_name    => l_def_credential_name,
      o_provider           => l_def_provider,
      o_default_repo       => l_def_repo,
      o_default_owner      => l_def_owner,
      o_default_branch     => l_def_branch,
      o_aws_region         => l_def_region,
      o_azure_organization => l_def_org,
      o_azure_project      => l_def_project
    );

    resolve_repo_context(
      p_repo_name          => repo_name,
      p_provider           => provider,
      p_owner              => owner,
      p_credential_name    => credential_name,
      p_region             => region,
      p_organization       => organization,
      p_project            => project,
      p_default_repo       => l_def_repo,
      p_default_provider   => l_def_provider,
      p_default_owner      => l_def_owner,
      p_default_credential => l_def_credential_name,
      p_default_region     => l_def_region,
      p_default_org        => l_def_org,
      p_default_project    => l_def_project,
      o_repo_name          => l_repo_name,
      o_provider           => l_provider,
      o_owner              => l_owner,
      o_credential_name    => l_credential_name,
      o_region             => l_region,
      o_organization       => l_organization,
      o_project            => l_project
    );

    l_repo_handle := github_repo_selectai.init_repo_handle(
      provider        => l_provider,
      repo_name       => l_repo_name,
      owner           => l_owner,
      credential_name => l_credential_name,
      region          => l_region,
      organization    => l_organization,
      project         => l_project
    );

    l_effective_branch := NVL(TRIM(branch_name), l_def_branch);

    l_commit_details := github_repo_selectai.build_commit_details(
      message_txt  => commit_message,
      author_name  => author_name,
      author_email => author_email
    );

    RETURN github_repo_selectai.delete_file(
      repo_handle    => l_repo_handle,
      file_path      => file_path,
      branch_name    => l_effective_branch,
      commit_details => l_commit_details
    );
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('delete_file', SQLERRM);
  END delete_file;

  -- Implements function: export object.
  FUNCTION export_object(
    file_path       IN VARCHAR2,
    object_type     IN VARCHAR2,
    object_name     IN VARCHAR2 DEFAULT NULL,
    object_schema   IN VARCHAR2 DEFAULT NULL,
    branch_name     IN VARCHAR2 DEFAULT NULL,
    commit_message  IN VARCHAR2 DEFAULT NULL,
    author_name     IN VARCHAR2 DEFAULT NULL,
    author_email    IN VARCHAR2 DEFAULT NULL,
    append_flag     IN NUMBER DEFAULT 0,
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_repo_handle         CLOB;
    l_commit_details      CLOB;
    l_effective_branch    VARCHAR2(4000);
    l_def_credential_name VARCHAR2(4000);
    l_def_provider        VARCHAR2(4000);
    l_def_repo            VARCHAR2(4000);
    l_def_owner           VARCHAR2(4000);
    l_def_branch          VARCHAR2(4000);
    l_def_region          VARCHAR2(4000);
    l_def_org             VARCHAR2(4000);
    l_def_project         VARCHAR2(4000);
    l_repo_name           VARCHAR2(4000);
    l_provider            VARCHAR2(4000);
    l_owner               VARCHAR2(4000);
    l_credential_name     VARCHAR2(4000);
    l_region              VARCHAR2(4000);
    l_organization        VARCHAR2(4000);
    l_project             VARCHAR2(4000);
  BEGIN
    get_runtime_config(
      o_credential_name    => l_def_credential_name,
      o_provider           => l_def_provider,
      o_default_repo       => l_def_repo,
      o_default_owner      => l_def_owner,
      o_default_branch     => l_def_branch,
      o_aws_region         => l_def_region,
      o_azure_organization => l_def_org,
      o_azure_project      => l_def_project
    );

    resolve_repo_context(
      p_repo_name          => repo_name,
      p_provider           => provider,
      p_owner              => owner,
      p_credential_name    => credential_name,
      p_region             => region,
      p_organization       => organization,
      p_project            => project,
      p_default_repo       => l_def_repo,
      p_default_provider   => l_def_provider,
      p_default_owner      => l_def_owner,
      p_default_credential => l_def_credential_name,
      p_default_region     => l_def_region,
      p_default_org        => l_def_org,
      p_default_project    => l_def_project,
      o_repo_name          => l_repo_name,
      o_provider           => l_provider,
      o_owner              => l_owner,
      o_credential_name    => l_credential_name,
      o_region             => l_region,
      o_organization       => l_organization,
      o_project            => l_project
    );

    l_repo_handle := github_repo_selectai.init_repo_handle(
      provider        => l_provider,
      repo_name       => l_repo_name,
      owner           => l_owner,
      credential_name => l_credential_name,
      region          => l_region,
      organization    => l_organization,
      project         => l_project
    );

    l_effective_branch := NVL(TRIM(branch_name), l_def_branch);

    l_commit_details := github_repo_selectai.build_commit_details(
      message_txt  => commit_message,
      author_name  => author_name,
      author_email => author_email
    );

    RETURN github_repo_selectai.export_object(
      repo_handle    => l_repo_handle,
      file_path      => file_path,
      object_type    => object_type,
      object_name    => object_name,
      object_schema  => object_schema,
      branch_name    => l_effective_branch,
      commit_details => l_commit_details,
      append_flag    => append_flag
    );
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('export_object', SQLERRM);
  END export_object;

  -- Implements function: export schema.
  FUNCTION export_schema(
    file_path       IN VARCHAR2,
    schema_name     IN VARCHAR2,
    filter_list     IN CLOB DEFAULT NULL,
    branch_name     IN VARCHAR2 DEFAULT NULL,
    commit_message  IN VARCHAR2 DEFAULT NULL,
    author_name     IN VARCHAR2 DEFAULT NULL,
    author_email    IN VARCHAR2 DEFAULT NULL,
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_repo_handle      CLOB;
    l_default_branch   VARCHAR2(4000);
    l_effective_branch VARCHAR2(4000);
    l_commit_details   CLOB;
  BEGIN
    resolve_and_init_repo_handle(
      p_repo_name       => repo_name,
      p_provider        => provider,
      p_owner           => owner,
      p_credential_name => credential_name,
      p_region          => region,
      p_organization    => organization,
      p_project         => project,
      o_repo_handle     => l_repo_handle,
      o_default_branch  => l_default_branch
    );

    l_effective_branch := NVL(TRIM(branch_name), l_default_branch);
    l_commit_details := github_repo_selectai.build_commit_details(
      message_txt  => commit_message,
      author_name  => author_name,
      author_email => author_email
    );

    RETURN github_repo_selectai.export_schema(
      repo_handle    => l_repo_handle,
      file_path      => file_path,
      schema_name    => schema_name,
      filter_list    => filter_list,
      branch_name    => l_effective_branch,
      commit_details => l_commit_details
    );
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('export_schema', SQLERRM);
  END export_schema;

  -- Implements function: install file.
  FUNCTION install_file(
    file_path       IN VARCHAR2,
    branch_name     IN VARCHAR2 DEFAULT NULL,
    tag_name        IN VARCHAR2 DEFAULT NULL,
    commit_name     IN VARCHAR2 DEFAULT NULL,
    stop_on_error   IN NUMBER DEFAULT 1,
    repo_name       IN VARCHAR2 DEFAULT NULL,
    provider        IN VARCHAR2 DEFAULT NULL,
    owner           IN VARCHAR2 DEFAULT NULL,
    credential_name IN VARCHAR2 DEFAULT NULL,
    region          IN VARCHAR2 DEFAULT NULL,
    organization    IN VARCHAR2 DEFAULT NULL,
    project         IN VARCHAR2 DEFAULT NULL
  ) RETURN CLOB IS
    l_repo_handle      CLOB;
    l_default_branch   VARCHAR2(4000);
    l_effective_branch VARCHAR2(4000);
  BEGIN
    resolve_and_init_repo_handle(
      p_repo_name       => repo_name,
      p_provider        => provider,
      p_owner           => owner,
      p_credential_name => credential_name,
      p_region          => region,
      p_organization    => organization,
      p_project         => project,
      o_repo_handle     => l_repo_handle,
      o_default_branch  => l_default_branch
    );

    IF TRIM(branch_name) IS NOT NULL THEN
      l_effective_branch := TRIM(branch_name);
    ELSIF tag_name IS NULL AND commit_name IS NULL THEN
      l_effective_branch := l_default_branch;
    ELSE
      l_effective_branch := NULL;
    END IF;

    RETURN github_repo_selectai.install_file(
      repo_handle    => l_repo_handle,
      file_path      => file_path,
      branch_name    => l_effective_branch,
      tag_name       => tag_name,
      commit_name    => commit_name,
      stop_on_error  => stop_on_error
    );
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('install_file', SQLERRM);
  END install_file;

  -- Implements function: install sql.
  FUNCTION install_sql(
    sql_content    IN CLOB,
    stop_on_error  IN NUMBER DEFAULT 1
  ) RETURN CLOB IS
  BEGIN
    RETURN github_repo_selectai.install_sql(
      sql_content   => sql_content,
      stop_on_error => stop_on_error
    );
  EXCEPTION
    WHEN OTHERS THEN
      RETURN build_error_response('install_sql', SQLERRM);
  END install_sql;
END select_ai_github_connector;
/

CREATE OR REPLACE PROCEDURE initialize_cloud_repo_tools
IS
  PROCEDURE drop_tool_if_exists(tool_name IN VARCHAR2) IS
    l_tool_count NUMBER;
    l_sql        CLOB;
  BEGIN
    l_sql := 'SELECT COUNT(*) FROM USER_AI_AGENT_TOOLS WHERE TOOL_NAME = :1';
    EXECUTE IMMEDIATE l_sql INTO l_tool_count USING tool_name;
    IF l_tool_count > 0 THEN
      DBMS_CLOUD_AI_AGENT.DROP_TOOL(tool_name);
    END IF;
  END drop_tool_if_exists;
BEGIN
  drop_tool_if_exists('INIT_GENERIC_REPO_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'INIT_GENERIC_REPO_TOOL',
    attributes => '{
      "instruction": "Initialize a cloud code repository handle using INIT_REPO JSON parameters. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.init_repo"
    }',
    description => 'Initialize generic repository handle'
  );

  drop_tool_if_exists('INIT_GITHUB_REPO_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'INIT_GITHUB_REPO_TOOL',
    attributes => '{
      "instruction": "Initialize a GitHub repository handle. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.init_github_repo"
    }',
    description => 'Initialize GitHub repository handle'
  );

  drop_tool_if_exists('INIT_AWS_REPO_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'INIT_AWS_REPO_TOOL',
    attributes => '{
      "instruction": "Initialize an AWS CodeCommit repository handle. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.init_aws_repo"
    }',
    description => 'Initialize AWS CodeCommit repository handle'
  );

  drop_tool_if_exists('INIT_AZURE_REPO_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'INIT_AZURE_REPO_TOOL',
    attributes => '{
      "instruction": "Initialize an Azure Repos repository handle. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.init_azure_repo"
    }',
    description => 'Initialize Azure Repos repository handle'
  );

  drop_tool_if_exists('CREATE_REPOSITORY_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'CREATE_REPOSITORY_TOOL',
    attributes => '{
      "instruction": "Create a repository using DBMS_CLOUD_REPO.CREATE_REPOSITORY. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.create_repository"
    }',
    description => 'Create repository'
  );

  drop_tool_if_exists('UPDATE_REPOSITORY_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'UPDATE_REPOSITORY_TOOL',
    attributes => '{
      "instruction": "Update repository metadata using DBMS_CLOUD_REPO.UPDATE_REPOSITORY. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.update_repository"
    }',
    description => 'Update repository'
  );

  drop_tool_if_exists('LIST_REPOSITORIES_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_REPOSITORIES_TOOL',
    attributes => '{
      "instruction": "List repositories using DBMS_CLOUD_REPO.LIST_REPOSITORIES. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.list_repositories"
    }',
    description => 'List repositories'
  );

  drop_tool_if_exists('GET_REPOSITORY_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_REPOSITORY_TOOL',
    attributes => '{
      "instruction": "Get repository metadata by repository name. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.get_repository"
    }',
    description => 'Get repository metadata'
  );

  drop_tool_if_exists('DELETE_REPOSITORY_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'DELETE_REPOSITORY_TOOL',
    attributes => '{
      "instruction": "Delete a repository using DBMS_CLOUD_REPO.DELETE_REPOSITORY. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.delete_repository"
    }',
    description => 'Delete repository'
  );

  drop_tool_if_exists('CREATE_BRANCH_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'CREATE_BRANCH_TOOL',
    attributes => '{
      "instruction": "Create a repository branch using DBMS_CLOUD_REPO.CREATE_BRANCH. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.create_branch"
    }',
    description => 'Create repository branch'
  );

  drop_tool_if_exists('DELETE_BRANCH_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'DELETE_BRANCH_TOOL',
    attributes => '{
      "instruction": "Delete a repository branch using DBMS_CLOUD_REPO.DELETE_BRANCH. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.delete_branch"
    }',
    description => 'Delete repository branch'
  );

  drop_tool_if_exists('LIST_BRANCHES_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_BRANCHES_TOOL',
    attributes => '{
      "instruction": "List repository branches using DBMS_CLOUD_REPO.LIST_BRANCHES. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.list_branches"
    }',
    description => 'List repository branches'
  );

  drop_tool_if_exists('LIST_COMMITS_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_COMMITS_TOOL',
    attributes => '{
      "instruction": "List repository commits using DBMS_CLOUD_REPO.LIST_COMMITS. Optionally provide a branch. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.list_commits"
    }',
    description => 'List repository commits'
  );

  drop_tool_if_exists('MERGE_BRANCH_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'MERGE_BRANCH_TOOL',
    attributes => '{
      "instruction": "Merge source branch into target branch using DBMS_CLOUD_REPO.MERGE_BRANCH. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.merge_branch"
    }',
    description => 'Merge repository branches'
  );

  drop_tool_if_exists('PUT_REPO_FILE_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'PUT_REPO_FILE_TOOL',
    attributes => '{
      "instruction": "Upload a file to repository from database content using DBMS_CLOUD_REPO.PUT_FILE. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.put_file"
    }',
    description => 'Upload repository file'
  );

  drop_tool_if_exists('GET_REPO_FILE_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'GET_REPO_FILE_TOOL',
    attributes => '{
      "instruction": "Download file content from repository using DBMS_CLOUD_REPO.GET_FILE. Return content in a fenced code block and choose the code block language from the file extension. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.get_file"
    }',
    description => 'Download repository file'
  );

  drop_tool_if_exists('LIST_REPO_FILES_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'LIST_REPO_FILES_TOOL',
    attributes => '{
      "instruction": "List repository files using DBMS_CLOUD_REPO.LIST_FILES. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.list_files"
    }',
    description => 'List repository files'
  );

  drop_tool_if_exists('DELETE_REPO_FILE_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'DELETE_REPO_FILE_TOOL',
    attributes => '{
      "instruction": "Delete repository file using DBMS_CLOUD_REPO.DELETE_FILE. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.delete_file"
    }',
    description => 'Delete repository file'
  );

  drop_tool_if_exists('EXPORT_DB_OBJECT_REPO_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'EXPORT_DB_OBJECT_REPO_TOOL',
    attributes => '{
      "instruction": "Export object metadata DDL to repository using DBMS_CLOUD_REPO.EXPORT_OBJECT. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.export_object"
    }',
    description => 'Export DB object metadata to repository'
  );

  drop_tool_if_exists('EXPORT_SCHEMA_REPO_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'EXPORT_SCHEMA_REPO_TOOL',
    attributes => '{
      "instruction": "Export schema metadata DDL to repository using DBMS_CLOUD_REPO.EXPORT_SCHEMA. filter_list must be a JSON array string when provided. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.export_schema"
    }',
    description => 'Export schema metadata to repository'
  );

  drop_tool_if_exists('INSTALL_REPO_FILE_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'INSTALL_REPO_FILE_TOOL',
    attributes => '{
      "instruction": "Install SQL statements from a repository file using DBMS_CLOUD_REPO.INSTALL_FILE. file_path is required. Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.install_file"
    }',
    description => 'Install SQL from repository file'
  );

  drop_tool_if_exists('INSTALL_SQL_BUFFER_TOOL');
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'INSTALL_SQL_BUFFER_TOOL',
    attributes => '{
      "instruction": "Install SQL statements from provided SQL text using DBMS_CLOUD_REPO.INSTALL_SQL. sql_content must be a valid SQL script where statements are terminated with slash (/). Resolve repository context from SELECTAI_AGENT_CONFIG/SELECTAIAGENT_CONFIG first. Do not ask for optional context fields; pass NULL for repo_name, provider, owner, credential_name, region, organization, project, and branch_name unless user explicitly overrides.",
      "function": "select_ai_github_connector.install_sql"
    }',
    description => 'Install SQL from buffer'
  );

  DBMS_OUTPUT.PUT_LINE('initialize_cloud_repo_tools completed.');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error in initialize_cloud_repo_tools: ' || SQLERRM);
    RAISE;
END initialize_cloud_repo_tools;
/

BEGIN
  initialize_cloud_repo_tools;
END;
/

ALTER SESSION SET CURRENT_SCHEMA = ADMIN;
