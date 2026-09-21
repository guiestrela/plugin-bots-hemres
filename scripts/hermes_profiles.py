#!/usr/bin/env python3
"""Allowlisted read-only bridge for the Hermes Bots service."""
from __future__ import annotations

import argparse
import asyncio
import json
from pathlib import Path
import sys
from typing import Any

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


async def run(args: argparse.Namespace) -> dict[str, Any]:
    if not args.url:
        return {"ok": False, "error": "configuration_required"}
    try:
        validate_gateway_url(args.url)
        transport = HermesWebSocketTransport(args.url)
        # Allowlist: profiles.list and profiles.get_asset only.
        if args.profile:
            result = await transport.get_asset(args.profile, args.asset)
            return {"ok": True, "kind": "avatar", "profile": args.profile, "asset": result}
        result = await transport.list_profiles()
        profiles = result.get("profiles")
        if not isinstance(profiles, list):
            return {"ok": False, "error": "invalid_response"}
        return {"ok": True, "kind": "profiles", "profiles": profiles}
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
