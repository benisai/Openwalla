from __future__ import annotations

import json
import time
from dataclasses import dataclass
from typing import Any


def _text(value: Any) -> str:
    return "" if value is None else str(value)


def _number(value: Any) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


@dataclass(frozen=True)
class ProcessedFlow:
    values: tuple[Any, ...]
    raw_json: str


class FlowProcessor:
    def __init__(
        self,
        excluded_protocols: frozenset[str],
        router_lan_ip: str = "",
    ) -> None:
        self.excluded_protocols = excluded_protocols
        self.router_lan_ip = router_lan_ip

    def process(self, line: str) -> ProcessedFlow | None:
        try:
            payload = json.loads(line)
        except (json.JSONDecodeError, TypeError):
            return None
        if not isinstance(payload, dict) or payload.get("type") != "flow":
            return None
        flow = payload.get("flow")
        if not isinstance(flow, dict):
            return None

        protocol = _text(flow.get("detected_protocol_name")).strip()
        if protocol.upper() in self.excluded_protocols:
            return None

        local_ip = _text(flow.get("local_ip")).strip()
        local_port = _number(flow.get("local_port"))
        destination_ip = _text(flow.get("other_ip")).strip()
        if self.router_lan_ip:
            if destination_ip == self.router_lan_ip:
                return None
            if local_ip == self.router_lan_ip and local_port == 80:
                return None

        ssl = flow.get("ssl") if isinstance(flow.get("ssl"), dict) else {}
        risks = flow.get("risks") if isinstance(flow.get("risks"), dict) else {}
        category = (
            flow.get("category") if isinstance(flow.get("category"), dict) else {}
        )
        client_sni = _text(ssl.get("client_sni")).strip()
        fqdn = next(
            (
                value
                for value in (
                    _text(flow.get("fqdn")).strip(),
                    client_sni,
                    _text(flow.get("host_server_name")).strip(),
                    _text(flow.get("dns_host_name")).strip(),
                    destination_ip,
                )
                if value
            ),
            "",
        )
        normalized = json.dumps(payload, separators=(",", ":"), ensure_ascii=True)
        return ProcessedFlow(
            values=(
                int(time.time()),
                local_ip,
                local_port,
                _text(flow.get("local_mac")).strip().lower(),
                fqdn,
                destination_ip,
                _number(flow.get("other_port")),
                "remote",
                protocol,
                _text(
                    flow.get("detected_application_name")
                    or flow.get("detected_app_name")
                ).strip(),
                _text(payload.get("interface") or flow.get("interface")).strip(),
                1 if payload.get("internal") else 0,
                _number(risks.get("ndpi_risk_score")),
                _number(risks.get("ndpi_risk_score_client")),
                _number(risks.get("ndpi_risk_score_server")),
                client_sni,
                _number(category.get("application")),
                _number(category.get("domain")),
                _number(category.get("protocol")),
                _number(flow.get("detected_application")),
                _number(flow.get("detected_protocol")),
                1 if flow.get("detection_guessed") else 0,
                _text(flow.get("dns_host_name")).strip(),
                _text(flow.get("host_server_name")).strip(),
                _text(flow.get("digest")).strip(),
                normalized,
            ),
            raw_json=normalized,
        )
