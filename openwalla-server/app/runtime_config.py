"""Validated, volume-backed settings. Environment values bootstrap a new server."""

import json
import os
import re
import secrets
from ipaddress import ip_address
from dataclasses import replace
from pathlib import Path

from pydantic import BaseModel, ConfigDict, Field, field_validator

from .auth import create_password_hash
from .config import Settings


class RuntimeOptions(BaseModel):
    model_config = ConfigDict(extra="forbid")

    netify_host: str = Field(min_length=1, max_length=253)
    netify_port: int = Field(ge=1, le=65535)
    router_lan_ip: str = Field(max_length=253)
    retention_hours: int = Field(ge=1, le=8760)
    excluded_protocols: list[str] = Field(max_length=100)
    reconnect_seconds: int = Field(ge=1, le=300)
    tunnel_host: str = Field(min_length=1, max_length=253)
    tunnel_http_port: int = Field(ge=1, le=65535)
    tunnel_ssh_port: int = Field(ge=1, le=65535)
    ui_username: str = Field(
        min_length=1, max_length=128, pattern=r"^[A-Za-z0-9_.@-]+$"
    )
    login_enabled: bool
    session_hours: int = Field(ge=1, le=720)
    auth_max_failures: int = Field(ge=2, le=100)
    auth_window_seconds: int = Field(ge=30, le=86400)
    auth_ban_seconds: int = Field(ge=30, le=604800)
    ui_password: str = Field(default="", max_length=1024, exclude=True)
    api_token: str = Field(
        default="", max_length=1024, pattern=r"^[\x21-\x7e]*$", exclude=True
    )
    clear_api_token: bool = Field(default=False, exclude=True)

    @field_validator("netify_host", "router_lan_ip", "tunnel_host")
    @classmethod
    def validate_host(cls, value: str) -> str:
        if not value:
            return value
        try:
            ip_address(value)
        except ValueError:
            if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", value):
                raise ValueError(
                    "Use a hostname or IP address, without a URL or spaces"
                )
        return value

    @field_validator("excluded_protocols")
    @classmethod
    def validate_protocols(cls, values: list[str]) -> list[str]:
        if any(not value.strip() or len(value) > 64 for value in values):
            raise ValueError("Protocol names must contain 1 to 64 characters")
        return sorted({value.strip().upper() for value in values})


def public_settings(settings: Settings) -> dict:
    values = {
        name: getattr(settings, name)
        for name in RuntimeOptions.model_fields
        if hasattr(settings, name)
    }
    values["excluded_protocols"] = sorted(settings.excluded_protocols)
    values["login_enabled"] = bool(settings.ui_password or settings.ui_password_hash)
    result = RuntimeOptions(**values).model_dump()
    result["api_token_configured"] = bool(settings.api_token)
    return result


class RuntimeConfig:
    def __init__(self, defaults: Settings):
        self.defaults = defaults
        self.path = defaults.database_path.parent / "openwalla-settings.json"

    def load(self) -> Settings:
        if not self.path.exists():
            return self.defaults
        payload = json.loads(self.path.read_text(encoding="utf-8"))
        options = RuntimeOptions.model_validate(payload["options"])
        values = options.model_dump(exclude={"login_enabled"})
        values["excluded_protocols"] = frozenset(options.excluded_protocols)
        values.update(payload["credentials"])
        return replace(self.defaults, **values)

    def prepare(self, current: Settings, options: RuntimeOptions) -> Settings:
        values = options.model_dump(exclude={"login_enabled"})
        values["excluded_protocols"] = frozenset(options.excluded_protocols)
        if not options.login_enabled:
            values.update(ui_password="", ui_password_hash="")
        elif options.ui_password:
            values.update(
                ui_password="",
                ui_password_hash=create_password_hash(options.ui_password),
            )
        elif not (current.ui_password or current.ui_password_hash):
            raise ValueError("Set a password before enabling dashboard login")
        if options.clear_api_token:
            values["api_token"] = ""
        elif options.api_token:
            values["api_token"] = options.api_token
        if (
            options.ui_password
            or options.ui_username != current.ui_username
            or (
                options.login_enabled
                != bool(current.ui_password or current.ui_password_hash)
            )
        ):
            values["session_secret"] = secrets.token_urlsafe(32)
        return replace(current, **values)

    def save(self, settings: Settings) -> None:
        options = public_settings(settings)
        options.pop("api_token_configured")
        # Never persist the dashboard password in plain text, including env bootstrap.
        password_hash = settings.ui_password_hash
        if settings.ui_password and not password_hash:
            password_hash = create_password_hash(settings.ui_password)
        payload = {
            "version": 1,
            "options": options,
            "credentials": {
                "ui_password": "",
                "ui_password_hash": password_hash,
                "api_token": settings.api_token,
                "session_secret": settings.session_secret or secrets.token_urlsafe(32),
            },
        }
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(".tmp")
        try:
            with os.fdopen(
                os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w"
            ) as handle:
                os.fchmod(handle.fileno(), 0o600)
                json.dump(payload, handle, indent=2)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, self.path)
        finally:
            temporary.unlink(missing_ok=True)
