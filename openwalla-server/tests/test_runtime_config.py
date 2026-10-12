import json
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from unittest.mock import Mock

from pydantic import ValidationError

from app.auth import AuthenticationManager
from app.collector import NetifyCollector
from app.config import Settings
from app.runtime_config import RuntimeConfig, RuntimeOptions, public_settings


class RuntimeConfigTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.settings = replace(
            Settings.from_environment(),
            database_path=Path(self.tempdir.name) / "flows.sqlite",
            auth_ban_path=Path(self.tempdir.name) / "bans.json",
            ui_password="",
            ui_password_hash="",
            api_token="",
        )
        self.store = RuntimeConfig(self.settings)

    def tearDown(self):
        self.tempdir.cleanup()

    def options(self, **changes):
        values = public_settings(self.settings)
        values.pop("api_token_configured")
        return RuntimeOptions(**{**values, **changes})

    def test_environment_bootstraps_until_settings_are_saved(self):
        self.assertEqual(self.store.load(), self.settings)
        updated = self.store.prepare(
            self.settings, self.options(netify_host="10.0.4.1", retention_hours=72)
        )
        self.store.save(updated)
        restarted = RuntimeConfig(
            replace(self.settings, netify_host="192.0.2.1")
        ).load()
        self.assertEqual(restarted.netify_host, "10.0.4.1")
        self.assertEqual(restarted.retention_hours, 72)
        self.assertEqual(self.store.path.stat().st_mode & 0o777, 0o600)

    def test_password_hashed_and_secrets_not_returned(self):
        updated = self.store.prepare(
            self.settings,
            self.options(
                login_enabled=True,
                ui_password="secret-password",
                api_token="secret-token",
            ),
        )
        self.store.save(updated)
        payload = self.store.path.read_text()
        self.assertNotIn("secret-password", payload)
        restarted = self.store.load()
        manager = AuthenticationManager(restarted)
        self.assertTrue(manager.login("192.0.2.1", "admin", "secret-password").accepted)
        for key in ("ui_password", "ui_password_hash", "api_token", "session_secret"):
            self.assertNotIn(key, public_settings(restarted))
        self.assertTrue(public_settings(restarted)["api_token_configured"])

    def test_blank_secrets_preserve_existing_values(self):
        self.settings = replace(
            self.settings, ui_password="existing", api_token="existing-token"
        )
        updated = self.store.prepare(self.settings, self.options(retention_hours=48))
        self.assertEqual(updated.api_token, "existing-token")
        self.assertEqual(updated.ui_password, "existing")

    def test_disable_login_and_clear_token(self):
        self.settings = replace(
            self.settings, ui_password="existing", api_token="existing-token"
        )
        updated = self.store.prepare(
            self.settings, self.options(login_enabled=False, clear_api_token=True)
        )
        self.assertEqual(updated.api_token, "")
        self.assertEqual(updated.ui_password, "")
        self.assertEqual(updated.ui_password_hash, "")

    def test_initial_login_requires_password(self):
        with self.assertRaisesRegex(ValueError, "Set a password"):
            self.store.prepare(self.settings, self.options(login_enabled=True))

    def test_sessions_survive_restart_with_saved_credentials(self):
        updated = self.store.prepare(
            self.settings, self.options(login_enabled=True, ui_password="password")
        )
        self.store.save(updated)
        token = AuthenticationManager(self.store.load()).create_session()
        self.assertTrue(AuthenticationManager(self.store.load()).valid_session(token))

    def test_failed_atomic_save_preserves_previous_config(self):
        from unittest.mock import patch

        self.store.save(self.settings)
        updated = replace(self.settings, retention_hours=72)
        with patch("app.runtime_config.os.replace", side_effect=OSError("Disk full")):
            with self.assertRaises(OSError):
                self.store.save(updated)
        self.assertEqual(
            self.store.load().retention_hours, self.settings.retention_hours
        )
        self.assertFalse(self.store.path.with_suffix(".tmp").exists())

    def test_invalid_settings_rejected(self):
        for changes in (
            {"netify_port": 0},
            {"netify_host": "http://router"},
            {"retention_hours": 0},
            {"ui_username": "a|b"},
            {"unexpected": 1},
        ):
            with self.subTest(changes=changes), self.assertRaises(ValidationError):
                self.options(**changes)

    def test_authentication_reconfigure_preserves_bans(self):
        self.settings = replace(
            self.settings, ui_password="password", auth_max_failures=2
        )
        manager = AuthenticationManager(self.settings)
        manager.login("192.0.2.1", "admin", "wrong")
        manager.login("192.0.2.1", "admin", "wrong")
        token = manager.create_session()
        manager.reconfigure(replace(self.settings, retention_hours=72))
        self.assertEqual(len(manager.status()["banned"]), 1)
        self.assertTrue(manager.valid_session(token))

    def test_collector_reconfigures_without_restarting_writer(self):
        collector = NetifyCollector(self.settings, Mock())
        connection = Mock()
        collector._connection = connection
        status = collector.status
        updated = replace(
            self.settings, netify_host="10.0.4.1", excluded_protocols=frozenset({"DNS"})
        )
        collector.reconfigure(updated)
        connection.shutdown.assert_called_once()
        self.assertTrue(collector._reconnect.is_set())
        self.assertIs(collector.status, status)
        self.assertIs(collector.settings, updated)


if __name__ == "__main__":
    unittest.main()
