"""Offline delegation regression tests. No gateway or credentials are used."""
import asyncio
import json
import unittest
from unittest.mock import patch

from scripts import hermes_delegate as delegate

PAYLOAD = {"url": "ws://127.0.0.1:8765/api/ws", "profile": "fixture", "text": "fixture task"}


class FakeTransport:
    def __init__(self, reply=None):
        self.calls = []
        self.reply = {"status": "streaming", "private": "DO_NOT_LEAK"} if reply is None else reply

    async def request(self, method, params):
        self.calls.append((method, params))
        if method == "session.create":
            return {"session_id": "abc12345", "stored_session_id": "20260101_120000_fixture"}
        return self.reply


class FixtureSocket:
    def __init__(self, incoming, send_error=False):
        self.incoming = list(incoming)
        self.sent = []
        self.send_error = send_error

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        return False

    async def send(self, wire):
        self.sent.append(json.loads(wire))
        if self.send_error:
            raise OSError("DO_NOT_LEAK")

    async def recv(self):
        if not self.incoming:
            raise OSError("DO_NOT_LEAK")
        frame = self.incoming.pop(0)
        return json.dumps(frame)


def rpc(result, rid):
    return {"jsonrpc": "2.0", "id": rid, "result": result}


READY = {"jsonrpc": "2.0", "method": "gateway.ready", "params": {}}


class DelegateTests(unittest.TestCase):
    def wire_run(self, submit_frames, *, send_error=False):
        created = FixtureSocket([READY, rpc({"session_id": "abc12345"}, 1)])
        submitted = FixtureSocket(submit_frames, send_error)
        sockets = iter([created, submitted])
        transport = delegate.HermesWebSocketTransport(PAYLOAD["url"], connect=lambda *a, **k: next(sockets))
        with patch.object(delegate, "HermesWebSocketTransport", return_value=transport):
            result = asyncio.run(delegate.run(PAYLOAD))
        return result, submitted

    def test_explicit_rpc_rejection_is_failed(self):
        result, socket = self.wire_run([READY, {"jsonrpc": "2.0", "id": 2,
            "error": {"code": 4009, "message": "DO_NOT_LEAK"}}])
        self.assertEqual(result, {"ok": False, "state": "failed", "error": "rpc_rejected", "session_id": "abc12345"})
        self.assertEqual(len(socket.sent), 1)

    def test_disconnect_before_send_is_failed(self):
        result, socket = self.wire_run([])
        self.assertEqual(result["state"], "failed")
        self.assertEqual(socket.sent, [])

    def test_disconnect_after_send_is_uncertain_no_retry(self):
        for frames, send_error in (([READY], False), ([READY], True),
                                   ([READY, {"jsonrpc": "2.0", "id": 2, "error": "bad"}], False)):
            with self.subTest(frames=frames, send_error=send_error):
                result, socket = self.wire_run(frames, send_error=send_error)
                self.assertEqual(result["state"], "delivery-uncertain")
                self.assertEqual(result["session_id"], "abc12345")
                self.assertNotIn("DO_NOT_LEAK", json.dumps(result))
                self.assertEqual(len(socket.sent), 1)

    def test_wire_ack_ignores_other_ids_and_events(self):
        result, socket = self.wire_run([READY, rpc({"status": "completed"}, 999),
            {"jsonrpc": "2.0", "method": "message.complete", "params": {"text": "private"}},
            rpc({"status": "streaming"}, 2)])
        self.assertEqual(result["state"], "submitted")
        self.assertEqual(len(socket.sent), 1)

    def test_invalid_payload_fails_before_transport(self):
        invalid = [None, [], True, 1, "text", {}, dict(PAYLOAD, text=" "),
                   dict(PAYLOAD, text="bad\u0000text"), dict(PAYLOAD, text="x" * 16385),
                   dict(PAYLOAD, text="\ud800"), dict(PAYLOAD, profile="../other"),
                   dict(PAYLOAD, url="ws://example.com:8765/api/ws")]
        with patch.object(delegate, "HermesWebSocketTransport") as factory:
            for payload in invalid:
                with self.subTest(payload=repr(payload)[:70]):
                    self.assertEqual(asyncio.run(delegate.run(payload)),
                                     {"ok": False, "state": "failed", "error": "invalid_request"})
            factory.assert_not_called()

    def test_only_streaming_ack_confirms_submission(self):
        for ack in ({}, [], True, {"status": "completed"}, {"accepted": True}, {"voice_stopped": True}):
            with self.subTest(ack=ack), patch.object(delegate, "HermesWebSocketTransport", return_value=FakeTransport(ack)):
                result = asyncio.run(delegate.run(PAYLOAD))
                self.assertEqual(result["state"], "delivery-uncertain")
                self.assertFalse(result["ok"])
                self.assertEqual(result["session_id"], "abc12345")

    def test_real_ack_is_submitted_not_completed_and_sanitized(self):
        transport = FakeTransport()
        with patch.object(delegate, "HermesWebSocketTransport", return_value=transport):
            result = asyncio.run(delegate.run(PAYLOAD))
        self.assertEqual(result, {"ok": True, "state": "submitted", "session_id": "abc12345",
                                  "stored_session_id": "20260101_120000_fixture"})
        self.assertEqual(transport.calls, [
            ("session.create", {"profile": "fixture", "source": "hermes-bots-plugin", "close_on_disconnect": False}),
            ("prompt.submit", {"session_id": "abc12345", "text": "fixture task"}),
        ])


if __name__ == "__main__":
    unittest.main()
