# ==============================================================================
# HELPER FUNCTIONS LIBRARY FOR R+AI RAG IMPLEMENTATION
# ==============================================================================

# ------------------------------------------------------------------------------
# DATABASE CONNECTION FUNCTIONS
# ------------------------------------------------------------------------------

testConnection <- function(con) {
  result <- dbGetQuery(con, "SELECT '\nConnection successful!\n' as status FROM dual")
  cat(result$STATUS, "\n")
  return(invisible(result))
}

close_connection <- function(connection, driver) {
  dbDisconnect(connection)
  dbUnloadDriver(driver)
  cat("\nConnection closed successfully\n")
}

# ------------------------------------------------------------------------------
# CREDENTIAL MANAGEMENT FUNCTIONS
# ------------------------------------------------------------------------------

createCredentialsTable <- function(con) {
  # Drop existing table if it exists
  tryCatch({
    dbExecute(con, "DROP TABLE OCI_CREDENTIALS")
    cat("\nExisting credentials table dropped\n")
  }, error = function(e) {
    # Table doesn't exist, continue
  })
  
  # Create new credentials table
  dbExecute(con, "
    CREATE TABLE OCI_CREDENTIALS (
      credential_key VARCHAR2(50) PRIMARY KEY,
      credential_value CLOB
    )")
  
  cat("\nCredentials table created\n")
}

storeOCICredentials <- function(con, user_ocid, tenancy_ocid, private_key, fingerprint) {
  # Clear any existing credentials
  dbExecute(con, "DELETE FROM OCI_CREDENTIALS")
  
  # Insert new credentials
  dbExecute(con, paste0("INSERT INTO OCI_CREDENTIALS VALUES ('user_ocid', '",    user_ocid, "')"))
  dbExecute(con, paste0("INSERT INTO OCI_CREDENTIALS VALUES ('tenancy_ocid', '", tenancy_ocid, "')"))
  dbExecute(con, paste0("INSERT INTO OCI_CREDENTIALS VALUES ('private_key', '",  private_key, "')"))
  dbExecute(con, paste0("INSERT INTO OCI_CREDENTIALS VALUES ('fingerprint', '",  fingerprint, "')"))
  cat("\nCloud credentials stored in database\n")
}

createOCICredential <- function(con, credential_name = "OCI_CRED") {
  # Fetch credentials from table
  creds <- dbGetQuery(con, "SELECT credential_key, credential_value FROM OCI_CREDENTIALS")
  
  user_ocid    <- creds$CREDENTIAL_VALUE[creds$CREDENTIAL_KEY == "user_ocid"]
  tenancy_ocid <- creds$CREDENTIAL_VALUE[creds$CREDENTIAL_KEY == "tenancy_ocid"]
  private_key  <- creds$CREDENTIAL_VALUE[creds$CREDENTIAL_KEY == "private_key"]
  fingerprint  <- creds$CREDENTIAL_VALUE[creds$CREDENTIAL_KEY == "fingerprint"]
  
  # Drop credential if it already exists
  dbExecute(con, paste0("BEGIN
    DBMS_CLOUD.DROP_CREDENTIAL(credential_name => '", credential_name, "');
    EXCEPTION WHEN OTHERS THEN NULL;
  END;"))
  
  # Create new credential
  dbExecute(con, paste0("BEGIN
    DBMS_CLOUD.CREATE_CREDENTIAL(
      credential_name => '", credential_name, "',
      user_ocid       => '", user_ocid, "',
      tenancy_ocid    => '", tenancy_ocid, "',
      private_key     => '", private_key, "',
      fingerprint     => '", fingerprint, "'
    );
  END;"))
  
  cat("\nOCI credential '", credential_name, "' created\n", sep = "")
}

# ------------------------------------------------------------------------------
# AI PROFILE MANAGEMENT FUNCTIONS
# ------------------------------------------------------------------------------

createAIProfile <- function(con, 
                            profileName,
                            provider            = "oci",
                            embeddingModel      = NULL,
                            credentialName      = NULL,
                            vectorIndexName     = NULL,
                            temperature         = 0.2,
                            maxTokens           = 4000,
                            enableSourceOffsets = TRUE) {
  
  # Drop existing profile if it exists
  dbExecute(con, sprintf(
    "BEGIN DBMS_CLOUD_AI.DROP_PROFILE(profile_name => '%s'); 
     EXCEPTION WHEN OTHERS THEN NULL; END;",
    profileName))
  
  # Build attributes for profile
  attrs <- list(
    provider              = provider,
    credential_name       = credentialName,
    temperature           = temperature,
    max_tokens            = maxTokens,
    enable_source_offsets = enableSourceOffsets)
  
  # Only add embedding_model if provided (for in-database transformer)
  if (!is.null(embeddingModel)) attrs$embedding_model <- embeddingModel
  
  if (!is.null(vectorIndexName)) attrs$vector_index_name <- vectorIndexName
  
  json <- jsonlite::toJSON(attrs, auto_unbox = TRUE)
  
  # Create and set profile
  dbExecute(con, sprintf(
    "BEGIN DBMS_CLOUD_AI.CREATE_PROFILE(
       profile_name => '%s',
       attributes   => '%s'); END;",
    profileName, json))
  
  dbExecute(con, sprintf(
    "BEGIN DBMS_CLOUD_AI.SET_PROFILE(profile_name => '%s'); END;",
    profileName))
  
  cat("\nProfile '", profileName, "' created successfully\n\n", sep = "")
}

updateAIProfileAttribute <- function(con, profileName, attributeName, value) {
  val <- if (is.character(value)) sprintf("'%s'", value) else value
  
  dbExecute(con, sprintf(
    "BEGIN DBMS_CLOUD_AI.SET_ATTRIBUTE(
      profile_name => '%s', attribute_name => '%s', attribute_value => %s); END;",
    profileName, attributeName, val))
  
  cat("'", attributeName, "' set to ", value, "\n", sep = "")
}

# ------------------------------------------------------------------------------
# VECTOR INDEX MANAGEMENT FUNCTIONS
# ------------------------------------------------------------------------------


dropVectorIndex <- function(con, indexName, includeData = TRUE) {
  query <- sprintf(
    "BEGIN
      DBMS_CLOUD_AI.DROP_VECTOR_INDEX(
        index_name   => '%s',
        include_data => %s);
      EXCEPTION WHEN OTHERS THEN NULL;
    END;",
    indexName,
    toupper(includeData))
  
  dbExecute(con, query)
  cat("\nVector index '", indexName, "' dropped\n\n", sep = "")
}

createVectorIndex <- function(con, 
                              indexName, 
                              vectorTableName,
                              profileName,
                              location,
                              objectStorageCredential,
                              vectorDistanceMetric = "cosine",
                              chunkOverlap         = 128,
                              chunkSize            = 1024,
                              vectorDimension      = NULL,
                              refreshRate          = 1440,
                              showQuery            = FALSE) {
  
  # Build attributes for vector index
  attributes <- list(
    vector_db_provider             = "oracle",
    vector_table_name              = vectorTableName,
    profile_name                   = profileName,
    location                       = location,
    object_storage_credential_name = objectStorageCredential,
    vector_distance_metric         = tolower(vectorDistanceMetric),
    chunk_overlap                  = chunkOverlap,
    chunk_size                     = chunkSize,
    refresh_rate                   = refreshRate)
  
  if (!is.null(vectorDimension)) attributes$vector_dimension <- vectorDimension
  
  json <- gsub("'", "''", jsonlite::toJSON(attributes, auto_unbox = TRUE))
  
  query <- sprintf(
    "BEGIN DBMS_CLOUD_AI.CREATE_VECTOR_INDEX(index_name => '%s', attributes => '%s'); END;",
    indexName, json)
  
  if (showQuery) cat("Query:\n", query, "\n\n")
  
  dbExecute(con, query)
  cat("\nVector indexing for '", indexName, "' started\n\n", sep = "")
}

viewVectorIndexTable <- function(con, indexName, nRows = 1) {
  
  # Get the vector index table name
  query <- paste0("SELECT INDEX_NAME, INDEX_TYPE, INDEX_SUBTYPE, TABLE_NAME, STATUS 
    FROM USER_INDEXES 
    WHERE INDEX_NAME = '", indexName, "'")
  
  index_info <- dbGetQuery(con, query)
  table_name <- index_info$TABLE_NAME[1]
  
  cat("\nVector index table name:", table_name, "\n\n")
  
  # Query the vector table
  query <- paste0("SELECT CONTENT, ATTRIBUTES, EMBEDDING 
    FROM ", table_name, " 
    FETCH FIRST ", nRows, " ROWS ONLY")
  
  result <- dbGetQuery(con, query)
  
  return(result)
}

createVectorIndexStatusView <- function(con, indexName = "RCB_VECTOR_INDEX") {
  
  # Get pipeline name and status table
  query <- paste0("
    SELECT pipeline_name, status_table
    FROM   user_cloud_pipelines
    WHERE  pipeline_name = '", indexName, "$VECPIPELINE'")
  
  result <- dbGetQuery(con, query)
  
  if (nrow(result) == 0) {
    cat("\nNo pipeline found for index:", indexName, "\n\n")
    return(invisible(NULL))
  }
  
  pipeline_name <- result$PIPELINE_NAME[1]
  table_name    <- result$STATUS_TABLE[1]
  
  # Create view
  view_name <- paste0(indexName, "_STATUS_VIEW")
  create_view_query <- paste0("
    CREATE OR REPLACE VIEW ", view_name, " AS 
    SELECT name, status, error_message 
    FROM ", table_name)
  
  invisible(dbExecute(con, create_view_query))
}

# ------------------------------------------------------------------------------
# CLOUD STORAGE FUNCTIONS
# ------------------------------------------------------------------------------

listCloudStorageObjects <- function(con, locationURI, credentialName = "OCI_CRED") {
  
  list_query <- paste0("SELECT OBJECT_NAME, BYTES 
    FROM DBMS_CLOUD.LIST_OBJECTS(
      credential_name => '", credentialName, "',
      location_uri    => '", locationURI, "'
    )")
  
  object_list <- dbGetQuery(con, list_query)
  
  return(object_list)
}

# ------------------------------------------------------------------------------
# RAG and CHAT FUNCTIONS
# ------------------------------------------------------------------------------


rag <- function(con, profile, prompt, conversationId = NULL) {
  
  # Conditionally add params if conversationId provided
  params_part <- if (!is.null(conversationId)) {
    sprintf(",\n      params => '{\"conversation_id\":\"%s\"}'", conversationId)
  } else {
    ""
  }
  
  query <- sprintf("SELECT DBMS_CLOUD_AI.GENERATE(
    prompt       => '%s',
    profile_name => '%s',
    action       => 'narrate'%s) AS response 
  FROM dual", prompt, profile, params_part)
  
  result <- dbGetQuery(con, query)
  return(result$RESPONSE[1])
}

showChunks <- function(con, profile, prompt) {
  
  # Build query with 'runsql' action (backend name for showchunks)
  query <- sprintf("SELECT DBMS_CLOUD_AI.GENERATE(
    prompt       => '%s',
    profile_name => '%s',
    action       => 'runsql') AS response 
  FROM dual", prompt, profile)
  
  result <- dbGetQuery(con, query)
  return(result$RESPONSE[1])
}

chat <- function(con, profile, prompt, conversationId = NULL) {
  
  # Conditionally add params if conversationId provided
  params_part <- if (!is.null(conversationId)) {
    sprintf(",\n      params => '{\"conversation_id\":\"%s\"}'", conversationId)
  } else {
    ""
  }
  
  # Build query - action is always 'chat' for direct LLM access
  query <- sprintf("SELECT DBMS_CLOUD_AI.GENERATE(
    prompt       => '%s',
    profile_name => '%s',
    action       => 'chat'%s) AS response
  FROM dual", prompt, profile, params_part)
  
  result <- dbGetQuery(con, query)
  return(result$RESPONSE[1])
}

# ------------------------------------------------------------------------------
# CONVERSATION MANAGEMENT FUNCTIONS
# ------------------------------------------------------------------------------

createConversation <- function(con, profileName) {
  # Set the profile
  dbExecute(con, sprintf(
    "BEGIN DBMS_CLOUD_AI.SET_PROFILE(profile_name => '%s'); END;",
    profileName))
  
  # Create conversation and capture the ID
  result          <- dbGetQuery(con, "SELECT DBMS_CLOUD_AI.create_conversation() AS conversation_id FROM dual")
  conversation_id <- result$CONVERSATION_ID[1]
  
  cat("\nConversation created\n")
  cat("Conversation ID: ", conversation_id, "\n", sep = "")
  
  return(conversation_id)
}

# ------------------------------------------------------------------------------
# DISPLAY FUNCTIONS
# ------------------------------------------------------------------------------

displayResult <- function(prompt, result, display = c("console", "viewer", "browser")) {
  display <- match.arg(display)
  
  # Helper functions
  in_rstudio <- function() {
    suppressWarnings(requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable())
  }
  
  html_escape <- function(x) {
    x <- gsub("&", "&amp;", x, fixed = TRUE)
    x <- gsub("<", "&lt;",  x, fixed = TRUE)
    x <- gsub(">", "&gt;",  x, fixed = TRUE)
    x
  }
  
  # Console display mode
  if (display == "console") {
    cat("\n", strrep("=", 80), "\n", sep = "")
    cat("Prompt: ", prompt, "\n\n", sep = "")
    cat("Response:\n", strrep("-", 80), "\n", sep = "")
    cat(strwrap(result, width = 78), sep = "\n")
    cat("\n", strrep("=", 80), "\n", sep = "")
    return(invisible(result))
  }
  
  # Build HTML (used by viewer and browser) 
  build_html <- function(prompt, result, fullscreen = FALSE) {
    is_json <- FALSE
    if (requireNamespace("jsonlite", quietly = TRUE)) {
      is_json <- tryCatch(jsonlite::validate(result), error = function(e) FALSE)
    }
    
    content_html <- ""
    if (is_json) {
      # Try to tabulate arrays of objects; otherwise show JSON as-is
      jd <- tryCatch(jsonlite::fromJSON(result, simplifyVector = FALSE), error = function(e) NULL)
      if (is.list(jd) && length(jd) > 0 && is.list(jd[[1]])) {
        headers <- unique(unlist(lapply(jd, names)))
        
        # Remove 'url' column if present
        headers <- headers[headers != "url"]
        
        # Replace underscores with <br> for headers display
        display_headers <- gsub("_", "<br>", headers)
        
        # Limit to first 100 rows for performance
        max_rows <- min(length(jd), 100)
        total_rows <- length(jd)
        
        make_cell <- function(v) {
          if (is.null(v)) return("")
          if (is.list(v)) v <- paste(unlist(v), collapse = ", ")
          v <- as.character(v)
          if (nchar(v) > 200) v <- paste0(substr(v, 1, 200), "...")
          html_escape(v)
        }
        
        rows <- vapply(seq_len(max_rows), function(i) {
          cells <- vapply(headers, function(h) make_cell(jd[[i]][[h]]), character(1))
          paste0("<tr>", paste0("<td>", cells, "</td>", collapse = ""), "</tr>")
        }, character(1))
        
        head_html <- paste0("<tr>", paste0("<th>", display_headers, "</th>", collapse = ""), "</tr>")
        
        truncation_notice <- if (total_rows > max_rows) {
          sprintf('<p style="color:#64748b;font-size:0.85rem;margin-top:0.5rem">Showing first %d of %d rows</p>', max_rows, total_rows)
        } else {
          ''
        }
        
        content_html <- sprintf(
          '<div class="table-container"><table class="data-table"><thead>%s</thead><tbody>%s</tbody></table>%s</div>
           <details class="raw-json"><summary>View Raw JSON</summary><pre class="response-content">%s</pre></details>',
          head_html, paste0(rows, collapse = ""), truncation_notice, html_escape(result))
      } else {
        # Skip 'prettify' for speed - display JSON as-is
        content_html <- sprintf('<pre class="response-content">%s</pre>', html_escape(result))
      }
    } else {
      content_html <- sprintf('<pre class="response-content">%s</pre>', html_escape(result))
    }
    
    # Enhanced styles for fullscreen mode
    extra_styles <- if (fullscreen) {
      'body{padding:3rem 4rem}.container{max-width:1400px}.response-content{font-size:0.9rem;line-height:1.6}.data-table{font-size:0.8rem}@media print{body{padding:1rem}.container{box-shadow:none}}'
    } else {
      ''
    }
    
    sprintf('
<!DOCTYPE html><html><head><meta charset="UTF-8">
<title>%s</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#f5f7fa;padding:2rem;margin:0}
.container{background:#fff;max-width:1200px;margin:0 auto;padding:2rem;border-radius:8px;box-shadow:0 4px 12px rgba(0,0,0,.15)}
.page-header{font-size:0.95rem;font-weight:700;color:#0f172a;margin-bottom:0.75rem;line-height:1.3;background:linear-gradient(135deg,#1e40af,#1e3a8a);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
.section-label{font-size:.75rem;font-weight:700;color:#64748b;text-transform:uppercase;margin:.25rem 0}
.response-box{border-radius:6px;padding:1.25rem;background:#fafafa}
.response-content{white-space:pre-wrap;word-wrap:break-word;font-family:ui-monospace,Menlo,Consolas,Monaco,monospace;font-size:0.8rem;line-height:1.5;color:#0f172a}
.table-container{overflow-x:auto;margin:0}
.data-table{width:100%%;border-collapse:collapse;font-size:.75rem;table-layout:fixed}
.data-table th:nth-child(1),.data-table td:nth-child(1){width:36%%}
.data-table th:nth-child(2),.data-table td:nth-child(2){width:23%%}
.data-table th:nth-child(3),.data-table td:nth-child(3){width:10%%}
.data-table th:nth-child(4),.data-table td:nth-child(4){width:10%%}
.data-table th:nth-child(5),.data-table td:nth-child(5){width:10%%}
.data-table thead{background:#f1f5f9;border-bottom:2px solid #e2e8f0}
.data-table th,.data-table td{padding:.6rem .8rem;border-bottom:1px solid #f1f5f9;text-align:left;vertical-align:top;word-wrap:break-word;overflow-wrap:break-word}
.data-table tbody tr:hover{background:#f8fafc}
.raw-json{margin-top:1rem;border-top:1px solid #e2e8f0;padding-top:.75rem}
.raw-json summary{cursor:pointer;color:#2563eb;font-size:0.9rem}
.raw-json summary:hover{color:#1d4ed8}
%s
</style></head>
<body>
<div class="container">
<h1 class="page-header">%s</h1>
<div class="section-label">Response</div>
<div class="response-box">%s</div>
</div>
</body></html>
', html_escape(prompt), extra_styles, html_escape(prompt), content_html)
  }
  
  # Viewer display mode (RStudio viewer pane)
  if (display == "viewer") {
    html <- build_html(prompt, result, fullscreen = FALSE)
    tf   <- tempfile(fileext = ".html")
    writeLines(html, tf, useBytes = TRUE)
    if (in_rstudio()) {
      rstudioapi::viewer(tf)
    } else {
      utils::browseURL(tf)
    }
    cat("\nOpening result in viewer...\n\n")
    return(invisible(result))
  }
  
  # Browser display mode (full browser tab)
  if (display == "browser") {
    html <- build_html(prompt, result, fullscreen = TRUE)
    tf   <- tempfile(fileext = ".html")
    writeLines(html, tf, useBytes = TRUE)
    utils::browseURL(tf)
    cat("\nOpening result in browser tab...\n\n")
    return(invisible(result))
  }
  
  invisible(result)
}

clearViewer <- function() {
  dir <- tempfile()
  dir.create(dir)
  TextFile <- file.path(dir, "blank.html")
  writeLines("", con = TextFile)
  rstudioapi::viewer(TextFile) 
}

# ------------------------------------------------------------------------------
# MONITORING FUNCTIONS
# ------------------------------------------------------------------------------

checkVectorIndexStatus <- function(con, indexName, type = "summary") {
  # Validate type parameter
  if (!type %in% c("summary", "list")) {
    stop("type must be either 'summary' or 'list'")
  }
  
  # Build view name (Oracle stores names in uppercase by default)
  view_name <- paste0(toupper(indexName), "_STATUS_VIEW")
  
  # Build query based on type
  if (type == "summary") {
    query <- sprintf("
      SELECT STATUS,
             COUNT(*) AS COUNT,
             ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS PERCENTAGE
      FROM   %s
      WHERE  STATUS NOT IN ('2', '4', 'SKIPPED')
      GROUP BY STATUS
      ORDER BY STATUS", view_name)
  } else {
    # list view - detailed file-by-file status
    query <- sprintf("
      SELECT NAME,
             STATUS,
             ERROR_MESSAGE
      FROM   %s
      WHERE  STATUS NOT IN ('2', '4', 'SKIPPED')
      ORDER BY NAME", view_name)
  }
  
  # Run query
  result <- dbGetQuery(con, query)
  
  # Handle empty result
  if (nrow(result) == 0) {
    cat("No matching status found for index '", indexName, "'\n", sep = "")
    return(invisible(NULL))
  }
  
  return(result)
}

listDatabaseTransformers <- function(con, filter = NULL) {
  query <- "SELECT model_name, mining_function
            FROM   USER_MINING_MODELS 
            WHERE  algorithm = 'ONNX'"
  
  if (!is.null(filter)) {
    query <- paste0(query, " AND model_name LIKE '%", filter, "%'")
  }
  
  dbGetQuery(con, query)
}