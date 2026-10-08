"""Independent, signed deletion intents. No names, email, IDs or image keys."""
import hashlib
import hmac
import json
from app.core.config import settings


class DeletionJournal:
    def __init__(self, container=None, key=None, required=None):
        self.container = container
        self.key = key if key is not None else settings.DELETION_JOURNAL_HMAC_KEY
        self.required = required if required is not None else settings.DELETION_JOURNAL_REQUIRED
        if container is None and settings.DELETION_JOURNAL_ACCOUNT_URL:
            from urllib.parse import urlsplit
            from azure.identity import ManagedIdentityCredential
            from azure.storage.blob import BlobServiceClient
            if settings.DELETION_JOURNAL_CONNECTION_STRING:
                raise ValueError("Choose one journal authentication mode")
            endpoint = urlsplit(settings.DELETION_JOURNAL_ACCOUNT_URL)
            if (endpoint.scheme != "https" or not endpoint.hostname
                    or endpoint.username or endpoint.password or endpoint.query
                    or endpoint.fragment or endpoint.path not in {"", "/"}):
                raise ValueError("Credential-free HTTPS journal account endpoint required")
            credential = ManagedIdentityCredential(
                client_id=settings.DELETION_JOURNAL_MANAGED_IDENTITY_CLIENT_ID or None)
            client = BlobServiceClient(settings.DELETION_JOURNAL_ACCOUNT_URL,
                                      credential=credential, connection_timeout=5,
                                      read_timeout=10, retry_total=2)
            self.container = client.get_container_client(settings.DELETION_JOURNAL_CONTAINER)
        if container is None and settings.DELETION_JOURNAL_CONNECTION_STRING:
            from azure.storage.blob import BlobServiceClient
            client = BlobServiceClient.from_connection_string(
                settings.DELETION_JOURNAL_CONNECTION_STRING,
                connection_timeout=5, read_timeout=10, retry_total=2)
            if not client.url.startswith("https://"):
                raise ValueError("HTTPS journal required")
            self.container = client.get_container_client(settings.DELETION_JOURNAL_CONTAINER)

    def token(self, kind, value):
        if len(self.key) < 32:
            raise RuntimeError("Independent journal key required")
        return hmac.new(self.key.encode(), (kind + "\0" + value).encode(), hashlib.sha256).hexdigest()

    def health(self):
        if self.container is None or not self.required:
            return "unconfigured"
        try:
            self.token("health", "probe")
            if self.container.get_container_properties(connection_timeout=3, read_timeout=3, retry_total=0).get("public_access"):
                raise RuntimeError("Journal must be private")
            return "available"
        except Exception:
            return "unavailable"

    def signature(self, record):
        return self.token("record", json.dumps(record, sort_keys=True, separators=(",", ":")))

    @staticmethod
    def canonical(record):
        return json.dumps(record, sort_keys=True, separators=(",", ":"))

    def validate(self, envelope):
        try:
            record = envelope["record"]
            if (set(record) != {"schema", "owner", "images"}
                    or type(record["schema"]) is not int or record["schema"] not in {1, 2}
                    or not isinstance(record["images"], list)
                    or any(not isinstance(x, str) or len(x) != 64
                           or any(c not in "0123456789abcdef" for c in x)
                           for x in [record["owner"], *record["images"]])
                    or (record["schema"] == 2 and record["images"] != sorted(set(record["images"])))
                    or not hmac.compare_digest(self.signature(record), envelope["signature"])):
                raise ValueError()
            return record
        except Exception:
            raise RuntimeError("Invalid deletion journal; recovery must remain offline") from None

    def record_name(self, record):
        return "v2/" + hashlib.sha256(self.canonical(record).encode()).hexdigest() + ".json"

    def inventory(self):
        """Verify every record and its binding before returning any replay input."""
        if self.container is None:
            raise RuntimeError("Journal required for restore")
        self.token("health", "probe")
        if self.container.get_container_properties().get("public_access"):
            raise RuntimeError("Journal must be private")
        records = []
        for blob in self.container.list_blobs():
            record = self.validate(json.loads(self.container.get_blob_client(blob.name)
                                             .download_blob().readall()))
            expected = self.record_name(record) if record["schema"] == 2 else record["owner"] + ".json"
            if blob.name != expected:
                raise RuntimeError("Journal record path mismatch")
            records.append(record)
        return records

    def record(self, owner_id, image_keys):
        if self.container is None:
            if self.required:
                raise RuntimeError("Deletion journal unavailable")
            return
        if self.container.get_container_properties().get("public_access"):
            raise RuntimeError("Journal must be private")
        from azure.core.exceptions import ResourceExistsError
        record = {"schema": 2, "owner": self.token("owner", owner_id),
                  "images": sorted({self.token("image", name) for name in image_keys})}
        blob = self.container.get_blob_client(self.record_name(record))
        payload = json.dumps({"record": record, "signature": self.signature(record)}).encode()
        # Azure block-blob create with overwrite=False is atomic create-if-absent.
        # An ambiguous transport failure is not acknowledged; retry is deterministic.
        try:
            blob.upload_blob(payload, blob_type="BlockBlob", overwrite=False)
        except ResourceExistsError:
            pass  # Concurrent identical intent/retry: verify exact existing content.
        durable = self.validate(json.loads(blob.download_blob().readall()))
        if durable != record:
            raise RuntimeError("Journal persistence mismatch")
        return self.record_name(record)

    def replay(self, db, storage, delete_account):
        """Offline only. Verify complete journal before any mutation; fail closed."""
        if self.container is None:
            raise RuntimeError("Journal required for restore")
        if self.container.get_container_properties().get("public_access"):
            raise RuntimeError("Journal must be private")
        if not storage.is_live:
            raise RuntimeError("Restore requires configured Azure photo storage")
        records = self.inventory()
        owners = {r["owner"] for r in records}
        images = {i for r in records for i in r["images"]}
        from app.models import User
        user_ids = [u.id for u in db.query(User) if self.token("owner", u.id) in owners]
        for owner_id in user_ids:
            delete_account(db, owner_id, journal=self)
        deleted = 0
        # Scan also catches restored orphan uploads; never store their raw keys.
        for blob in list(storage.container_client.list_blobs(include=["deleted", "versions", "snapshots"])):
            parts = blob.name.split("/")
            owned = len(parts) >= 3 and parts[0] == "skin_photos" and self.token("owner", parts[1]) in owners
            if owned or self.token("image", blob.name) in images:
                storage.delete_image(blob.name)
                deleted += 1
        return {"restored_accounts_removed": len(user_ids), "image_cleanup_calls": deleted,
                "journal_intents": len(records)}


deletion_journal = DeletionJournal()
