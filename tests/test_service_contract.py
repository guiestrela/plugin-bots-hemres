import json
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]


class ServiceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        cls.service = (ROOT / "service.qml").read_text(encoding="utf-8")
        cls.bar = (ROOT / "BarWidget.qml").read_text(encoding="utf-8")
        cls.helper = (ROOT / "scripts" / "hermes_profiles.py").read_text(encoding="utf-8")
        cls.panel = (ROOT / "ui" / "BotPanel.qml").read_text(encoding="utf-8")

    def test_manifest_registers_persistent_service(self):
        self.assertIn("service", self.manifest["kinds"])
        self.assertTrue(self.manifest["keepLoaded"])
        self.assertEqual(self.manifest["entryPoints"]["service"], "service.qml")

    def test_service_exposes_read_only_panel_state_and_rpc_calls(self):
        for property_name in ("profiles", "loading", "error", "selectedProfile"):
            self.assertIn(f"property", self.service)
            self.assertIn(property_name, self.service)
        self.assertIn('"profiles.list"', self.service)
        self.assertIn('"include_sessions": false', self.service)
        self.assertIn('"profiles.get_asset"', self.service)
        self.assertIn("prompt.submit", self.service)
        self.assertIn("delegationBlocked", self.service)

    def test_helper_requires_explicit_loopback_url_and_never_accepts_tokens(self):
        self.assertIn("--url", self.helper)
        self.assertIn("validate_gateway_url", self.helper)
        self.assertIn("profiles.list", self.helper)
        self.assertIn("profiles.get_asset", self.helper)
        self.assertIn("configuration_required", self.helper)
        self.assertNotIn("auth.json", self.helper)
        self.assertNotIn("token", self.helper.lower())

    def test_bar_widget_gets_service_and_passes_it_to_panel(self):
        self.assertIn("serviceFor", self.bar)
        self.assertIn("panelContent.service", self.bar)
        self.assertIn("selectedProfile", self.bar)

    def test_panel_uses_service_state_without_enabling_delegation(self):
        self.assertIn("service:", self.panel)
        self.assertIn("profiles:", self.panel)
        self.assertIn("selectedProfile", self.panel)
        self.assertIn("enabled: false", self.panel)
        self.assertNotIn("service.delegate", self.panel)


if __name__ == "__main__":
    unittest.main()
