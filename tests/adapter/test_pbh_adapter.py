import json
import unittest
from unittest.mock import patch

from adapter.pbh_adapter import PBHAdapter, RosterBot, FixtureRoster


class PBHAdapterTests(unittest.TestCase):
    def setUp(self):
        self.adapter = PBHAdapter(
            FixtureRoster(
                [RosterBot("backend", "Backend", "engineering")],
            )
        )

    def request(self, request_id, operation, params=None):
        return self.adapter.handle(
            {"version": 1, "requestId": request_id, "operation": operation, "params": params or {}}
        )

    def test_list_bots_is_offline_and_marks_runtime_capabilities_unsupported(self):
        response = self.request("r-list", "listBots")
        self.assertTrue(response["ok"])
        result = response["result"]
        self.assertEqual(result["source"], "fixture")
        self.assertFalse(result["stale"])
        bot = result["bots"][0]
        self.assertEqual(bot["id"], "backend")
        self.assertEqual(bot["availability"], "unknown")
        self.assertEqual(bot["capabilities"]["delegateTask"], "unsupported")
        self.assertEqual(bot["capabilities"]["streaming"], "unsupported")
        self.assertFalse(bot["capabilities"]["openChat"])

    def test_unknown_operation_and_hermes_method_fields_are_rejected(self):
        response = self.request("r-bad", "profiles.list", {"method": "cli.exec"})
        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "INVALID_REQUEST")
        self.assertNotIn("cli.exec", response["error"]["message"])

    def test_non_string_operations_are_rejected_without_type_error(self):
        for operation in ([], {}, None):
            with self.subTest(operation=operation):
                response = self.request("r-operation", operation)
                self.assertFalse(response["ok"])
                self.assertEqual(response["error"]["code"], "INVALID_REQUEST")
                self.assertEqual(response["requestId"], "r-operation")

    def test_version_requires_exact_integer_one(self):
        for index, version in enumerate((True, False, 1.0, "1", None)):
            with self.subTest(version=version):
                response = self.adapter.handle({
                    "version": version, "requestId": "r-version-" + str(index),
                    "operation": "listBots"
                })
                self.assertFalse(response["ok"])
                self.assertEqual(response["error"]["code"], "UNSUPPORTED_VERSION")
                self.assertEqual(response["requestId"], "r-version-" + str(index))

    def test_invalid_request_ids_are_never_reflected(self):
        invalid_ids = ["line\nmarker", "x" * 129, "bad\ud800"]
        for request_id in invalid_ids:
            with self.subTest(request_id=repr(request_id)):
                response = self.request(request_id, "listBots")
                self.assertFalse(response["ok"])
                self.assertEqual(response["error"]["code"], "INVALID_REQUEST")
                self.assertEqual(response["requestId"], "")

        valid = self.request("r-after-invalid-id", "listBots")
        self.assertTrue(valid["ok"])

    def test_surrogate_text_is_rejected_and_next_request_is_processed(self):
        response = self.request(
            "r-surrogate-text", "delegateTask",
            {"botId": "backend", "text": "bad\ud800"},
        )
        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "INVALID_REQUEST")
        self.assertEqual(response["requestId"], "r-surrogate-text")

        valid = self.request(
            "r-after-surrogate", "delegateTask",
            {"botId": "backend", "text": "valid text"},
        )
        self.assertTrue(valid["ok"])

    def test_excessive_json_depth_is_sanitized_and_next_request_is_processed(self):
        reasonable = envelope = {
            "version": 1, "requestId": "r-reasonable-depth", "operation": "listBots"
        }
        for _ in range(32):
            envelope["metadata"] = {}
            envelope = envelope["metadata"]
        self.assertTrue(self.adapter.handle(reasonable)["ok"])

        nested = value = {}
        for _ in range(65):
            value["nested"] = {}
            value = value["nested"]
        nested.update({"version": 1, "requestId": "r-deep", "operation": "listBots"})
        response = self.adapter.handle(nested)
        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "INVALID_REQUEST")
        self.assertEqual(response["requestId"], "")

        valid = self.request("r-after-depth", "listBots")
        self.assertTrue(valid["ok"])

    def test_envelope_validation_rejects_version_id_and_params_errors(self):
        cases = [
            ({"version": 2, "requestId": "r", "operation": "listBots"}, "UNSUPPORTED_VERSION"),
            ({"version": 1, "requestId": "", "operation": "listBots"}, "INVALID_REQUEST"),
            ({"version": 1, "requestId": "r", "operation": "listBots", "params": []}, "INVALID_REQUEST"),
        ]
        for envelope, code in cases:
            with self.subTest(code=code):
                response = self.adapter.handle(envelope)
                self.assertFalse(response["ok"])
                self.assertEqual(response["error"]["code"], code)
                self.assertEqual(response["requestId"], envelope.get("requestId", ""))

    def test_request_id_is_deduplicated_without_cross_operation_collision(self):
        first = self.request("same", "listBots")
        second = self.request("same", "listBots")
        other_operation = self.request("same", "getAvatar", {"botId": "backend"})
        self.assertTrue(first["ok"])
        self.assertFalse(second["ok"])
        self.assertEqual(second["error"]["code"], "DUPLICATE_REQUEST")
        self.assertTrue(other_operation["ok"])

    def test_get_avatar_only_returns_validated_opaque_fixture(self):
        response = self.request("r-avatar", "getAvatar", {"botId": "backend"})
        self.assertTrue(response["ok"])
        avatar = response["result"]["avatar"]
        self.assertEqual(avatar["kind"], "image")
        self.assertTrue(avatar["ref"].startswith("fixture-avatar-"))
        self.assertNotIn("data:", json.dumps(response))

    def test_invalid_bot_and_avatar_params_are_sanitized(self):
        missing = self.request("r-missing", "getAvatar", {"botId": "../secret"})
        self.assertFalse(missing["ok"])
        self.assertEqual(missing["error"]["code"], "INVALID_BOT_ID")
        self.assertNotIn("secret", missing["error"]["message"])

        unknown = self.request("r-unknown", "getAvatar", {"botId": "nobody"})
        self.assertFalse(unknown["ok"])
        self.assertEqual(unknown["error"]["code"], "BOT_NOT_FOUND")

    def test_open_chat_and_delegate_task_are_unsupported_without_side_effects(self):
        opened = self.request("r-open", "openChat", {"botId": "backend"})
        delegated = self.request(
            "r-delegate", "delegateTask",
            {"botId": "backend", "text": "literal $(not shell)", "confirmed": True},
        )
        self.assertTrue(opened["ok"])
        self.assertEqual(opened["result"], {"state": "unsupported", "reason": "PANEL_ONLY_V1"})
        self.assertTrue(delegated["ok"])
        self.assertEqual(delegated["result"]["state"], "unsupported")
        self.assertEqual(delegated["result"]["reason"], "RPC_RUNTIME_UNVERIFIED")

    def test_delegate_does_not_echo_prompt_or_accept_boolean_confirmation(self):
        response = self.request(
            "r-secret", "delegateTask",
            {"botId": "backend", "text": "do not echo this", "confirmed": True},
        )
        serialized = json.dumps(response)
        self.assertNotIn("do not echo this", serialized)
        self.assertNotIn("confirmed", serialized)

    def test_text_and_line_limits_are_enforced_before_processing(self):
        too_long = self.request("r-long", "delegateTask", {"botId": "backend", "text": "x" * 16385})
        self.assertFalse(too_long["ok"])
        self.assertEqual(too_long["error"]["code"], "LIMIT_EXCEEDED")

        line = json.dumps({"version": 1, "requestId": "r-line", "operation": "listBots"})
        response = self.adapter.handle_line(line.encode() + b"x" * (4 * 1024 * 1024))
        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "LIMIT_EXCEEDED")

    def test_process_line_rejects_invalid_json_without_leaking_input(self):
        response = self.adapter.handle_line(b'{"operation":"cli.exec","secret":"top-secret"')
        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "INVALID_REQUEST")
        self.assertNotIn("top-secret", json.dumps(response))

    def test_process_line_sanitizes_oversized_json_integer_and_processes_next_request(self):
        oversized = (
            b'{"version":1,"requestId":"r-big-int","operation":"listBots",'
            b'"value":' + b"9" * 5000 + b"}"
        )
        response = self.adapter.handle_line(oversized)
        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "INVALID_REQUEST")
        self.assertNotIn("9" * 5000, json.dumps(response))

        valid = self.adapter.handle_line(
            b'{"version":1,"requestId":"r-after-big-int","operation":"listBots"}'
        )
        self.assertTrue(valid["ok"])
        self.assertEqual(valid["requestId"], "r-after-big-int")
    def test_arbitrary_json_value_error_is_not_swallowed(self):
        with patch("adapter.pbh_adapter.json.loads", side_effect=ValueError("unexpected parser failure")):
            with self.assertRaisesRegex(ValueError, "unexpected parser failure"):
                self.adapter.handle_line(b"{}")


if __name__ == "__main__":
    unittest.main()
