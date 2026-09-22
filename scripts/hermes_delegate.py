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

from adapter.hermes_ws import HermesTransportError, HermesWebSocketTransport, validate_gateway_url

async def run(payload: dict[str, Any]) -> dict[str, Any]:
    url = payload.get("url")
    profile = payload.get("profile")
    text = payload.get("text")
    if (not isinstance(url, str) or not isinstance(profile, str) or not isinstance(text, str)
            or not url or not profile or not text.strip() or "\x00" in text):
        return {"ok": False, "error": "invalid_request"}
    validate_gateway_url(url)
    transport = HermesWebSocketTransport(url)
    created = await transport.request("session.create", {"profile": profile, "source": "hermes-bots-plugin"})
    if not isinstance(created, dict) or not isinstance(created.get("session_id"), str):
        return {"ok": False, "error": "invalid_session_response"}
    session_id = created["session_id"]
    submitted = await transport.request("prompt.submit", {"session_id": session_id, "text": text})
    return {"ok": True, "session_id": session_id, "submitted": submitted if isinstance(submitted, dict) else {}}

def main() -> int:
    try:
        payload = json.loads(sys.stdin.read())
        result = asyncio.run(run(payload))
    except HermesTransportError:
        result = {"ok": False, "error": "gateway_unavailable"}
    except (OSError, RuntimeError, TypeError, ValueError, json.JSONDecodeError):
        result = {"ok": False, "error": "delegation_failed"}
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
