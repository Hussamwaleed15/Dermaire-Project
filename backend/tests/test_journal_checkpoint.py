import hashlib
import hmac
import json
from types import SimpleNamespace

import pytest
from azure.core.exceptions import ResourceExistsError

from app.services.deletion_journal import DeletionJournal
from app.tools.checkpoint_journal import canonical, create_checkpoint


class Store:
    def __init__(self, name):
        self.account_name = name
        self.container_name = "intents"
        self.data = {}
        self.metadata = {}
        self.on_upload = None
        self.tamper_read = False

    def get_container_properties(self):
        return {"public_access": None}

    def list_blobs(self):
        return [SimpleNamespace(name=name) for name in self.data]

    def get_blob_client(self, name):
        def upload(payload, overwrite=False, **kwargs):
            assert not overwrite
            if name in self.data:
                raise ResourceExistsError("exists")
            self.data[name] = payload
            self.metadata[name] = kwargs.get("metadata", {})
            if self.on_upload:
                self.on_upload()

        def read():
            payload = self.data[name]
            if self.tamper_read:
                altered = json.loads(payload)
                altered["signature"] = "0" * 64
                return json.dumps(altered).encode()
            return payload

        return SimpleNamespace(upload_blob=upload,
                               download_blob=lambda: SimpleNamespace(readall=read),
                               get_blob_properties=lambda: SimpleNamespace(metadata=self.metadata.get(name, {})))


def fixture():
    source, backup, evidence = Store("source"), Store("backup"), Store("evidence")
    journal = DeletionJournal(source, "k" * 32, True)
    name = journal.record("synthetic-owner", ["synthetic-image"])
    source.metadata[name] = {"synthetic": "true"}
    return source, backup, evidence, journal


def test_checkpoint_preserves_signed_bytes_markers_and_duplicate_backup():
    source, backup, evidence, journal = fixture()
    first = create_checkpoint(source, backup, evidence, journal, boundary="synthetic only")
    second = create_checkpoint(source, backup, evidence, journal, boundary="synthetic only")
    assert first["source_verified"] == second["independent_backup_verified"] == 1
    assert source.data == backup.data and source.metadata == backup.metadata
    envelope = json.loads(evidence.data[first["manifest"]])
    expected = hmac.new(journal.key.encode(),
                        ("journal-checkpoint\0" + canonical(envelope["checkpoint"])).encode(),
                        hashlib.sha256).hexdigest()
    assert hmac.compare_digest(expected, envelope["signature"])


def test_checkpoint_mixed_product_photo_account_inventory():
    source, backup, evidence, journal = fixture()
    journal.record_photos("synthetic-owner", ["orphan"])
    journal.record_product("synthetic-owner", "synthetic-product")
    result = create_checkpoint(source, backup, evidence, journal, boundary="synthetic mixed only")
    assert result["source_verified"] == result["independent_backup_verified"] == 3
    assert source.data == backup.data
    assert {r["schema"] for r in DeletionJournal(backup, journal.key, True).inventory()} == {2, 3}


def test_corrupt_source_blocks_every_backup_and_manifest_write():
    source, backup, evidence, journal = fixture()
    source.data["corrupt.json"] = b"{}"
    with pytest.raises(RuntimeError):
        create_checkpoint(source, backup, evidence, journal, boundary="synthetic only")
    assert not backup.data and not evidence.data


def test_retained_backup_record_missing_from_source_blocks_completeness_claim():
    source, backup, evidence, journal = fixture()
    DeletionJournal(backup, journal.key, True).record("previously-backed-up-owner", [])
    with pytest.raises(RuntimeError, match="Backup inventory differs"):
        create_checkpoint(source, backup, evidence, journal, boundary="synthetic only")
    assert not evidence.data


def test_source_writer_during_copy_cannot_receive_checkpoint_acknowledgement():
    source, backup, evidence, journal = fixture()
    backup.on_upload = lambda: journal.record("late-writer", [])
    with pytest.raises(RuntimeError, match="Source changed"):
        create_checkpoint(source, backup, evidence, journal, boundary="synthetic only")
    assert not evidence.data


def test_corrupt_manifest_readback_is_never_acknowledged():
    source, backup, evidence, journal = fixture()
    evidence.tamper_read = True
    with pytest.raises(RuntimeError, match="checkpoint verification"):
        create_checkpoint(source, backup, evidence, journal, boundary="synthetic only")
