"""Represent the intentional v2 routine-entry index without editing the baseline."""

from alembic import context, op
import sqlalchemy as sa

revision = "20261008_01"
down_revision = "20261006_01"
branch_labels = None
depends_on = None
NAME = "ix_experiments_routine_entry_id"


def upgrade():
    if context.is_offline_mode():
        raise RuntimeError(
            "This revision requires online index validation; use the reviewed adoption SQL for existing databases"
        )
    connection = op.get_bind()
    if connection.dialect.name == "postgresql":
        existing = (
            connection.execute(
                sa.text("""
            SELECT pg_get_indexdef(i.indexrelid) AS definition,
                   i.indisvalid AND i.indisready AND i.indislive AS healthy
            FROM pg_index i WHERE i.indexrelid = to_regclass('public.' || :name)
        """),
                {"name": NAME},
            )
            .mappings()
            .one_or_none()
        )
        if existing is not None:
            expected = (
                "CREATE INDEX ix_experiments_routine_entry_id "
                "ON public.experiments USING btree (routine_entry_id)"
            )
            if not existing["healthy"] or existing["definition"] != expected:
                raise RuntimeError(
                    "Existing routine-entry index differs from reviewed definition"
                )
            return
    else:
        existing = next(
            (
                i
                for i in sa.inspect(connection).get_indexes("experiments")
                if i["name"] == NAME
            ),
            None,
        )
        if existing is not None:
            if (
                existing["unique"]
                or existing["column_names"] != ["routine_entry_id"]
                or existing.get("dialect_options")
            ):
                raise RuntimeError(
                    "Existing routine-entry index differs from reviewed definition"
                )
            return
    # Fresh databases have empty experiments at the preceding frozen baseline.
    # Existing populated databases must provision this index through the reviewed
    # adoption sequence before upgrading; otherwise use a maintenance write pause.
    op.create_index(NAME, "experiments", ["routine_entry_id"], unique=False)


def downgrade():
    # Preserve the historical index, including when upgrade merely adopted it.
    # Returning to the frozen revision can expose metadata drift; no index/data
    # deletion is justified by an application rollback.
    pass
