# Delta Sharing

## Overview

Oracle Autonomous Database supports versioned shares through the open Delta Sharing protocol. Providers publish data from Autonomous Database, and recipients access shares using a JSON profile and query Parquet data for a selected version window. Oracle also provides a fully scriptable sharing workflow through the `DBMS_SHARE` package.

## Files

- `./change-data-feed/Oracle Delta Sharing CDF.ipynb` — Python code that compares two versions of a Delta Share and prints the raw change rows returned for that version window.

## What the notebook shows

This notebook demonstrates a file-based CDF-style workflow for versioned Delta Shares published by Oracle Autonomous Database.

The notebook:

- authenticates with a Delta Sharing profile
- requests changes between `START_VERSION` and `END_VERSION`
- downloads only the Parquet/action files returned for that version window
- displays raw rows together with `_commit_version` and `_change_type`

This makes it useful for validating what changed between two published versions of a share without scanning the full share.

## Important behavior

This sample operates at file level.

When a file changes between two versions:

- rows from the previous file can appear as `delete`
- rows from the replacement file can appear as `insert`

As a result, unchanged rows inside a replaced file can appear as matching delete/insert pairs. The notebook intentionally shows the raw output so downstream logic can derive the net inserts, deletes, and updates.

In practice, this means that if a share is large but only a small incremental change was published, the notebook reads only the files returned for the requested version window rather than scanning the full share.

## References

- [Overview of the Data Share Tool](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/overview-adp-share.html)
- [Manage Shares with DBMS_SHARE](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/manage-shares.html)
- [DBMS_SHARE Constants](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/dbms-share-package-constants.html)
- [High-Level Steps for Receiving Shares for Versioned Data](https://docs.oracle.com/en/database/oracle/sql-developer-web/sdwfd/high-level-steps-recieving-data-shares-versioned-data.html)
- [Sharing Data from On-Premise Oracle Databases](https://blogs.oracle.com/autonomous-ai-database/sharing-data-from-onpremise-oracle-databases)
- [Seamless, Open Data Sharing Between Oracle Autonomous Database and Databricks](https://blogs.oracle.com/autonomous-ai-database/open-data-sharing-between-oracle-and-databricks)