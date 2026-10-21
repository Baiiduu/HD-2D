import hashlib
import json
import re
import secrets
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, RedirectResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import delete, func, select, text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from .config import Settings
from .database import build_engine, write_transaction
from .models import Base, BestScore, Board, Device, Submission, DemoConsent, RevokedCredential
from .schemas import (
    BoardCreate, BoardId, BoardView, PlayerId, RankedScore,
    DemoDataDelete, DemoScoreSubmit, ScorePage, ScoreSubmit, SubmissionView,
)


def now_utc():
    return datetime.now(UTC).replace(tzinfo=None)


def fail(status_code: int, code: str, message: str, **kwargs):
    raise HTTPException(status_code, detail={"code": code, "message": message}, **kwargs)


def get_session(request: Request):
    with Session(request.app.state.engine, expire_on_commit=False) as session:
        yield session


def get_read_session(request: Request):
    with Session(request.app.state.engine) as session:
        # Python's legacy SQLite driver does not begin transactions for SELECT.
        # Keep rows, total and ranks in the same snapshot during concurrent writes.
        if session.get_bind().dialect.name == "sqlite":
            session.connection().exec_driver_sql("BEGIN")
        else:
            session.connection(execution_options={"isolation_level": "REPEATABLE READ"})
        yield session


Database = Annotated[Session, Depends(get_session)]
ReadDatabase = Annotated[Session, Depends(get_read_session)]
bearer = HTTPBearer(auto_error=False)


def require_writer(
    request: Request,
    credential: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
):
    token = request.app.state.settings.api_token
    if not token:
        fail(503, "write_not_configured", "Configure a server API token to enable writes")
    if credential is None or not secrets.compare_digest(
        credential.credentials.encode("utf-8"), token.encode("utf-8")
    ):
        fail(401, "unauthorized", "A valid server API token is required",
             headers={"WWW-Authenticate": "Bearer"})


def find_board(session: Session, board_id: str, *, lock=False):
    query = select(Board).where(Board.id == board_id)
    if lock:
        query = query.with_for_update()
    board = session.scalar(query)
    if board is None:
        fail(404, "board_not_found", "Leaderboard does not exist")
    return board


def board_view(board: Board):
    return BoardView(id=board.id, title=board.title, sort_order=board.sort_order,
                     created_at=board.created_at.replace(tzinfo=UTC))


def better_than(board: Board, score: int):
    return BestScore.score > score if board.sort_order == "desc" else BestScore.score < score


def publicly_visible():
    consent = select(DemoConsent.device_id).where(
        BestScore.player_id == "demo:" + DemoConsent.device_id,
        DemoConsent.policy_version == "2026-10-21",
    ).exists()
    return ~BestScore.player_id.like("demo:%") | consent


def rank_of(session: Session, board: Board, score: int):
    return 1 + session.scalar(select(func.count()).select_from(BestScore).where(
        BestScore.board_id == board.id, publicly_visible(), better_than(board, score)
    ))


def ranked_view(entry: BestScore, rank: int):
    return RankedScore(player_id=entry.player_id, display_name=entry.display_name,
                       score=entry.score, metadata=entry.extra_data, rank=rank,
                       achieved_at=entry.achieved_at.replace(tzinfo=UTC))


def submission_view(receipt: Submission, replayed: bool):
    return SubmissionView(
        board_id=receipt.board_id, submission_id=receipt.submission_id,
        player_id=receipt.player_id, submitted_score=receipt.submitted_score,
        personal_best=receipt.personal_best, best_updated=receipt.best_updated, replayed=replayed,
    )


def create_app(settings: Settings | None = None):
    @asynccontextmanager
    async def lifespan(application: FastAPI):
        configuration = settings or Settings.from_environment()
        configuration.validate()
        engine = build_engine(configuration)
        try:
            Base.metadata.create_all(engine)
            application.state.settings = configuration
            application.state.engine = engine
            yield
        finally:
            engine.dispose()

    application = FastAPI(
        title="HD-2D Leaderboard API", version="0.1.0", lifespan=lifespan,
        description=("Independent leaderboard storage. Public reads; trusted server writes. "
                     "Scoring rules, player authentication and platform integration are deferred."),
    )

    @application.exception_handler(RequestValidationError)
    async def validation_error(_request: Request, exception: RequestValidationError):
        # Echoing invalid input (e.g. NaN) can itself break JSON serialization.
        # Return field locations and messages without reflecting request contents.
        details = [{key: error[key] for key in ("type", "loc", "msg")}
                   for error in exception.errors()]
        return JSONResponse(status_code=422, content={"detail": details})

    @application.get("/", include_in_schema=False)
    def root():
        return RedirectResponse("/docs")

    @application.get("/health", tags=["Service"])
    def health(session: Database):
        try:
            session.execute(text("SELECT 1"))
        except SQLAlchemyError:
            fail(503, "database_unavailable", "Database is unavailable")
        return {"status": "ok"}

    @application.post("/v1/leaderboards", response_model=BoardView, status_code=201,
                      dependencies=[Depends(require_writer)], tags=["Leaderboards"])
    def create_board(payload: BoardCreate, session: Database):
        board = Board(**payload.model_dump(), created_at=now_utc())
        try:
            with write_transaction(session):
                session.add(board)
        except IntegrityError:
            fail(409, "board_exists", "Leaderboard ID already exists")
        return board_view(board)

    @application.get("/v1/leaderboards", response_model=list[BoardView], tags=["Leaderboards"])
    def list_boards(session: ReadDatabase, limit: Annotated[int, Query(ge=1, le=100)] = 100,
                    offset: Annotated[int, Query(ge=0, le=10000)] = 0):
        boards = session.scalars(select(Board).order_by(Board.id).offset(offset).limit(limit))
        return [board_view(board) for board in boards]

    def save_score(board_id: str, payload: ScoreSubmit, session: Session,
                   device_id: str | None = None, device_hash: str | None = None,
                   privacy_version: str | None = None):
        canonical = json.dumps(payload.model_dump(mode="json"), sort_keys=True,
                               ensure_ascii=False, separators=(",", ":"), allow_nan=False)
        fingerprint = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
        submission_id = str(payload.submission_id)
        with write_transaction(session):
            # Board-first locking gives all writes the same order on PostgreSQL.
            board = find_board(session, board_id, lock=True)
            if device_id is not None:
                if session.get(RevokedCredential, device_hash) is not None:
                    fail(401, "device_revoked", "This credential has been revoked")
                if board.sort_order != "desc":
                    fail(503, "demo_not_configured", "Demo scores require a descending leaderboard")
                # Registration and score commit share the board lock and transaction.
                # A device UUID alone never grants access to an existing identity.
                device = session.get(Device, device_id)
                if device is None:
                    session.add(Device(id=device_id, token_hash=device_hash, created_at=now_utc()))
                    session.flush()
                elif not secrets.compare_digest(device.token_hash, device_hash):
                    fail(401, "device_unauthorized", "Device credential does not match")
                consent = session.get(DemoConsent, device_id)
                if consent is None:
                    session.add(DemoConsent(device_id=device_id, policy_version=privacy_version,
                                            accepted_at=now_utc()))
                elif consent.policy_version != privacy_version:
                    consent.policy_version = privacy_version
                    consent.accepted_at = now_utc()
            receipt = session.get(Submission, (board_id, submission_id))
            if receipt is not None:
                if receipt.payload_hash != fingerprint:
                    fail(409, "submission_conflict", "Submission ID was already used for different data")
                return submission_view(receipt, replayed=True)
            entry = session.get(BestScore, (board_id, payload.player_id))
            improved = entry is None or (
                payload.score > entry.score if board.sort_order == "desc" else payload.score < entry.score
            )
            if improved:
                if entry is None:
                    entry = BestScore(board_id=board_id, player_id=payload.player_id)
                    session.add(entry)
                entry.score = payload.score
                entry.display_name = payload.display_name
                entry.extra_data = payload.metadata
                entry.achieved_at = now_utc()
            receipt = Submission(
                board_id=board_id, submission_id=submission_id, player_id=payload.player_id,
                payload_hash=fingerprint, submitted_score=payload.score, personal_best=entry.score,
                best_updated=improved, created_at=now_utc(),
            )
            session.add(receipt)
        return submission_view(receipt, replayed=False)

    @application.post("/v1/leaderboards/{board_id}/scores", response_model=SubmissionView,
                      dependencies=[Depends(require_writer)], tags=["Scores"])
    def submit_score(board_id: BoardId, payload: ScoreSubmit, session: Database):
        return save_score(board_id, payload, session)

    @application.post("/v1/demo/scores", response_model=SubmissionView, tags=["Demo"])
    def submit_demo_score(
        request: Request, payload: DemoScoreSubmit, session: Database,
        credential: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    ):
        board_id = request.app.state.settings.demo_board_id
        if not board_id:
            fail(503, "demo_disabled", "Anonymous demo submissions are disabled")
        if credential is None or not re.fullmatch(r"[0-9a-f]{64}", credential.credentials):
            fail(401, "device_unauthorized", "A device credential is required")
        device_id = str(payload.device_id)
        score = ScoreSubmit(
            **payload.model_dump(exclude={"device_id", "metadata", "privacy_version", "public_consent"}),
            player_id="demo:" + device_id,
            metadata={**payload.metadata, "verification": "client_reported"},
        )
        return save_score(board_id, score, session, device_id,
                          hashlib.sha256(credential.credentials.encode()).hexdigest(), payload.privacy_version)

    @application.post("/v1/demo/privacy/delete", status_code=204, tags=["Demo"])
    def delete_demo_data(
        payload: DemoDataDelete, session: Database,
        credential: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    ):
        if credential is None or not re.fullmatch(r"[0-9a-f]{64}", credential.credentials):
            fail(401, "device_unauthorized", "A device credential is required")
        device_id = str(payload.device_id)
        fingerprint = hashlib.sha256(credential.credentials.encode()).hexdigest()
        with write_transaction(session):
            # Match the board-first order used by submissions. Serialize deletion
            # with all affected boards so delayed submissions cannot win a race.
            list(session.scalars(select(Board).order_by(Board.id).with_for_update()))
            device = session.get(Device, device_id)
            if device is not None and not secrets.compare_digest(device.token_hash, fingerprint):
                fail(401, "device_unauthorized", "Device credential does not match")
            if session.get(RevokedCredential, fingerprint) is None:
                session.add(RevokedCredential(token_hash=fingerprint, revoked_at=now_utc()))
            if device is not None:
                player_id = "demo:" + device_id
                session.execute(delete(BestScore).where(BestScore.player_id == player_id))
                session.execute(delete(Submission).where(Submission.player_id == player_id))
                session.execute(delete(DemoConsent).where(DemoConsent.device_id == device_id))
                session.delete(device)
        return Response(status_code=204)

    @application.get("/v1/leaderboards/{board_id}/scores", response_model=ScorePage, tags=["Scores"])
    def list_scores(board_id: BoardId, session: ReadDatabase,
                    limit: Annotated[int, Query(ge=1, le=100)] = 20,
                    offset: Annotated[int, Query(ge=0, le=10000)] = 0):
        board = find_board(session, board_id)
        score_order = BestScore.score.desc() if board.sort_order == "desc" else BestScore.score.asc()
        entries = list(session.scalars(select(BestScore).where(BestScore.board_id == board_id, publicly_visible())
                       .order_by(score_order, BestScore.achieved_at, BestScore.player_id)
                       .offset(offset).limit(limit)))
        total = session.scalar(select(func.count()).select_from(BestScore).where(BestScore.board_id == board_id, publicly_visible()))
        ranked = []
        if entries:
            rank = rank_of(session, board, entries[0].score)
            for index, entry in enumerate(entries):
                if index and entry.score != entries[index - 1].score:
                    rank = offset + index + 1
                ranked.append(ranked_view(entry, rank))
        return ScorePage(board_id=board_id, total=total, offset=offset, limit=limit, entries=ranked)

    @application.get("/v1/leaderboards/{board_id}/players/{player_id}",
                     response_model=RankedScore, tags=["Scores"])
    def player_score(board_id: BoardId, player_id: PlayerId, session: ReadDatabase):
        board = find_board(session, board_id)
        entry = session.scalar(select(BestScore).where(BestScore.board_id == board_id,
            BestScore.player_id == player_id, publicly_visible()))
        if entry is None:
            fail(404, "score_not_found", "Player has no score on this leaderboard")
        return ranked_view(entry, rank_of(session, board, entry.score))

    @application.delete("/v1/leaderboards/{board_id}/players/{player_id}/score", status_code=204,
                        dependencies=[Depends(require_writer)], tags=["Scores"])
    def delete_score(board_id: BoardId, player_id: PlayerId, session: Database):
        with write_transaction(session):
            find_board(session, board_id, lock=True)
            entry = session.get(BestScore, (board_id, player_id))
            if entry is None:
                fail(404, "score_not_found", "Player has no score on this leaderboard")
            session.delete(entry)
            # Keep receipts so retrying a previously removed score cannot restore it.
        return Response(status_code=204)

    return application


app = create_app()
