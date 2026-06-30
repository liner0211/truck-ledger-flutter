"""卡车记账 — 简易云端后端：用户注册/登录 + 账本 JSON + 附件存储。"""
from __future__ import annotations

import json
import os
import re
import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Annotated, Any

from fastapi import Depends, FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse, Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from passlib.context import CryptContext
from pydantic import BaseModel, Field

from admin_routes import register_admin_routes

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
DB_PATH = DATA_DIR / "truck_ledger.db"
ATTACHMENTS_DIR = DATA_DIR / "attachments"

JWT_SECRET = os.environ.get("JWT_SECRET", "dev-change-me-in-production")
JWT_ALG = "HS256"
JWT_EXPIRE_SEC = 60 * 60 * 24 * 30  # 30 天

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
bearer = HTTPBearer(auto_error=False)

app = FastAPI(title="Truck Ledger API", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _init_db() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    ATTACHMENTS_DIR.mkdir(parents=True, exist_ok=True)
    with _db() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              username TEXT NOT NULL UNIQUE,
              password_hash TEXT NOT NULL,
              created_at INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS ledgers (
              user_id INTEGER PRIMARY KEY,
              data_json TEXT NOT NULL,
              updated_at INTEGER NOT NULL,
              FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            );
            """
        )


@contextmanager
def _db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


class RegisterBody(BaseModel):
    username: str = Field(min_length=3, max_length=32)
    password: str = Field(min_length=6, max_length=128)


class LoginBody(BaseModel):
    username: str
    password: str


class AuthResponse(BaseModel):
    token: str
    username: str
    user_id: int


class LedgerPayload(BaseModel):
    rounds: list[Any] = Field(default_factory=list)


class LedgerResponse(BaseModel):
    rounds: list[Any]
    updated_at: int


class SyncPushResponse(BaseModel):
    updated_at: int


def _validate_username(username: str) -> str:
    u = username.strip()
    if not re.fullmatch(r"[A-Za-z0-9_]{3,32}", u):
        raise HTTPException(
            status_code=400,
            detail="用户名须为 3–32 位字母、数字或下划线",
        )
    return u


def _hash_password(password: str) -> str:
    return pwd_context.hash(password)


def _verify_password(password: str, password_hash: str) -> bool:
    return pwd_context.verify(password, password_hash)


def _create_token(user_id: int, username: str) -> str:
    now = int(time.time())
    payload = {
        "sub": str(user_id),
        "username": username,
        "iat": now,
        "exp": now + JWT_EXPIRE_SEC,
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALG)


def _current_user(
    cred: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> sqlite3.Row:
    if cred is None or not cred.credentials:
        raise HTTPException(status_code=401, detail="未登录")
    try:
        payload = jwt.decode(cred.credentials, JWT_SECRET, algorithms=[JWT_ALG])
        user_id = int(payload["sub"])
    except (JWTError, ValueError, KeyError):
        raise HTTPException(status_code=401, detail="登录已失效，请重新登录")
    with _db() as conn:
        row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=401, detail="用户不存在")
    return row


@app.on_event("startup")
def startup() -> None:
    _init_db()
    register_admin_routes(app, DB_PATH, ATTACHMENTS_DIR)


@app.get("/")
def root() -> RedirectResponse:
    return RedirectResponse("/admin", status_code=303)


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/api/auth/register", response_model=AuthResponse)
def register(body: RegisterBody) -> AuthResponse:
    username = _validate_username(body.username)
    password_hash = _hash_password(body.password)
    now = int(time.time() * 1000)
    with _db() as conn:
        try:
            cur = conn.execute(
                "INSERT INTO users (username, password_hash, created_at) VALUES (?, ?, ?)",
                (username, password_hash, now),
            )
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=409, detail="用户名已存在")
        user_id = int(cur.lastrowid)
        conn.execute(
            "INSERT INTO ledgers (user_id, data_json, updated_at) VALUES (?, ?, ?)",
            (user_id, json.dumps({"rounds": []}, ensure_ascii=False), 0),
        )
    token = _create_token(user_id, username)
    return AuthResponse(token=token, username=username, user_id=user_id)


@app.post("/api/auth/login", response_model=AuthResponse)
def login(body: LoginBody) -> AuthResponse:
    username = body.username.strip()
    with _db() as conn:
        row = conn.execute(
            "SELECT * FROM users WHERE username = ?", (username,)
        ).fetchone()
    if row is None or not _verify_password(body.password, row["password_hash"]):
        raise HTTPException(status_code=401, detail="用户名或密码错误")
    token = _create_token(int(row["id"]), row["username"])
    return AuthResponse(token=token, username=row["username"], user_id=int(row["id"]))


@app.get("/api/auth/me")
def me(user: Annotated[sqlite3.Row, Depends(_current_user)]) -> dict[str, Any]:
    return {"user_id": int(user["id"]), "username": user["username"]}


@app.get("/api/ledger", response_model=LedgerResponse)
def get_ledger(user: Annotated[sqlite3.Row, Depends(_current_user)]) -> LedgerResponse:
    with _db() as conn:
        row = conn.execute(
            "SELECT data_json, updated_at FROM ledgers WHERE user_id = ?",
            (int(user["id"]),),
        ).fetchone()
    if row is None:
        return LedgerResponse(rounds=[], updated_at=0)
    data = json.loads(row["data_json"])
    rounds = data.get("rounds", []) if isinstance(data, dict) else []
    return LedgerResponse(rounds=rounds, updated_at=int(row["updated_at"]))


@app.put("/api/ledger", response_model=SyncPushResponse)
def put_ledger(
    body: LedgerPayload,
    user: Annotated[sqlite3.Row, Depends(_current_user)],
) -> SyncPushResponse:
    updated_at = int(time.time() * 1000)
    payload = json.dumps({"rounds": body.rounds}, ensure_ascii=False)
    with _db() as conn:
        conn.execute(
            """
            INSERT INTO ledgers (user_id, data_json, updated_at) VALUES (?, ?, ?)
            ON CONFLICT(user_id) DO UPDATE SET
              data_json = excluded.data_json,
              updated_at = excluded.updated_at
            """,
            (int(user["id"]), payload, updated_at),
        )
    return SyncPushResponse(updated_at=updated_at)


def _user_attachment_dir(user_id: int) -> Path:
    d = ATTACHMENTS_DIR / str(user_id)
    d.mkdir(parents=True, exist_ok=True)
    return d


def _safe_filename(name: str) -> str:
    base = Path(name).name
    if not re.fullmatch(r"[A-Za-z0-9._-]+\.jpg", base):
        raise HTTPException(status_code=400, detail="非法附件文件名")
    return base


@app.post("/api/attachments/{filename}")
async def upload_attachment(
    filename: str,
    user: Annotated[sqlite3.Row, Depends(_current_user)],
    file: UploadFile = File(...),
) -> dict[str, str]:
    safe = _safe_filename(filename)
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="空文件")
    if len(data) > 20 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="附件过大（上限 20MB）")
    path = _user_attachment_dir(int(user["id"])) / safe
    path.write_bytes(data)
    return {"filename": safe}


@app.get("/api/attachments/{filename}")
def download_attachment(
    filename: str,
    user: Annotated[sqlite3.Row, Depends(_current_user)],
) -> Response:
    safe = _safe_filename(filename)
    path = _user_attachment_dir(int(user["id"])) / safe
    if not path.exists():
        raise HTTPException(status_code=404, detail="附件不存在")
    return Response(content=path.read_bytes(), media_type="image/jpeg")


@app.get("/api/attachments")
def list_attachments(
    user: Annotated[sqlite3.Row, Depends(_current_user)],
) -> dict[str, list[str]]:
    d = _user_attachment_dir(int(user["id"]))
    names = sorted(p.name for p in d.glob("*.jpg") if p.is_file())
    return {"files": names}


if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("PORT", "8080"))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
