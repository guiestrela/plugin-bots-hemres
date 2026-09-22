import asyncio
import json
import unittest
from urllib.parse import urlparse

from adapter.hermes_ws import (
    HermesWebSocketTransport,
    HermesTransportError,
    HermesDelegationController,
    UnsupportedHermesMethod,
    validate_gateway_url,
)


class FakeSocket:
    def __init__(self, incoming):
        self.incoming = list(incoming)
        self.sent = []
        self.closed = False

    async def send(self, message):
        self.sent.append(message)

    async def recv(self):
        if not self.incoming:
            await asyncio.sleep(0)
            raise AssertionError("fake socket exhausted")
        return self.incoming.pop(0)

    async def close(self):
        self.closed = True


class SocketContext:
    def __init__(self, socket):
        self.socket = socket

    async def __aenter__(self):
        return self.socket

    async def __aexit__(self, exc_type, exc, tb):
        await self.socket.close()


class HermesWebSocketTransportTests(unittest.TestCase):
    def run_async(self, awaitable):
        return asyncio.run(awaitable)

    def test_gateway_url_requires_loopback_api_websocket_endpoint(self):
        self.assertEqual(
            validate_gateway_url("ws://127.0.0.1:8765/api/ws"),
            "ws://127.0.0.1:8765/api/ws",
        )
        for url in (
            "http://127.0.0.1:8765/api/ws",
            "ws://192.168.1.5:8765/api/ws",
            "ws://127.0.0.1:8765/other",
            "ws://user:pass@127.0.0.1:8765/api/ws",
            "ws://127.0.0.1/api/ws",
        ):
            with self.subTest(url=url):
                with self.assertRaises(HermesTransportError):
                    validate_gateway_url(url)

    def test_list_profiles_sends_newline_delimited_json_rpc_and_correlates_id(self):
        socket = FakeSocket([
            '{"jsonrpc":"2.0","method":"gateway.ready","params":{}}\n',
            '{"jsonrpc":"2.0","id":999,"result":{"ignored":true}}\n',
            '{"jsonrpc":"2.0","id":1,"result":{"profiles":[]}}\n',
        ])

        def connect(url, **kwargs):
            self.assertEqual(url, "ws://127.0.0.1:8765/api/ws")
            return SocketContext(socket)

        transport = HermesWebSocketTransport(
            "ws://127.0.0.1:8765/api/ws", connect=connect, timeout=0.2
        )
        result = self.run_async(transport.list_profiles())
        self.assertEqual(result, {"profiles": []})
        self.assertTrue(socket.closed)
        request = json.loads(socket.sent[0])
        self.assertEqual(request, {
            "jsonrpc": "2.0", "id": 1, "method": "profiles.list",
            "params": {"include_sessions": False},
        })
        self.assertTrue(socket.sent[0].endswith("\n"))

    def test_get_asset_is_on_demand_and_uses_correlated_id(self):
        socket = FakeSocket([
            '{"jsonrpc":"2.0","id":1,"result":{"found":true,"data":"data:image/png;base64,AA=="}}\n'
        ])
        transport = HermesWebSocketTransport(
            "ws://127.0.0.1:8765/api/ws",
            connect=lambda *args, **kwargs: SocketContext(socket),
        )
        result = self.run_async(transport.get_asset("backend", "avatar"))
        self.assertTrue(result["found"])
        request = json.loads(socket.sent[0])
        self.assertEqual(request["id"], 1)
        self.assertEqual(request["method"], "profiles.get_asset")
        self.assertEqual(request["params"], {"name": "backend", "asset": "avatar"})

    def test_rpc_errors_are_sanitized_and_socket_closes(self):
        socket = FakeSocket([
            '{"jsonrpc":"2.0","id":1,"error":{"code":-32603,"message":"secret token"}}\n'
        ])
        transport = HermesWebSocketTransport(
            "ws://127.0.0.1:8765/api/ws",
            connect=lambda *args, **kwargs: SocketContext(socket),
        )
        with self.assertRaises(HermesTransportError) as raised:
            self.run_async(transport.list_profiles())
        self.assertEqual(str(raised.exception), "Hermes RPC request failed.")
        self.assertNotIn("secret", str(raised.exception))
        self.assertTrue(socket.closed)

    def test_timeout_closes_socket(self):
        class HangingSocket(FakeSocket):
            async def recv(self):
                await asyncio.sleep(1)

        socket = HangingSocket([])
        transport = HermesWebSocketTransport(
            "ws://127.0.0.1:8765/api/ws",
            connect=lambda *args, **kwargs: SocketContext(socket),
            timeout=0.01,
        )
        with self.assertRaises(HermesTransportError) as raised:
            self.run_async(transport.list_profiles())
        self.assertEqual(str(raised.exception), "Hermes request timed out.")
        self.assertTrue(socket.closed)

    def test_arbitrary_method_is_not_active(self):
        transport = HermesWebSocketTransport("ws://127.0.0.1:8765/api/ws", session_token="test")
        with self.assertRaises(UnsupportedHermesMethod):
            self.run_async(transport.request("shell.exec", {"command": "do not send"}))


class FakeDelegationTransport:
    def __init__(self, responses=None, error=None):
        self.calls = []
        self.responses = list(responses or [])
        self.error = error

    async def request(self, method, params):
        self.calls.append((method, params))
        if self.error:
            raise self.error
        return self.responses.pop(0)


class HermesDelegationControllerTests(unittest.TestCase):
    def run_async(self, awaitable):
        return asyncio.run(awaitable)

    def test_fake_session_creation_and_prompt_submission_are_structured(self):
        fake = FakeDelegationTransport([{"session_id": "sess-1"}, {"accepted": True}])
        controller = HermesDelegationController(fake)
        self.assertEqual(self.run_async(controller.create_session("backend")), "sess-1")
        result = self.run_async(controller.submit("sess-1", "Faça a tarefa"))
        self.assertEqual(result["state"], "streaming")
        self.assertEqual(fake.calls, [
            ("session.create", {"profile": "backend"}),
            ("prompt.submit", {"session_id": "sess-1", "text": "Faça a tarefa"}),
        ])

    def test_deltas_and_completion_update_panel_only_state(self):
        controller = HermesDelegationController(FakeDelegationTransport())
        self.assertEqual(controller.handle_event({"method": "message.delta", "params": {"session_id": "s", "text": "olá"}})["state"], "streaming")
        controller.handle_event({"method": "reasoning.delta", "params": {"session_id": "s", "text": "r"}})
        controller.handle_event({"method": "thinking.delta", "params": {"session_id": "s", "text": "t"}})
        state = controller.handle_event({"method": "message.completed", "params": {"session_id": "s"}})
        self.assertEqual(state["state"], "completed")
        self.assertEqual(state["message"], "olá")
        self.assertEqual(state["reasoning"], "r")
        self.assertEqual(state["thinking"], "t")

    def test_approval_is_redacted_and_only_allow_deny_are_sendable(self):
        fake = FakeDelegationTransport([{"ok": True}])
        controller = HermesDelegationController(fake)
        approval = controller.handle_event({"method": "approval.requested", "params": {
            "session_id": "s", "request_id": "r", "kind": "command", "description": "sudo cat secret.txt"
        }})
        self.assertEqual(approval["state"], "approval")
        self.assertNotIn("secret.txt", approval["approval"])
        self.run_async(controller.respond_approval("s", "r", "allow"))
        self.assertEqual(fake.calls[0], ("approval.respond", {"session_id": "s", "request_id": "r", "choice": "allow", "all": False}))
        with self.assertRaises(HermesTransportError):
            self.run_async(controller.respond_approval("s", "r", "sudo"))

    def test_cancel_timeout_and_delivery_uncertain_are_explicit(self):
        fake = FakeDelegationTransport([{"interrupted": True}])
        controller = HermesDelegationController(fake)
        self.run_async(controller.cancel("s"))
        self.assertEqual(controller.state("s")["state"], "cancelled")
        timed_out = HermesTransportError("Hermes request timed out.")
        uncertain = HermesDelegationController(FakeDelegationTransport(error=timed_out))
        with self.assertRaises(HermesTransportError):
            self.run_async(uncertain.submit("s", "texto"))
        self.assertEqual(uncertain.state("s")["state"], "delivery-uncertain")

    def test_secret_and_sudo_approval_events_are_rejected(self):
        controller = HermesDelegationController(FakeDelegationTransport())
        for kind in ("secret", "sudo"):
            with self.subTest(kind=kind):
                with self.assertRaises(HermesTransportError):
                    controller.handle_event({"method": "approval.requested", "params": {"session_id": "s", "request_id": "r", "kind": kind}})


if __name__ == "__main__":
    unittest.main()
