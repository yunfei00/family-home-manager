import hashlib
import hmac
import json
import os
import secrets
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


class FamilyCreate(BaseModel):
    name: str = Field(default="我的家", max_length=100)


class BackupPut(BaseModel):
    expected_revision: int = Field(ge=0)
    backup: dict[str, Any]


class SyncStore:
    def __init__(self, db_path: str):
        self.db_path = db_path
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)
        self._init_schema()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=30)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_schema(self) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS families (
                    family_id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    token_hash TEXT NOT NULL,
                    revision INTEGER NOT NULL DEFAULT 0,
                    backup_json TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """
            )

    def create_family(self, name: str) -> dict[str, Any]:
        family_id = secrets.token_urlsafe(9)
        token = secrets.token_urlsafe(32)
        now = _now()
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO families (
                    family_id, name, token_hash, revision,
                    backup_json, created_at, updated_at
                )
                VALUES (?, ?, ?, 0, NULL, ?, ?)
                """,
                (family_id, name.strip() or "我的家", _hash_token(token), now, now),
            )
        return {
            "family_id": family_id,
            "token": token,
            "revision": 0,
        }

    def _get_authorized(
        self,
        family_id: str,
        token: str,
        conn: sqlite3.Connection,
    ) -> sqlite3.Row:
        row = conn.execute(
            "SELECT * FROM families WHERE family_id = ?",
            (family_id,),
        ).fetchone()
        if row is None or not hmac.compare_digest(
            row["token_hash"],
            _hash_token(token),
        ):
            raise PermissionError("invalid family id or token")
        return row

    def get_backup(self, family_id: str, token: str) -> dict[str, Any]:
        with self._connect() as conn:
            row = self._get_authorized(family_id, token, conn)
            raw_backup = row["backup_json"]
            return {
                "revision": int(row["revision"]),
                "backup": None if raw_backup is None else json.loads(raw_backup),
                "updated_at": row["updated_at"],
            }

    def put_backup(
        self,
        family_id: str,
        token: str,
        expected_revision: int,
        backup: dict[str, Any],
    ) -> tuple[bool, int]:
        conn = self._connect()
        try:
            conn.execute("BEGIN IMMEDIATE")
            row = self._get_authorized(family_id, token, conn)
            current = int(row["revision"])
            if current != expected_revision:
                conn.rollback()
                return False, current

            revision = current + 1
            conn.execute(
                """
                UPDATE families
                SET revision = ?, backup_json = ?, updated_at = ?
                WHERE family_id = ?
                """,
                (
                    revision,
                    json.dumps(backup, ensure_ascii=False, separators=(",", ":")),
                    _now(),
                    family_id,
                ),
            )
            conn.commit()
            return True, revision
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()


DB_PATH = os.environ.get(
    "FHM_SYNC_DB",
    str(Path(__file__).with_name("family_sync.db")),
)
store = SyncStore(DB_PATH)
app = FastAPI(title="Family Home Manager Sync", version="1.0.0")


def _bearer_token(authorization: str | None) -> str:
    if not authorization:
        raise HTTPException(status_code=401, detail="missing authorization")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="invalid authorization")
    return token


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/api/v1/families", status_code=201)
def create_family(request: FamilyCreate) -> dict[str, Any]:
    return store.create_family(request.name)


@app.get("/api/v1/families/{family_id}/backup")
def get_backup(
    family_id: str,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    token = _bearer_token(authorization)
    try:
        return store.get_backup(family_id, token)
    except PermissionError as error:
        raise HTTPException(status_code=401, detail=str(error)) from error


@app.put("/api/v1/families/{family_id}/backup")
def put_backup(
    family_id: str,
    request: BackupPut,
    authorization: str | None = Header(default=None),
):
    if request.backup.get("format") != "family-home-manager-backup":
        raise HTTPException(status_code=400, detail="invalid backup format")

    token = _bearer_token(authorization)
    try:
        success, revision = store.put_backup(
            family_id,
            token,
            request.expected_revision,
            request.backup,
        )
    except PermissionError as error:
        raise HTTPException(status_code=401, detail=str(error)) from error

    if not success:
        return JSONResponse(
            status_code=409,
            content={
                "error": "revision_conflict",
                "current_revision": revision,
            },
        )

    return {"revision": revision}
