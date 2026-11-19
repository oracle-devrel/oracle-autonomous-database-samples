# OCI CLI — Update an ADB-S Maintenance Window

Updates the maintenance schedule of an existing Autonomous Database Serverless instance using OCI CLI and `UpdateAutonomousDatabase`. Discover available windows, submit a target through `scheduledMaintenanceWindow`, then verify completion.

Commands are written on one line and use double-quoted placeholders so they can be copied into PowerShell, Windows Command Prompt (CMD), Bash or Zsh. No shell script or environment-variable file is required.

## Files

| File | Description |
|---|---|
| `README.md` | Setup and complete command sequence |
| `maintenance-window.json` | Target maintenance window to edit |

## Prerequisites

- An existing eligible ADB-S: ECPU, Regular patch level, not Always Free or Developer.
- OCI CLI with `list-available-maintenance-windows` and `--scheduled-maintenance-window` support. This example targets CLI 3.96.2; older releases may lack these features.
- An OCI API-key profile with permissions to read and update the database.
- The OCID and region of your existing database.

### Install OCI CLI

If OCI CLI is already installed, check `oci --version` and command support below. Otherwise, follow the [official installation instructions](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm).

Alternatively, with a compatible Python installation, create an isolated environment in this example's directory. These setup commands differ by operating system; the OCI commands in Quick Start are shared.

**Windows PowerShell or CMD:**

```text
py -m venv .venv
.venv\Scripts\python.exe -m pip install "oci-cli==3.96.2"
.venv\Scripts\oci.exe --version
```

**macOS or Linux:**

```text
python3 -m venv .venv
.venv/bin/python -m pip install "oci-cli==3.96.2"
.venv/bin/oci --version
```

Activation is not required. If you use this isolated installation, replace the initial `oci` in every command below with `.venv\Scripts\oci.exe` on Windows or `.venv/bin/oci` on macOS/Linux. Run commands from this example's directory.

Check support without calling OCI:

```text
oci db autonomous-database list-available-maintenance-windows --help
oci db autonomous-database update --generate-param-json-input scheduled-maintenance-window
```

### Configure authentication

Reuse an existing OCI profile or configure one with:

```text
oci setup config
```

The default configuration file is `.oci/config` under your user home directory (`~/.oci/config` on macOS/Linux; typically `%USERPROFILE%\.oci\config` on Windows). The configured fingerprint must match the public key registered for that OCI user, and `key_file` must point to the corresponding private key. Register the public key in OCI if setup generates a new pair. Do not share the private key.

The commands use `--profile DEFAULT`. Replace `DEFAULT` if you use another profile. For a non-default configuration path, add `--config-file "FULL_PATH_TO_CONFIG"` to each command.

## Quick Start

Open a terminal in the directory containing `maintenance-window.json`. Replace `<ADB_OCID>` and `<REGION>` in every command, retaining the double quotes. `<REGION>` is the database's region identifier, for example `us-ashburn-1`.

### 1. Read the current database state

```text
oci db autonomous-database get --autonomous-database-id "<ADB_OCID>" --region "<REGION>" --profile DEFAULT
```

Inspect `lifecycle-state`, `autonomous-database-maintenance-window`, `scheduled-maintenance-window` and `time-scheduled-maintenance-window-update`. Also check the console for a pending change before submitting a new request.

### 2. List available windows

```text
oci db autonomous-database list-available-maintenance-windows --autonomous-database-id "<ADB_OCID>" --all --region "<REGION>" --profile DEFAULT
```

This is a read-only operation; `--all` retrieves every page.

### 3. Edit maintenance-window.json

Copy the day, UTC start/end times and full availability domain identifier from the same returned option. The file contains an illustrative Sunday 01:00–03:00 window; replace it if it is not available for your database.

```json
{
  "dayOfWeek": { "name": "SUNDAY" },
  "maintenanceStartTime": "01:00",
  "maintenanceEndTime": "03:00",
  "availabilityDomain": "<exact-AD-from-available-windows>"
}
```

| CLI response field | Request JSON field |
|---|---|
| `day-of-week.name` | `dayOfWeek.name` |
| `maintenance-start-time` | `maintenanceStartTime` |
| `maintenance-end-time` | `maintenanceEndTime` |
| `availability-domain` | `availabilityDomain` |

Use the complete AD identifier, including its prefix, rather than only a label such as `AD-1`. Do not copy the optional scheduling status flag. Save as UTF-8 JSON using a text editor.

### 4. Request the change

This command performs a real update. Run it once you have reviewed the selected window and confirmed that there is no conflicting request pending:

```text
oci db autonomous-database update --autonomous-database-id "<ADB_OCID>" --scheduled-maintenance-window file://maintenance-window.json --region "<REGION>" --profile DEFAULT
```

`file://maintenance-window.json` reads the file in your current directory. The CLI may ask for confirmation; review it before proceeding.

### 5. Verify scheduling and completion

```text
oci db autonomous-database get --autonomous-database-id "<ADB_OCID>" --region "<REGION>" --profile DEFAULT
```

Check Maintenance schedule and Work requests in the OCI console. Record the assigned execution timestamp. After that time, verify that the new day, hours and AD appear in the active maintenance window. A successful update response is not proof that the transition has completed.

## Scheduling semantics

The JSON describes the new recurring window, not when the transition executes. This example omits `timeScheduledMaintenanceWindowUpdate`, leaving execution-time selection to the service. Check the assigned timestamp in OCI instead of assuming the change happens immediately. This CLI workflow has not yet been live-tested.

The database can be `AVAILABLE` while a change is pending. Changes can involve movement to another AD and a brief service interruption. Do not submit the same update again while the previous request is pending.

The CLI also exposes `--time-scheduled-maintenance-window-update` for an explicit execution timestamp. Explicit future scheduling, cancellation and rescheduling are outside this example's validated scope; review the service's scheduling limits and possible charges before using them.

## Troubleshooting

- Unknown command or option: check `oci --version`. If using the isolated environment, use its executable path consistently.
- `401 NotAuthenticated`: check the selected profile, user/tenancy, fingerprint and matching private key, and system clock.
- `Active Maintenance Window cannot be scheduled`: use `--scheduled-maintenance-window`, not `--autonomous-database-maintenance-window`.
- File not found: run the command from the folder containing `maintenance-window.json`.
- Empty available options: check eligibility and capacity; do not invent a window.

## Validation

The JSON was parsed locally, and command syntax was reviewed against Oracle's OCI CLI documentation. No live API update or cross-platform execution test was performed for this example. Service acceptance and final completion remain to be validated.

## References

- [Install OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)
- [List available windows](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/db/autonomous-database/list-available-maintenance-windows.html)
- [Update Autonomous Database](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/db/autonomous-database/update.html)
- [ADB-S maintenance scheduling](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/maintenance-windows-patching.html)
