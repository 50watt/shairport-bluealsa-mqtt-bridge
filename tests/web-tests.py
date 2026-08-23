#!/usr/bin/env python3

"""Exercise BluePort authentication and password changes."""

from __future__ import annotations

import hashlib
import json
import re
import sys
import tempfile
from pathlib import Path


PROJECT_DIRECTORY = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_DIRECTORY / "web"))

from bridge_web import create_app  # noqa: E402


def csrf_token(response_body: bytes) -> str:
    match = re.search(
        rb'name="csrf_token" type="hidden" value="([^"]+)"', response_body
    )
    assert match is not None
    return match.group(1).decode("ascii")


with tempfile.TemporaryDirectory() as temporary_directory:
    temporary_path = Path(temporary_directory)
    web_config_file = temporary_path / "web.json"
    password_file = temporary_path / "state" / "password.json"

    web_config_file.write_text(
        json.dumps(
            {
                "session_secret": "test-session-secret",
                "token_sha256": hashlib.sha256(b"test-token").hexdigest(),
            }
        ),
        encoding="utf-8",
    )

    application = create_app(
        {
            "TESTING": True,
            "BRIDGE_WEB_CONFIG": str(web_config_file),
            "BRIDGE_PASSWORD_FILE": str(password_file),
            "BRIDGE_STATUS_FILE": str(temporary_path / "missing-status.json"),
        }
    )
    application.logger.disabled = True
    client = application.test_client()

    login_page = client.get("/login")
    assert login_page.status_code == 200
    assert b"Welcome to BluePort" in login_page.data
    assert b"Setup code" in login_page.data

    login_response = client.post(
        "/login",
        data={
            "csrf_token": csrf_token(login_page.data),
            "credential": "test-token",
        },
    )
    assert login_response.status_code == 302
    assert login_response.headers["Location"].endswith("/settings/password")

    dashboard = client.get("/")
    assert dashboard.status_code == 302
    assert dashboard.headers["Location"].endswith("/settings/password")

    password_page = client.get("/settings/password")
    assert b"Setup code verified" in password_page.data
    password_response = client.post(
        "/settings/password",
        data={
            "csrf_token": csrf_token(password_page.data),
            "new_password": "correct horse battery staple",
            "confirm_password": "correct horse battery staple",
        },
    )
    assert password_response.status_code == 302
    assert "password_changed=1" in password_response.headers["Location"]
    assert password_file.is_file()
    assert password_file.stat().st_mode & 0o777 == 0o600

    login_page = client.get("/login")
    assert b"Setup code" not in login_page.data
    assert b"Password" in login_page.data

    old_credential = client.post(
        "/login",
        data={
            "csrf_token": csrf_token(login_page.data),
            "credential": "test-token",
        },
    )
    assert old_credential.status_code == 200

    login_page = client.get("/login")
    new_credential = client.post(
        "/login",
        data={
            "csrf_token": csrf_token(login_page.data),
            "credential": "correct horse battery staple",
        },
    )
    assert new_credential.status_code == 302

    dashboard = client.get("/")
    assert dashboard.status_code == 200
    assert b"BluePort" in dashboard.data
    assert b"Change password" in dashboard.data

print("Web authentication tests passed.")
