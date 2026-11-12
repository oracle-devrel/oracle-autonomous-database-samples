"""Manage an existing ADB-S maintenance window with the OCI Python SDK."""
import argparse
import json
import re
import sys
from pathlib import Path

import oci


def emit(value):
    print(json.dumps(oci.util.to_dict(value), indent=2, default=str))


def read_window(path):
    value = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    keys = {"dayOfWeek", "maintenanceStartTime", "maintenanceEndTime", "availabilityDomain"}
    if not isinstance(value, dict) or set(value) != keys:
        raise ValueError("Window JSON must contain exactly: " + ", ".join(sorted(keys)))
    day = value["dayOfWeek"]
    if not isinstance(day, dict) or set(day) != {"name"} or day["name"] not in (
        "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"
    ):
        raise ValueError("dayOfWeek must contain an uppercase day name.")
    for key in ("maintenanceStartTime", "maintenanceEndTime"):
        if not isinstance(value[key], str) or not re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", value[key]):
            raise ValueError(key + " must be a UTC time in HH:mm format.")
    ad = value["availabilityDomain"]
    if not isinstance(ad, str) or not ad.strip() or "<" in ad:
        raise ValueError("Set availabilityDomain to the exact AD returned by OCI.")
    return oci.database.models.AutonomousDatabaseMaintenanceWindowSummary(
        day_of_week=oci.database.models.DayOfWeek(name=day["name"]),
        maintenance_start_time=value["maintenanceStartTime"],
        maintenance_end_time=value["maintenanceEndTime"],
        availability_domain=ad,
    )


def signature(window):
    return (window.day_of_week.name, window.maintenance_start_time,
            window.maintenance_end_time, window.availability_domain)


def windows(client, adb_id):
    result, page = [], None
    while True:
        response = client.list_available_maintenance_windows(
            adb_id, **({"page": page} if page else {})
        )
        result.extend(response.data.items)
        page = response.headers.get("opc-next-page")
        if not page:
            return result


def summary(db):
    return {
        "id": db.id,
        "display_name": db.display_name,
        "state": db.lifecycle_state,
        "lifecycle_details": db.lifecycle_details,
        "availability_domain": db.availability_domain,
        "active_window": db.autonomous_database_maintenance_window,
        "scheduled_window": db.scheduled_maintenance_window,
        "change_at": db.time_scheduled_maintenance_window_update,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["status", "list", "update"])
    parser.add_argument("--adb-id", required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--profile", default="DEFAULT")
    parser.add_argument("--config-file", default=oci.config.DEFAULT_LOCATION)
    parser.add_argument("--window-file", default="maintenance-window.json")
    args = parser.parse_args()
    # Validate local input before reading credentials or making API calls.
    target = read_window(args.window_file) if args.action == "update" else None
    config = oci.config.from_file(args.config_file, args.profile)
    config["region"] = args.region
    oci.config.validate_config(config)
    client = oci.database.DatabaseClient(config)
    if args.action == "list":
        emit({"items": windows(client, args.adb_id)})
        return
    response = client.get_autonomous_database(args.adb_id)
    db = response.data
    if args.action == "status":
        emit(summary(db))
        return
    if db.lifecycle_state != "AVAILABLE":
        raise ValueError("Database is " + db.lifecycle_state + "; wait before submitting a change.")
    if db.scheduled_maintenance_window is not None or db.time_scheduled_maintenance_window_update is not None:
        raise ValueError("OCI reports a pending window change. Inspect status and the console first.")
    if db.autonomous_database_maintenance_window and signature(target) == signature(db.autonomous_database_maintenance_window):
        raise ValueError("The selected window is already active.")
    if signature(target) not in {signature(w) for w in windows(client, args.adb_id)}:
        raise ValueError("The selected window is not currently returned as available for this database.")
    details = oci.database.models.UpdateAutonomousDatabaseDetails(scheduled_maintenance_window=target)
    # ETag prevents applying against a database changed since the GET above.
    options = {"retry_strategy": oci.retry.NoneRetryStrategy()}
    if response.headers.get("etag"):
        options["if_match"] = response.headers["etag"]
    result = client.update_autonomous_database(args.adb_id, details, **options)
    emit({"request_accepted": True, "work_request_id": result.headers.get("opc-work-request-id"),
          "opc_request_id": result.headers.get("opc-request-id"), "database": summary(result.data)})
    print("Request accepted; use status and OCI Work requests to verify scheduling and final completion.", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except oci.exceptions.ServiceError as error:
        emit({"status": error.status, "code": error.code, "message": error.message,
              "opc_request_id": error.headers.get("opc-request-id") if error.headers else None})
        sys.exit(1)
    except (ValueError, OSError, oci.exceptions.ConfigFileNotFound,
            oci.exceptions.ProfileNotFound, oci.exceptions.InvalidConfig) as error:
        print("Error: " + str(error), file=sys.stderr)
        sys.exit(1)
