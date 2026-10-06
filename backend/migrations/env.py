from alembic import context
from sqlalchemy import create_engine, pool
from app.core.config import settings
from app.core.database import Base
import app.models  # register all models

config = context.config
url = settings.DATABASE_URL

if context.is_offline_mode():
    context.configure(url=url, target_metadata=Base.metadata, literal_binds=True,
                      compare_type=True)
    with context.begin_transaction():
        context.run_migrations()
else:
    connect_args = {"connect_timeout": 5} if url.startswith("postgresql") else {}
    engine = create_engine(url, poolclass=pool.NullPool, connect_args=connect_args)
    with engine.connect() as connection:
        context.configure(connection=connection, target_metadata=Base.metadata,
                          compare_type=True)
        with context.begin_transaction():
            context.run_migrations()
