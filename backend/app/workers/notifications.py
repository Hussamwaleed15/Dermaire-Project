"""Isolated notification worker: python -m app.workers.notifications --once.

Only explicit local/test DBs are accepted. No network provider is enabled.
"""
import argparse
import json
import time
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.core.database import connection_options
from app.services.notifications import dispatch_one, DisabledPushProvider
from app.services.routine_reminders import generate


def cycle(factory, *, max_jobs=100, provider=None):
    if type(max_jobs) is not int or not 1 <= max_jobs <= 1000:
        raise ValueError("max_jobs must be 1..1000")
    from app.services.agent_platform import expire_requests
    with factory() as db:
        expire_requests(db)
    with factory() as db:
        generated=generate(db)
    processed=0
    for _ in range(max_jobs):
        with factory() as db:
            result=dispatch_one(db,provider or DisabledPushProvider())
        if result is None:
            break
        processed+=1
    return {"occurrences_created":generated["occurrences_created"],"jobs_processed":processed,
            "provider":"disabled" if provider is None else "injected_test_adapter", "delivery_confirmed":False}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database-url",required=True,help="Explicit isolated sqlite or loopback test PG URL")
    parser.add_argument("--once",action="store_true")
    parser.add_argument("--max-jobs",type=int,default=100)
    parser.add_argument("--interval",type=int,default=30)
    args=parser.parse_args()
    from sqlalchemy.engine import make_url
    url=make_url(args.database_url)
    if url.get_backend_name() != "sqlite" and not (url.get_backend_name()=="postgresql" and
        url.host=="127.0.0.1" and url.port==55441 and url.username=="gate" and
        url.database and url.database.startswith("dermaire_gate_")):
        parser.error("Only explicit isolated SQLite or disposable loopback PostgreSQL gate is permitted")
    if not 1<=args.max_jobs<=1000 or not 1<=args.interval<=300:
        parser.error("Bounds: max-jobs 1..1000; interval 1..300 seconds")
    engine=create_engine(url,connect_args=connection_options(args.database_url))
    factory=sessionmaker(bind=engine,autoflush=False)
    try:
        while True:
            print(json.dumps(cycle(factory,max_jobs=args.max_jobs)),flush=True)
            if args.once:break
            time.sleep(args.interval)
    finally:
        engine.dispose()


if __name__=="__main__":
    main()
