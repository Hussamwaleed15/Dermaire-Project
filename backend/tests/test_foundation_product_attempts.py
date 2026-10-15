from datetime import datetime, timedelta, timezone
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from pathlib import Path
from unittest.mock import Mock
import pytest
from fastapi import Request, Response, HTTPException
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session
from alembic import command
from alembic.config import Config
from app.models import User, Product, ProductCreateAttempt, AuditLog
from app.schemas import ProductCreate
from app.core.config import settings
from app.core.security import create_access_token
from app.api.v1.products import create_product
from app.services import product_attempts
from app.services.deletion_journal import deletion_journal
from app.services.azure_blob import azure_blob_service
from tests.test_account_deletion import deletion_context
from tests.test_postgres_gate import pg_engine, seed

KEY='synthetic-product-attempt-0001'
BODY={'name':'Synthetic new product', 'in_routine':False}
PATH='/api/v1/products'


def test_create_replay_restart_frozen_after_edit_and_delete(deletion_context, monkeypatch):
    client, db, auth=deletion_context
    headers={**auth,'Idempotency-Key':KEY}
    first=client.post(PATH,headers=headers,json=BODY)
    assert first.status_code == 201,first.text
    original=first.json(); resource=original['id']
    assert first.headers['operation-attempt-id']
    assert first.headers['etag'] == '"1"'
    assert client.patch(PATH+'/'+resource,headers={**auth,'If-Match':'"1"'},json={'notes':'Later'}).status_code == 200
    db.expire_all()
    lookup=client.get(PATH+'/attempts/'+KEY,headers=auth)
    assert lookup.headers['cache-control'] == 'no-store'
    assert lookup.json()['result'] == original
    again=client.post(PATH,headers=headers,json=BODY)
    assert again.status_code == 201 and again.json() == original and again.headers['etag'] == '"1"'
    assert client.post(PATH,headers=headers,json={**BODY,'notes':'Different'}).status_code == 409
    assert db.query(AuditLog).filter_by(action='PRODUCT_CREATED').count() == 1
    monkeypatch.setattr(deletion_journal,'record_product',Mock())
    assert client.delete(PATH+'/'+resource,headers={**auth,'If-Match':'"2"'}).status_code == 204
    assert client.get(PATH+'/'+resource,headers=auth).status_code == 404
    erased=client.get(PATH+'/attempts/'+KEY,headers=auth).json()
    assert erased['status'] == 'committed' and erased['result_availability'] == 'erased'
    assert erased['resource_id'] == resource and erased['result'] is None
    assert client.post(PATH,headers=headers,json=BODY).status_code == 410
    assert db.get(Product,resource) is None
    with Session(db.get_bind()) as restarted:
        assert product_attempts.lookup(restarted,'delete-patient',KEY).resource_id == resource


def test_unknown_scope_expiry_headers_and_policy(deletion_context, monkeypatch):
    client,db,auth=deletion_context
    assert client.get(PATH+'/attempts/'+KEY,headers=auth).json()['status'] == 'unknown'
    other={'Authorization':'Bearer '+create_access_token('delete-doctor','doctor',hashed_password='unused')}
    assert client.post(PATH,headers={**auth,'Idempotency-Key':KEY},json=BODY).status_code == 201
    foreign=client.get(PATH+'/attempts/'+KEY,headers=other).json()
    assert foreign['status'] == 'unknown' and foreign['result'] is None
    assert client.get(PATH+'/attempts/'+KEY).status_code == 401
    assert client.post(PATH,headers=[*auth.items(),('Idempotency-Key',KEY),('Idempotency-Key',KEY)],json=BODY).status_code == 422
    assert client.post(PATH,headers={**auth,'Idempotency-Key':'bad'},json=BODY).status_code == 422
    assert client.get(PATH+'/attempts/bad',headers=auth).status_code == 422
    monkeypatch.setattr(settings,'SAFETY_POLICY_ENFORCE',True)
    assert client.post(PATH,headers={**auth,'Idempotency-Key':KEY},json=BODY).status_code == 403
    monkeypatch.setattr(settings,'SAFETY_POLICY_ENFORCE',False)
    row=db.query(ProductCreateAttempt).one();row.recorded_at=datetime.now(timezone.utc)-timedelta(days=31);db.commit()
    expired=client.get(PATH+'/attempts/'+KEY,headers=auth).json()
    assert expired['status'] == 'expired' and expired['result'] is None and expired['resource_id']
    assert client.post(PATH,headers={**auth,'Idempotency-Key':KEY},json=BODY).status_code == 410
    assert db.query(ProductCreateAttempt).count() == 1


@pytest.mark.parametrize('after_commit',[False,True])
def test_failure_before_or_after_commit_is_recoverable(deletion_context, monkeypatch, after_commit):
    client,db,auth=deletion_context
    original=db.commit
    def fail():
        if after_commit: original()
        raise RuntimeError('Synthetic lost response')
    monkeypatch.setattr(db,'commit',fail)
    response=client.post(PATH,headers={**auth,'Idempotency-Key':KEY},json=BODY)
    assert response.status_code == 503
    monkeypatch.setattr(db,'commit',original)
    found=client.get(PATH+'/attempts/'+KEY,headers=auth).json()
    assert found['status'] == ('committed' if after_commit else 'unknown')
    assert db.query(AuditLog).filter_by(action='PRODUCT_CREATED').count() == int(after_commit)
    assert db.query(Product).filter_by(name=BODY['name']).count() == int(after_commit)
    assert client.post(PATH,headers={**auth,'Idempotency-Key':KEY},json=BODY).status_code == 201
    assert db.query(AuditLog).filter_by(action='PRODUCT_CREATED').count() == 1


def test_account_erasure_removes_receipts_and_original_payload(deletion_context, monkeypatch):
    client,db,auth=deletion_context
    assert client.post(PATH,headers={**auth,'Idempotency-Key':KEY},json=BODY).status_code == 201
    monkeypatch.setattr(azure_blob_service,'delete_image',Mock())
    monkeypatch.setattr(azure_blob_service,'delete_owned_images',Mock())
    assert client.delete('/api/v1/users/me',headers=auth).status_code == 204
    assert db.query(ProductCreateAttempt).count() == 0
    assert client.get(PATH+'/attempts/'+KEY,headers=auth).status_code == 401


@pytest.mark.parametrize('changed',[False,True])
def test_pg_product_create_parallel_owner_key_and_payload(pg_engine,changed):
    factory=seed(pg_engine);barrier=Barrier(2)
    def create(index):
        with factory() as db:
            user=db.get(User,'owner');barrier.wait(timeout=5)
            req=Request({'type':'http','headers':[(b'idempotency-key',KEY.encode())]})
            try:
                result=create_product(ProductCreate(**{**BODY,'notes':'Changed' if changed and index else None}),
                    Response(),user,db,req)
                return 201,result.id
            except HTTPException as exc:
                db.rollback();return exc.status_code,None
    with ThreadPoolExecutor(2) as pool: results=list(pool.map(create,range(2)))
    assert sorted(code for code,_ in results) == ([201,409] if changed else [201,201])
    with factory() as db:
        assert db.query(Product).count() == db.query(ProductCreateAttempt).count() == 1
        assert db.query(AuditLog).filter_by(action='PRODUCT_CREATED').count() == 1
        assert product_attempts.lookup(db,'owner',KEY).status == 'committed'
        assert product_attempts.lookup(db,'doctor0',KEY).status == 'unknown'


def migration_rehearsal(engine,monkeypatch):
    monkeypatch.setattr(settings,'DATABASE_URL',engine.url.render_as_string(hide_password=False))
    cfg=Config(str(Path(__file__).parents[1]/'alembic.ini'))
    command.upgrade(cfg,'20261015_02')
    with engine.begin() as c:
        c.execute(text("INSERT INTO users(id,email,hashed_password,full_name,role,reset_token_attempts) VALUES ('owner','owner@synthetic.test','test','Synthetic','patient',0)"))
        c.execute(text("INSERT INTO products(id,user_id,name,category) VALUES ('old','owner','Preserved','treatment')"))
    command.upgrade(cfg,'head');command.check(cfg)
    with Session(engine) as db:
        assert db.get(Product,'old').name == 'Preserved'
        req=Request({'type':'http','headers':[(b'idempotency-key',KEY.encode())]})
        create_product(ProductCreate(**BODY),Response(),db.get(User,'owner'),db,req)
    with pytest.raises(RuntimeError,match='durable product create attempts'):
        command.downgrade(cfg,'20261015_02')
    with Session(engine) as db:
        assert product_attempts.lookup(db,'owner',KEY).status == 'committed'
        db.query(ProductCreateAttempt).delete();db.commit()
    command.downgrade(cfg,'20261015_02');command.upgrade(cfg,'head');command.check(cfg)


def test_product_attempt_seeded_sqlite_migration(tmp_path,monkeypatch):
    engine=create_engine('sqlite:///'+(tmp_path/'migration.db').as_posix())
    try: migration_rehearsal(engine,monkeypatch)
    finally: engine.dispose()


def test_pg_product_attempt_seeded_migration(pg_engine,monkeypatch):
    migration_rehearsal(pg_engine,monkeypatch)


@pytest.mark.parametrize('product_present',[False,True])
def test_product_deletion_restore_scrubs_receipts_even_without_resource(deletion_context, product_present):
    from app.services.deletion_journal import DeletionJournal
    from tests.test_deletion_journal import Container
    client,db,auth=deletion_context
    response=client.post(PATH,headers={**auth,'Idempotency-Key':KEY},json=BODY)
    resource=response.json()['id']
    if not product_present:
        db.query(Product).filter_by(id=resource).delete();db.commit()
    journal=DeletionJournal(Container(),'j'*32,True)
    journal.record_product('delete-patient',resource)
    storage=Mock(is_live=True);storage.container_client.list_blobs.return_value=[]
    journal.replay(db,storage,Mock())
    db.expire_all()
    value=product_attempts.lookup(db,'delete-patient',KEY)
    assert value.status == 'committed' and value.result_availability == 'erased' and value.result is None
    assert db.query(ProductCreateAttempt).one().result_snapshot is None
