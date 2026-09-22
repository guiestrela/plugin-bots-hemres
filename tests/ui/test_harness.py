from pathlib import Path
import unittest


ROOT = Path(__file__).parents[2]
UI = ROOT / "ui"
MAIN = (UI / "Main.qml").read_text(encoding="utf-8")
BOT_ROW = (UI / "BotRow.qml").read_text(encoding="utf-8")
AVATAR = (UI / "BotAvatar.qml").read_text(encoding="utf-8")
PANEL = (UI / "BotPanel.qml").read_text(encoding="utf-8")
BAR = (ROOT / "BarWidget.qml").read_text(encoding="utf-8")
TOKENS = (UI / "OmarchyTokens.qml").read_text(encoding="utf-8")


class QmlHarnessContractTests(unittest.TestCase):
    def test_harness_contains_required_fixture_states(self):
        for state in ("loading", "empty", "error", "unsupported", "streaming", "approval", "secret-sudo"):
            self.assertIn(f'"{state}"', MAIN)

    def test_unsupported_capabilities_are_explicit(self):
        self.assertIn("RPC_RUNTIME_UNVERIFIED", MAIN)
        self.assertIn("Streaming permanece unsupported", MAIN)
        self.assertIn("Envio real permanece unsupported", MAIN)
        self.assertIn("secret.request e sudo.request não são suportados", MAIN)

    def test_approval_fixture_is_redacted_and_allowlisted(self):
        self.assertIn("Detalhes redigidos", MAIN)
        for choice in ("uma vez", "sessão", "sempre", "negar"):
            self.assertIn(choice, MAIN)
        self.assertNotIn("sudo.respond", MAIN)
        self.assertNotIn("secret.respond", MAIN)

    def test_qt_accessibility_and_focus_metadata_are_present(self):
        for source in (MAIN, (UI / "BotAvatar.qml").read_text(encoding="utf-8"),
                       (UI / "BotRow.qml").read_text(encoding="utf-8")):
            self.assertIn("Accessible.", source)
        self.assertIn("keyNavigationEnabled: true", MAIN)
        self.assertIn("focus: true", MAIN)

    def test_variable_labels_are_explicitly_plain_text(self):
        for source in (MAIN, BOT_ROW):
            self.assertGreater(source.count("Label {"), 0)
            self.assertEqual(source.count("Label {"), source.count("textFormat: Text.PlainText"))
        for variable in ("botName", "botRole", "availability", "selectedBotId"):
            self.assertIn(variable, MAIN + BOT_ROW)

    def test_avatar_source_is_empty_when_image_is_invalid(self):
        source_lines = [line.strip() for line in AVATAR.splitlines() if line.strip().startswith("source:")]
        self.assertEqual(source_lines, ["source: avatar.imageValid ? avatar.imageSource : \"\""])
        self.assertIn("imageValid", source_lines[0])

    def test_semantic_omarchy_tokens_are_verifiable(self):
        for token in ("Color.popups", "Color.accent", "Color.urgent", "Style.spacing", "Style.cornerRadius"):
            self.assertIn(token, TOKENS)
        for role in ("popupBackground", "popupBorder", "accent", "urgent", "spacing", "cornerRadius"):
            self.assertIn(role, TOKENS)

    def test_scope_is_native_qml_only(self):
        all_ui = "\n".join(p.read_text(encoding="utf-8") for p in UI.glob("*.qml"))
        self.assertNotIn("React", all_ui)
        self.assertNotIn("<style", all_ui.lower())
        self.assertNotIn("shell.json", all_ui)
        self.assertNotIn("hermes-agent", all_ui)

    def test_bar_widget_is_interactive_and_uses_bot_icon(self):
        self.assertNotIn('text: qsTr("HB")', BAR)
        self.assertNotIn('text: "♟"', BAR)
        self.assertIn("Avatar {", BAR)
        self.assertIn("onPressed: function(buttonCode)", BAR)
        self.assertIn("property var adapter", BAR)

    def test_panel_covers_adapter_states_and_real_profile_fields(self):
        for state in ("loading", "error", "empty", "ready"):
            self.assertIn(f'"{state}"', PANEL)
        for field in ("name", "display_name", "description", "has_avatar"):
            self.assertIn(field, PANEL)
        self.assertIn("RPC_RUNTIME_UNVERIFIED", PANEL)
        self.assertIn("delegateTask", PANEL)
        self.assertIn("enabled: false", PANEL)

    def test_panel_does_not_embed_transport_endpoints(self):
        for forbidden in ("/api/ws", "profiles.list", "prompt.submit", "WebSocket", "Qt.network"):
            self.assertNotIn(forbidden, PANEL + BAR)


if __name__ == "__main__":
    unittest.main()
