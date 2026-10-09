from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _integer(name: str, default: int, minimum: int, maximum: int) -> int:
    try:
        value = int(os.getenv(name, str(default)))
    except ValueError:
        value = default
    return max(minimum, min(maximum, value))


@dataclass(frozen=True)
class Settings:
    netify_host: str
    netify_port: int
    database_path: Path
    retention_hours: int
    api_token: str
    excluded_protocols: frozenset[str]
    router_lan_ip: str
    reconnect_seconds: int

    @classmethod
    def from_environment(cls) -> "Settings":
        protocols = os.getenv(
            "OPENWALLA_EXCLUDE_PROTOCOLS", "MDNS,DNS,QUIC,DHCPv6,ICMP"
        )
        return cls(
            netify_host=os.getenv("OPENWALLA_NETIFY_HOST", "192.168.1.1").strip(),
            netify_port=_integer("OPENWALLA_NETIFY_PORT", 7150, 1, 65535),
            database_path=Path(
                os.getenv("OPENWALLA_DATABASE_PATH", "/data/openwalla-netify.sqlite")
            ),
            retention_hours=_integer("OPENWALLA_RETENTION_HOURS", 24, 1, 8760),
            api_token=os.getenv("OPENWALLA_API_TOKEN", "").strip(),
            excluded_protocols=frozenset(
                value.strip().upper() for value in protocols.split(",") if value.strip()
            ),
            router_lan_ip=os.getenv("OPENWALLA_ROUTER_LAN_IP", "").strip(),
            reconnect_seconds=_integer("OPENWALLA_RECONNECT_SECONDS", 5, 1, 300),
        )
