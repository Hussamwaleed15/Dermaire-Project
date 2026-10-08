import json
from types import SimpleNamespace
from unittest.mock import Mock
import pytest
from azure.core.exceptions import ResourceNotFoundError, ResourceExistsError
from threading import Lock, Barrier
from concurrent.futures import ThreadPoolExecutor
from app.services.deletion_journal import DeletionJournal


class Container:
    def __init__(self):
        self.data = {}
        self.lock = Lock()

    def get_container_properties(self):
        return {"public_access": None}

    def get_blob_client(self, name):
        def read():
            if name not in self.data:
                raise ResourceNotFoundError("absent")
            return self.data[name]
        def upload(value, overwrite, **kwargs):
            assert overwrite is False
            with self.lock:
                if name in self.data:
                    raise ResourceExistsError("exists")
                self.data[name] = value
        return SimpleNamespace(download_blob=lambda: SimpleNamespace(readall=read),
                               upload_blob=upload)

    def list_blobs(self):
        return [SimpleNamespace(name=n) for n in self.data]


def test_private_signed_intents_union_and_key_separation():
    container = Container()
    journal = DeletionJournal(container, "j" * 32, True)
    journal.record("private-user", ["skin_photos/private-user/a"])
    journal.record("private-user", ["legacy-private.jpg"])
    raw = next(iter(container.data.values()))
    assert b"private-user" not in raw and b"legacy-private" not in raw
    assert len({i for r in journal.inventory() for i in r["images"]}) == 2
    assert journal.token("owner", "x") != journal.token("image", "x")
    tampered = json.loads(raw)
    tampered["record"]["images"] = []
    with pytest.raises(RuntimeError):
        journal.validate(tampered)


def test_photo_only_v2_replay_preserves_account_and_sibling_photos():
    container = Container(); journal = DeletionJournal(container, "j" * 32, True)
    image = "skin_photos/kept/deleted.png"
    name = journal.record_photos("kept", [image])
    assert journal.record_photos("kept", [image, image]) == name
    assert len(journal.inventory()) == 1
    assert journal.inventory()[0]["schema"] == 2
    assert journal.inventory()[0]["owner"] != journal.token("owner", "kept")
    assert b"kept" not in container.data[name] and image.encode() not in container.data[name]
    db = Mock(); db.query.return_value = [SimpleNamespace(id="kept")]
    photos = {image, "skin_photos/kept/sibling.png"}
    storage = Mock(is_live=True)
    storage.container_client.list_blobs.side_effect = lambda **_: [SimpleNamespace(name=n) for n in photos]
    storage.delete_image.side_effect = photos.remove
    delete = Mock(); snapshot = dict(container.data)
    result = journal.replay(db, storage, delete)
    delete.assert_not_called()
    assert result["restored_accounts_removed"] == 0 and result["image_cleanup_calls"] == 1
    assert photos == {"skin_photos/kept/sibling.png"}
    assert journal.replay(db, storage, delete)["image_cleanup_calls"] == 0
    assert container.data == snapshot


def test_photo_only_unavailable_journal_and_empty_keys_fail_closed():
    with pytest.raises(RuntimeError):
        DeletionJournal(None, "j" * 32, True).record_photos("kept", ["photo"])
    with pytest.raises(ValueError):
        DeletionJournal(Container(), "j" * 32, True).record_photos("kept", [])


def test_required_store_failure_and_invalid_key_fail_closed():
    with pytest.raises(RuntimeError):
        DeletionJournal(None, "j" * 32, True).record("u", [])
    for key in ("short", ""):
        journal = DeletionJournal(Container(), key, True)
        with pytest.raises(RuntimeError): journal.record("u", [])
        delete = Mock(); storage = Mock(is_live=True)
        with pytest.raises(RuntimeError): journal.replay(Mock(), storage, delete)
        delete.assert_not_called(); storage.delete_image.assert_not_called()


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
    delete.assert_called_once_with(db, "deleted", journal=journal)
    assert result["image_cleanup_calls"] == 2
    assert [c.args[0] for c in storage.delete_image.call_args_list] == ["legacy.jpg", "skin_photos/deleted/orphan"]


def test_corrupt_journal_prevents_all_replay_mutations():
    container = Container()
    container.data["corrupt"] = b"{}"
    journal = DeletionJournal(container, "j" * 32, True)
    delete = Mock()
    with pytest.raises(RuntimeError):
        journal.replay(Mock(), Mock(), delete)
    delete.assert_not_called()


@pytest.mark.parametrize("writers", [2, 16])
def test_concurrent_distinct_intents(writers):
    journal = DeletionJournal(Container(), "j" * 32, True)
    barrier = Barrier(writers)
    def write(i):
        barrier.wait(timeout=10)
        return journal.record("same", [f"legacy-{i}"])
    with ThreadPoolExecutor(max_workers=writers) as pool:
        acknowledged = list(pool.map(write, range(writers)))
    assert len(set(acknowledged)) == len(journal.inventory()) == writers
    assert len({i for r in journal.inventory() for i in r["images"]}) == writers


def test_stress_and_duplicate_conflict():
    journal = DeletionJournal(Container(), "j" * 32, True)
    acknowledged = set()
    with ThreadPoolExecutor(max_workers=16) as pool:
        for batch in range(50):
            acknowledged.update(pool.map(lambda i: journal.record(f"owner-{i % 4}",
                                      [f"legacy-{batch}-{i}"]), range(16)))
        retries = list(pool.map(lambda _: journal.record("duplicate", ["a", "b", "a"]), range(32)))
    acknowledged.update(retries)
    assert len(set(retries)) == 1
    assert len(acknowledged) == len(journal.inventory()) == 801


@pytest.mark.parametrize("mode", ["before", "after", "read", "corrupt", "missing"])
def test_persistence_failure_never_acknowledged(mode):
    container = Container(); original = container.get_blob_client
    def client(name):
        blob = original(name); upload = blob.upload_blob
        def write(value, overwrite, **kwargs):
            if mode == "before": raise OSError("unavailable")
            upload(value, overwrite)
            if mode == "after": raise OSError("response lost")
            if mode == "corrupt": container.data[name] = b'{}'
            if mode == "missing": container.data.pop(name)
        blob.upload_blob = write
        if mode == "read": blob.download_blob = Mock(side_effect=OSError("read unavailable"))
        return blob
    container.get_blob_client = client
    journal = DeletionJournal(container, "j" * 32, True)
    with pytest.raises(Exception): journal.record("u", ["legacy"])
    container.get_blob_client = original
    if mode in {"after", "read"}:
        assert journal.record("u", ["legacy"])
        assert len(journal.inventory()) == 1


def test_legacy_compatibility_and_path_binding():
    container = Container(); journal = DeletionJournal(container, "j" * 32, True)
    legacy = {"schema": 1, "owner": journal.token("owner", "u"), "images": [journal.token("image", "legacy")]}
    name = legacy["owner"] + ".json"
    container.data[name] = json.dumps({"record": legacy, "signature": journal.signature(legacy)}).encode()
    before = container.data[name]
    journal.record("u", ["new"])
    assert len(journal.inventory()) == 2 and container.data[name] == before
    container.data["wrong.json"] = container.data.pop(name)
    with pytest.raises(RuntimeError): journal.inventory()


@pytest.mark.parametrize("fault", ["signature", "key", "storage"])
def test_replay_integrity_preflight(fault):
    container = Container(); journal = DeletionJournal(container, "j" * 32, True)
    journal.record("u", ["legacy"])
    if fault == "signature":
        name = next(iter(container.data)); envelope = json.loads(container.data[name]); envelope.pop("signature")
        container.data[name] = json.dumps(envelope).encode()
    elif fault == "key": journal.key = "wrong" * 8
    else: container.list_blobs = Mock(side_effect=OSError("unavailable"))
    delete = Mock(); storage = Mock(is_live=True)
    with pytest.raises(Exception): journal.replay(Mock(), storage, delete)
    delete.assert_not_called(); storage.delete_image.assert_not_called()


def test_replay_repeat_noop_and_source_readonly():
    container = Container(); journal = DeletionJournal(container, "j" * 32, True)
    journal.record("u", ["legacy"]); snapshot = dict(container.data)
    users = [SimpleNamespace(id="u"), SimpleNamespace(id="kept")]
    photos = {"legacy", "skin_photos/u/orphan", "skin_photos/kept/a"}
    db = Mock(); db.query.side_effect = lambda _: list(users)
    storage = Mock(is_live=True)
    storage.container_client.list_blobs.side_effect = lambda **_: [SimpleNamespace(name=n) for n in photos]
    storage.delete_image.side_effect = photos.remove
    def delete(db, uid, **kwargs): users[:] = [u for u in users if u.id != uid]
    first = journal.replay(db, storage, delete); second = journal.replay(db, storage, delete)
    assert first["restored_accounts_removed"] == 1 and first["image_cleanup_calls"] == 2
    assert second["restored_accounts_removed"] == second["image_cleanup_calls"] == 0
    assert container.data == snapshot


def test_existing_valid_but_wrong_record_is_not_acknowledged():
    container = Container(); journal = DeletionJournal(container, "j" * 32, True)
    expected = {"schema": 2, "owner": journal.token("owner", "u"),
                "images": [journal.token("image", "a")]}
    wrong = dict(expected, images=[])
    container.data[journal.record_name(expected)] = json.dumps(
        {"record": wrong, "signature": journal.signature(wrong)}).encode()
    with pytest.raises(RuntimeError, match="persistence mismatch"):
        journal.record("u", ["a"])


def test_duplicate_retry_cannot_accept_corrupt_existing_record():
    container = Container(); journal = DeletionJournal(container, "j" * 32, True)
    name = journal.record("u", ["a"]); container.data[name] = b'{}'
    with pytest.raises(RuntimeError): journal.record("u", ["a"])


def test_account_only_and_image_intents_for_distinct_owners_concurrently():
    journal = DeletionJournal(Container(), "j" * 32, True)
    inputs = [("account-a", []), ("account-a", ["legacy-a"]), ("account-b", ["legacy-b"])]
    barrier = Barrier(3)
    def write(intent):
        barrier.wait(timeout=10)
        return journal.record(*intent)
    with ThreadPoolExecutor(max_workers=3) as pool:
        acknowledged = list(pool.map(write, inputs))
    records = journal.inventory()
    assert len(set(acknowledged)) == len(records) == 3
    assert len({r["owner"] for r in records}) == 2
    assert any(not r["images"] for r in records)
