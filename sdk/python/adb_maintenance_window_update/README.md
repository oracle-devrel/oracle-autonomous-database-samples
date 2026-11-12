# Python SDK — Update an ADB-S Maintenance Window

A standalone example using the OCI Python SDK to inspect an existing Autonomous Database Serverless instance, list available windows, request a change, and inspect its status. Works with Python on Windows, macOS and Linux; no shell script is required.

## Files

| File | Description |
|---|---|
| `maintenance.py` | Separate `status`, `list` and `update` actions |
| `maintenance-window.json` | Target window; replace the illustrative values |
| `requirements.txt` | OCI SDK 2.191.0 dependency |

## Setup

Use Python 3.10 or later and an eligible existing ADB-S (ECPU, Regular patch level, not Always Free or Developer). Your OCI user needs read/update permissions.

Open a terminal in this directory. Create an isolated Python environment:

**Windows PowerShell or CMD:**

```text
py -m venv .venv
.venv\Scripts\python.exe -m pip install -r requirements.txt
```

**macOS or Linux:**

```text
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
```

Each step below includes the exact command for your operating system. The commands use the virtual environment directly; no activation or global `python` command is required.

### Authentication

The SDK reads the OCI API-key configuration from `.oci/config` in your home directory by default. For example:

```ini
[DEFAULT]
user=ocid1.user...
tenancy=ocid1.tenancy...
fingerprint=<fingerprint-of-registered-public-key>
key_file=<absolute-path-to-corresponding-private-key.pem>
region=us-ashburn-1
```

Register the public key under the specified user's API keys. Keep the private key on your machine. The fingerprint and private key must belong to the same pair. Use `--profile PROFILE_NAME` or `--config-file "PATH"` for another profile or file. The explicit `--region` overrides the profile's region.

## Workflow

Replace `<ADB_OCID>` and `<REGION>` in every command. Run commands from this directory so the default JSON path resolves correctly.

### 1. Read status

**macOS or Linux:**

```text
.venv/bin/python maintenance.py status --adb-id "<ADB_OCID>" --region "<REGION>"
```

**Windows PowerShell or CMD:**

```text
.venv\Scripts\python.exe maintenance.py status --adb-id "<ADB_OCID>" --region "<REGION>"
```

Outputs the database state, active window, pending window and assigned execution time. Inspect any existing pending operation before requesting another change.

### 2. List available windows

**macOS or Linux:**

```text
.venv/bin/python maintenance.py list --adb-id "<ADB_OCID>" --region "<REGION>"
```

**Windows PowerShell or CMD:**

```text
.venv\Scripts\python.exe maintenance.py list --adb-id "<ADB_OCID>" --region "<REGION>"
```

Fetches all pages. This action and `status` are read-only.

### 3. Edit maintenance-window.json

Copy all four values from the same returned option. Output uses snake_case; the input file uses camelCase:

| SDK output | Input JSON |
|---|---|
| `day_of_week.name` | `dayOfWeek.name` |
| `maintenance_start_time` | `maintenanceStartTime` |
| `maintenance_end_time` | `maintenanceEndTime` |
| `availability_domain` | `availabilityDomain` |

Use the full AD identifier, including its prefix. Times are UTC. The sample Sunday 01:00–03:00 window is illustrative, not guaranteed available. Do not copy the scheduling flag into the input file.

### 4. Submit the change

**macOS or Linux:**

```text
.venv/bin/python maintenance.py update --adb-id "<ADB_OCID>" --region "<REGION>" --window-file maintenance-window.json
```

**Windows PowerShell or CMD:**

```text
.venv\Scripts\python.exe maintenance.py update --adb-id "<ADB_OCID>" --region "<REGION>" --window-file maintenance-window.json
```

**This action performs a real update without an interactive confirmation.** Review the database OCID and JSON before running it.

The script validates the JSON, checks that the database is AVAILABLE and has no reported pending window, rejects an unchanged target, and verifies the target against currently available options. It uses the GET response's ETag for concurrency control and disables automatic update retries. Capacity may still change between listing and submitting; OCI makes the final decision.

The SDK call is:

```python
details = oci.database.models.UpdateAutonomousDatabaseDetails(
    scheduled_maintenance_window=target
)
client.update_autonomous_database(adb_id, details)
```

The actual script adds the ETag and retry options. It sends the target window, not the active-window field. A successful response prints `request_accepted`, the work request ID when returned, and a compact database summary.

### 5. Verify scheduling and final completion

**macOS or Linux:**

```text
.venv/bin/python maintenance.py status --adb-id "<ADB_OCID>" --region "<REGION>"
```

**Windows PowerShell or CMD:**

```text
.venv\Scripts\python.exe maintenance.py status --adb-id "<ADB_OCID>" --region "<REGION>"
```

The script does not poll automatically. Check the OCI console's Maintenance schedule and Work requests for progress and the assigned execution time. After that time, verify the target day, hours and AD are active.

`UPDATING` is an in-progress state. `AVAILABLE` or an accepted request does not by itself mean the new window is active. Immediately after submission, pending fields may still be null. Do not resubmit while the operation is being processed.

## Scheduling behavior

The JSON defines the recurring maintenance window. This example does not supply `time_scheduled_maintenance_window_update`; execution-time selection is left to OCI. Verify the assigned timestamp in the console rather than assuming an immediate change. Explicit future scheduling, cancellation and rescheduling are outside this example's scope.

Changing the window can involve movement within the infrastructure or to another AD and a brief service interruption. A local standby may also move. Review the service's eligibility and capacity restrictions.

## Troubleshooting

- `command not found: python`: use the exact virtual-environment executable shown for your OS. If it does not exist, complete Setup first.
- A pip upgrade notice is informational; it does not mean dependency installation or script execution failed.

- `401 NotAuthenticated`: verify the selected profile, registered user/tenancy, matching fingerprint/private key, and system clock.
- Missing model fields or method: install the pinned SDK using the same Python executable that runs the script.
- Pending-window error: inspect the existing operation; this script does not cancel or overwrite it.
- Window unavailable: list options again and choose a current combination.
- Concurrency/precondition failure: re-read state and re-evaluate the target before retrying.
- Timeout or connection loss during update: check status and Work requests before retrying; the service might have accepted the request.
- `Active Maintenance Window cannot be scheduled`: the request must use `scheduled_maintenance_window`.

## References

- [OCI Python SDK configuration](https://docs.oracle.com/en-us/iaas/tools/python/latest/configuration.html)
- [DatabaseClient operations](https://docs.oracle.com/en-us/iaas/tools/python/latest/api/database/client/oci.database.DatabaseClient.html)
- [UpdateAutonomousDatabaseDetails](https://docs.oracle.com/en-us/iaas/tools/python/latest/api/database/models/oci.database.models.UpdateAutonomousDatabaseDetails.html)
- [ADB-S maintenance scheduling](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/maintenance-windows-patching.html)
