"""
Standalone account + license-key server for the MSN Signal Bot Flutter app.

Deliberately separate from api_server.py: that process bridges the Quotex
broker WebSocket and is meant to run on the operator's own machine/network
(see quotex_connection_requirements memory — TLS fingerprint + handshake
order gates). Account/license gating has nothing to do with the broker feed
and needs to be reachable from any phone on any network, so it lives in its
own tiny FastAPI app that can be deployed to a free host (Render/Fly.io/etc)
independently of the local Quotex bridge.

Flow:
  1. Flutter app signs the user in with Google (google_sign_in package),
     gets a Google ID token, POSTs it to /auth/google.
  2. This server verifies the ID token against Google's public keys,
     upserts a `users` row, and returns an app-issued JWT session token.
  3. If the user isn't licensed yet, the app shows a "enter license key"
     screen that POSTs to /auth/redeem-key with that session token.
  4. /admin/keys/generate lets the operator (you) mint new keys to hand out
     — no UI needed, just curl + the admin secret.

Everything is SQLite + stdlib where possible to keep this free to run and
easy to self-host.
"""

from __future__ import annotations

import os
import secrets
import sqlite3
import string
import time
from contextlib import contextmanager
from pathlib import Path

import jwt
from dotenv import load_dotenv
from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from pydantic import BaseModel

load_dotenv()

# ─────────────────────────────────────────────────────────────────────────
# Configuration — all from environment, nothing hardcoded.
# ─────────────────────────────────────────────────────────────────────────
GOOGLE_CLIENT_ID = os.environ.get("GOOGLE_CLIENT_ID", "")
JWT_SECRET = os.environ.get("AUTH_JWT_SECRET", "")
ADMIN_SECRET = os.environ.get("AUTH_ADMIN_SECRET", "")
DB_PATH = Path(os.environ.get("AUTH_DB_PATH", "auth.db"))
JWT_TTL_SECONDS = 60 * 60 * 24 * 30  # 30 days — re-issued on every /auth/google

if not GOOGLE_CLIENT_ID:
    raise RuntimeError(
        "GOOGLE_CLIENT_ID is not set. Create a Web OAuth Client ID in Google "
        "Cloud Console and set it as this app's serverClientId (Flutter side) "
        "and GOOGLE_CLIENT_ID (this server's audience check)."
    )
if not JWT_SECRET:
    raise RuntimeError(
        "AUTH_JWT_SECRET is not set. Generate one with: "
        "python -c \"import secrets; print(secrets.token_hex(32))\""
    )
if not ADMIN_SECRET:
    raise RuntimeError(
        "AUTH_ADMIN_SECRET is not set. Generate one with: "
        "python -c \"import secrets; print(secrets.token_hex(24))\""
    )

app = FastAPI(title="MSN Signal Bot — Account & License Server", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─────────────────────────────────────────────────────────────────────────
# Storage
# ─────────────────────────────────────────────────────────────────────────


@contextmanager
def db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db() -> None:
    with db() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS users (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                google_sub    TEXT UNIQUE NOT NULL,
                email         TEXT UNIQUE NOT NULL,
                name          TEXT,
                is_licensed   INTEGER NOT NULL DEFAULT 0,
                license_key   TEXT,
                created_at    REAL NOT NULL,
                licensed_at   REAL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS license_keys (
                key           TEXT PRIMARY KEY,
                is_used       INTEGER NOT NULL DEFAULT 0,
                used_by_email TEXT,
                note          TEXT,
                created_at    REAL NOT NULL,
                redeemed_at   REAL
            )
            """
        )


init_db()

# ─────────────────────────────────────────────────────────────────────────
# JWT session tokens — app-issued, short list of claims, HS256.
# ─────────────────────────────────────────────────────────────────────────


def issue_session_token(user_row: sqlite3.Row) -> str:
    payload = {
        "sub": user_row["google_sub"],
        "email": user_row["email"],
        "iat": int(time.time()),
        "exp": int(time.time()) + JWT_TTL_SECONDS,
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")


def require_session(authorization: str | None) -> sqlite3.Row:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer session token")
    token = authorization.removeprefix("Bearer ").strip()
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
    except jwt.PyJWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired session token")

    with db() as conn:
        row = conn.execute(
            "SELECT * FROM users WHERE google_sub = ?", (payload["sub"],)
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=401, detail="Unknown session subject")
    return row


def require_admin(x_admin_secret: str | None) -> None:
    if not x_admin_secret or not secrets.compare_digest(x_admin_secret, ADMIN_SECRET):
        raise HTTPException(status_code=403, detail="Invalid admin secret")


# ─────────────────────────────────────────────────────────────────────────
# Request/response models
# ─────────────────────────────────────────────────────────────────────────


class GoogleAuthRequest(BaseModel):
    id_token: str


class RedeemKeyRequest(BaseModel):
    license_key: str


class GenerateKeysRequest(BaseModel):
    count: int = 1
    note: str | None = None


def user_status_payload(row: sqlite3.Row, session_token: str | None = None) -> dict:
    out = {
        "email": row["email"],
        "name": row["name"],
        "is_licensed": bool(row["is_licensed"]),
    }
    if session_token is not None:
        out["session_token"] = session_token
    return out


# ─────────────────────────────────────────────────────────────────────────
# Auth endpoints — called by the Flutter app
# ─────────────────────────────────────────────────────────────────────────


@app.post("/auth/google")
def auth_google(body: GoogleAuthRequest):
    try:
        claims = google_id_token.verify_oauth2_token(
            body.id_token, google_requests.Request(), GOOGLE_CLIENT_ID
        )
    except ValueError:
        raise HTTPException(status_code=401, detail="Invalid Google ID token")

    google_sub = claims["sub"]
    email = claims.get("email", "")
    name = claims.get("name", "")

    with db() as conn:
        row = conn.execute(
            "SELECT * FROM users WHERE google_sub = ?", (google_sub,)
        ).fetchone()
        if row is None:
            conn.execute(
                "INSERT INTO users (google_sub, email, name, created_at) "
                "VALUES (?, ?, ?, ?)",
                (google_sub, email, name, time.time()),
            )
            row = conn.execute(
                "SELECT * FROM users WHERE google_sub = ?", (google_sub,)
            ).fetchone()
        elif row["email"] != email or row["name"] != name:
            conn.execute(
                "UPDATE users SET email = ?, name = ? WHERE google_sub = ?",
                (email, name, google_sub),
            )
            row = conn.execute(
                "SELECT * FROM users WHERE google_sub = ?", (google_sub,)
            ).fetchone()

    token = issue_session_token(row)
    return user_status_payload(row, session_token=token)


@app.get("/auth/me")
def auth_me(authorization: str | None = Header(default=None)):
    row = require_session(authorization)
    return user_status_payload(row)


@app.post("/auth/redeem-key")
def redeem_key(body: RedeemKeyRequest, authorization: str | None = Header(default=None)):
    row = require_session(authorization)
    key = body.license_key.strip().upper()

    if row["is_licensed"]:
        return user_status_payload(row)

    with db() as conn:
        key_row = conn.execute(
            "SELECT * FROM license_keys WHERE key = ?", (key,)
        ).fetchone()
        if key_row is None:
            raise HTTPException(status_code=404, detail="License key not found")
        if key_row["is_used"]:
            raise HTTPException(status_code=409, detail="License key already used")

        now = time.time()
        conn.execute(
            "UPDATE license_keys SET is_used = 1, used_by_email = ?, redeemed_at = ? "
            "WHERE key = ?",
            (row["email"], now, key),
        )
        conn.execute(
            "UPDATE users SET is_licensed = 1, license_key = ?, licensed_at = ? "
            "WHERE google_sub = ?",
            (key, now, row["google_sub"]),
        )
        updated = conn.execute(
            "SELECT * FROM users WHERE google_sub = ?", (row["google_sub"],)
        ).fetchone()

    return user_status_payload(updated)


# ─────────────────────────────────────────────────────────────────────────
# Admin endpoints — you only, gated by AUTH_ADMIN_SECRET. Not exposed to
# the app. Use curl or the CLI helper at the bottom of this file.
# ─────────────────────────────────────────────────────────────────────────


def _generate_key() -> str:
    # Excludes 0/O/1/I/L to avoid keys that are ambiguous to type by hand.
    alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    groups = ["".join(secrets.choice(alphabet) for _ in range(4)) for _ in range(4)]
    return "-".join(groups)


@app.post("/admin/keys/generate")
def admin_generate_keys(
    body: GenerateKeysRequest, x_admin_secret: str | None = Header(default=None)
):
    require_admin(x_admin_secret)
    if body.count < 1 or body.count > 500:
        raise HTTPException(status_code=400, detail="count must be between 1 and 500")

    keys: list[str] = []
    with db() as conn:
        while len(keys) < body.count:
            candidate = _generate_key()
            try:
                conn.execute(
                    "INSERT INTO license_keys (key, note, created_at) VALUES (?, ?, ?)",
                    (candidate, body.note, time.time()),
                )
            except sqlite3.IntegrityError:
                continue  # collision — astronomically unlikely, just retry
            keys.append(candidate)

    return {"keys": keys}


@app.get("/admin/keys")
def admin_list_keys(x_admin_secret: str | None = Header(default=None)):
    require_admin(x_admin_secret)
    with db() as conn:
        rows = conn.execute(
            "SELECT key, is_used, used_by_email, note, created_at, redeemed_at "
            "FROM license_keys ORDER BY created_at DESC"
        ).fetchall()
    return {"keys": [dict(r) for r in rows]}


@app.get("/admin/users")
def admin_list_users(x_admin_secret: str | None = Header(default=None)):
    require_admin(x_admin_secret)
    with db() as conn:
        rows = conn.execute(
            "SELECT email, name, is_licensed, license_key, created_at, licensed_at "
            "FROM users ORDER BY created_at DESC"
        ).fetchall()
    return {"users": [dict(r) for r in rows]}


@app.get("/healthz")
def healthz():
    return {"ok": True}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", 8001)))
