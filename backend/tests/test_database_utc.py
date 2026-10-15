from datetime import datetime,timedelta,timezone
from sqlalchemy import create_engine,text
from app.core.database import connection_options
from tests.test_postgres_gate import pg_engine


def test_pg_application_connection_pins_utc_cast_semantics(pg_engine):
    engine=create_engine(pg_engine.url,connect_args=connection_options(str(pg_engine.url)))
    try:
        with engine.connect() as connection:
            assert connection.execute(text("SHOW timezone")).scalar()=="UTC"
            assert connection.execute(text("SHOW statement_timeout")).scalar()=="5s"
            connection.execute(text("CREATE TEMP TABLE utc_probe (at TIMESTAMP WITHOUT TIME ZONE)"))
            aware=datetime(2026,1,1,12,tzinfo=timezone(timedelta(hours=5,minutes=30)))
            connection.execute(text("INSERT INTO utc_probe VALUES (:at)"),{"at":aware})
            assert connection.execute(text("SELECT at FROM utc_probe")).scalar()==datetime(2026,1,1,6,30)
    finally:engine.dispose()
