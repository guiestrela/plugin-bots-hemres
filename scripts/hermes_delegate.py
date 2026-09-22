#!/usr/bin/env python3
"""Explicit panel action bridge: create a session and submit one user task."""
from __future__ import annotations
import asyncio
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

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

    async def _connect_context(self):
        connect = self._connect
        if connect is None:
            try:
                from websockets import connect as connect
            except ImportError as exc:  # pragma: no cover - environment dependent
                raise HermesTransportError(
                    "WebSocket support is unavailable; install websockets to enable Hermes transport."
                ) from exc
        return connect(
            _with_token(self.url, self._session_token) if self._session_token else self.url,
            open_timeout=self.timeout, close_timeout=1.0, max_size=_MAX_MESSAGE_BYTES,
        )

    async def submit_and_wait(self, profile: str, text: str) -> dict[str, Any]:
        """Create, submit, and observe one turn on the same live socket."""
        create_id, submit_id = 1, 2
        create = {"jsonrpc": "2.0", "id": create_id, "method": "session.create",
                  "params": {"profile": profile, "source": "hermes-bots-plugin", "close_on_disconnect": False}}
        created = None
        acked = False
        submitted = {"ok": False, "state": "delivery-uncertain"}
        async with await self._connect_context() as socket:
            await asyncio.wait_for(socket.recv(), timeout=self.timeout)
            await socket.send(json.dumps(create, ensure_ascii=False, separators=(",", ":")) + "\\n")
            while True:
                message = await asyncio.wait_for(socket.recv(), timeout=self.timeout)
                if isinstance(message, bytes):
                    message = message.decode("utf-8")
                if not isinstance(message, str):
                    raise HermesTransportError("Invalid response")
                for line in message.splitlines():
                    if not line.strip():
                        continue
                    response = self._decode_response(line)
                    if response.get("id") == create_id:
                        if "error" in response or not isinstance(response.get("result"), dict):
                            raise RpcRejected("RPC rejected")
                        created = response["result"]
                        session_id = created.get("session_id")
                        if not _valid_id(session_id):
                            raise HermesTransportError("Invalid session response")
                        submit = {"jsonrpc": "2.0", "id": submit_id, "method": "prompt.submit",
                                  "params": {"session_id": session_id, "text": text}}
                        await socket.send(json.dumps(submit, ensure_ascii=False, separators=(",", ":")) + "\\n")
                    elif response.get("id") == submit_id:
                        if "error" in response:
                            return {"ok": False, "state": "failed", "error": "rpc_rejected", "session_id": created["session_id"]}
                        if isinstance(response.get("result"), dict) and response["result"].get("status") == "streaming":
                            acked = True
                            submitted = {"ok": True, "state": "submitted", "session_id": created["session_id"]}
                    elif isinstance(response.get("method"), str):
                        params = response.get("params") if isinstance(response.get("params"), dict) else {}
                        if params.get("session_id") != (created or {}).get("session_id"):
                            continue
                        method = response["method"]
                        if method == "message.complete":
                            payload = params.get("payload") if isinstance(params.get("payload"), dict) else params
                            failed = payload.get("status") == "error"
                            result = dict(submitted)
                            result["ok"] = not failed
                            result["state"] = "failed" if failed else "completed"
                            if isinstance(payload.get("text"), str):
                                result["completion"] = payload["text"][:_MAX_MESSAGE_BYTES]
                            return result
                        if method == "session.info":
                            payload = params.get("payload") if isinstance(params.get("payload"), dict) else params
                            if payload.get("running") is False and acked:
                                result = dict(submitted)
                                result["state"] = "completed"
                                return result

    async def _request_once(self, request_id: int, request: dict[str, Any]) -> Any:
        wire = json.dumps(request, ensure_ascii=False, separators=(",", ":")) + "\n"
        connect = self._connect
        if connect is None:
            try:
                from websockets import connect as connect
            except ImportError as exc:  # pragma: no cover - environment dependent
                raise HermesTransportError(
                    "WebSocket support is unavailable; install websockets to enable Hermes transport."
                ) from exc
        async with connect(
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




def run_canonical_chat(profile: str, text: str) -> dict[str, Any]:
    """Use Hermes' canonical Bot Chat, matching the Desktop Bot Mode path."""
    fd, query_path = tempfile.mkstemp(prefix="hermes-bots-", suffix=".txt")
    try:
        with open(fd, "w", encoding="utf-8", closefd=True) as stream:
            stream.write(text)
        hermes = shutil.which("hermes") or "/home/guiestrela/.hermes/hermes-agent/venv/bin/hermes"
        command = [hermes]
        if profile != "default":
            command += ["-p", profile]
        command += ["chat", "--in", str(Path.home()), "-c", "Bot Chat",
                    "--create-if-missing", "-Q", "--query-file", query_path]
        completed = subprocess.run(command, capture_output=True, text=True,
                                   timeout=120, cwd=str(Path.home()))
        output = (completed.stdout or "").strip()
        if completed.returncode != 0:
            return {"ok": False, "state": "failed", "error": "bot_execution_failed"}
        result = {"ok": True, "state": "completed"}
        if output:
            result["completion"] = output[-_MAX_MESSAGE_BYTES:]
        return result
    except subprocess.TimeoutExpired:
        return {"ok": False, "state": "delivery-uncertain", "error": "bot_timeout"}
    except (OSError, ValueError):
        return {"ok": False, "state": "failed", "error": "bot_unavailable"}
    finally:
        try:
            Path(query_path).unlink()
        except OSError:
            pass


async def run(payload: Any) -> dict[str, Any]:
    invalid = {"ok": False, "state": "failed", "error": "invalid_request"}
    if not isinstance(payload, dict):
        return invalid
    url, profile, text = (payload.get(key) for key in ("url", "profile", "text"))
    canonical = payload.get("transport") == "canonical-chat"
    try:
        if not canonical:
            validate_gateway_url(url)
        _validate_text(text)
        if not _valid_id(profile) or not text.strip():
            return invalid
    except (HermesTransportError, ValueError):
        return invalid
    if canonical:
        return run_canonical_chat(profile, text)
    try:
        transport = HermesWebSocketTransport(url)
        if payload.get("wait_for_completion") is True:
            result = await transport.submit_and_wait(profile, text)
            return result
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
