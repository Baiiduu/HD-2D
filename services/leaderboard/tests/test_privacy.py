from concurrent.futures import ThreadPoolExecutor

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from leaderboard.models import BestScore, Device, Submission
from test_demo_api import DEVICE_TOKEN, demo, payload, send, settings
from test_api import AUTH


def consented(**changes):
    return payload(privacy_version="2026-10-21", public_consent=True, **changes)


def erase(client, body, token=DEVICE_TOKEN):
    return client.post("/v1/demo/privacy/delete", json={"device_id": body["device_id"]},
                       headers={"Authorization": f"Bearer {token}"})


def test_upload_requires_current_explicit_public_consent(demo):
    legacy = payload()
    legacy.pop("privacy_version", None)
    legacy.pop("public_consent", None)
    assert send(demo, legacy).status_code == 422
    assert send(demo, consented()).status_code == 200
    for changes in ({"privacy_version": "old"}, {"public_consent": False}, {"public_consent": 1}):
        assert send(demo, {**consented(), **changes}).status_code == 422


def test_old_unconsented_demo_records_are_hidden_without_destroying_them(demo):
    body = consented(score=150)
    player = "demo:" + body["device_id"]
    response = demo.post("/v1/leaderboards/world-demo-v1/scores", headers=AUTH, json={
        "submission_id": body["submission_id"], "player_id": player,
        "score": 100, "display_name": "legacy"})
    assert response.status_code == 200
    assert demo.get("/v1/leaderboards/world-demo-v1/scores").json()["total"] == 0
    assert demo.get("/v1/leaderboards/world-demo-v1/players/" + player).status_code == 404
    with Session(demo.app.state.engine) as session:
        assert session.get(BestScore, ("world-demo-v1", player)) is not None
    from uuid import uuid4
    assert send(demo, {**body, "submission_id": str(uuid4())}).status_code == 200
    page = demo.get("/v1/leaderboards/world-demo-v1/scores").json()
    assert page["total"] == 1 and page["entries"][0]["rank"] == 1


def test_deletion_authenticates_and_removes_owned_records_only(demo):
    owned = consented()
    other = consented()
    assert send(demo, owned).status_code == 200
    assert send(demo, other, token="b2" * 32).status_code == 200
    assert erase(demo, owned, token="c3" * 32).status_code == 401
    assert erase(demo, owned).status_code == 204
    with Session(demo.app.state.engine) as session:
        assert session.get(Device, owned["device_id"]) is None
        player = "demo:" + owned["device_id"]
        assert session.scalar(select(func.count()).select_from(BestScore).where(BestScore.player_id == player)) == 0
        assert session.scalar(select(func.count()).select_from(Submission).where(Submission.player_id == player)) == 0
        assert session.get(Device, other["device_id"]) is not None
    assert erase(demo, owned).status_code == 204
    assert send(demo, owned).status_code == 401
    assert send(demo, {**owned, "score": 9999}).status_code == 401
    page = demo.get("/v1/leaderboards/world-demo-v1/scores").json()
    assert page["total"] == 1 and page["entries"][0]["player_id"] == "demo:" + other["device_id"]


def test_delete_before_first_commit_blocks_late_registration(demo):
    body = consented()
    assert erase(demo, body).status_code == 204
    assert send(demo, body).status_code == 401


def test_deletion_and_inflight_replays_cannot_recreate_score(demo):
    body = consented()
    assert send(demo, body).status_code == 200
    with ThreadPoolExecutor(max_workers=5) as pool:
        futures = [pool.submit(send, demo, body) for _ in range(4)]
        futures.append(pool.submit(erase, demo, body))
        results = [future.result().status_code for future in futures]
    assert results[-1] == 204 and set(results[:-1]) <= {200, 401}
    assert demo.get("/v1/leaderboards/world-demo-v1/scores").json()["total"] == 0
    assert send(demo, body).status_code == 401


def test_deleted_consent_record_and_minimal_revocation(demo):
    from leaderboard.models import DemoConsent, RevokedCredential

    body = consented()
    assert send(demo, body).status_code == 200
    with Session(demo.app.state.engine) as session:
        assert session.get(DemoConsent, body["device_id"]).policy_version == "2026-10-21"
    assert erase(demo, body).status_code == 204
    with Session(demo.app.state.engine) as session:
        assert session.get(DemoConsent, body["device_id"]) is None
        revoked = list(session.scalars(select(RevokedCredential)))
        assert len(revoked) == 1
        assert len(revoked[0].token_hash) == 64 and revoked[0].token_hash != DEVICE_TOKEN
        assert not hasattr(revoked[0], "device_id")
