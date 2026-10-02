import tempfile
from pathlib import Path

from fastapi.testclient import TestClient

from server import app as server_app


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



def test_ai_fallback_endpoints_require_auth_and_answer_locally(monkeypatch):
    monkeypatch.delenv("FHM_LLM_BASE_URL", raising=False)
    monkeypatch.delenv("FHM_LLM_MODEL", raising=False)
    monkeypatch.delenv("FHM_VISION_MODEL", raising=False)

    with tempfile.TemporaryDirectory() as directory:
        client = _client(Path(directory))
        created = client.post("/api/v1/families", json={"name": "AI家庭"}).json()
        family_id = created["family_id"]
        headers = {"Authorization": f"Bearer {created['token']}"}

        denied = client.get(
            f"/api/v1/families/{family_id}/ai/status",
            headers={"Authorization": "Bearer wrong"},
        )
        assert denied.status_code == 401

        status = client.get(
            f"/api/v1/families/{family_id}/ai/status",
            headers=headers,
        )
        assert status.status_code == 200
        assert status.json()["configured"] is False
        assert status.json()["fallback"] == "local-rules"

        classified = client.post(
            f"/api/v1/families/{family_id}/ai/classify",
            headers=headers,
            json={"name": "儿童体温计", "notes": ""},
        )
        assert classified.status_code == 200
        assert classified.json()["category"] == "医药"
        assert classified.json()["source"] == "local"

        asked = client.post(
            f"/api/v1/families/{family_id}/ai/ask",
            headers=headers,
            json={
                "question": "体温计在哪里？",
                "items": [
                    {
                        "name": "体温计",
                        "category": "医药",
                        "location": "我的家 / 卫生间 / 医药盒",
                        "quantity": 1,
                        "unit": "个",
                    }
                ],
            },
        )
        assert asked.status_code == 200
        assert "卫生间" in asked.json()["answer"]
        assert asked.json()["source"] == "local"

        vision = client.post(
            f"/api/v1/families/{family_id}/ai/vision",
            headers=headers,
            json={
                "image_base64": "ZmFrZQ==",
                "mime_type": "image/jpeg",
            },
        )
        assert vision.status_code == 200
        assert vision.json()["available"] is False



def test_sync_meta_returns_revision_without_backup_payload():
    with tempfile.TemporaryDirectory() as directory:
        client = _client(Path(directory))
        created = client.post(
            "/api/v1/families",
            json={"name": "自动同步家庭"},
        ).json()
        family_id = created["family_id"]
        headers = {"Authorization": f"Bearer {created['token']}"}

        meta0 = client.get(
            f"/api/v1/families/{family_id}/meta",
            headers=headers,
        )
        assert meta0.status_code == 200
        assert meta0.json()["revision"] == 0
        assert meta0.json()["has_backup"] is False
        assert "backup" not in meta0.json()

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

        meta1 = client.get(
            f"/api/v1/families/{family_id}/meta",
            headers=headers,
        )
        assert meta1.status_code == 200
        assert meta1.json()["revision"] == 1
        assert meta1.json()["has_backup"] is True
