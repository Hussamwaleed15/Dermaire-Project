import json
from types import SimpleNamespace
from unittest.mock import Mock
import pytest
from azure.core.exceptions import ResourceNotFoundError
from app.services.deletion_journal import DeletionJournal


class Container:
    def __init__(self):
        self.data = {}

    def get_container_properties(self):
        return {"public_access": None}

    def get_blob_client(self, name):
        def read():
            if name not in self.data:
                raise ResourceNotFoundError("absent")
            return self.data[name]
        return SimpleNamespace(download_blob=lambda: SimpleNamespace(readall=read),
                               upload_blob=lambda value, overwrite: self.data.__setitem__(name, value))

    def list_blobs(self):
        return [SimpleNamespace(name=n) for n in self.data]


def test_private_signed_intents_union_and_key_separation():
    container = Container()
    journal = DeletionJournal(container, "j" * 32, True)
    journal.record("private-user", ["skin_photos/private-user/a"])
    journal.record("private-user", ["legacy-private.jpg"])
    raw = next(iter(container.data.values()))
    assert b"private-user" not in raw and b"legacy-private" not in raw
    record = journal.validate(json.loads(raw))
    assert len(record["images"]) == 2
    assert journal.token("owner", "x") != journal.token("image", "x")
    tampered = json.loads(raw)
    tampered["record"]["images"] = []
    with pytest.raises(RuntimeError):
        journal.validate(tampered)


def test_required_store_failure_and_invalid_key_fail_closed():
    with pytest.raises(RuntimeError):
        DeletionJournal(None, "j" * 32, True).record("u", [])
    with pytest.raises(RuntimeError):
        DeletionJournal(Container(), "short", True).record("u", [])


def test_restore_replays_accounts_legacy_and_orphan_images():
    journal = DeletionJournal(Container(), "j" * 32, True)
    journal.record("deleted", ["legacy.jpg"])
    db = Mock()
    db.query.return_value = [SimpleNamespace(id="deleted"), SimpleNamespace(id="kept")]
    storage = Mock(is_live=True)
    storage.container_client.list_blobs.return_value = [
        SimpleNamespace(name=n) for n in ("legacy.jpg", "skin_photos/deleted/orphan", "skin_photos/kept/a")]
    delete = Mock()
    result = journal.replay(db, storage, delete)
    delete.assert_called_once_with(db, "deleted")
    assert result["image_cleanup_calls"] == 2
    assert [c.args[0] for c in storage.delete_image.call_args_list] == ["legacy.jpg", "skin_photos/deleted/orphan"]


def test_corrupt_journal_prevents_all_replay_mutations():
    container = Container()
    container.data["corrupt"] = b"{}"
    journal = DeletionJournal(container, "j" * 32, True)
    delete = Mock()
    with pytest.raises(KeyError):
        journal.replay(Mock(), Mock(), delete)
    delete.assert_not_called()
