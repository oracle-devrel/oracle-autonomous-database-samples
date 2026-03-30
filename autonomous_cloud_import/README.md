# Heterogeneous Database Migration Prerequisites (PostgreSQL & MySQL)

This repository contains prerequisite SQL objects (views) to support **optimal parallel processing** and **reliable restart capability** when migrating from **non-Oracle (heterogeneous) source databases**.

You can place the SQL statements provided below into separate files (recommended structure included).

---

## Overview

For heterogeneous source databases, certain prerequisites must be met to enable:
- **Parallel processing** during migration, and
- **Reliable restart capability** (resume in-progress work without restarting from the beginning)

If the required views are **not** created on the source database, the migration may **fall back to CTAS**, and any in-progress table migration may **restart from the beginning**.

> Note: API parameters are similar to **database link parameters**. For details, refer to **Database Link Parameters** in the public documentation.

---

## General Prerequisites (All Heterogeneous Sources)

- Ensure the supplied user credentials have the required privileges to access the schema being migrated.
- The database specified by `service_name` must provide access to the target schema.

---

## PostgreSQL

### Purpose
To enable parallel processing and reliable restart capability on a PostgreSQL source database, create the required views.

### Files (recommended)
Place the SQL into files such as:

- `postgres/ALL_TAB_PARTITIONS.sql`
- `postgres/ALL_PART_KEY_COLUMNS.sql`
- `postgres/ALL_PART_TABLES.sql`

### Required Views
- `ALL_TAB_PARTITIONS`
- `ALL_PART_KEY_COLUMNS`
- `ALL_PART_TABLES`

> Add the PostgreSQL SQL definitions to the files above.

---

## MySQL

### Parameter Requirements
- For a MySQL source database, set `schema_list` to an empty array (`[]`).
- The value provided in `service_name` is used as the schema name, because MySQL does not support schemas in the same way as other databases.
- For `table_list`, specify tables using the `service_name` value as the schema name, along with the corresponding table name.

### Purpose
To enable parallel processing and reliable restart capability on a MySQL source database, create the required views.

### Files (recommended)
Place the SQL into files such as:

- `mysql/ALL_PART_TABLES.sql`
- `mysql/ALL_PART_KEY_COLUMNS.sql`
- `mysql/ALL_TAB_PARTITIONS.sql`

### Required Views
- `ALL_PART_TABLES`
- `ALL_PART_KEY_COLUMNS`
- `ALL_TAB_PARTITIONS`
