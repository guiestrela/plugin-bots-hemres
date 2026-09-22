#!/usr/bin/env python3
"""Allowlisted read-only bridge for the Hermes Bots service."""
from __future__ import annotations

import argparse
import asyncio
import json
from pathlib import Path
import sys
from typing import Any
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from adapter.hermes_ws import (
    HermesTransportError,
    HermesWebSocketTransport,
    validate_gateway_url,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--url", default="")
    parser.add_argument("--profile", default="")
    parser.add_argument("--asset", default="avatar")
    return parser.parse_args()


def local_gateway_urls() -> list[str]:
    """Return candidate loopback WebSocket URLs from kernel listener data."""
    urls = []
    try:
        lines = Path("/proc/net/tcp").read_text(encoding="ascii").splitlines()[1:]
        for line in lines:
            fields = line.split()
            if len(fields) < 4 or fields[1].split(":", 1)[0] != "0100007F" or fields[3] != "0A":
                continue
            port = int(fields[1].split(":", 1)[1], 16)
            if 1 <= port <= 65535:
                urls.append(f"ws://127.0.0.1:{port}/api/ws")
    except (OSError, ValueError, UnicodeError):
        return []
    return sorted(set(urls), key=lambda value: int(urlsplit(value).port or 0))


async def discover_gateway() -> tuple[str, dict[str, Any]]:
    for url in local_gateway_urls():
        try:
            response = await run_url(url)
            if isinstance(response, dict) and isinstance(response.get("profiles"), list):
                return url, response
        except Exception:
            continue
    raise HermesTransportError("Hermes gateway unavailable.")


async def run_url(url: str) -> dict[str, Any]:
    validate_gateway_url(url)
    transport = HermesWebSocketTransport(url, timeout=2.0)
    result = await transport.list_profiles()
    if not isinstance(result, dict):
        raise HermesTransportError("Hermes response is invalid.")
    return result


async def run(args: argparse.Namespace) -> dict[str, Any]:
    try:
        url = args.url
        if not url:
            url, result = await discover_gateway()
        else:
            try:
                validate_gateway_url(url)
                result = await run_url(url)
            except Exception:
                url, result = await discover_gateway()
        # Allowlist: profiles.list and profiles.get_asset only.
        if args.profile:
            transport = HermesWebSocketTransport(url)
            result = await transport.get_asset(args.profile, args.asset)
            return {"ok": True, "kind": "avatar", "profile": args.profile, "asset": result, "gateway_url": url}
        profiles = result.get("profiles")
        if not isinstance(profiles, list):
            return {"ok": False, "error": "invalid_response"}
        return {"ok": True, "kind": "profiles", "profiles": profiles, "gateway_url": url}
    except HermesTransportError:
        return {"ok": False, "error": "gateway_unavailable"}
    except (OSError, RuntimeError, TypeError, ValueError):
        return {"ok": False, "error": "gateway_unavailable"}


def main() -> int:
    args = parse_args()
    try:
        result = asyncio.run(run(args))
        print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    except Exception:
        print(json.dumps({"ok": False, "error": "bridge_failed"}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
