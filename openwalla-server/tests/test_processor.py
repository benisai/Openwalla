import json
import unittest

from app.processor import FlowProcessor


class FlowProcessorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.processor = FlowProcessor(frozenset({"DNS"}), "192.168.1.1")

    def test_preserves_hybrid_columns_and_json(self) -> None:
        event = {
            "type": "flow",
            "interface": "br-lan",
            "flow": {
                "local_ip": "192.168.1.20",
                "local_port": 51000,
                "local_mac": "AA:BB:CC:DD:EE:FF",
                "other_ip": "1.1.1.1",
                "other_port": 443,
                "detected_protocol_name": "HTTP/S",
                "ssl": {"client_sni": "example.com"},
            },
        }
        result = self.processor.process(json.dumps(event))
        self.assertIsNotNone(result)
        assert result is not None
        self.assertEqual(result.values[3], "aa:bb:cc:dd:ee:ff")
        self.assertEqual(result.values[4], "example.com")
        self.assertEqual(json.loads(result.raw_json)["type"], "flow")

    def test_filters_router_destination(self) -> None:
        event = {
            "type": "flow",
            "flow": {
                "local_ip": "192.168.1.20",
                "other_ip": "192.168.1.1",
                "detected_protocol_name": "HTTP/S",
            },
        }
        self.assertIsNone(self.processor.process(json.dumps(event)))

    def test_filters_router_web_source(self) -> None:
        event = {
            "type": "flow",
            "flow": {
                "local_ip": "192.168.1.1",
                "local_port": 80,
                "other_ip": "192.168.1.20",
                "detected_protocol_name": "HTTP",
            },
        }
        self.assertIsNone(self.processor.process(json.dumps(event)))


if __name__ == "__main__":
    unittest.main()
