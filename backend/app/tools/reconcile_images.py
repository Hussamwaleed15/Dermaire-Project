"""Operational reconciliation command; dry-run default, no keys/secrets printed."""
import argparse
import json
from app.core.database import SessionLocal
from app.services.azure_blob import azure_blob_service
from app.services.image_reconciliation import reconcile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--minimum-age-hours", type=int, default=24)
    args = parser.parse_args()
    with SessionLocal() as db:
        if args.apply and db.bind.dialect.name != "postgresql":
            parser.error("Apply requires PostgreSQL owner locks; SQLite is development only")
        try:
            print(json.dumps(reconcile(db, azure_blob_service, args.apply, args.minimum_age_hours)))
        except Exception:
            raise SystemExit("Image reconciliation failed; no completion claim. Retry after recovery.")


if __name__ == "__main__":
    main()
