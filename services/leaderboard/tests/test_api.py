import os
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, create_mock_engine, select
from sqlalchemy.dialects import postgresql
from sqlalchemy.engine import make_url

from leaderboard.app import create_app
from leaderboard.config import Settings
from leaderboard.models import Base, Board


TOKEN = "test-only-credential-0123456789abcdef"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


DATABASES = ["sqlite"] + (["postgresql"] if os.getenv("LEADERBOARD_TEST_DATABASE_URL") else [])


@pytest.fixture(params=DATABASES)
def settings(request, tmp_path):
    if request.param == "sqlite":
        yield Settings(database_url=f"sqlite:///{tmp_path.as_posix()}/scores.sqlite3", api_token=TOKEN)
        return
    url = make_url(os.environ["LEADERBOARD_TEST_DATABASE_URL"])
    if url.get_backend_name() != "postgresql":
        raise ValueError("Integration tests require a dedicated PostgreSQL test database")
    if url.drivername == "postgresql":
        url = url.set(drivername="postgresql+psycopg")
    password = os.getenv("LEADERBOARD_TEST_DATABASE_PASSWORD", url.password)
    engine = create_engine(url.set(password=password))
    schema = "leaderboard_test_" + uuid4().hex
    try:
        with engine.begin() as connection:
            connection.exec_driver_sql(f'CREATE SCHEMA "{schema}"')
        isolated = url.set(password="").update_query_dict({"options": f"-csearch_path={schema}"})
        yield Settings(database_url=isolated.render_as_string(hide_password=False),
                       database_password=password, api_token=TOKEN)
    finally:
        # Only this test's random schema is removed; existing tables are untouched.
        with engine.begin() as connection:
            connection.exec_driver_sql(f'DROP SCHEMA IF EXISTS "{schema}" CASCADE')
        engine.dispose()


@pytest.fixture
def client(settings):
    with TestClient(create_app(settings)) as test_client:
        yield test_client


def board(client, board_id="test", sort_order="desc"):
    response = client.post("/v1/leaderboards", headers=AUTH,
                           json={"id": board_id, "title": "测试榜", "sort_order": sort_order})
    assert response.status_code == 201, response.text
    return f"/v1/leaderboards/{board_id}"


def submit(client, path, player, score, **extra):
    payload = {"submission_id": str(uuid4()), "player_id": player, "score": score, **extra}
    response = client.post(f"{path}/scores", headers=AUTH, json=payload)
    assert response.status_code == 200, response.text
    return response.json()


def test_discovery_auth_and_missing_resources(client):
    assert client.get("/health").json() == {"status": "ok"}
    assert client.get("/docs").status_code == 200
    spec = client.get("/openapi.json").json()
    assert "/v1/leaderboards/{board_id}/scores" in spec["paths"]
    payload = {"id": "test", "title": "测试"}
    for headers in ({}, {"Authorization": "Bearer wrong"}, {"Authorization": "Basic wrong"}):
        assert client.post("/v1/leaderboards", headers=headers, json=payload).status_code == 401
    path = board(client)
    assert client.post("/v1/leaderboards", headers=AUTH, json=payload).status_code == 409
    assert client.get("/v1/leaderboards").json()[0]["id"] == "test"
    assert client.get(f"{path}/players/missing").status_code == 404
    assert client.get("/v1/leaderboards/absent/scores").status_code == 404
    missing = client.post("/v1/leaderboards/absent/scores", headers=AUTH,
                          json={"submission_id": str(uuid4()), "player_id": "p", "score": 1})
    assert missing.status_code == 404


def test_unconfigured_writes_are_disabled(tmp_path):
    settings = Settings(database_url=f"sqlite:///{tmp_path.as_posix()}/disabled.sqlite3")
    with TestClient(create_app(settings)) as client:
        response = client.post("/v1/leaderboards", json={"id": "test", "title": "测试"})
        assert response.status_code == 503
        assert response.json()["detail"]["code"] == "write_not_configured"
        assert client.get("/v1/leaderboards").json() == []


@pytest.mark.parametrize("sort_order, scores, best", [("desc", [10, 5, 20], 20), ("asc", [10, 20, 5], 5)])
def test_personal_best_and_board_isolation(client, sort_order, scores, best):
    path = board(client, sort_order=sort_order)
    results = [submit(client, path, "one", score, metadata={"any_future_field": score}) for score in scores]
    assert [result["best_updated"] for result in results] == [True, False, True]
    entry = client.get(f"{path}/players/one").json()
    assert entry["score"] == best
    assert entry["metadata"] == {"any_future_field": best}
    assert entry["achieved_at"].endswith("Z")
    other = board(client, "independent", "asc")
    submit(client, other, "one", 999)
    assert client.get(f"{path}/players/one").json()["score"] == best


@pytest.mark.parametrize("sort_order, scores", [("desc", [100, 100, 90, 90, 50]), ("asc", [1, 1, 2, 2, 3])])
def test_ties_and_pagination(client, sort_order, scores):
    path = board(client, sort_order=sort_order)
    for index, score in enumerate(scores):
        submit(client, path, f"p{index}", score, display_name=f"人物{index}")
    original = client.get(f"{path}/players/p0").json()
    result = submit(client, path, "p0", scores[0], display_name="同分不替换")
    assert result["best_updated"] is False
    assert client.get(f"{path}/players/p0").json() == original
    page = client.get(f"{path}/scores").json()
    assert page["total"] == 5
    assert [entry["rank"] for entry in page["entries"]] == [1, 1, 3, 3, 5]
    assert [entry["player_id"] for entry in page["entries"]] == [f"p{i}" for i in range(5)]
    middle = client.get(f"{path}/scores?offset=1&limit=3").json()["entries"]
    assert [entry["rank"] for entry in middle] == [1, 3, 3]
    assert client.get(f"{path}/scores?offset=50").json()["entries"] == []
    for index in range(5):
        assert client.get(f"{path}/players/p{index}").json()["rank"] == [1, 1, 3, 3, 5][index]


def test_idempotency_conflicts_and_delete(client):
    path = board(client)
    payload = {"submission_id": str(uuid4()), "player_id": "person", "score": 42,
               "metadata": {"wave": 2, "details": {"a": 1, "b": 2}}}
    first = client.post(f"{path}/scores", headers=AUTH, json=payload).json()
    reordered = {**payload, "metadata": {"details": {"b": 2, "a": 1}, "wave": 2}}
    retry = client.post(f"{path}/scores", headers=AUTH, json=reordered).json()
    assert retry == {**first, "replayed": True}
    for change in ({"score": 43}, {"player_id": "other"}, {"metadata": {}}):
        response = client.post(f"{path}/scores", headers=AUTH, json={**payload, **change})
        assert response.status_code == 409
    assert client.delete(f"{path}/players/person/score").status_code == 401
    assert client.delete(f"{path}/players/person/score", headers=AUTH).status_code == 204
    assert client.post(f"{path}/scores", headers=AUTH, json=payload).json()["replayed"] is True
    assert client.get(f"{path}/players/person").status_code == 404
    assert client.get(f"{path}/scores").json()["total"] == 0
    submit(client, path, "person", 7)
    assert client.get(f"{path}/players/person").json()["score"] == 7


def test_persistence_across_restart(settings):
    with TestClient(create_app(settings)) as client:
        path = board(client)
        receipt = submit(client, path, "persistent", 123)
    with TestClient(create_app(settings)) as client:
        assert client.get(f"{path}/players/persistent").json()["score"] == 123
        response = client.post(f"{path}/scores", headers=AUTH, json={
            "submission_id": receipt["submission_id"], "player_id": "persistent", "score": 123})
        assert response.json()["replayed"] is True


@pytest.mark.parametrize("sort_order, expected", [("desc", 39), ("asc", 0)])
def test_concurrent_submissions_keep_best(client, sort_order, expected):
    path = board(client, sort_order=sort_order)
    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(lambda score: submit(client, path, "same-player", score), range(40)))
    assert len(results) == 40
    assert client.get(f"{path}/players/same-player").json()["score"] == expected
    assert client.get(f"{path}/scores").json()["total"] == 1


def test_concurrent_duplicate_submission(client):
    path = board(client)
    payload = {"submission_id": str(uuid4()), "player_id": "same-player", "score": 20}
    def send(_index):
        response = client.post(f"{path}/scores", headers=AUTH, json=payload)
        assert response.status_code == 200, response.text
        return response.json()
    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(send, range(12)))
    assert sum(not result["replayed"] for result in results) == 1


def test_pages_remain_consistent_during_writes(client):
    path = board(client)
    for index in range(10):
        submit(client, path, f"initial-{index}", index)

    def operation(index):
        if index % 2:
            submit(client, path, f"new-{index}", 100 + index)
        else:
            response = client.get(f"{path}/scores?limit=100")
            assert response.status_code == 200
            page = response.json()
            assert len(page["entries"]) == page["total"]
            assert [row["rank"] for row in page["entries"]] == list(range(1, page["total"] + 1))

    with ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(operation, range(40)))
    assert client.get(f"{path}/scores").json()["total"] == 30


@pytest.mark.parametrize("change", [
    {"score": True}, {"score": 1.5}, {"score": 2**53}, {"score": -(2**53)},
    {"player_id": "../bad"}, {"player_id": "p" * 129}, {"submission_id": "not-a-uuid"},
    {"display_name": "  "}, {"display_name": "bad\nname"}, {"display_name": "a" * 49},
    {"metadata": {"text": "中" * 3000}}, {"unexpected": 1},
])
def test_invalid_submission(client, change):
    path = board(client)
    payload = {"submission_id": str(uuid4()), "player_id": "person", "score": 1, **change}
    assert client.post(f"{path}/scores", headers=AUTH, json=payload).status_code == 422


@pytest.mark.parametrize("query", ["limit=0", "limit=101", "offset=-1", "offset=10001"])
def test_pagination_bounds(client, query):
    path = board(client)
    assert client.get(f"{path}/scores?{query}").status_code == 422


def test_case_sensitive_players_and_safe_integer_limits(client):
    path = board(client)
    submit(client, path, "Player", 2**53 - 1)
    submit(client, path, "player", -(2**53 - 1))
    assert client.get(f"{path}/scores").json()["total"] == 2


@pytest.mark.parametrize("number", ["NaN", "Infinity", "-Infinity"])
def test_nonfinite_metadata_is_rejected(client, number):
    path = board(client)
    raw = ('{"submission_id":"' + str(uuid4()) + '","player_id":"person",'
           '"score":1,"metadata":{"number":' + number + '}}')
    response = client.post(f"{path}/scores", headers={**AUTH, "Content-Type": "application/json"}, content=raw)
    assert response.status_code == 422


def test_postgres_schema_and_lock_compile():
    statements = []
    engine = create_mock_engine("postgresql+psycopg://", lambda sql, *a, **kw:
                               statements.append(str(sql.compile(dialect=postgresql.dialect()))))
    Base.metadata.create_all(engine)
    ddl = "\n".join(statements)
    assert "BIGINT" in ddl and "JSON" in ddl
    assert "TIMESTAMP WITHOUT TIME ZONE" in ddl
    locking = str(select(Board).with_for_update().compile(dialect=postgresql.dialect()))
    assert "FOR UPDATE" in locking


def test_plain_postgres_url_uses_psycopg_and_separate_password():
    settings = Settings(database_url="postgresql://leaderboard@localhost/leaderboard",
                        database_password="a password with @:/#")
    settings.validate()
    resolved = settings.resolved_database_url()
    assert resolved.drivername == "postgresql+psycopg"
    assert resolved.password == "a password with @:/#"


@pytest.mark.parametrize("token", ["short", "replace-with-a-random-token-at-least-32-characters"])
def test_bad_configuration_fails_closed(tmp_path, token):
    with pytest.raises(ValueError):
        with TestClient(create_app(Settings(database_url=f"sqlite:///{tmp_path}/bad.sqlite3", api_token=token))):
            pass
