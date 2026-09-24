"""
CLI helper to mint license keys against a running auth_server.py instance.

Usage:
    python generate_license_keys.py --count 5 --note "batch 1"
    python generate_license_keys.py --count 1 --url https://your-app.onrender.com

Reads AUTH_SERVER_URL and AUTH_ADMIN_SECRET from the environment / .env if
--url / --admin-secret are not passed explicitly.
"""

from __future__ import annotations

import argparse
import os

import httpx
from dotenv import load_dotenv

load_dotenv()


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate license keys.")
    parser.add_argument("--count", type=int, default=1)
    parser.add_argument("--note", type=str, default=None)
    parser.add_argument(
        "--url",
        type=str,
        default=os.environ.get("AUTH_SERVER_URL", "http://127.0.0.1:8001"),
        help="Base URL of the deployed auth_server.py (no trailing slash).",
    )
    parser.add_argument(
        "--admin-secret",
        type=str,
        default=os.environ.get("AUTH_ADMIN_SECRET"),
    )
    args = parser.parse_args()

    if not args.admin_secret:
        raise SystemExit(
            "No admin secret. Pass --admin-secret or set AUTH_ADMIN_SECRET in .env"
        )

    resp = httpx.post(
        f"{args.url}/admin/keys/generate",
        json={"count": args.count, "note": args.note},
        headers={"X-Admin-Secret": args.admin_secret},
        timeout=15.0,
    )
    resp.raise_for_status()
    keys = resp.json()["keys"]

    print(f"Generated {len(keys)} key(s):\n")
    for key in keys:
        print(f"  {key}")


if __name__ == "__main__":
    main()
