from __future__ import annotations

import json
import sqlite3
import threading
import time
from pathlib import Path
from typing import Any, Iterable

from .processor import ProcessedFlow

FLOW_COLUMNS = """
    timeinsert,local_ip,local_port,local_mac,fqdn,dest_ip,dest_port,dest_type,
    detected_protocol_name,detected_app_name,interface,internal,
    ndpi_risk_score,ndpi_risk_score_client,ndpi_risk_score_server,client_sni,
    category_application,category_domain,category_protocol,detected_application,
    detected_protocol,detection_guessed,dns_host_name,host_server_name,digest,json
"""


class FlowDatabase:
    def __init__(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        self.path = path
        self._lock = threading.RLock()
        self._connection = sqlite3.connect(path, check_same_thread=False, timeout=30)
        self._connection.row_factory = sqlite3.Row
        self._initialize()

    def _initialize(self) -> None:
        with self._lock, self._connection:
            self._connection.executescript("""
                PRAGMA journal_mode=WAL;
                PRAGMA synchronous=NORMAL;
                PRAGMA busy_timeout=30000;
                CREATE TABLE IF NOT EXISTS flow_raw (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timeinsert INTEGER NOT NULL,
                    local_ip TEXT NOT NULL DEFAULT '',
                    local_port INTEGER NOT NULL DEFAULT 0,
                    local_mac TEXT NOT NULL DEFAULT '',
                    fqdn TEXT NOT NULL DEFAULT '',
                    dest_ip TEXT NOT NULL DEFAULT '',
                    dest_port INTEGER NOT NULL DEFAULT 0,
                    dest_type TEXT NOT NULL DEFAULT 'remote',
                    detected_protocol_name TEXT NOT NULL DEFAULT '',
                    detected_app_name TEXT NOT NULL DEFAULT '',
                    interface TEXT NOT NULL DEFAULT '',
                    internal INTEGER NOT NULL DEFAULT 0,
                    ndpi_risk_score INTEGER NOT NULL DEFAULT 0,
                    ndpi_risk_score_client INTEGER NOT NULL DEFAULT 0,
                    ndpi_risk_score_server INTEGER NOT NULL DEFAULT 0,
                    client_sni TEXT NOT NULL DEFAULT '',
                    category_application INTEGER NOT NULL DEFAULT 0,
                    category_domain INTEGER NOT NULL DEFAULT 0,
                    category_protocol INTEGER NOT NULL DEFAULT 0,
                    detected_application INTEGER NOT NULL DEFAULT 0,
                    detected_protocol INTEGER NOT NULL DEFAULT 0,
                    detection_guessed INTEGER NOT NULL DEFAULT 0,
                    dns_host_name TEXT NOT NULL DEFAULT '',
                    host_server_name TEXT NOT NULL DEFAULT '',
                    digest TEXT NOT NULL DEFAULT '',
                    json TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_flow_raw_time
                    ON flow_raw(timeinsert DESC);
                CREATE INDEX IF NOT EXISTS idx_flow_raw_mac_time
                    ON flow_raw(local_mac, timeinsert DESC);
                CREATE INDEX IF NOT EXISTS idx_flow_raw_ip_time
                    ON flow_raw(local_ip, timeinsert DESC);
                CREATE INDEX IF NOT EXISTS idx_flow_raw_app_time
                    ON flow_raw(detected_app_name, timeinsert DESC);
                """)

    def insert_many(self, flows: Iterable[ProcessedFlow]) -> int:
        values = [flow.values for flow in flows]
        if not values:
            return 0
        placeholders = ",".join("?" for _ in range(26))
        with self._lock, self._connection:
            self._connection.executemany(
                f"INSERT INTO flow_raw ({FLOW_COLUMNS}) VALUES ({placeholders})",
                values,
            )
        return len(values)

    @staticmethod
    def _where(
        protocol: str | None,
        mac: str | None,
        search: str | None,
        hours: int | None,
    ) -> tuple[str, list[Any]]:
        conditions: list[str] = []
        parameters: list[Any] = []
        if hours is not None:
            conditions.append("timeinsert >= ?")
            parameters.append(int(time.time()) - (hours * 3600))
        normalized = (protocol or "").strip().upper()
        if normalized == "HTTP":
            conditions.append(
                "(UPPER(detected_protocol_name) = 'HTTP' OR dest_port = 80)"
            )
        elif normalized == "HTTPS":
            conditions.append(
                "(UPPER(detected_protocol_name) IN ('HTTP/S','HTTPS','TLS') OR dest_port = 443)"
            )
        elif normalized == "DNS":
            conditions.append(
                "(UPPER(detected_protocol_name) = 'DNS' OR dest_port = 53)"
            )
        if mac:
            conditions.append("LOWER(local_mac) = ?")
            parameters.append(mac.strip().lower())
        if search:
            value = f"%{search.strip().lower()}%"
            conditions.append(
                "(LOWER(fqdn) LIKE ? OR LOWER(client_sni) LIKE ? OR "
                "LOWER(dns_host_name) LIKE ? OR LOWER(host_server_name) LIKE ? OR "
                "LOWER(dest_ip) LIKE ? OR LOWER(detected_app_name) LIKE ?)"
            )
            parameters.extend([value] * 6)
        return (" WHERE " + " AND ".join(conditions) if conditions else "", parameters)

    def list_flows(
        self,
        *,
        limit: int,
        offset: int,
        protocol: str | None,
        mac: str | None,
        search: str | None,
        hours: int | None,
        normalized: bool = False,
    ) -> list[dict[str, Any]]:
        where, parameters = self._where(protocol, mac, search, hours)
        parameters.extend([limit, offset])
        with self._lock:
            columns = "*" if normalized else "json"
            rows = self._connection.execute(
                f"SELECT {columns} FROM flow_raw{where} ORDER BY id DESC LIMIT ? OFFSET ?",
                parameters,
            ).fetchall()
        if normalized:
            return [
                {key: row[key] for key in row.keys() if key != "json"} for row in rows
            ]
        result: list[dict[str, Any]] = []
        for row in rows:
            try:
                decoded = json.loads(row["json"])
                if isinstance(decoded, dict):
                    result.append(decoded)
            except json.JSONDecodeError:
                continue
        return result

    def count_flows(
        self,
        *,
        protocol: str | None,
        mac: str | None,
        search: str | None,
        hours: int | None,
    ) -> int:
        where, parameters = self._where(protocol, mac, search, hours)
        with self._lock:
            row = self._connection.execute(
                f"SELECT COUNT(*) AS count FROM flow_raw{where}", parameters
            ).fetchone()
        return int(row["count"] if row else 0)

    def dashboard_summary(self, hours: int = 24) -> dict[str, Any]:
        cutoff = int(time.time()) - (hours * 3600)
        with self._lock:
            totals = self._connection.execute(
                """
                SELECT COUNT(*) AS flow_count,
                       COUNT(DISTINCT NULLIF(local_mac, '')) AS device_count,
                       MAX(timeinsert) AS latest_flow
                FROM flow_raw
                WHERE timeinsert >= ?
                """,
                (cutoff,),
            ).fetchone()
            top_applications = self._connection.execute(
                """
                SELECT CASE
                         WHEN detected_app_name != '' THEN detected_app_name
                         WHEN detected_protocol_name != '' THEN detected_protocol_name
                         ELSE 'Unknown'
                       END AS name,
                       COUNT(*) AS count
                FROM flow_raw
                WHERE timeinsert >= ?
                GROUP BY name
                ORDER BY count DESC, name ASC
                LIMIT 8
                """,
                (cutoff,),
            ).fetchall()
            recent = self._connection.execute(
                """
                SELECT timeinsert, local_ip, local_mac, fqdn, dest_ip, dest_port,
                       detected_protocol_name, detected_app_name, ndpi_risk_score
                FROM flow_raw
                WHERE timeinsert >= ?
                ORDER BY id DESC
                LIMIT 40
                """,
                (cutoff,),
            ).fetchall()
        return {
            "hours": hours,
            "flow_count": int(totals["flow_count"] if totals else 0),
            "device_count": int(totals["device_count"] if totals else 0),
            "latest_flow": totals["latest_flow"] if totals else None,
            "database_bytes": self.path.stat().st_size if self.path.exists() else 0,
            "top_applications": [dict(row) for row in top_applications],
            "recent_flows": [dict(row) for row in recent],
        }

    def prune(self, retention_hours: int) -> int:
        cutoff = int(time.time()) - (retention_hours * 3600)
        with self._lock, self._connection:
            cursor = self._connection.execute(
                "DELETE FROM flow_raw WHERE timeinsert < ?", (cutoff,)
            )
        return max(0, cursor.rowcount)

    def close(self) -> None:
        with self._lock:
            self._connection.close()
