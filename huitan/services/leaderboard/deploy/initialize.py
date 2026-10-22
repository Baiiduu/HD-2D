"""Initialize only a new deployment. Existing configuration and credentials win."""
import os
from pathlib import Path
import secrets
import subprocess
import sys

from dotenv import load_dotenv

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from leaderboard.config import Settings
from leaderboard.database import build_engine
from leaderboard.models import Base, Board
from leaderboard.app import now_utc
from sqlalchemy.orm import Session


def psql(query):
    result = subprocess.run(['runuser', '-u', 'postgres', '--', 'psql', '-v', 'ON_ERROR_STOP=1', '-At'],
                            input=query, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError('Database initialization failed; credentials were not printed.')
    return result.stdout.strip()


config = Path('/etc/hd2d-leaderboard/leaderboard.env')
if not config.exists():
    if psql("SELECT rolname FROM pg_roles WHERE rolname='leaderboard';"):
        raise RuntimeError('Application role exists; restore its private configuration instead of overwriting it.')
    password, token = secrets.token_hex(32), secrets.token_hex(32)
    psql(f"CREATE ROLE leaderboard LOGIN PASSWORD '{password}' NOSUPERUSER NOCREATEDB NOCREATEROLE;")
    psql('CREATE DATABASE leaderboard OWNER leaderboard;')
    # Exclusive creation avoids replacing private configuration from another deployment.
    descriptor = os.open(config, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w') as output:
        output.write('LEADERBOARD_DATABASE_URL=postgresql+psycopg://leaderboard@127.0.0.1:5432/leaderboard\n'
                     f'LEADERBOARD_DATABASE_PASSWORD={password}\nLEADERBOARD_API_TOKEN={token}\n'
                     'LEADERBOARD_DEMO_BOARD_ID=world-demo-v1\nLEADERBOARD_DB_POOL_SIZE=3\n')
load_dotenv(config, override=False)
settings = Settings.from_environment()
settings.validate()
engine = build_engine(settings)
Base.metadata.create_all(engine)
with Session(engine) as session, session.begin():
    if not session.get(Board, settings.demo_board_id):
        session.add(Board(id=settings.demo_board_id, title='匿名试玩榜', sort_order='desc', created_at=now_utc()))
engine.dispose()
print('Database and demo board initialized; existing private configuration preserved.')
