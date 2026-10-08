"""Frozen-writer journal checkpoint to an independent WORM account; never deletes.

Use only after the release/recovery owner has frozen every journal writer.
This is an explicit checkpoint, not a scheduler or a historical coverage claim.
Credentials and the signing secret stay in memory; output contains counts only.
"""
import argparse
import datetime
import hashlib
import hmac
import json
import os
import sys
import urllib.request


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def create_checkpoint(source, backup, evidence, journal, *, boundary):
    """Verify both inventories, copy atomically, and protect a signed manifest."""
    from azure.core.exceptions import ResourceExistsError
    from app.services.deletion_journal import DeletionJournal

    if any(c.get_container_properties().get("public_access")
           for c in (source, backup, evidence)):
        raise RuntimeError("Private checkpoint containers required")
    # Full verification precedes any copy. A corrupt/unknown object fails closed.
    journal.inventory()
    objects = {}
    for blob in source.list_blobs():
        payload = source.get_blob_client(blob.name).download_blob().readall()
        record = journal.validate(json.loads(payload))
        expected = journal.record_name(record) if record["schema"] == 2 else record["owner"] + ".json"
        if expected != blob.name:
            raise RuntimeError("Source path binding failed")
        target = backup.get_blob_client(blob.name)
        try:
            target.upload_blob(payload, blob_type="BlockBlob", overwrite=False,
                               metadata=dict(source.get_blob_client(blob.name).get_blob_properties().metadata or {}))
        except ResourceExistsError:
            pass
        if target.download_blob().readall() != payload:
            raise RuntimeError("Protected backup differs from source")
        objects[blob.name] = hashlib.sha256(payload).hexdigest()

    backup_journal = DeletionJournal(backup, journal.key, True)
    backup_journal.inventory()
    backup_names = {b.name for b in backup.list_blobs()}
    if backup_names != set(objects):
        raise RuntimeError("Backup inventory differs; reconcile retained evidence offline")
    current = {b.name: hashlib.sha256(source.get_blob_client(b.name).download_blob().readall()).hexdigest()
               for b in source.list_blobs()}
    if current != objects:
        raise RuntimeError("Source changed during checkpoint; remain offline")
    stamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
    checkpoint = {"schema": 1, "observed_utc": stamp, "coverage_boundary": boundary,
                  "source_account": source.account_name, "source_container": source.container_name,
                  "backup_account": backup.account_name, "backup_container": backup.container_name,
                  "objects": objects}
    signature = hmac.new(journal.key.encode(), ("journal-checkpoint\0" + canonical(checkpoint)).encode(),
                         hashlib.sha256).hexdigest()
    envelope = {"checkpoint": checkpoint, "signature": signature}
    payload = canonical(envelope).encode()
    name = "checkpoints/" + stamp.replace(":", "").replace("+", "_") + ".json"
    try:
        evidence.get_blob_client(name).upload_blob(payload, blob_type="BlockBlob", overwrite=False)
    except ResourceExistsError:
        pass  # Same clock tick/retry is acknowledged only after exact read-back.
    downloaded = json.loads(evidence.get_blob_client(name).download_blob().readall())
    expected = hmac.new(journal.key.encode(),
                        ("journal-checkpoint\0" + canonical(downloaded["checkpoint"])).encode(),
                        hashlib.sha256).hexdigest()
    if downloaded != envelope or not hmac.compare_digest(downloaded["signature"], expected):
        raise RuntimeError("Protected checkpoint verification failed")
    return {"gate": "PASS", "observed_utc": stamp, "source_verified": len(objects),
            "independent_backup_verified": len(backup_names), "manifest": name,
            "manifest_sha256": hashlib.sha256(payload).hexdigest(), "source_unchanged": True}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--writers-frozen", action="store_true", required=True)
    parser.add_argument("--coverage-boundary", required=True,
                        help="Explicit evidence boundary; do not claim historical/live hooks")
    parser.add_argument("--secret-uri", required=True,
                        help="Pinned Azure Key Vault secret version URI, never its value")
    args = parser.parse_args()
    # No local dotenv credential may activate a DB/photo client in this tool.
    os.environ.update(ENVIRONMENT="test", DATABASE_URL="sqlite://",
                      AZURE_STORAGE_CONNECTION_STRING="", DELETION_JOURNAL_ACCOUNT_URL="",
                      DELETION_JOURNAL_CONNECTION_STRING="", DELETION_JOURNAL_REQUIRED="false")
    from azure.identity import AzureCliCredential
    from azure.storage.blob import BlobServiceClient
    from app.services.deletion_journal import DeletionJournal

    credential = AzureCliCredential()
    sub = "384c0376-d023-4a61-9dce-69ff8cbdcd0c"
    group = "/subscriptions/" + sub + "/resourceGroups/dermaire-journal-prod"
    primary = "dermairejrnlprod261008"
    secondary = "dermairejrnlbkprod261008"
    token = credential.get_token("https://management.azure.com/.default").token

    def get(url):
        with urllib.request.urlopen(urllib.request.Request(url,
                headers={"Authorization": "Bearer " + token}), timeout=30) as response:
            return json.load(response)

    for account, containers in [(primary, ["intents"]),
                                (secondary, ["intents-copy", "protected-evidence"])]:
        rid = group + "/providers/Microsoft.Storage/storageAccounts/" + account
        props = get("https://management.azure.com" + rid + "?api-version=2023-05-01")["properties"]
        if (props.get("allowSharedKeyAccess") is not False
                or props.get("allowBlobPublicAccess") is not False
                or not props.get("supportsHttpsTrafficOnly")
                or props["networkAcls"]["defaultAction"] != "Deny"
                or props["networkAcls"].get("bypass") != "None"):
            raise RuntimeError("Protected account posture failed")
        try:
            policy = get("https://management.azure.com" + rid + "/managementPolicies/default?api-version=2023-05-01")
        except urllib.error.HTTPError as exc:
            if exc.code != 404:
                raise
        else:
            # A future lifecycle review must be explicit; this tool accepts none.
            if policy.get("properties", {}).get("policy", {}).get("rules"):
                raise RuntimeError("Lifecycle rule requires separate retention review")
        for container in containers:
            p = get("https://management.azure.com" + rid + "/blobServices/default/containers/"
                    + container + "?api-version=2023-05-01")["properties"]
            hold = p.get("legalHold", {})
            if not p.get("hasLegalHold") or hold.get("protectedAppendWritesHistory", {}).get("allowProtectedAppendWritesAll"):
                raise RuntimeError("Indefinite no-overwrite hold required")

    vault_token = credential.get_token("https://vault.azure.net/.default").token
    from urllib.parse import urlsplit
    secret_uri = args.secret_uri
    parsed = urlsplit(secret_uri)
    if (parsed.scheme != "https" or parsed.hostname != "dermaire-journal-prod-kv.vault.azure.net"
            or parsed.query or parsed.fragment or parsed.username or parsed.password
            or not parsed.path.startswith("/secrets/deletion-journal-hmac-v1/")
            or len(parsed.path.split("/")) != 4 or not parsed.path.split("/")[-1]):
        raise RuntimeError("Explicit pinned production key version required")
    with urllib.request.urlopen(urllib.request.Request(secret_uri + "?api-version=7.4",
            headers={"Authorization": "Bearer " + vault_token}), timeout=30) as response:
        secret = json.load(response)
    if secret["attributes"].get("exp"):
        raise RuntimeError("Journal signing key must not expire")
    source = BlobServiceClient("https://" + primary + ".blob.core.windows.net", credential=credential).get_container_client("intents")
    client = BlobServiceClient("https://" + secondary + ".blob.core.windows.net", credential=credential)
    result = create_checkpoint(source, client.get_container_client("intents-copy"),
                               client.get_container_client("protected-evidence"),
                               DeletionJournal(source, secret["value"], True), boundary=args.coverage_boundary)
    print(json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"gate": "FAIL", "failure_type": type(exc).__name__,
                          "details": "withheld; recovery must remain offline"}))
        sys.exit(1)
