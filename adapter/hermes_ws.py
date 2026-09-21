"""Minimal, read-only Hermes gateway WebSocket transport.

The offline fixture in :mod:`pbh_adapter` remains the QML-facing fallback. This
module is deliberately separate and only implements the two read operations
needed for roster and avatar discovery; it never sends prompts or approvals.
"""

from __future__ import annotations

import asyncio
from itertools import count
import json
import re
from typing import Any, Callable
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen


_ALLOWED_HOSTS = frozenset({"127.0.0.1", "::1", "localhost"})
_GATEWAY_PATH = "/api/ws"
_MAX_MESSAGE_BYTES = 4 * 1024 * 1024


class HermesTransportError(Exception):
    """Safe, user-facing transport error without remote payload details."""


class UnsupportedHermesMethod(HermesTransportError):
    """Raised for methods intentionally not active in this adapter slice."""


def validate_gateway_url(url: str, allowed_hosts: frozenset[str] = _ALLOWED_HOSTS) -> str:
    """Validate and return a loopback-only Hermes gateway URL.

    The path is fixed to the documented gateway endpoint. Credentials, query
    strings, fragments, and non-loopback hosts are rejected to avoid silently
    sending local data to an unintended endpoint.
    """
    if not isinstance(url, str):
        raise HermesTransportError("Gateway URL is invalid.")
    try:
        parsed = urlsplit(url)
    except ValueError as exc:
        raise HermesTransportError("Gateway URL is invalid.") from exc
    try:
        hostname = parsed.hostname
        port = parsed.port
        username = parsed.username
        password = parsed.password
    except ValueError as exc:
        raise HermesTransportError("Gateway URL is invalid.") from exc
    if (
        parsed.scheme != "ws"
        or hostname not in allowed_hosts
        or port is None
        or username is not None
        or password is not None
        or parsed.path != _GATEWAY_PATH
        or parsed.query
        or parsed.fragment
    ):
        raise HermesTransportError("Gateway URL is not an allowed local endpoint.")
    # urlsplit lowercases hostname in .hostname; reconstructing also rejects
    # hidden path/authority variations while preserving the caller's port.
    return urlunsplit((parsed.scheme, parsed.netloc, parsed.path, "", ""))


def _http_gateway_url(ws_url: str) -> str:
    parsed = urlsplit(ws_url)
    return urlunsplit(("http", parsed.netloc, "/", "", ""))


def discover_session_token(ws_url: str, timeout: float = 3.0) -> str:
    """Read the ephemeral loopback token from the headless gateway root."""
    request = Request(_http_gateway_url(ws_url), headers={"Cache-Control": "no-store"})
    with urlopen(request, timeout=timeout) as response:
        body = response.read(64 * 1024).decode("utf-8", "replace")
    match = re.search(r"window\.__HERMES_SESSION_TOKEN__\s*=\s*([\"'])([^\"']+)\1", body)
    if not match:
        raise HermesTransportError("Hermes session token is unavailable.")
    return match.group(2)


def _with_token(ws_url: str, token: str) -> str:
    parsed = urlsplit(ws_url)
    query = dict(parse_qsl(parsed.query, keep_blank_values=True))
    query["token"] = token
    return urlunsplit((parsed.scheme, parsed.netloc, parsed.path, urlencode(query), ""))


class HermesWebSocketTransport:
    """One-request-per-connection, read-only JSON-RPC/WebSocket client."""

    def __init__(
        self,
        url: str,
        *,
        connect: Callable[..., Any] | None = None,
        timeout: float = 10.0,
        allowed_hosts: frozenset[str] = _ALLOWED_HOSTS,
        session_token: str | None = None,
    ) -> None:
        if timeout <= 0:
            raise HermesTransportError("Timeout is invalid.")
        self.url = validate_gateway_url(url, allowed_hosts)
        self.timeout = timeout
        self._ids = count(1)
        self._session_token = ""
        if session_token:
            self._session_token = session_token
        elif connect is None:
            self._session_token = discover_session_token(self.url, timeout=min(timeout, 3.0))
        if connect is None:
            try:
                from websockets import connect as websocket_connect
            except ImportError as exc:  # pragma: no cover - environment dependent
                raise HermesTransportError(
                    "WebSocket support is unavailable; install websockets to enable Hermes transport."
                ) from exc
            connect = websocket_connect
        self._connect = connect

    async def list_profiles(self) -> dict[str, Any]:
        """Read the profile roster without requesting session data."""
        result = await self.request("profiles.list", {"include_sessions": False})
        if not isinstance(result, dict):
            raise HermesTransportError("Hermes response is invalid.")
        return result

    async def get_asset(self, name: str, asset: str = "avatar") -> dict[str, Any]:
        """Fetch one profile asset on demand."""
        if not isinstance(name, str) or not name or not isinstance(asset, str) or not asset:
            raise HermesTransportError("Asset request is invalid.")
        result = await self.request("profiles.get_asset", {"name": name, "asset": asset})
        if not isinstance(result, dict):
            raise HermesTransportError("Hermes response is invalid.")
        return result

    async def request(self, method: str, params: dict[str, Any]) -> Any:
        """Send one supported JSON-RPC request and close its socket."""
        if method not in {"profiles.list", "profiles.get_asset"}:
            raise UnsupportedHermesMethod("Hermes method is not enabled.")
        if not isinstance(params, dict):
            raise HermesTransportError("Hermes request is invalid.")
        request_id = next(self._ids)
        request = {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": method,
            "params": params,
        }
        try:
            return await asyncio.wait_for(
                self._request_once(request_id, request), timeout=self.timeout
            )
        except asyncio.TimeoutError as exc:
            raise HermesTransportError("Hermes request timed out.") from exc
        except HermesTransportError:
            raise
        except (OSError, RuntimeError, ValueError, TypeError) as exc:
            raise HermesTransportError("Hermes connection failed.") from exc

    async def _request_once(self, request_id: int, request: dict[str, Any]) -> Any:
        # websockets sends a complete message; newline framing is still explicit
        # because Hermes' gateway contract is JSON-RPC delimited by newline.
        wire = (json.dumps(request, separators=(",", ":"), ensure_ascii=False) + "\n")
        async with self._connect(
            _with_token(self.url, self._session_token) if self._session_token else self.url,
            open_timeout=self.timeout,
            close_timeout=self.timeout,
            max_size=_MAX_MESSAGE_BYTES,
        ) as socket:
            buffer = ""
            sent = False
            while True:
                message = await socket.recv()
                if isinstance(message, bytes):
                    message = message.decode("utf-8")
                if not isinstance(message, str):
                    raise HermesTransportError("Hermes response is invalid.")
                buffer += message if message.endswith("\n") else message + "\n"
                if len(buffer.encode("utf-8")) > _MAX_MESSAGE_BYTES:
                    raise HermesTransportError("Hermes response exceeded the limit.")
                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    if not line.strip():
                        continue
                    response = self._decode_response(line)
                    if not sent:
                        await socket.send(wire)
                        sent = True
                    if response.get("id") != request_id:
                        continue
                    if "error" in response:
                        raise HermesTransportError("Hermes RPC request failed.")
                    if "result" not in response:
                        raise HermesTransportError("Hermes response is invalid.")
                    return response["result"]

    @staticmethod
    def _decode_response(line: str) -> dict[str, Any]:
        try:
            value = json.loads(line)
        except (UnicodeDecodeError, json.JSONDecodeError, RecursionError, ValueError) as exc:
            raise HermesTransportError("Hermes response is invalid.") from exc
        if not isinstance(value, dict) or value.get("jsonrpc") != "2.0":
            raise HermesTransportError("Hermes response is invalid.")
        return value
