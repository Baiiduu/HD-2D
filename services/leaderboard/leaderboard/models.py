from datetime import datetime

from sqlalchemy import BigInteger, Boolean, DateTime, ForeignKey, Index, JSON, String
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


utc_datetime = DateTime()


class Board(Base):
    __tablename__ = "leaderboards"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    title: Mapped[str] = mapped_column(String(100))
    sort_order: Mapped[str] = mapped_column(String(4))
    created_at: Mapped[datetime] = mapped_column(utc_datetime)


class BestScore(Base):
    __tablename__ = "best_scores"
    __table_args__ = (Index("ix_best_scores_board_score", "board_id", "score"),)

    board_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("leaderboards.id"), primary_key=True
    )
    player_id: Mapped[str] = mapped_column(String(128), primary_key=True)
    score: Mapped[int] = mapped_column(BigInteger)
    display_name: Mapped[str | None] = mapped_column(String(48))
    extra_data: Mapped[dict] = mapped_column("metadata", JSON)
    achieved_at: Mapped[datetime] = mapped_column(utc_datetime)


class Submission(Base):
    __tablename__ = "score_submissions"

    board_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("leaderboards.id"), primary_key=True
    )
    submission_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    player_id: Mapped[str] = mapped_column(String(128))
    payload_hash: Mapped[str] = mapped_column(String(64))
    submitted_score: Mapped[int] = mapped_column(BigInteger)
    personal_best: Mapped[int] = mapped_column(BigInteger)
    best_updated: Mapped[bool] = mapped_column(Boolean)
    created_at: Mapped[datetime] = mapped_column(utc_datetime)
