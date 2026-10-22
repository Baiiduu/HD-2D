import os
import re
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy.engine import make_url


@dataclass(frozen=True)
class Settings:
    database_url: str = field(default="sqlite:///./var/leaderboard.sqlite3", repr=False)
    api_token: str = field(default="", repr=False)
    database_password: str | None = field(default=None, repr=False)
    demo_board_id: str = ""
    database_pool_size: int = 3

    @classmethod
    def from_environment(cls) -> "Settings":
        # Do not search parent directories: the repo has unrelated credentials.
        load_dotenv(Path(__file__).resolve().parents[1] / ".env", override=False)
        return cls(
            database_url=os.getenv("LEADERBOARD_DATABASE_URL", cls.database_url),
            api_token=os.getenv("LEADERBOARD_API_TOKEN", ""),
            database_password=os.getenv("LEADERBOARD_DATABASE_PASSWORD"),
            demo_board_id=os.getenv("LEADERBOARD_DEMO_BOARD_ID", ""),
            database_pool_size=int(os.getenv("LEADERBOARD_DB_POOL_SIZE", "3")),
        )

    def validate(self) -> None:
        if not 1 <= self.database_pool_size <= 16:
            raise ValueError("LEADERBOARD_DB_POOL_SIZE must be between 1 and 16")
        if self.demo_board_id and not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", self.demo_board_id):
            raise ValueError("Invalid LEADERBOARD_DEMO_BOARD_ID")
        if self.api_token and len(self.api_token) < 32:
            raise ValueError("LEADERBOARD_API_TOKEN must contain at least 32 characters")
        if self.api_token.startswith("replace-with-"):
            raise ValueError("Replace the example LEADERBOARD_API_TOKEN before enabling writes")
        if make_url(self.database_url).get_backend_name() not in {"sqlite", "postgresql"}:
            raise ValueError("Supported databases: SQLite and PostgreSQL")

    def resolved_database_url(self):
        url = make_url(self.database_url)
        if url.drivername == "postgresql":
            url = url.set(drivername="postgresql+psycopg")
        if self.database_password is not None and url.get_backend_name() != "sqlite":
            url = url.set(password=self.database_password)
        if url.get_backend_name() == "sqlite" and url.database not in {None, "", ":memory:"}:
            Path(url.database).parent.mkdir(parents=True, exist_ok=True)
        return url
