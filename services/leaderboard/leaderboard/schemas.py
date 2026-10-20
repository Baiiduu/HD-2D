import json
import unicodedata
from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StrictInt, field_validator


BoardId = Annotated[str, Field(pattern=r"^[a-z0-9][a-z0-9_-]{0,63}$")]
PlayerId = Annotated[str, Field(pattern=r"^[A-Za-z0-9][A-Za-z0-9_:.\-]{0,127}$")]
# JSON numbers stay exact in both Godot and JavaScript clients.
Score = Annotated[StrictInt, Field(ge=-(2**53 - 1), le=2**53 - 1)]


class RequestModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


def clean_text(value: str | None):
    if value is not None:
        value = value.strip()
        if not value or any(unicodedata.category(char).startswith("C") for char in value):
            raise ValueError("Text must be nonempty and contain no control characters")
    return value


class BoardCreate(RequestModel):
    id: BoardId
    title: Annotated[str, Field(min_length=1, max_length=100)]
    sort_order: Literal["desc", "asc"] = "desc"

    _clean_title = field_validator("title")(clean_text)


class BoardView(BaseModel):
    id: str
    title: str
    sort_order: Literal["desc", "asc"]
    created_at: datetime


class ScorePayload(RequestModel):
    submission_id: UUID
    score: Score
    display_name: Annotated[str | None, Field(max_length=48)] = None
    metadata: dict = Field(default_factory=dict)

    _clean_name = field_validator("display_name")(clean_text)

    @field_validator("metadata")
    @classmethod
    def validate_metadata(cls, value):
        try:
            encoded = json.dumps(value, ensure_ascii=False, allow_nan=False).encode("utf-8")
        except (ValueError, TypeError, OverflowError, RecursionError) as exc:
            raise ValueError("Metadata must contain finite JSON values") from exc
        if len(encoded) > 8192:
            raise ValueError("Metadata must not exceed 8192 UTF-8 bytes")
        return value


class ScoreSubmit(ScorePayload):
    player_id: PlayerId


class DemoScoreSubmit(ScorePayload):
    device_id: UUID
    score: Annotated[StrictInt, Field(ge=0, le=2**53 - 1)]


class SubmissionView(BaseModel):
    board_id: str
    submission_id: UUID
    player_id: str
    submitted_score: int
    personal_best: int
    best_updated: bool
    replayed: bool


class RankedScore(BaseModel):
    player_id: str
    display_name: str | None
    score: int
    metadata: dict
    achieved_at: datetime
    rank: int


class ScorePage(BaseModel):
    board_id: str
    total: int
    offset: int
    limit: int
    entries: list[RankedScore]
