from __future__ import annotations

import logging
import queue
import socket
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timedelta

from .config import Settings
from .database import FlowDatabase
from .processor import FlowProcessor, ProcessedFlow


LOGGER = logging.getLogger("openwalla.collector")


@dataclass
class CollectorStatus:
    connected: bool = False
    received: int = 0
    stored: int = 0
    discarded: int = 0
    last_event_at: int | None = None
    last_error: str = ""


class NetifyCollector:
    def __init__(self, settings: Settings, database: FlowDatabase) -> None:
        self.settings = settings
        self.database = database
        self.processor = FlowProcessor(
            settings.excluded_protocols, settings.router_lan_ip
        )
        self.status = CollectorStatus()
        self._queue: queue.Queue[ProcessedFlow] = queue.Queue(maxsize=10000)
        self._stop = threading.Event()
        self._threads: list[threading.Thread] = []
        self._connection: socket.socket | None = None

    def start(self) -> None:
        self._threads = [
            threading.Thread(target=self._collect_loop, name="netify-reader", daemon=True),
            threading.Thread(target=self._write_loop, name="sqlite-writer", daemon=True),
            threading.Thread(target=self._prune_loop, name="retention", daemon=True),
        ]
        for thread in self._threads:
            thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._connection is not None:
            try:
                self._connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self._connection.close()
        for thread in self._threads:
            thread.join(timeout=3)

    def _collect_loop(self) -> None:
        while not self._stop.is_set():
            try:
                LOGGER.info(
                    "Connecting to Netify at %s:%s",
                    self.settings.netify_host,
                    self.settings.netify_port,
                )
                with socket.create_connection(
                    (self.settings.netify_host, self.settings.netify_port), timeout=15
                ) as connection:
                    self._connection = connection
                    connection.settimeout(None)
                    self.status.connected = True
                    self.status.last_error = ""
                    with connection.makefile("r", encoding="utf-8", errors="replace") as stream:
                        while not self._stop.is_set():
                            line = stream.readline()
                            if not line:
                                break
                            self.status.received += 1
                            flow = self.processor.process(line)
                            if flow is None:
                                self.status.discarded += 1
                                continue
                            try:
                                self._queue.put(flow, timeout=2)
                            except queue.Full:
                                self.status.discarded += 1
            except (OSError, TimeoutError) as error:
                self.status.last_error = str(error)
                LOGGER.warning("Netify connection failed: %s", error)
            finally:
                self.status.connected = False
                self._connection = None
            self._stop.wait(self.settings.reconnect_seconds)

    def _write_loop(self) -> None:
        while not self._stop.is_set():
            batch: list[ProcessedFlow] = []
            try:
                batch.append(self._queue.get(timeout=1))
            except queue.Empty:
                continue
            deadline = time.monotonic() + 0.25
            while len(batch) < 250 and time.monotonic() < deadline:
                try:
                    batch.append(self._queue.get_nowait())
                except queue.Empty:
                    break
            try:
                stored = self.database.insert_many(batch)
                self.status.stored += stored
                self.status.last_event_at = int(time.time())
            except Exception as error:  # keep ingestion alive after a DB failure
                self.status.last_error = str(error)
                LOGGER.exception("Unable to store Netify flow batch")

    def _prune_loop(self) -> None:
        while not self._stop.is_set():
            now = datetime.now()
            midnight = (now + timedelta(days=1)).replace(
                hour=0, minute=0, second=0, microsecond=0
            )
            if self._stop.wait((midnight - now).total_seconds()):
                return
            removed = self.database.prune(self.settings.retention_hours)
            LOGGER.info("Retention removed %s flow records", removed)
