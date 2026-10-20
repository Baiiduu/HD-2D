from dataclasses import replace
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from leaderboard.app import create_app
from test_api import AUTH, settings


DEVICE_TOKEN = 'a1' * 32


@pytest.fixture
def demo(settings):
    with TestClient(create_app(replace(settings, demo_board_id='world-demo-v1'))) as client:
        response = client.post('/v1/leaderboards', headers=AUTH,
                               json={'id': 'world-demo-v1', 'title': '匿名试玩榜'})
        assert response.status_code == 201
        yield client


def payload(device=None, **changes):
    return {'device_id': str(device or uuid4()), 'submission_id': str(uuid4()),
            'score': 120, 'display_name': '玩家', 'metadata': {}, **changes}


def send(client, body, token=DEVICE_TOKEN):
    return client.post('/v1/demo/scores', headers={'Authorization': f'Bearer {token}'}, json=body)


def test_demo_disabled_by_default(settings):
    with TestClient(create_app(settings)) as client:
        assert send(client, payload()).status_code == 503


def test_device_owns_identity_and_cannot_write_admin_routes(demo):
    body = payload()
    response = send(demo, body)
    assert response.status_code == 200, response.text
    result = response.json()
    assert result['board_id'] == 'world-demo-v1'
    assert result['player_id'] == 'demo:' + body['device_id']
    assert result['personal_best'] == 120
    assert send(demo, body).json()['replayed'] is True
    assert send(demo, payload(body['device_id'], score=500), token='b2' * 32).status_code == 401
    page = demo.get('/v1/leaderboards/world-demo-v1/scores').json()
    assert page['total'] == 1 and page['entries'][0]['score'] == 120
    assert demo.post('/v1/leaderboards', headers={'Authorization': f'Bearer {DEVICE_TOKEN}'},
                     json={'id': 'other', 'title': 'other'}).status_code == 401
    assert demo.post('/v1/leaderboards/world-demo-v1/scores',
                     headers={'Authorization': f'Bearer {DEVICE_TOKEN}'}, json={}).status_code == 401


def test_demo_retains_best_receipts_and_device_hash_only(demo):
    body = payload()
    assert send(demo, body).status_code == 200
    assert send(demo, payload(body['device_id'], score=80)).json()['personal_best'] == 120
    assert send(demo, payload(body['device_id'], score=200)).json()['personal_best'] == 200
    assert send(demo, {**body, 'score': 121}).status_code == 409
    from leaderboard.models import Device
    with Session(demo.app.state.engine) as session:
        device = session.get(Device, body['device_id'])
        assert device is not None and len(device.token_hash) == 64
        assert device.token_hash != DEVICE_TOKEN
        assert DEVICE_TOKEN not in str(session.execute(select(Device)).all())


def test_first_submission_and_duplicates_are_atomic_under_concurrency(demo):
    body = payload()
    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(lambda _: send(demo, body), range(8)))
    assert all(response.status_code == 200 for response in results)
    assert sum(not response.json()['replayed'] for response in results) == 1
    assert demo.get('/v1/leaderboards/world-demo-v1/scores').json()['total'] == 1


def test_demo_identity_survives_restart(settings):
    config = replace(settings, demo_board_id='world-demo-v1')
    body = payload()
    with TestClient(create_app(config)) as first:
        first.post('/v1/leaderboards', headers=AUTH,
                   json={'id': 'world-demo-v1', 'title': '试玩'})
        assert send(first, body).status_code == 200
    with TestClient(create_app(config)) as second:
        assert send(second, body).json()['replayed'] is True
        assert send(second, payload(body['device_id']), token='b2' * 32).status_code == 401


@pytest.mark.parametrize('token', ['', 'short', 'x' * 64])
def test_demo_rejects_invalid_tokens(demo, token):
    assert send(demo, payload(), token).status_code == 401


@pytest.mark.parametrize('changes', [
    {'score': -1}, {'score': 1.5}, {'score': True}, {'device_id': 'person'},
    {'player_id': 'someone'}, {'board_id': 'admin-board'}, {'metadata': {'n': float('inf')}},
])
def test_demo_rejects_invalid_claims(demo, changes):
    body = payload(**changes)
    if changes.get('metadata'):
        # httpx rejects Infinity before the server sees it; use a raw JSON request.
        import json
        result = demo.post('/v1/demo/scores', content=json.dumps(body),
                           headers={'Authorization': f'Bearer {DEVICE_TOKEN}', 'Content-Type': 'application/json'})
    else:
        result = send(demo, body)
    assert result.status_code == 422
