# ==============================================================================
# R+AI: Use RAG from your database to answer questions about the R Consortium
# ==============================================================================
#
# This script demonstrates Retrieval Augmented Generation (RAG) using 
# Oracle Autonomous AI Database Select AI to answer natural language questions 
# based on R Consortium blog content.
#
# RAG augments your prompt to give the LLM new knowledge without fine tuning 
# using your natural language prompt for semantic similarity search.
#
# Prerequisite: Run R+AI-helper-functions.R
# ==============================================================================
# SETUP: Load Libraries and establish database connection
# ==============================================================================

library(ROracle)
library(dplyr)

# Initialize Oracle driver
drv <- dbDriver("Oracle") 

# Connect to Oracle Autonomous AI Database
con <- dbConnect(drv, 
                 dbname   = "selectaidemo_medium",     
                 username = "SELECT_AI_USER", 
                 password = Sys.getenv("PASSWORD"))

testConnection(con)

# ==============================================================================
# CREATE CLOUD CREDENTIALS (replace with your unique values)
# ==============================================================================

# createCredentialsTable(con)

# storeOCICredentials(
#   con,
#   user_ocid    = "ocid1.user.oc1..aaaaafccti...", 
#   tenancy_ocid = "ocid1.tenancy.oc1..aaaaaaa...",
#   private_key  = "MIIEvgIBADANBgkqhkiG9wISKg...",
#   fingerprint  = "73:d0:f7:76:48:ba:97:9a:6h...")

# createOCICredential(con, "OCI_CRED")

# ==============================================================================
# CREATE AI PROFILE AND VECTOR INDEX
# ==============================================================================

createAIProfile(
  con, 
  profileName     = "OCI_FOR_RCB",
  provider        = "oci", 
  credentialName  = "OCI_CRED",
  vectorIndexName = "RCB_VECTOR_INDEX",
  temperature     = 0.2,
  maxTokens       = 4000)

# List objects in cloud storage 
objects <- listCloudStorageObjects(
  con         = con,
  locationURI = "https://adwc4pm.objectstorage.ap-tokyo-1.oci.customer-oci.com/p/UlOrZRmWUU4-wXx4DyYIPb_8gOA6lBvR9PfOUOV2bO2USORCmQlQAO5NGLsx0frG/n/adwc4pm/b/R-Consortium-blogs/o/")

objects %>%
  head(5) %>%
  mutate(OBJECT_NAME = substr(OBJECT_NAME, 1, 55)) %>%
  print(row.names = FALSE)

# ==============================================================================
# CREATE VECTOR INDEX
# ==============================================================================

# Drop vector index if it exists
dropVectorIndex(con, "RCB_VECTOR_INDEX")

createVectorIndex(    
  con,
  indexName                   = "RCB_VECTOR_INDEX",
  vectorTableName             = "RCB_VECTOR_TABLE",
  profileName                 = "OCI_FOR_RCB",
  location                    = "https://adwc4pm.objectstorage.ap-tokyo-1.oci.customer-oci.com/p/UlOrZRmWUU4-wXx4DyYIPb_8gOA6lBvR9PfOUOV2bO2USORCmQlQAO5NGLsx0frG/n/adwc4pm/b/R-Consortium-blogs/o/",
  objectStorageCredential     = "OCI_CRED",
  refreshRate                 = 2)

# Create the vector index status view
createVectorIndexStatusView(con, "RCB_VECTOR_INDEX")

# Check the status of vector index creation (in progress)
checkVectorIndexStatus(con, 
                       indexName = "RCB_VECTOR_INDEX", 
                       type      = "summary")

# Check the status of vector index creation (complete)
checkVectorIndexStatus(con, 
                       indexName = "RCB_VECTOR_INDEX", 
                       type      = "summary")

# ==============================================================================
# QUERY WITH Chat - direct LLM interaction
# ==============================================================================

prompt1 <- "Tell me about the R+AI 2025 conference"
result1 <- chat(con,
                profile = "OCI_FOR_RCB", 
                prompt  = prompt1)

displayResult(prompt1, result1, display = "viewer")

# ==============================================================================
# QUERY WITH RAG
# ==============================================================================

# Use RAG for the same prompt
clearViewer()
result2 <- rag(con,
               profile  = "OCI_FOR_RCB", 
               prompt   = prompt1)

displayResult(prompt1, result2, display = "viewer")

# Same query with showChunks
clearViewer()
result3 <- showChunks(con, 
                      profile = "OCI_FOR_RCB", 
                      prompt  = prompt1)

displayResult(prompt1, result3, display = "viewer")

# User group plan query
clearViewer()
prompt2 <- "Create a 5-step plan for someone new to R who 
            wants to get involved with R user groups and the
            R community, focusing on R programming
            fundamentals, community participation, and 
            contribution opportunities."

result4 <- rag(con, 
               profile        = "OCI_FOR_RCB", 
               prompt         = prompt2)

displayResult(prompt2, result4, display = "viewer")

# Learning resources query 
clearViewer()
prompt3 <- "What learning resources and educational 
            initiatives does the R Consortium have?"

result5 <- rag(con,
               profile        = "OCI_FOR_RCB",
               prompt         = prompt3)

displayResult(prompt3, result5, display = "viewer")

# ==============================================================================
# USING CONVERSATION CONTEXT
# ==============================================================================

# Create a conversation and capture the ID
clearViewer()
conversation_id <- createConversation(con, "OCI_FOR_RCB")

prompt4 <- "What does the R Consortium do to support the R community?"

result6 <- rag(con,
               profile        = "OCI_FOR_RCB", 
               prompt         = prompt4,
               conversationId = conversation_id)

displayResult(prompt4, result6, display = "viewer")

# Follow-up question: uses conversation_id to 
# maintain context
clearViewer()
prompt5 <- "What specific programs do they offer for funding?"

result7 <- rag(con, 
               profile        = "OCI_FOR_RCB", 
               prompt         = prompt5, 
               conversationId = conversation_id)

displayResult(prompt5, result7, display = "viewer")

# ==============================================================================
# USING IN-DATABASE TRANSFORMERS            
# ==============================================================================

# List available in-database transformers   
clearViewer()
listDatabaseTransformers(con)
listDatabaseTransformers(con, filter = "E5")

# Create a profile for in-database transformer
createAIProfile(con,
                profileName     = "OCI_FOR_RCB2",
                provider        = "oci",
                credentialName  = "OCI_CRED",
                embeddingModel  = "database:MULTILINGUAL_E5_SMALL",
                vectorIndexName = "RCB_VECTOR_INDEX2")

# Create vector index for the in-database transformer
dropVectorIndex(con, "RCB_VECTOR_INDEX2")

createVectorIndex(con,
                  indexName               = "RCB_VECTOR_INDEX2",
                  vectorTableName         = "RCB_VECTOR_TABLE2",
                  profileName             = "OCI_FOR_RCB2",
                  location                = "https://adwc4pm.objectstorage.ap-tokyo-1.oci.customer-oci.com/p/UlOrZRmWUU4-wXx4DyYIPb_8gOA6lBvR9PfOUOV2bO2USORCmQlQAO5NGLsx0frG/n/adwc4pm/b/R-Consortium-blogs/o/",
                  objectStorageCredential = "OCI_CRED",
                  vectorDimension         = 384,
                  chunkSize               = 500,
                  chunkOverlap            = 50)

# Create the vector index status view
createVectorIndexStatusView(con, "RCB_VECTOR_INDEX2")

# Check the status of vector index creation (in progress)
checkVectorIndexStatus(con, 
                       indexName = "RCB_VECTOR_INDEX2", 
                       type      = "summary")

# Check the status of vector index creation (completed)
checkVectorIndexStatus(con, 
                       indexName = "RCB_VECTOR_INDEX2", 
                       type      = "summary")

prompt6 <- "What are the benefits of participating in R user groups?"
result8 <- rag(con, 
               profile = "OCI_FOR_RCB", 
               prompt  = prompt6)

displayResult(prompt6, result8, display = "viewer")

# Queries in Italian, Spanish and Portuguese
clearViewer()
languages <- c("Italian", "Spanish", "Brazilian Portuguese")

multilingual_prompts <- c(
 "Quali sono i vantaggi di partecipare ai gruppi di utenti R?",
 "Cuales son los beneficios de participar en grupos de usuarios de R?",
 "Quais sao os beneficios de participar em um grupo de usuarios do R?")

for (i in 1:length(multilingual_prompts)) {
  result <- rag(con, 
                profile = "OCI_FOR_RCB2", 
                prompt  = multilingual_prompts[i])
  
  displayResult(multilingual_prompts[i], 
                result, 
                display = "browser")
}

# ==============================================================================
# CLEANUP
# ==============================================================================

# Close database connection
close_connection(con, drv)

cat("\nEnd of script\n")
