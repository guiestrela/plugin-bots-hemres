import asyncio
import json
import unittest
from urllib.parse import urlparse

from adapter.hermes_ws import (
    HermesWebSocketTransport,
    HermesTransportError,
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

    def test_prompt_submit_is_not_active(self):
        transport = HermesWebSocketTransport("ws://127.0.0.1:8765/api/ws", session_token="test")
        with self.assertRaises(UnsupportedHermesMethod):
            self.run_async(transport.request("prompt.submit", {"text": "do not send"}))


if __name__ == "__main__":
    unittest.main()
