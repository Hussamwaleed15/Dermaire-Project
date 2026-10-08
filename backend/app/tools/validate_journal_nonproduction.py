"""Explicit isolated Azure rehearsal; counts-only output, credentials stay in memory."""
import os
# Never load local .env credentials into application clients.
os.environ.update(ENVIRONMENT='test', DATABASE_URL='sqlite://', AZURE_STORAGE_CONNECTION_STRING='',
                  DELETION_JOURNAL_CONNECTION_STRING='', DELETION_JOURNAL_REQUIRED='false')
import json, secrets, subprocess, sys, time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from types import SimpleNamespace
from unittest.mock import Mock
from azure.storage.blob import BlobServiceClient
from azure.core.exceptions import ResourceExistsError
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from app.services.deletion_journal import DeletionJournal
from app.services.azure_blob import AzureBlobService
from app.services import account_deletion
from app.core.database import Base
from app.models import User, CheckIn, Product, Experiment
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

def az(*args):
    result = subprocess.run(['az.cmd', *args, '-o', 'json'], capture_output=True, text=True)
    if result.returncode: raise RuntimeError('Nonproduction Azure management operation failed')
    return json.loads(result.stdout)

def main():
    group = 'dermaire-readiness-nonprod-20261006'
    account = 'dermairerehearsal261006'
    assert az('group', 'show', '-n', group)['tags']['production'] == 'false'
    info = az('storage', 'account', 'show', '-g', group, '-n', account)
    assert info['resourceGroup'] == group and account != 'dermaireimg479341'
    credential = az('storage', 'account', 'keys', 'list', '-g', group, '-n', account)[0]['value']
    client = BlobServiceClient(f'https://{account}.blob.core.windows.net', credential=credential,
                              connection_timeout=5, read_timeout=10, retry_total=2)
    suffix = secrets.token_hex(6)
    journal_container = client.get_container_client('journal-concurrency-' + suffix)
    photo_container = client.get_container_client('journal-replay-' + suffix)
    created = []; result = {'production_mutations': 0, 'account': account, 'resource_group': group}
    started = time.monotonic()
    try:
        for container in (journal_container, photo_container):
            container.create_container(); created.append(container)
        journal = DeletionJournal(journal_container, secrets.token_hex(32), True)
        ack = set(); calls = 0
        with ThreadPoolExecutor(max_workers=16) as pool:
            for writers in (2, 16):
                barrier = Barrier(writers)
                def write(i):
                    barrier.wait(timeout=20)
                    return journal.record('same', [f'batch-{writers}-{i}'])
                names = list(pool.map(write, range(writers)))
                ack.update(names); calls += writers
                assert len(set(names)) == writers
                result[f'{writers}_writers'] = {'acknowledged': writers, 'retained': len(set(names))}
            for batch in range(10):
                names = list(pool.map(lambda i: journal.record(f'owner-{i%4}', [f'stress-{batch}-{i}']), range(16)))
                ack.update(names); calls += 16
            retries = list(pool.map(lambda _: journal.record('duplicate', ['a', 'b', 'a']), range(32)))
            assert len(set(retries)) == 1
            ack.update(retries); calls += 32
        print('Concurrent Azure writes complete; verifying full inventory', flush=True)
        records = journal.inventory()
        assert len(records) == len(ack) == 179
        result['stress'] = {'batches': 10, 'writers': 16, 'acknowledged_unique': len(ack),
                            'durable_verifiable': len(records), 'successful_calls': calls, 'lost': 0}
        # Prove actual Azure conflict: unconditional create-if-absent must return 409.
        blob = journal_container.get_blob_client(retries[0]); original = blob.download_blob().readall()
        try: blob.upload_blob(b'invalid replacement', overwrite=False)
        except ResourceExistsError as exc:
            assert exc.status_code == 409
            result['azure_create_conflict_status'] = exc.status_code
        else: raise AssertionError('Azure allowed overwrite')
        assert blob.download_blob().readall() == original
        # Persist to actual Azure, then simulate a lost successful response.
        class AmbiguousContainer:
            def get_container_properties(self): return journal_container.get_container_properties()
            def get_blob_client(self, name):
                real = journal_container.get_blob_client(name)
                def upload(*args, **kwargs):
                    real.upload_blob(*args, **kwargs)
                    raise OSError('synthetic lost response after Azure persistence')
                return SimpleNamespace(upload_blob=upload, download_blob=real.download_blob)
        try: DeletionJournal(AmbiguousContainer(), journal.key, True).record('crash-owner', ['crash-image'])
        except OSError: pass
        else: raise AssertionError('Ambiguous persistence acknowledged')
        ack.add(journal.record('crash-owner', ['crash-image']))
        assert len(ack) == len(journal.inventory()) == 180
        result['ambiguous_write'] = {'failure_unacknowledged': True, 'retry_verified': True,
                                     'acknowledged_unique': 180, 'durable_verifiable': 180}
        print('Azure concurrency/conflict/crash checks passed; running offline replay', flush=True)
        # Actual restored synthetic DB and real private Azure photo blobs.
        engine = create_engine('sqlite://'); Base.metadata.create_all(engine)
        storage = AzureBlobService(); storage.is_live = True
        storage.client = client; storage.container_client = photo_container
        assert not storage._has_retention_or_versioning(client.get_service_properties())
        account_deletion.azure_blob_service = storage
        journal.record('restore-user', ['legacy-fixture.png'])
        for name in ('legacy-fixture.png', 'skin_photos/restore-user/orphan.png', 'skin_photos/keep-user/keep.png'):
            photo_container.get_blob_client(name).upload_blob(b'synthetic fixture', overwrite=False)
        with Session(engine) as db:
            db.add_all([User(id='restore-user', email='restore@example.invalid', full_name='Synthetic', hashed_password='unused'),
                        User(id='keep-user', email='keep@example.invalid', full_name='Synthetic', hashed_password='unused')]); db.commit()
            db.add(Product(id='fixture-product', user_id='restore-user', name='Synthetic')); db.commit()
            db.add(Experiment(id='fixture-experiment', user_id='restore-user', product_id='fixture-product')); db.commit()
            db.add(CheckIn(user_id='restore-user', experiment_id='fixture-experiment', date_str='2026-10-08', image_blob_name='legacy-fixture.png')); db.commit()
            before = {b.name: journal_container.get_blob_client(b.name).download_blob().readall() for b in journal_container.list_blobs()}
            first = journal.replay(db, storage, account_deletion.delete_account)
            second = journal.replay(db, storage, account_deletion.delete_account)
            assert first['restored_accounts_removed'] == 1
            assert second['restored_accounts_removed'] == second['image_cleanup_calls'] == 0
            assert db.query(User).count() == 1 and db.query(CheckIn).count() == 0
            assert [b.name for b in photo_container.list_blobs()] == ['skin_photos/keep-user/keep.png']
            after = {b.name: journal_container.get_blob_client(b.name).download_blob().readall() for b in journal_container.list_blobs()}
            assert before == after
            result['replay'] = {'first': first, 'repeat': second, 'source_unchanged': True, 'legacy_orphan_removed': True}
            corrupt = journal_container.get_blob_client('corrupt-fixture.json'); corrupt.upload_blob(b'{}', overwrite=False)
            callback = Mock()
            try: journal.replay(db, storage, callback)
            except RuntimeError: pass
            else: raise AssertionError('Corruption accepted')
            callback.assert_not_called(); corrupt.delete_blob()
            missing = client.get_container_client('absent-' + suffix)
            try: DeletionJournal(missing, journal.key, True).replay(db, storage, callback)
            except Exception: pass
            else: raise AssertionError('Missing storage accepted')
            callback.assert_not_called()
            result['fail_closed'] = {'corruption': True, 'unavailable_storage': True}
        result['final_durable_intents'] = len(journal.inventory())
        result['final_acknowledged_unique'] = len(ack) + 1
        assert result['final_durable_intents'] == result['final_acknowledged_unique'] == 181
        result['seconds'] = round(time.monotonic() - started, 3)
    finally:
        for container in reversed(created):
            container.delete_container()
            assert not container.exists()
        result['temporary_containers_removed'] = True
    target = Path('docs/evidence/journal-concurrency-20261008/azure-result.json')
    target.parent.mkdir(parents=True, exist_ok=True); target.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result))

if __name__ == '__main__':
    try: main()
    except Exception as exc:
        print('Nonproduction rehearsal failed: ' + type(exc).__name__)
        sys.exit(1)
