from contextlib import contextmanager

from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from .config import Settings


def build_engine(settings: Settings):
    url = settings.resolved_database_url()
    options = {"pool_pre_ping": True}
    if url.get_backend_name() == "postgresql":
        # A writer waiting on the board lock must see the previous writer's
        # committed receipts and best scores in its subsequent statements.
        options["isolation_level"] = "READ COMMITTED"
        options.update(pool_size=settings.database_pool_size, max_overflow=0)
    if url.get_backend_name() == "sqlite":
        options["connect_args"] = {"check_same_thread": False, "timeout": 30}
        if url.database in {None, "", ":memory:"}:
            options["poolclass"] = StaticPool
    engine = create_engine(url, **options)
    if engine.dialect.name == "sqlite":
        @event.listens_for(engine, "connect")
        def configure_sqlite(connection, _record):
            cursor = connection.cursor()
            cursor.execute("PRAGMA foreign_keys=ON")
            cursor.execute("PRAGMA busy_timeout=30000")
            cursor.execute("PRAGMA journal_mode=WAL")
            cursor.close()
    return engine


@contextmanager
def write_transaction(session: Session):
    with session.begin():
        # SQLite ignores FOR UPDATE. Lock before the first read so concurrent
        # submissions cannot both replace a best score based on stale data.
        if session.get_bind().dialect.name == "sqlite":
            session.connection().exec_driver_sql("BEGIN IMMEDIATE")
        yield
