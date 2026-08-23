"""BluePort web dashboard for Shairport Sync and BlueALSA."""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import secrets
import tempfile
import threading
from datetime import timedelta
from functools import wraps
from pathlib import Path
from typing import Any, Callable, TypeVar

from flask import Flask, Response, jsonify, redirect, render_template, request, session, url_for
from werkzeug.security import check_password_hash, generate_password_hash


ViewFunction = TypeVar("ViewFunction", bound=Callable[..., Any])
DEFAULT_STATUS_FILE = "/run/shairport-bluealsa-mqtt-bridge/status.json"
DEFAULT_WEB_CONFIG = "/etc/shairport-bluealsa-mqtt-bridge/web.json"
DEFAULT_PASSWORD_FILE = "/var/lib/shairport-bluealsa-mqtt-bridge/password.json"
MINIMUM_PASSWORD_LENGTH = 8


def _load_json(path: str) -> dict[str, Any]:
    with Path(path).open("r", encoding="utf-8") as handle:
        value = json.load(handle)

    if not isinstance(value, dict):
        raise ValueError(f"Expected a JSON object in {path}")

    return value


def _load_status(app: Flask) -> dict[str, Any]:
    try:
        return _load_json(app.config["BRIDGE_STATUS_FILE"])
    except (FileNotFoundError, PermissionError, json.JSONDecodeError, ValueError) as error:
        app.logger.warning("Unable to read bridge status: %s", error)
        return {
            "schema_version": 1,
            "bridge_version": "unknown",
            "generated_at": None,
            "overall": "unavailable",
            "configuration": {
                "state": "unavailable",
                "message": "No status snapshot is available yet.",
            },
            "audio": {
                "state": "unavailable",
                "speaker_name": "Unavailable",
                "speaker_mac": None,
                "connected": False,
                "profile": "none",
                "running": False,
                "volume": None,
                "muted": None,
                "delay_ms": None,
                "sequence": None,
            },
            "network": {
                "hostname": "unavailable",
                "connectivity": None,
                "interface": None,
                "address": None,
            },
            "services": {},
        }


def _password_hash(app: Flask) -> str | None:
    try:
        password_config = _load_json(app.config["BRIDGE_PASSWORD_FILE"])
    except (FileNotFoundError, PermissionError, json.JSONDecodeError, ValueError):
        return None

    value = password_config.get("password_hash")
    return str(value) if value else None


def _verify_credential(app: Flask, supplied_credential: str) -> bool:
    password_hash = _password_hash(app)

    if password_hash is not None:
        return check_password_hash(password_hash, supplied_credential)

    supplied_hash = hashlib.sha256(supplied_credential.encode("utf-8")).hexdigest()
    expected_hash = str(app.config["BRIDGE_SETUP_TOKEN_SHA256"])
    return hmac.compare_digest(supplied_hash, expected_hash)


def _store_password(app: Flask, password: str) -> None:
    password_file = Path(app.config["BRIDGE_PASSWORD_FILE"])
    password_file.parent.mkdir(mode=0o750, parents=True, exist_ok=True)
    password_config = {
        "password_hash": generate_password_hash(password),
    }

    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=password_file.parent,
        prefix=f".{password_file.name}.",
        delete=False,
    ) as temporary_file:
        temporary_path = Path(temporary_file.name)
        json.dump(password_config, temporary_file, indent=2)
        temporary_file.write("\n")

    try:
        temporary_path.chmod(0o600)
        temporary_path.replace(password_file)
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise


def create_app(test_config: dict[str, Any] | None = None) -> Flask:
    """Create the dashboard application."""

    app = Flask(__name__, instance_relative_config=False)
    app.config.update(
        BRIDGE_STATUS_FILE=os.environ.get("BRIDGE_STATUS_FILE", DEFAULT_STATUS_FILE),
        BRIDGE_WEB_CONFIG=os.environ.get("BRIDGE_WEB_CONFIG", DEFAULT_WEB_CONFIG),
        BRIDGE_PASSWORD_FILE=os.environ.get(
            "BRIDGE_PASSWORD_FILE", DEFAULT_PASSWORD_FILE
        ),
        PERMANENT_SESSION_LIFETIME=timedelta(hours=12),
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Strict",
    )

    if test_config:
        app.config.update(test_config)

    try:
        web_config = _load_json(app.config["BRIDGE_WEB_CONFIG"])
    except (FileNotFoundError, PermissionError, json.JSONDecodeError, ValueError) as error:
        if not app.config.get("TESTING"):
            raise RuntimeError("The web configuration is unavailable or invalid.") from error
        web_config = {
            "session_secret": "test-session-secret",
            "token_sha256": hashlib.sha256(b"test-token").hexdigest(),
        }

    app.secret_key = str(web_config["session_secret"])
    app.config["BRIDGE_SETUP_TOKEN_SHA256"] = str(web_config["token_sha256"])
    password_write_lock = threading.Lock()

    def csrf_token() -> str:
        value = session.get("csrf_token")

        if not isinstance(value, str):
            value = secrets.token_urlsafe(32)
            session["csrf_token"] = value

        return value

    def csrf_is_valid() -> bool:
        expected = session.get("csrf_token", "")
        supplied = request.form.get("csrf_token", "")
        return bool(expected) and hmac.compare_digest(str(expected), supplied)

    app.jinja_env.globals["csrf_token"] = csrf_token

    def login_required(view: ViewFunction) -> ViewFunction:
        @wraps(view)
        def wrapped(*args: Any, **kwargs: Any) -> Any:
            if not session.get("authenticated"):
                return redirect(url_for("login", next=request.path))
            return view(*args, **kwargs)

        return wrapped  # type: ignore[return-value]

    def setup_complete_required(view: ViewFunction) -> ViewFunction:
        @wraps(view)
        def wrapped(*args: Any, **kwargs: Any) -> Any:
            if not session.get("authenticated"):
                return redirect(url_for("login", next=request.path))
            if session.get("must_change_password"):
                return redirect(url_for("change_password"))
            return view(*args, **kwargs)

        return wrapped  # type: ignore[return-value]

    @app.after_request
    def add_security_headers(response: Response) -> Response:
        response.headers["Cache-Control"] = "no-store"
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; style-src 'self'; script-src 'self'; "
            "img-src 'self' data:; frame-ancestors 'none'; form-action 'self'"
        )
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        return response

    @app.route("/login", methods=["GET", "POST"])
    def login() -> str | Response:
        error = None
        password_changed = request.args.get("password_changed") == "1"
        auth_mode = "password" if _password_hash(app) is not None else "setup-code"

        if request.method == "POST":
            supplied_credential = request.form.get("credential", "")

            if not csrf_is_valid():
                error = "The form expired. Please try again."
            elif _verify_credential(app, supplied_credential):
                session.clear()
                session["authenticated"] = True
                session.permanent = True

                if auth_mode == "setup-code":
                    session["must_change_password"] = True
                    return redirect(url_for("change_password"))

                return redirect(url_for("dashboard"))

            else:
                error = (
                    "The password is not valid."
                    if auth_mode == "password"
                    else "The setup code is not valid."
                )

        return render_template(
            "login.html",
            error=error,
            password_changed=password_changed,
            auth_mode=auth_mode,
        )

    @app.post("/logout")
    @login_required
    def logout() -> Response:
        if not csrf_is_valid():
            return Response("Invalid CSRF token", status=400)

        session.clear()
        return redirect(url_for("login"))

    @app.route("/settings/password", methods=["GET", "POST"])
    @login_required
    def change_password() -> str | Response:
        error = None
        initial_setup = bool(session.get("must_change_password"))

        if request.method == "POST":
            current_password = request.form.get("current_password", "")
            new_password = request.form.get("new_password", "")
            confirm_password = request.form.get("confirm_password", "")

            if not csrf_is_valid():
                error = "The form expired. Please try again."
            elif not initial_setup and not _verify_credential(app, current_password):
                error = "The current password or setup code is not valid."
            elif len(new_password) < MINIMUM_PASSWORD_LENGTH:
                error = (
                    f"The new password must contain at least "
                    f"{MINIMUM_PASSWORD_LENGTH} characters."
                )
            elif new_password != confirm_password:
                error = "The new passwords do not match."
            elif _verify_credential(app, new_password):
                error = "Choose a password that differs from the current credential."
            else:
                try:
                    with password_write_lock:
                        _store_password(app, new_password)
                except OSError:
                    app.logger.exception("Unable to store the dashboard password")
                    error = "The password could not be stored. Check the service log."
                else:
                    session.clear()
                    return redirect(url_for("login", password_changed="1"))

        return render_template(
            "change_password.html", error=error, initial_setup=initial_setup
        )

    @app.get("/")
    @setup_complete_required
    def dashboard() -> str:
        return render_template("dashboard.html", status=_load_status(app))

    @app.get("/api/status")
    @setup_complete_required
    def api_status() -> Response:
        return jsonify(_load_status(app))

    @app.get("/healthz")
    def healthz() -> Response:
        return jsonify({"status": "ok"})

    return app
