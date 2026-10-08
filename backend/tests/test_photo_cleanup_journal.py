from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import Mock
import pytest
from app.services import image_reconciliation as cleanup


@pytest.mark.parametrize("mode", ["failed_upload", "orphan"])
@pytest.mark.parametrize("unavailable", [False, True])
def test_photo_cleanup_durable_intent_precedes_delete(monkeypatch, mode, unavailable):
    owner = "disposable-owner"
    name = f"skin_photos/{owner}/{owner}_00000000-0000-0000-0000-000000000000.png"
    db = Mock(); db.query.return_value.filter_by.return_value.first.return_value = None
    storage = Mock()
    storage.container_client.list_blobs.return_value = [SimpleNamespace(
        name=name, last_modified=datetime.now(timezone.utc) - timedelta(hours=25))]
    events = []
    journal = Mock()
    def record(uid, keys):
        assert uid == owner and keys == [name]
        events.append("durable")
        if unavailable: raise RuntimeError("journal unavailable")
    journal.record_photos.side_effect = record
    monkeypatch.setattr(cleanup, "deletion_journal", journal)
    storage.delete_image.side_effect = lambda key: events.append("delete")
    def run():
        if mode == "failed_upload": cleanup.cleanup_failed_upload(db, storage, owner, name)
        else: cleanup.reconcile(db, storage, apply=True)
    if unavailable:
        with pytest.raises(RuntimeError): run()
        storage.delete_image.assert_not_called()
    else:
        run(); assert events == ["durable", "delete"]
        storage.delete_image.assert_called_once_with(name)
