import importlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi import Request
from fastapi.responses import FileResponse, RedirectResponse
from fastapi.testclient import TestClient


class DashboardPagesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tempdir = tempfile.TemporaryDirectory()
        with patch.dict(
            "os.environ",
            {
                "OPENWALLA_DATABASE_PATH": str(Path(cls.tempdir.name) / "flows.sqlite"),
                "OPENWALLA_AUTH_BAN_PATH": str(Path(cls.tempdir.name) / "bans.json"),
            },
        ):
            # Importing registers every route and must not raise FastAPIError.
            cls.main = importlib.import_module("app.main")

    @classmethod
    def tearDownClass(cls):
        cls.main.database.close()
        cls.tempdir.cleanup()

    def test_html_routes_have_no_generated_response_model(self):
        for path in ("/", "/login", "/netify", "/tunnel", "/settings"):
            route = next(route for route in self.main.app.routes if route.path == path)
            self.assertIsNone(route.response_model)

    def test_http_pages_and_local_assets(self):
        client = TestClient(self.main.app)
        with patch.object(self.main, "authentication") as auth:
            auth.enabled = False
            for path in ("/", "/netify", "/tunnel", "/settings"):
                response = client.get(path)
                self.assertEqual(response.status_code, 200)
                self.assertIn("Openwalla", response.text)
            for path in ("server.js", "server.css", "lucide.min.js"):
                self.assertEqual(client.get(f"/static/{path}").status_code, 200)

    def test_settings_api_auth_validation_and_persistence(self):
        client = TestClient(self.main.app)
        with patch.object(self.main, "settings", self.main.settings), patch.object(
            self.main, "collector"
        ) as collector, patch.object(self.main, "authentication") as auth:
            auth.enabled = False
            payload = client.get("/api/v1/settings").json()
            self.assertNotIn("api_token", payload)
            payload.pop("api_token_configured")
            payload["retention_hours"] = 48
            result = client.put("/api/v1/settings", json=payload)
            self.assertEqual(result.status_code, 200)
            self.assertEqual(self.main.runtime_config.load().retention_hours, 48)
            collector.reconfigure.assert_called_once()
            result = client.put(
                "/api/v1/settings",
                json=payload,
                headers={"Origin": "http://evil.invalid"},
            )
            self.assertEqual(result.status_code, 403)
            payload["netify_port"] = -1
            self.assertEqual(
                client.put("/api/v1/settings", json=payload).status_code, 422
            )
            auth.enabled = True
            auth.valid_session.return_value = False
            self.assertEqual(client.get("/api/v1/settings").status_code, 401)
            self.assertEqual(
                client.put("/api/v1/settings", json=payload).status_code, 401
            )

    def test_dashboard_and_login_without_authentication(self):
        request = Request({"type": "http", "headers": []})
        with patch.object(self.main, "authentication") as auth:
            auth.enabled = False
            response = self.main.dashboard_page(request)
            self.assertIsInstance(response, FileResponse)
            self.assertTrue(Path(response.path).is_file())
            response = self.main.login_page(request)
            self.assertIsInstance(response, RedirectResponse)
            self.assertEqual(response.headers["location"], "/")

    def test_dashboard_and_login_with_authentication(self):
        request = Request({"type": "http", "headers": []})
        with patch.object(self.main, "authentication") as auth:
            auth.enabled = True
            auth.valid_session.return_value = False
            response = self.main.dashboard_page(request)
            self.assertEqual(response.status_code, 303)
            self.assertEqual(response.headers["location"], "/login")
            response = self.main.login_page(request)
            self.assertIsInstance(response, FileResponse)
            self.assertTrue(Path(response.path).is_file())
            auth.valid_session.return_value = True
            self.assertIsInstance(self.main.dashboard_page(request), FileResponse)
            self.assertEqual(self.main.login_page(request).headers["location"], "/")


if __name__ == "__main__":
    unittest.main()
