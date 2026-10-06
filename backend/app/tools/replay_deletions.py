"""Run with offline nonproduction restore target settings, never public traffic."""
import argparse
import json
from app.core.config import settings
from app.core.database import SessionLocal
from app.services.account_deletion import delete_account
from app.services.azure_blob import azure_blob_service
from app.services.deletion_journal import deletion_journal


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--offline-restore-target", required=True)
    args = parser.parse_args()
    from sqlalchemy.engine import make_url
    host = make_url(settings.DATABASE_URL).host
    if (settings.ENVIRONMENT not in {"test", "staging"} or not host
            or host != args.offline_restore_target
            or not settings.DELETION_JOURNAL_REQUIRED):
        raise RuntimeError("Explicit offline test/staging target and required journal needed")
    with SessionLocal() as db:
        result = deletion_journal.replay(db, azure_blob_service, delete_account)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
