"""List available maintenance windows without modifying an Autonomous Database."""
import argparse
import json

import oci


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb-id", required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--config-file", default=oci.config.DEFAULT_LOCATION)
    parser.add_argument("--profile", default="DEFAULT")
    args = parser.parse_args()
    config = oci.config.from_file(args.config_file, args.profile)
    config["region"] = args.region
    client = oci.database.DatabaseClient(config)
    items = []
    page = None
    while True:
        kwargs = {"page": page} if page else {}
        response = client.list_available_maintenance_windows(args.adb_id, **kwargs)
        items.extend(oci.util.to_dict(response.data)["items"])
        page = response.headers.get("opc-next-page")
        if not page:
            break
    print(json.dumps({"items": items}, indent=2))


if __name__ == "__main__":
    main()
