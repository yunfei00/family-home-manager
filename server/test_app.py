import tempfile
from pathlib import Path

from fastapi.testclient import TestClient

import app as server_app


def _client(tmp_path: Path) -> TestClient:
    server_app.store = server_app.SyncStore(str(tmp_path / "sync.db"))
    return TestClient(server_app.app)


def test_create_push_pull_and_revision_conflict():
    with tempfile.TemporaryDirectory() as directory:
        client = _client(Path(directory))

        created = client.post(
            "/api/v1/families",
            json={"name": "测试家庭"},
        )
        assert created.status_code == 201
        credentials = created.json()
        family_id = credentials["family_id"]
        token = credentials["token"]
        headers = {"Authorization": f"Bearer {token}"}

        empty = client.get(
            f"/api/v1/families/{family_id}/backup",
            headers=headers,
        )
        assert empty.status_code == 200
        assert empty.json()["revision"] == 0
        assert empty.json()["backup"] is None

        backup = {
            "format": "family-home-manager-backup",
            "format_version": 1,
            "tables": {"locations": [{"id": 1, "name": "我的家"}]},
            "photos": {},
        }
        pushed = client.put(
            f"/api/v1/families/{family_id}/backup",
            headers=headers,
            json={"expected_revision": 0, "backup": backup},
        )
        assert pushed.status_code == 200
        assert pushed.json()["revision"] == 1

        pulled = client.get(
            f"/api/v1/families/{family_id}/backup",
            headers=headers,
        )
        assert pulled.status_code == 200
        assert pulled.json()["revision"] == 1
        assert pulled.json()["backup"]["format"] == "family-home-manager-backup"

        conflict = client.put(
            f"/api/v1/families/{family_id}/backup",
            headers=headers,
            json={"expected_revision": 0, "backup": backup},
        )
        assert conflict.status_code == 409
        assert conflict.json()["current_revision"] == 1


def test_rejects_bad_token_and_bad_format():
    with tempfile.TemporaryDirectory() as directory:
        client = _client(Path(directory))
        created = client.post("/api/v1/families", json={"name": "家庭"}).json()
        family_id = created["family_id"]

        denied = client.get(
            f"/api/v1/families/{family_id}/backup",
            headers={"Authorization": "Bearer wrong"},
        )
        assert denied.status_code == 401

        bad = client.put(
            f"/api/v1/families/{family_id}/backup",
            headers={"Authorization": f"Bearer {created['token']}"},
            json={
                "expected_revision": 0,
                "backup": {"format": "something-else"},
            },
        )
        assert bad.status_code == 400
