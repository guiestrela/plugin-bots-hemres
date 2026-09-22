#!/usr/bin/env python3
"""Explicit panel action bridge: create a session and submit one user task."""
from __future__ import annotations
import asyncio
import json
import sys
from typing import Any
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from adapter.hermes_ws import (
    HermesTransportError, HermesWebSocketTransport as _BaseTransport,
    validate_gateway_url, _valid_id, _validate_text, _with_token, _MAX_MESSAGE_BYTES,
)


class RpcRejected(HermesTransportError):
    """A correlated, well-formed JSON-RPC error, never remote error text."""


class HermesWebSocketTransport(_BaseTransport):
    """Delegation-only send tracking; the read-only adapter stays unchanged."""

    prompt_sent = False

    async def _request_once(self, request_id: int, request: dict[str, Any]) -> Any:
        wire = json.dumps(request, ensure_ascii=False, separators=(",", ":")) + "\n"
        async with self._connect(
            _with_token(self.url, self._session_token) if self._session_token else self.url,
            open_timeout=self.timeout, close_timeout=1.0, max_size=_MAX_MESSAGE_BYTES,
        ) as socket:
            sent = False
            while True:
                message = await socket.recv()
                if isinstance(message, bytes):
                    message = message.decode("utf-8")
                if not isinstance(message, str) or len(message.encode("utf-8")) > _MAX_MESSAGE_BYTES:
                    raise HermesTransportError("Invalid response")
                for line in message.splitlines():
                    if not line.strip():
                        continue
                    response = self._decode_response(line)
                    if not sent:
                        # Mark BEFORE await: a send exception can follow delivery.
                        if request["method"] == "prompt.submit":
                            self.prompt_sent = True
                        sent = True
                        await socket.send(wire)
                    if type(response.get("id")) is not int or response["id"] != request_id:
                        continue
                    if "error" in response:
                        error = response["error"]
                        if ("result" not in response and isinstance(error, dict)
                                and type(error.get("code")) is int
                                and isinstance(error.get("message"), str)):
                            raise RpcRejected("RPC rejected")
                        raise HermesTransportError("Invalid response")
                    if "result" not in response:
                        raise HermesTransportError("Invalid response")
                    return response["result"]


async def run(payload: Any) -> dict[str, Any]:
    invalid = {"ok": False, "state": "failed", "error": "invalid_request"}
    if not isinstance(payload, dict):
        return invalid
    url, profile, text = (payload.get(key) for key in ("url", "profile", "text"))
    try:
        validate_gateway_url(url)
        _validate_text(text)
        if not _valid_id(profile) or not text.strip():
            return invalid
    except (HermesTransportError, ValueError):
        return invalid
    try:
        transport = HermesWebSocketTransport(url)
        created = await transport.request("session.create", {"profile": profile, "source": "hermes-bots-plugin", "close_on_disconnect": False})
        if not isinstance(created, dict) or not _valid_id(created.get("session_id")):
            return {"ok": False, "state": "failed", "error": "invalid_session_response"}
        session_id = created["session_id"]
        ids = {"session_id": session_id}
        if _valid_id(created.get("stored_session_id")):
            ids["stored_session_id"] = created["stored_session_id"]
        submitted = await transport.request("prompt.submit", {"session_id": session_id, "text": text})
        if not isinstance(submitted, dict) or not (
                submitted.get("status") == "streaming"
                or _valid_id(submitted.get("task_id"))):
            return {"ok": False, "state": "delivery-uncertain", "error": "invalid_submit_response", **ids}
        if _valid_id(submitted.get("task_id")):
            ids["task_id"] = submitted["task_id"]
        return {"ok": True, "state": "submitted", **ids}
    except RpcRejected:
        return {"ok": False, "state": "failed", "error": "rpc_rejected", **locals().get("ids", {})}
    except HermesTransportError:
        sent = bool(getattr(locals().get("transport"), "prompt_sent", False))
        state = "delivery-uncertain" if sent else "failed"
        return {"ok": False, "state": state, "error": "gateway_unavailable", **locals().get("ids", {})}

def main() -> int:
    try:
        payload = json.loads(sys.stdin.readline())
        result = asyncio.run(run(payload))
    except HermesTransportError:
        result = {"ok": False, "error": "gateway_unavailable"}
    except (OSError, RuntimeError, TypeError, ValueError, json.JSONDecodeError):
        result = {"ok": False, "error": "delegation_failed"}
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
