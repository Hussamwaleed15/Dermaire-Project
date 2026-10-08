"""Explicit isolated Azure rehearsal; counts-only output, credentials stay in memory."""
import os
# Never load local .env credentials into application clients.
os.environ.update(ENVIRONMENT='test', DATABASE_URL='sqlite://', AZURE_STORAGE_CONNECTION_STRING='',
                  DELETION_JOURNAL_CONNECTION_STRING='', DELETION_JOURNAL_ACCOUNT_URL='', DELETION_JOURNAL_REQUIRED='false')
import json, secrets, subprocess, sys, time, requests, datetime
from azure.core.credentials import AccessToken
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
    return json.loads(result.stdout) if result.stdout.strip() else None

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
    result['started_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    try:
        for container in (journal_container, photo_container):
            container.create_container(); created.append(container)
        scope=info['id']+'/blobServices/default/containers/'+journal_container.container_name
        role_name='Dermaire Journal Read Write No Delete Nonprod'
        role={'Name':role_name,'IsCustom':True,'Description':'Read/list and block blob write only; requires WORM hold','Actions':['Microsoft.Storage/storageAccounts/blobServices/containers/read'],'DataActions':['Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read','Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write'],'NotActions':[],'NotDataActions':[],'AssignableScopes':[info['id'].split('/providers/')[0]]}
        Path('work').mkdir(exist_ok=True)
        Path('work/role.json').write_text(json.dumps(role))
        existing = az('role','definition','list','--name',role_name)
        if not existing:
            az('role','definition','create','--role-definition','work/role.json')
        else:
            permissions = existing[0]['permissions']
            assert len(permissions) == 1
            for field in ('Actions', 'DataActions', 'NotActions', 'NotDataActions'):
                assert set(permissions[0][field[0].lower() + field[1:]]) == set(role[field])
            assert existing[0]['assignableScopes'] == role['AssignableScopes']
        Path('work/role.json').unlink()
        principal=az('ad','sp','create-for-rbac','--name','dermaire-journal-nonprod-'+suffix,'--skip-assignment')
        pid=az('ad','sp','show','--id',principal['appId'])['id']
        assignment=az('role','assignment','create','--assignee-object-id',pid,'--assignee-principal-type','ServicePrincipal','--role',role_name,'--scope',scope)
        result['identity']={'mode':'Entra service principal OAuth','app_id':principal['appId'],'object_id':pid,'tenant':principal['tenant']}
        result['rbac']={'name':role_name,'scope':scope,'definition':role}
        az('storage','container','legal-hold','set','-g',group,'--account-name',account,'-c',journal_container.container_name,'--tags','authmilestone','--w-all','false')
        class Credential:
            cached=None
            def get_token(self,*scopes,**kwargs):
                if self.cached and self.cached.expires_on > time.time()+300: return self.cached
                r=requests.post('https://login.microsoftonline.com/'+principal['tenant']+'/oauth2/v2.0/token',data={'grant_type':'client_credentials','client_id':principal['appId'],'client_secret':principal['password'],'scope':'https://storage.azure.com/.default'},timeout=20)
                if r.status_code!=200: raise RuntimeError('OAuth failed')
                t=r.json(); self.cached=AccessToken(t['access_token'],int(time.time())+int(t['expires_in'])); return self.cached
        oauth=BlobServiceClient(f'https://{account}.blob.core.windows.net',credential=Credential(),retry_total=0)
        admin_journal=journal_container
        journal_container=oauth.get_container_client(admin_journal.container_name)
        journal=DeletionJournal(journal_container,secrets.token_hex(32),True)
        for attempt in range(60):
            try: journal.record('same', ['batch-2-0']); break
            except Exception:
                if attempt==59: raise
                time.sleep(10)
        result['properties_oauth']='PASS'
        try: oauth.get_container_client(photo_container.container_name).get_container_properties()
        except Exception as e: result['sibling_container_denied']={'status':getattr(e,'status_code',None)}
        else: raise AssertionError('Scope escaped')
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
            corrupt_container=client.get_container_client('auth-corrupt-'+suffix); corrupt_container.create_container(); created.append(corrupt_container)
            corrupt_assignment=az('role','assignment','create','--assignee-object-id',pid,'--assignee-principal-type','ServicePrincipal','--role',role_name,'--scope',info['id']+'/blobServices/default/containers/'+corrupt_container.container_name)
            corrupt=corrupt_container.get_blob_client('corrupt-fixture.json'); corrupt.upload_blob(b'{}',overwrite=False)
            corrupt_oauth=oauth.get_container_client(corrupt_container.container_name)
            for attempt in range(60):
                try: corrupt_oauth.get_container_properties(); break
                except Exception:
                    if attempt==59: raise
                    time.sleep(10)
            callback = Mock()
            try: DeletionJournal(oauth.get_container_client(corrupt_container.container_name),journal.key,True).replay(db, storage, callback)
            except RuntimeError: pass
            else: raise AssertionError('Corruption accepted')
            callback.assert_not_called(); corrupt.delete_blob()
            missing = oauth.get_container_client('absent-' + suffix)
            try: DeletionJournal(missing, journal.key, True).replay(db, storage, callback)
            except Exception: pass
            else: raise AssertionError('Missing storage accepted')
            callback.assert_not_called()
            result['fail_closed'] = {'corruption': True, 'unavailable_storage': True}
        result['final_durable_intents'] = len(journal.inventory())
        result['final_acknowledged_unique'] = len(ack) + 1
        assert result['final_durable_intents'] == result['final_acknowledged_unique'] == 181
        print('Replay/corruption/unavailable checks passed; checking legacy and revoke/restore',flush=True)
        legacy={'schema':1,'owner':journal.token('owner','legacy-v1'),'images':[]}
        journal_container.get_blob_client(legacy['owner']+'.json').upload_blob(json.dumps({'record':legacy,'signature':journal.signature(legacy)}).encode(),overwrite=False)
        assert any(r['schema']==1 for r in journal.inventory())
        with Session(engine) as db:
            mixed=journal.replay(db,storage,account_deletion.delete_account)
            assert mixed['restored_accounts_removed']==mixed['image_cleanup_calls']==0
            result['mixed_v1_v2_replay']=mixed
        result['v1_compatibility']=True
        for op,fn in [('delete',lambda:journal_container.get_blob_client(retries[0]).delete_blob()),('overwrite',lambda:journal_container.get_blob_client(retries[0]).upload_blob(b'forbidden',overwrite=True))]:
            try: fn()
            except Exception as e: result[op+'_denied']={'status':getattr(e,'status_code',None),'code':str(getattr(e,'error_code',''))}
            else: raise AssertionError('Forbidden operation allowed')
        az('role','assignment','delete','--ids',assignment['id'])
        for attempt in range(60):
            try: journal_container.get_container_properties()
            except Exception: break
            if attempt==59: raise AssertionError('Revocation not observed')
            time.sleep(10)
        try: journal.record('blocked-fixture',[])
        except Exception: result['revoked_write_fail_closed']=True
        else: raise AssertionError('Revoked write allowed')
        callback=Mock()
        try: journal.replay(Mock(),Mock(is_live=True),callback)
        except Exception: pass
        else: raise AssertionError('Revoked replay allowed')
        callback.assert_not_called(); result['revoke_fail_closed']=True
        assignment=az('role','assignment','create','--assignee-object-id',pid,'--assignee-principal-type','ServicePrincipal','--role',role_name,'--scope',scope)
        for attempt in range(60):
            try: journal.record('same',['batch-2-0']); break
            except Exception:
                if attempt==59: raise
                time.sleep(10)
        result['restore_recovery']=True
        result['seconds']=round(time.monotonic()-started,3)
    finally:
        if 'assignment' in locals(): az('role','assignment','delete','--ids',assignment['id'])
        if 'corrupt_assignment' in locals(): az('role','assignment','delete','--ids',corrupt_assignment['id'])
        if 'principal' in locals(): az('ad','app','delete','--id',principal['appId'])
        if 'admin_journal' in locals(): az('storage','container','legal-hold','clear','-g',group,'--account-name',account,'-c',admin_journal.container_name,'--tags','authmilestone')
        for container in reversed(created):
            container.delete_container()
            assert not container.exists()
        result['temporary_containers_removed'] = True
        if 'pid' in locals():
            assert not [r for r in az('role', 'assignment', 'list', '--all') if r['principalId'] == pid]
            assert not az('ad', 'app', 'list', '--app-id', principal['appId'])
            result['ephemeral_principal_and_assignments_removed'] = True
    result['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    target = Path('docs/evidence/journal-auth-20261008/azure-result.json')
    target.parent.mkdir(parents=True, exist_ok=True); target.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result))

if __name__ == '__main__':
    try: main()
    except Exception as exc:
        print('Nonproduction rehearsal failed: ' + type(exc).__name__)
        sys.exit(1)
