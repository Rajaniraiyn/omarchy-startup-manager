import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "omarchy-startupctl"


class StartupCtlTests(unittest.TestCase):
    def invoke(self, *arguments: str) -> tuple[subprocess.CompletedProcess[str], dict]:
        result = subprocess.run([str(HELPER), *arguments], text=True, capture_output=True)
        self.assertTrue(result.stdout, result.stderr)
        return result, json.loads(result.stdout)

    def test_user_list_has_stable_schema(self):
        result, payload = self.invoke("list", "--scope", "user")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(payload["schema_version"], 1)
        self.assertEqual(payload["scope"], "user")
        self.assertIsInstance(payload["items"], list)
        self.assertIn("protected", payload["summary"])

    def test_autostart_list_has_stable_schema(self):
        result, payload = self.invoke("list", "--scope", "autostart")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(payload["scope"], "autostart")
        self.assertTrue(all(item["kind"] == "autostart" for item in payload["items"]))

    def test_invalid_unit_is_rejected_before_systemctl_action(self):
        result, payload = self.invoke(
            "action", "--scope", "user", "--unit", "../../bad.service", "--action", "stop"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(payload["ok"])
        self.assertIn("Invalid unit name", payload["error"])

    def test_protected_user_unit_is_rejected(self):
        result, payload = self.invoke(
            "action", "--scope", "user", "--unit", "pipewire.service", "--action", "stop"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(payload["ok"])
        self.assertIn("Protected unit", payload["error"])

    def test_dbus_broker_is_protected(self):
        result, payload = self.invoke(
            "action", "--scope", "user", "--unit", "dbus-broker.service", "--action", "stop"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(payload["ok"])
        self.assertIn("Desktop message bus", payload["error"])


if __name__ == "__main__":
    unittest.main()
