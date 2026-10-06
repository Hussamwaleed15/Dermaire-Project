"""Read-only schema inventory. No records, credentials or DDL are emitted."""
import json
from sqlalchemy import inspect, text
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from app.core.database import Base, engine
import app.models


def audit(connection):
    inspector = inspect(connection)
    tables = inspector.get_table_names()
    differences = compare_metadata(MigrationContext.configure(connection, opts={
        "compare_type": True,
        "include_object": lambda obj, name, kind, reflected, compare_to:
            not (kind == "table" and name == "alembic_version"),
    }), Base.metadata)
    return {
        "tables": tables,
        "alembic_version_present": "alembic_version" in tables,
        "detected_differences": [str(item) for item in differences],
        "check_constraints": {table: inspector.get_check_constraints(table)
                              for table in tables if table in Base.metadata.tables},
        "limitations": "Review CHECK expressions, triggers, grants, extensions and row policies manually before stamping; empty differences alone are insufficient.",
    }


if __name__ == "__main__":
    try:
        with engine.connect() as connection:
            if engine.dialect.name == "postgresql":
                connection.execute(text("SET TRANSACTION READ ONLY"))
                connection.execute(text("SET LOCAL statement_timeout = '15s'"))
            result = audit(connection)
            connection.rollback()
        print(json.dumps(result, indent=2, default=str))
        raise SystemExit(1 if result["detected_differences"] else 0)
    except Exception:
        print(json.dumps({"error": "Schema audit unavailable; no credentials or raw errors emitted"}))
        raise SystemExit(2)
