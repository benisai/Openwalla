from __future__ import annotations

import logging
import hmac
import socket
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Annotated
from urllib.parse import parse_qs

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.responses import FileResponse, RedirectResponse

from .auth import AuthenticationManager, SESSION_COOKIE
from .collector import NetifyCollector
from .config import Settings
from .database import FlowDatabase


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
settings = Settings.from_environment()
database = FlowDatabase(settings.database_path)
collector = NetifyCollector(settings, database)
authentication = AuthenticationManager(settings)
STATIC_DIRECTORY = Path(__file__).parent / "static"


def authorize(
    request: Request, authorization: Annotated[str | None, Header()] = None
) -> None:
    if settings.api_token and hmac.compare_digest(
        authorization or "", f"Bearer {settings.api_token}"
    ):
        return
    if authentication.enabled and authentication.valid_session(
        request.cookies.get(SESSION_COOKIE)
    ):
        return
    if not settings.api_token and not authentication.enabled:
        return
    raise HTTPException(status_code=401, detail="Authentication required")
@asynccontextmanager
async def lifespan(_: FastAPI):
    collector.start()
    try:
        yield
    finally:
        collector.stop()
        database.close()


app = FastAPI(title="Openwalla Server", version="1.0.0", lifespan=lifespan)


def _port_reachable(host: str, port: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=0.4):
            return True
    except (OSError, TimeoutError):
        return False


def _tunnel_status() -> dict[str, object]:
    luci_available = _port_reachable(settings.tunnel_host, settings.tunnel_http_port)
    ssh_available = _port_reachable(settings.tunnel_host, settings.tunnel_ssh_port)
    return {
        "connected": luci_available or ssh_available,
        "host": settings.tunnel_host,
        "luci": {
            "available": luci_available,
            "port": settings.tunnel_http_port,
        },
        "ssh": {
            "available": ssh_available,
            "port": settings.tunnel_ssh_port,
        },
    }


@app.get("/", include_in_schema=False, response_model=None)
def dashboard_page(request: Request) -> FileResponse | RedirectResponse:
    if authentication.enabled and not authentication.valid_session(
        request.cookies.get(SESSION_COOKIE)
    ):
        return RedirectResponse("/login", status_code=303)
    return FileResponse(STATIC_DIRECTORY / "dashboard.html")


@app.get("/login", include_in_schema=False, response_model=None)
def login_page(request: Request) -> FileResponse | RedirectResponse:
    if not authentication.enabled or authentication.valid_session(
        request.cookies.get(SESSION_COOKIE)
    ):
        return RedirectResponse("/", status_code=303)
    return FileResponse(STATIC_DIRECTORY / "login.html")


@app.post("/login", include_in_schema=False)
async def login(request: Request) -> RedirectResponse:
    values = parse_qs((await request.body()).decode("utf-8", errors="replace"))
    username = values.get("username", [""])[0]
    password = values.get("password", [""])[0]
    result = authentication.login(
        authentication.client_ip(request), username, password
    )
    if not result.accepted:
        suffix = f"?banned={result.banned_seconds}" if result.banned_seconds else "?error=1"
        return RedirectResponse(f"/login{suffix}", status_code=303)
    response = RedirectResponse("/", status_code=303)
    response.set_cookie(
        SESSION_COOKIE,
        authentication.create_session(),
        max_age=settings.session_hours * 3600,
        httponly=True,
        secure=settings.auth_secure_cookie,
        samesite="strict",
        path="/",
    )
    return response


@app.post("/logout", include_in_schema=False)
def logout() -> RedirectResponse:
    response = RedirectResponse("/login", status_code=303)
    response.delete_cookie(SESSION_COOKIE, path="/")
    return response


@app.get("/api/v1/health")
def health() -> dict[str, object]:
    return {"ok": True, "collector_connected": collector.status.connected}


@app.get("/api/v1/status", dependencies=[Depends(authorize)])
def status() -> dict[str, object]:
    state = collector.status
    return {
        "collector_connected": state.connected,
        "netify_host": settings.netify_host,
        "netify_port": settings.netify_port,
        "received": state.received,
        "stored": state.stored,
        "discarded": state.discarded,
        "last_event_at": state.last_event_at,
        "last_error": state.last_error,
        "retention_hours": settings.retention_hours,
    }


@app.get("/api/v1/tunnel/status", dependencies=[Depends(authorize)])
def tunnel_status() -> dict[str, object]:
    return _tunnel_status()


@app.get("/api/v1/dashboard", dependencies=[Depends(authorize)])
def dashboard(hours: Annotated[int, Query(ge=1, le=168)] = 24) -> dict[str, object]:
    state = collector.status
    return {
        "collector": {
            "connected": state.connected,
            "host": settings.netify_host,
            "port": settings.netify_port,
            "received": state.received,
            "stored": state.stored,
            "discarded": state.discarded,
            "last_event_at": state.last_event_at,
            "last_error": state.last_error,
        },
        "tunnel": _tunnel_status(),
        "flows": database.dashboard_summary(hours),
        "retention_hours": settings.retention_hours,
        "security": authentication.status(),
    }


@app.get("/api/v1/flows", dependencies=[Depends(authorize)])
def flows(
    limit: Annotated[int, Query(ge=1, le=250)] = 250,
    offset: Annotated[int, Query(ge=0)] = 0,
    protocol: str | None = None,
    mac: str | None = None,
    search: str | None = None,
    hours: Annotated[int | None, Query(ge=1, le=168)] = None,
) -> dict[str, object]:
    return {
        "items": database.list_flows(
            limit=limit,
            offset=offset,
            protocol=protocol,
            mac=mac,
            search=search,
            hours=hours,
        )
    }


@app.get("/api/v1/flows/count", dependencies=[Depends(authorize)])
def flow_count(
    protocol: str | None = None,
    mac: str | None = None,
    search: str | None = None,
    hours: Annotated[int | None, Query(ge=1, le=168)] = None,
) -> dict[str, int]:
    return {
        "count": database.count_flows(
            protocol=protocol, mac=mac, search=search, hours=hours
        )
    }


@app.post("/api/v1/maintenance/prune", dependencies=[Depends(authorize)])
def prune() -> dict[str, int]:
    return {"removed": database.prune(settings.retention_hours)}
