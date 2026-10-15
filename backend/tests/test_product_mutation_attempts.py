from datetime import datetime,timedelta,timezone
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from types import SimpleNamespace
from unittest.mock import Mock
import pytest
from fastapi import HTTPException,Request,Response
from app.models import User,Product,AuditLog
from app.models.product_mutations import ProductMutationAttempt
from app.schemas import ProductUpdate
from app.api.v1.products import update_product,delete_product
from app.core.security import create_access_token
from app.services import product_mutations
from app.services.deletion_journal import DeletionJournal
from tests.test_deletion_journal import Container
from tests.test_account_deletion import deletion_context
from tests.test_postgres_gate import pg_engine,seed

ROOT="/api/v1/products"
KEY="synthetic-product-mutation-0001"


def product(db):
    row=Product(id="erasable",user_id="delete-patient",name="Synthetic product",in_routine=False)
    db.add(row);db.commit();return row


def test_patch_original_receipt_bound_to_body_and_precondition(deletion_context):
    client,db,auth=deletion_context;product(db)
    headers={**auth,"Idempotency-Key":KEY,"If-Match":'"1"'}
    path=ROOT+"/erasable"
    first=client.patch(path,headers=headers,json={"notes":"Original private value"})
    assert first.status_code==200 and first.headers["operation-attempt-id"]
    assert first.headers["etag"]=='"2"' and first.headers["cache-control"]=="no-store"
    assert client.patch(path,headers={**auth,"If-Match":'"2"'},json={"notes":"Later"}).status_code==200
    assert client.patch(path,headers=headers,json={"notes":"Original private value"}).json()==first.json()
    assert client.patch(path,headers=headers,json={"notes":"Different"}).status_code==409
    assert client.patch(path,headers={**headers,"If-Match":'"3"'},json={"notes":"Original private value"}).status_code==409
    lookup=client.get(path+f"/operation-attempts/patch/{KEY}",headers=auth)
    assert lookup.json()["result"]==first.json()
    assert db.query(AuditLog).filter_by(action="PRODUCT_UPDATED").count()==2
    foreign={"Authorization":"Bearer "+create_access_token("delete-doctor","doctor",hashed_password="unused")}
    assert client.get(path+f"/operation-attempts/patch/{KEY}",headers=foreign).json()["status"]=="unknown"


def test_delete_receipt_survives_erasure_and_patch_content_is_scrubbed(deletion_context,monkeypatch):
    client,db,auth=deletion_context;product(db)
    journal=DeletionJournal(Container(),"j"*32,True)
    monkeypatch.setattr("app.api.v1.products.deletion_journal",journal)
    path=ROOT+"/erasable"
    assert client.patch(path,headers={**auth,"If-Match":'"1"',"Idempotency-Key":KEY},json={"notes":"Private"}).status_code==200
    headers={**auth,"If-Match":'"2"',"Idempotency-Key":KEY}
    assert client.delete(path,headers=headers).status_code==204
    assert client.delete(path,headers=headers).status_code==204
    assert len(journal.inventory())==1
    assert db.query(AuditLog).filter_by(action="PRODUCT_DELETED").count()==1
    patch=client.get(path+f"/operation-attempts/patch/{KEY}",headers=auth).json()
    deleted=client.get(path+f"/operation-attempts/delete/{KEY}",headers=auth).json()
    assert patch["status"]=="committed" and patch["result_availability"]=="erased" and patch["result"] is None
    assert deleted["result"]=={"deleted":True,"id":"erasable","revision":3}
    assert client.patch(path,headers={**auth,"If-Match":'"1"',"Idempotency-Key":KEY},json={"notes":"Private"}).status_code==410
    assert client.delete(path,headers={**headers,"If-Match":'"3"'}).status_code==409


@pytest.mark.parametrize("operation",["patch","delete"])
@pytest.mark.parametrize("after_commit",[False,True])
def test_uncertain_product_mutation_is_recoverable(deletion_context,monkeypatch,operation,after_commit):
    client,db,auth=deletion_context;product(db)
    journal=DeletionJournal(Container(),"j"*32,True);monkeypatch.setattr("app.api.v1.products.deletion_journal",journal)
    original=db.commit
    def fail():
        if after_commit:original()
        raise RuntimeError("Synthetic lost response")
    headers={**auth,"If-Match":'"1"',"Idempotency-Key":KEY}
    monkeypatch.setattr(db,"commit",fail)
    args={"json":{"notes":"Private"}} if operation=="patch" else {}
    assert getattr(client,operation)(ROOT+"/erasable",headers=headers,**args).status_code==503
    monkeypatch.setattr(db,"commit",original)
    result=client.get(ROOT+f"/erasable/operation-attempts/{operation}/{KEY}",headers=auth).json()
    assert result["status"]==("committed" if after_commit else "unknown")
    assert getattr(client,operation)(ROOT+"/erasable",headers=headers,**args).status_code==(200 if operation=="patch" else 204)
    assert db.query(ProductMutationAttempt).count()==1
    assert db.query(AuditLog).filter_by(action="PRODUCT_UPDATED" if operation=="patch" else "PRODUCT_DELETED").count()==1
    if operation=="delete":assert len(journal.inventory())==1


def test_receipt_expiry_and_unknown_are_honest(deletion_context):
    client,db,auth=deletion_context;product(db)
    path=ROOT+f"/erasable/operation-attempts/patch/{KEY}"
    assert client.get(path,headers=auth).json()["status"]=="unknown"
    headers={**auth,"If-Match":'"1"',"Idempotency-Key":KEY}
    assert client.patch(ROOT+"/erasable",headers=headers,json={"notes":"Private"}).status_code==200
    db.query(ProductMutationAttempt).one().recorded_at=datetime.now(timezone.utc)-timedelta(days=31);db.commit()
    assert client.get(path,headers=auth).json()["status"]=="expired"
    assert client.patch(ROOT+"/erasable",headers=headers,json={"notes":"Private"}).status_code==410
    assert client.get(path).status_code==401
    assert client.get(ROOT+"/erasable/operation-attempts/patch/bad",headers=auth).status_code==422


@pytest.mark.parametrize("present",[False,True])
def test_restore_scrubs_orphan_patch_receipts(deletion_context,present):
    client,db,auth=deletion_context;product(db)
    assert client.patch(ROOT+"/erasable",headers={**auth,"If-Match":'"1"',"Idempotency-Key":KEY},json={"notes":"Private"}).status_code==200
    if not present:db.delete(db.get(Product,"erasable"));db.commit()
    journal=DeletionJournal(Container(),"j"*32,True);journal.record_product("delete-patient","erasable")
    storage=Mock(is_live=True);storage.container_client.list_blobs.return_value=[]
    journal.replay(db,storage,Mock())
    assert db.query(ProductMutationAttempt).one().result_snapshot is None


@pytest.mark.parametrize("changed",[False,True])
def test_pg_patch_same_key_race(pg_engine,changed):
    factory=seed(pg_engine)
    with factory() as db:db.add(Product(id="product",user_id="owner",name="Synthetic",in_routine=False));db.commit()
    barrier=Barrier(2)
    def run(i):
        with factory() as db:
            user=db.get(User,"owner");barrier.wait(timeout=5)
            request=Request({"type":"http","headers":[(b'idempotency-key',KEY.encode()),(b'if-match',b'"1"')]})
            try:
                result=update_product("product",ProductUpdate(notes="Different" if changed and i else "Original"),Response(), '"1"',user,db,request)
                return result["revision"] if isinstance(result,dict) else result.revision
            except HTTPException as error:db.rollback();return error.status_code
    with ThreadPoolExecutor(2) as pool:results=list(pool.map(run,range(2)))
    assert sorted(results)==([2,409] if changed else [2,2])
    with factory() as db:
        assert db.query(ProductMutationAttempt).count()==1 and db.query(Product).one().revision==2


def test_pg_delete_same_key_has_one_commit_and_journal_intent(pg_engine,monkeypatch):
    factory=seed(pg_engine)
    journal=Mock();monkeypatch.setattr("app.api.v1.products.deletion_journal",journal)
    with factory() as db:db.add(Product(id="product",user_id="owner",name="Synthetic",in_routine=False));db.commit()
    barrier=Barrier(2)
    def run(_):
        with factory() as db:
            user=db.get(User,"owner");barrier.wait(timeout=5)
            request=Request({"type":"http","headers":[(b'idempotency-key',KEY.encode()),(b'if-match',b'"1"')]})
            response=Response()
            delete_product("product",'"1"',user,db,request,response)
            return response.headers["operation-attempt-id"]
    with ThreadPoolExecutor(2) as pool:results=list(pool.map(run,range(2)))
    assert results[0]==results[1] and journal.record_product.call_count==1
    with factory() as db:
        assert db.query(Product).count()==0 and db.query(ProductMutationAttempt).count()==1
        assert db.query(AuditLog).filter_by(action="PRODUCT_DELETED").count()==1
        assert product_mutations.lookup(db,"owner","product","delete",KEY)["status"]=="committed"


def test_patch_receipt_and_routine_side_effect_share_rollback(deletion_context,monkeypatch):
    client,db,auth=deletion_context;product(db)
    from app.models import RoutineEntry
    entry=RoutineEntry(id="entry",user_id="delete-patient",product_id="erasable",schedule="AM",frequency="daily",
        start_date=datetime.now(timezone.utc).date(),active=True)
    db.add(entry);db.commit()
    original=db.commit
    def fail():raise RuntimeError("Synthetic commit failure")
    monkeypatch.setattr(db,"commit",fail)
    headers={**auth,"If-Match":'"1"',"Idempotency-Key":KEY}
    assert client.patch(ROOT+"/erasable",headers=headers,json={"status":"archived"}).status_code==503
    monkeypatch.setattr(db,"commit",original)
    db.expire_all()
    assert db.get(Product,"erasable").status=="active" and db.get(RoutineEntry,"entry").active
    assert db.query(ProductMutationAttempt).count()==0
    assert client.patch(ROOT+"/erasable",headers=headers,json={"status":"archived"}).status_code==200
    assert not db.get(RoutineEntry,"entry").active and db.query(ProductMutationAttempt).count()==1


def test_account_erasure_removes_mutation_receipts(deletion_context,monkeypatch):
    client,db,auth=deletion_context;product(db)
    client.patch(ROOT+"/erasable",headers={**auth,"If-Match":'"1"',"Idempotency-Key":KEY},json={"notes":"Private"})
    from app.services.azure_blob import azure_blob_service
    monkeypatch.setattr(azure_blob_service,"delete_owned_images",Mock())
    assert client.delete("/api/v1/users/me",headers=auth).status_code==204
    assert db.query(ProductMutationAttempt).count()==0


def test_pg_populated_mutation_downgrade_refused(pg_engine,monkeypatch):
    from alembic import command
    from alembic.config import Config
    from app.core.config import settings
    from sqlalchemy.orm import Session
    from sqlalchemy import text
    monkeypatch.setattr(settings,"DATABASE_URL",pg_engine.url.render_as_string(hide_password=False))
    config=Config("alembic.ini");command.upgrade(config,"head")
    with Session(pg_engine) as db:
        db.add(User(id="owner",email="owner@synthetic.test",full_name="Synthetic",hashed_password="synthetic"));db.flush()
        db.add(ProductMutationAttempt(id="receipt",user_id="owner",resource_id="product",operation="delete",payload_hash="f"*64,resource_revision=2,result_snapshot={"deleted":True},recorded_at=datetime.now(timezone.utc)));db.commit()
    with pytest.raises(RuntimeError,match="committed product mutation"):command.downgrade(config,"20261015_07")
    command.check(config)
    with pg_engine.connect() as connection:
        assert connection.execute(text("SELECT count(*) FROM product_mutation_attempts")).scalar()==1
        assert connection.execute(text("SELECT version_num FROM alembic_version")).scalar()=="20261015_09"
