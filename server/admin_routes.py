"""Web 管理后台：用户列表、统计、删除用户。"""
from __future__ import annotations

import json
import os
import sqlite3
import time
from datetime import datetime
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from itsdangerous import BadSignature, URLSafeSerializer

TEMPLATES_DIR = Path(__file__).resolve().parent / "templates"
templates = Jinja2Templates(directory=str(TEMPLATES_DIR))

ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "admin123")
ADMIN_COOKIE = "truck_ledger_admin"
ADMIN_COOKIE_MAX_AGE = 60 * 60 * 8  # 8 小时

router = APIRouter(prefix="/admin", tags=["admin"])


def _serializer() -> URLSafeSerializer:
    secret = os.environ.get("JWT_SECRET", "dev-change-me-in-production")
    return URLSafeSerializer(secret, salt="truck-ledger-admin")


def _is_admin(request: Request) -> bool:
    token = request.cookies.get(ADMIN_COOKIE)
    if not token:
        return False
    try:
        data = _serializer().loads(token)
        return data.get("admin") is True
    except BadSignature:
        return False


def _require_admin(request: Request) -> None:
    if not _is_admin(request):
        raise HTTPException(status_code=303, headers={"Location": "/admin/login"})


def _fmt_ms(ms: int | None) -> str:
    if not ms:
        return "—"
    try:
        return datetime.fromtimestamp(ms / 1000).strftime("%Y-%m-%d %H:%M")
    except (OSError, ValueError):
        return "—"


def _collect_stats(db_path: Path, attachments_dir: Path) -> dict[str, Any]:
    user_count = 0
    round_count = 0
    attachment_count = 0

    if db_path.exists():
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        try:
            user_count = conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
            for row in conn.execute("SELECT data_json FROM ledgers"):
                try:
                    data = json.loads(row["data_json"])
                    rounds = data.get("rounds", []) if isinstance(data, dict) else []
                    round_count += len(rounds)
                except json.JSONDecodeError:
                    pass
        finally:
            conn.close()

    if attachments_dir.exists():
        attachment_count = sum(1 for p in attachments_dir.rglob("*.jpg") if p.is_file())

    data_size = 0
    data_root = db_path.parent
    if data_root.exists():
        for p in data_root.rglob("*"):
            if p.is_file():
                data_size += p.stat().st_size

    return {
        "user_count": user_count,
        "round_count": round_count,
        "attachment_count": attachment_count,
        "data_size_mb": round(data_size / (1024 * 1024), 2),
    }


def _list_users(db_path: Path, attachments_dir: Path) -> list[dict[str, Any]]:
    if not db_path.exists():
        return []
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    users: list[dict[str, Any]] = []
    try:
        rows = conn.execute(
            """
            SELECT u.id, u.username, u.created_at,
                   l.data_json, l.updated_at
            FROM users u
            LEFT JOIN ledgers l ON l.user_id = u.id
            ORDER BY u.id
            """
        ).fetchall()
        for row in rows:
            round_count = 0
            if row["data_json"]:
                try:
                    data = json.loads(row["data_json"])
                    rounds = data.get("rounds", []) if isinstance(data, dict) else []
                    round_count = len(rounds)
                except json.JSONDecodeError:
                    pass
            user_dir = attachments_dir / str(row["id"])
            att_count = (
                sum(1 for p in user_dir.glob("*.jpg") if p.is_file())
                if user_dir.exists()
                else 0
            )
            users.append(
                {
                    "id": row["id"],
                    "username": row["username"],
                    "created_at": _fmt_ms(row["created_at"]),
                    "round_count": round_count,
                    "attachment_count": att_count,
                    "updated_at": _fmt_ms(row["updated_at"]),
                }
            )
    finally:
        conn.close()
    return users


def register_admin_routes(app, db_path: Path, attachments_dir: Path) -> None:
    port = int(os.environ.get("PORT", "8080"))

    @router.get("", response_model=None)
    @router.get("/", response_model=None)
    def admin_root(request: Request):
        if _is_admin(request):
            return RedirectResponse("/admin/dashboard", status_code=303)
        return RedirectResponse("/admin/login", status_code=303)

    @router.get("/login", response_class=HTMLResponse, response_model=None)
    def admin_login_page(request: Request):
        if _is_admin(request):
            return RedirectResponse("/admin/dashboard", status_code=303)
        error = "密码错误" if request.query_params.get("error") else ""
        return templates.TemplateResponse(
            request,
            "admin_login.html",
            {"error": error},
        )

    @router.post("/login")
    def admin_login(request: Request, password: str = Form(...)) -> RedirectResponse:
        if password != ADMIN_PASSWORD:
            return RedirectResponse("/admin/login?error=1", status_code=303)
        token = _serializer().dumps({"admin": True, "t": int(time.time())})
        resp = RedirectResponse("/admin/dashboard", status_code=303)
        resp.set_cookie(
            ADMIN_COOKIE,
            token,
            max_age=ADMIN_COOKIE_MAX_AGE,
            httponly=True,
            samesite="lax",
        )
        return resp

    @router.get("/logout")
    def admin_logout() -> RedirectResponse:
        resp = RedirectResponse("/admin/login", status_code=303)
        resp.delete_cookie(ADMIN_COOKIE)
        return resp

    @router.get("/dashboard", response_class=HTMLResponse, response_model=None)
    def admin_dashboard(request: Request, msg: str = ""):
        if not _is_admin(request):
            return RedirectResponse("/admin/login", status_code=303)
        return templates.TemplateResponse(
            request,
            "admin_dashboard.html",
            {
                "stats": _collect_stats(db_path, attachments_dir),
                "users": _list_users(db_path, attachments_dir),
                "message": msg,
                "port": port,
            },
        )

    @router.post("/users/{user_id}/delete")
    def admin_delete_user(request: Request, user_id: int) -> RedirectResponse:
        if not _is_admin(request):
            return RedirectResponse("/admin/login", status_code=303)
        user_dir = attachments_dir / str(user_id)
        with sqlite3.connect(db_path) as conn:
            row = conn.execute(
                "SELECT username FROM users WHERE id = ?", (user_id,)
            ).fetchone()
            if row is None:
                return RedirectResponse("/admin/dashboard?msg=用户不存在", status_code=303)
            username = row[0]
            conn.execute("DELETE FROM ledgers WHERE user_id = ?", (user_id,))
            conn.execute("DELETE FROM users WHERE id = ?", (user_id,))
            conn.commit()
        if user_dir.exists():
            import shutil

            shutil.rmtree(user_dir, ignore_errors=True)
        return RedirectResponse(
            f"/admin/dashboard?msg=已删除用户 {username}",
            status_code=303,
        )

    app.include_router(router)
