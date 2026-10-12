import json
import tempfile
import unittest
from pathlib import Path

from app.database import FlowDatabase
from app.processor import FlowProcessor


class FlowDatabaseTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.database = FlowDatabase(Path(self.tempdir.name) / "flows.sqlite")
        processor = FlowProcessor(frozenset())
        events = [
            {
                "type": "flow",
                "interface": "br-lan",
                "flow": {
                    "local_ip": "192.168.1.20",
                    "local_mac": "aa:bb:cc:dd:ee:ff",
                    "other_ip": "1.1.1.1",
                    "other_port": 443,
                    "detected_protocol_name": "HTTP/S",
                    "ssl": {"client_sni": "api.example.com"},
                },
            },
            {
                "type": "flow",
                "interface": "br-lan",
                "flow": {
                    "local_ip": "192.168.1.21",
                    "local_mac": "11:22:33:44:55:66",
                    "other_ip": "9.9.9.9",
                    "other_port": 53,
                    "detected_protocol_name": "DNS",
                    "dns_host_name": "dns.example.net",
                },
            },
        ]
        rows = [processor.process(json.dumps(event)) for event in events]
        self.database.insert_many(row for row in rows if row is not None)

    def tearDown(self) -> None:
        self.database.close()
        self.tempdir.cleanup()

    def test_filters_by_device_and_search(self) -> None:
        rows = self.database.list_flows(
            limit=250,
            offset=0,
            protocol=None,
            mac="AA:BB:CC:DD:EE:FF",
            search="example.com",
            hours=24,
        )
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["flow"]["other_ip"], "1.1.1.1")

    def test_protocol_count(self) -> None:
        count = self.database.count_flows(
            protocol="DNS", mac=None, search=None, hours=24
        )
        self.assertEqual(count, 1)

    def test_normalized_records_for_web_explorer(self) -> None:
        rows = self.database.list_flows(
            limit=40,
            offset=0,
            protocol=None,
            mac=None,
            search="example.com",
            hours=24,
            normalized=True,
        )
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["fqdn"], "api.example.com")
        self.assertEqual(rows[0]["local_ip"], "192.168.1.20")
        self.assertGreater(rows[0]["timeinsert"], 0)
        self.assertNotIn("json", rows[0])

    def test_dashboard_summary(self) -> None:
        summary = self.database.dashboard_summary(24)

        self.assertEqual(summary["flow_count"], 2)
        self.assertEqual(summary["device_count"], 2)
        self.assertEqual(len(summary["recent_flows"]), 2)
        self.assertEqual(summary["top_applications"][0]["count"], 1)
        self.assertGreater(summary["database_bytes"], 0)


if __name__ == "__main__":
    unittest.main()
