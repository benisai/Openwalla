from __future__ import annotations

import base64
import getpass
import hashlib
import hmac
import json
import logging
import os
import secrets
import threading
import time
from collections import defaultdict
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any

from .config import Settings

if TYPE_CHECKING:
    from fastapi import Request


SESSION_COOKIE = "openwalla_session"
LOGGER = logging.getLogger("openwalla.auth")


def create_password_hash(password: str) -> str:
    salt = secrets.token_bytes(16)
    cost, block_size, parallelism = 16384, 8, 1
    digest = hashlib.scrypt(
        password.encode(), salt=salt, n=cost, r=block_size, p=parallelism, dklen=32
    )
    return ":".join(
        (
            "scrypt",
            str(cost),
            str(block_size),
            str(parallelism),
            base64.urlsafe_b64encode(salt).decode().rstrip("="),
            base64.urlsafe_b64encode(digest).decode().rstrip("="),
        )
    )


def _decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


@dataclass(frozen=True)
class LoginResult:
    accepted: bool
    banned_seconds: int = 0


class AuthenticationManager:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        secret = settings.session_secret or settings.api_token or settings.ui_password
        self._secret = hashlib.sha256(
            (secret or secrets.token_urlsafe(32)).encode()
        ).digest()
        self._failures: dict[str, list[float]] = defaultdict(list)
        self._bans: dict[str, float] = {}
        self._lock = threading.RLock()
        self._load_bans()

    @property
    def enabled(self) -> bool:
        return bool(self.settings.ui_password or self.settings.ui_password_hash)

    def reconfigure(self, settings: Settings) -> None:
        with self._lock:
            self.settings = settings
            secret = (
                settings.session_secret or settings.api_token or settings.ui_password
            )
            self._secret = hashlib.sha256(
                (secret or secrets.token_urlsafe(32)).encode()
            ).digest()

    def client_ip(self, request: Any) -> str:
        if self.settings.auth_trust_proxy:
            forwarded = request.headers.get("x-forwarded-for", "")
            if forwarded:
                return forwarded.split(",", 1)[0].strip()
        return request.client.host if request.client else "unknown"

    def _remaining_ban(self, address: str, now: float) -> int:
        expires = self._bans.get(address, 0)
        if expires <= now:
            if self._bans.pop(address, None) is not None:
                self._persist_bans()
            return 0
        return max(1, int(expires - now))

    def _load_bans(self) -> None:
        path = self.settings.auth_ban_path
        if not path.exists():
            return
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            stored = payload.get("bans", {}) if isinstance(payload, dict) else {}
            now = time.time()
            if isinstance(stored, dict):
                self._bans = {
                    str(address): float(expires)
                    for address, expires in stored.items()
                    if isinstance(address, str)
                    and isinstance(expires, (int, float))
                    and float(expires) > now
                }
            if len(self._bans) != len(stored):
                self._persist_bans()
        except (OSError, ValueError, TypeError, json.JSONDecodeError) as error:
            LOGGER.warning("Unable to load persisted authentication bans: %s", error)

    def _persist_bans(self) -> None:
        path = self.settings.auth_ban_path
        temporary = path.with_name(f"{path.name}.tmp")
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            with temporary.open("w", encoding="utf-8") as handle:
                json.dump(
                    {"version": 1, "bans": self._bans}, handle, separators=(",", ":")
                )
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(temporary, 0o600)
            os.replace(temporary, path)
        except OSError as error:
            LOGGER.error("Unable to persist authentication bans: %s", error)
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass

    def login(self, address: str, username: str, password: str) -> LoginResult:
        now = time.time()
        with self._lock:
            remaining = self._remaining_ban(address, now)
            if remaining:
                return LoginResult(False, remaining)

        username_matches = hmac.compare_digest(username, self.settings.ui_username)
        password_matches = self._password_matches(password)
        accepted = username_matches and password_matches
        with self._lock:
            if accepted:
                self._failures.pop(address, None)
                return LoginResult(True)

            cutoff = now - self.settings.auth_window_seconds
            failures = [stamp for stamp in self._failures[address] if stamp >= cutoff]
            failures.append(now)
            self._failures[address] = failures
            if len(failures) >= self.settings.auth_max_failures:
                self._bans[address] = now + self.settings.auth_ban_seconds
                self._failures.pop(address, None)
                self._persist_bans()
                return LoginResult(False, self.settings.auth_ban_seconds)
        return LoginResult(False)

    def _password_matches(self, password: str) -> bool:
        encoded = self.settings.ui_password_hash
        if encoded:
            try:
                algorithm, cost, block_size, parallelism, salt, expected = (
                    encoded.split(":", 5)
                )
                if algorithm != "scrypt":
                    return False
                actual = hashlib.scrypt(
                    password.encode(),
                    salt=_decode(salt),
                    n=int(cost),
                    r=int(block_size),
                    p=int(parallelism),
                    dklen=len(_decode(expected)),
                )
                return hmac.compare_digest(actual, _decode(expected))
            except (ValueError, TypeError):
                return False
        return hmac.compare_digest(password, self.settings.ui_password)

    def create_session(self) -> str:
        expires = int(time.time()) + (self.settings.session_hours * 3600)
        payload = f"{self.settings.ui_username}|{expires}".encode()
        signature = hmac.new(self._secret, payload, hashlib.sha256).digest()
        return ".".join(
            (
                base64.urlsafe_b64encode(payload).decode().rstrip("="),
                base64.urlsafe_b64encode(signature).decode().rstrip("="),
            )
        )

    def valid_session(self, token: str | None) -> bool:
        if not self.enabled:
            return True
        if not token:
            return False
        try:
            encoded_payload, encoded_signature = token.split(".", 1)
            payload = _decode(encoded_payload)
            signature = _decode(encoded_signature)
            expected = hmac.new(self._secret, payload, hashlib.sha256).digest()
            username, expires = payload.decode().rsplit("|", 1)
            return (
                hmac.compare_digest(signature, expected)
                and hmac.compare_digest(username, self.settings.ui_username)
                and int(expires) >= int(time.time())
            )
        except (ValueError, UnicodeDecodeError):
            return False

    def status(self) -> dict[str, object]:
        now = time.time()
        with self._lock:
            banned = []
            for address in list(self._bans):
                remaining = self._remaining_ban(address, now)
                if remaining:
                    banned.append({"address": address, "remaining_seconds": remaining})
        return {
            "enabled": self.enabled,
            "username": self.settings.ui_username,
            "max_failures": self.settings.auth_max_failures,
            "window_seconds": self.settings.auth_window_seconds,
            "ban_seconds": self.settings.auth_ban_seconds,
            "session_hours": self.settings.session_hours,
            "banned": banned,
        }


if __name__ == "__main__":
    password = getpass.getpass("New Openwalla UI password: ")
    confirmation = getpass.getpass("Confirm password: ")
    if not password or not hmac.compare_digest(password, confirmation):
        raise SystemExit("Passwords did not match or were empty.")
    print(create_password_hash(password))
