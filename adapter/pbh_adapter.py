"""Offline PBH v1 adapter fixture.

This module deliberately has no Hermes or subprocess integration. It validates the
QML-facing contract and returns safe fixture data until the RPC runtime is verified.
"""

from __future__ import annotations

from dataclasses import dataclass
import json
import re
from typing import Any, Iterable


PROTOCOL_VERSION = 1
MAX_LINE_BYTES = 4 * 1024 * 1024
MAX_TEXT_BYTES = 16 * 1024
MAX_ID_BYTES = 128
MAX_JSON_DEPTH = 64
_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$")
_FORBIDDEN_KEYS = {
    "command", "executable", "argv", "cwd", "path", "url", "token",
    "script", "method", "shell", "env", "secret", "password", "credential",
}


@dataclass(frozen=True)
class RosterBot:
    id: str
    display_name: str
    role: str = ""
    avatar_kind: str = "image"


class FixtureRoster:
    """Explicit in-memory roster; it never reads Hermes profiles or private files."""

    def __init__(self, bots: Iterable[RosterBot]):
        self._bots = tuple(bots)
        self._by_id = {bot.id: bot for bot in self._bots}

    def all(self) -> tuple[RosterBot, ...]:
        return self._bots

    def get(self, bot_id: str) -> RosterBot | None:
        return self._by_id.get(bot_id)


class PBHAdapter:
    def __init__(self, roster: FixtureRoster):
        self._roster = roster
        self._seen: set[tuple[str, str]] = set()

    def handle_line(self, raw: bytes) -> dict[str, Any]:
        if len(raw) > MAX_LINE_BYTES:
            return self._error("", "LIMIT_EXCEEDED", "Envelope excede o limite.", False)
        try:
            text = raw.decode("utf-8")
            envelope = json.loads(text)
        except (UnicodeDecodeError, json.JSONDecodeError, RecursionError):
            return self._error("", "INVALID_REQUEST", "Envelope inválido.", False)
        return self.handle(envelope)

    def handle(self, envelope: Any) -> dict[str, Any]:
        if not self._within_depth(envelope):
            return self._error("", "INVALID_REQUEST", "Envelope inválido.", False)
        if not isinstance(envelope, dict):
            return self._error("", "INVALID_REQUEST", "Envelope inválido.", False)
        request_id = envelope.get("requestId", "")
        safe_request_id = request_id if self._valid_id(request_id) else ""
        version = envelope.get("version")
        if type(version) is not int or version != PROTOCOL_VERSION:
            code = "UNSUPPORTED_VERSION" if "version" in envelope else "INVALID_REQUEST"
            return self._error(safe_request_id, code, "Versão do protocolo não suportada.", False)
        if not self._valid_id(request_id):
            return self._error("", "INVALID_REQUEST", "requestId inválido.", False)
        operation = envelope.get("operation")
        if not isinstance(operation, str) or operation not in {
            "listBots", "getAvatar", "openChat", "delegateTask"
        }:
            return self._error(request_id, "INVALID_REQUEST", "Operação não permitida.", False)
        params = envelope.get("params", {})
        if not isinstance(params, dict) or self._has_forbidden_key(envelope):
            return self._error(request_id, "INVALID_REQUEST", "Parâmetros inválidos.", False)
        if (operation, request_id) in self._seen:
            return self._error(request_id, "DUPLICATE_REQUEST", "Pedido duplicado.", False)
        self._seen.add((operation, request_id))

        if operation == "listBots":
            if params:
                return self._error(request_id, "INVALID_REQUEST", "Parâmetros inválidos.", False)
            result = {"bots": [self._bot_view(bot) for bot in self._roster.all()],
                      "source": "fixture", "stale": False, "warnings": []}
            return self._success(request_id, result)
        if operation == "getAvatar":
            return self._get_avatar(request_id, params)
        if operation == "openChat":
            if not self._valid_bot_param(params):
                return self._error(request_id, "INVALID_BOT_ID", "Identificador de bot inválido.", False)
            if self._roster.get(params["botId"]) is None:
                return self._error(request_id, "BOT_NOT_FOUND", "Bot não encontrado.", False)
            return self._success(request_id, {"state": "unsupported", "reason": "PANEL_ONLY_V1"})
        return self._delegate(request_id, params)

    def _get_avatar(self, request_id: str, params: dict[str, Any]) -> dict[str, Any]:
        if not self._valid_bot_param(params):
            return self._error(request_id, "INVALID_BOT_ID", "Identificador de bot inválido.", False)
        if self._roster.get(params["botId"]) is None:
            return self._error(request_id, "BOT_NOT_FOUND", "Bot não encontrado.", False)
        return self._success(request_id, {
            "botId": params["botId"],
            "avatar": {"kind": "image", "ref": "fixture-avatar-" + params["botId"],
                       "mime": "image/png", "size": 0},
        })

    def _delegate(self, request_id: str, params: dict[str, Any]) -> dict[str, Any]:
        if not self._valid_bot_param(params):
            return self._error(request_id, "INVALID_BOT_ID", "Identificador de bot inválido.", False)
        if self._roster.get(params["botId"]) is None:
            return self._error(request_id, "BOT_NOT_FOUND", "Bot não encontrado.", False)
        text = params.get("text")
        if not isinstance(text, str) or not text or "\x00" in text:
            return self._error(request_id, "INVALID_REQUEST", "Texto inválido.", False)
        try:
            text_bytes = text.encode("utf-8")
        except UnicodeEncodeError:
            return self._error(request_id, "INVALID_REQUEST", "Texto inválido.", False)
        if len(text_bytes) > MAX_TEXT_BYTES:
            return self._error(request_id, "LIMIT_EXCEEDED", "Texto excede o limite.", False)
        # No prompt is sent and no confirmation boolean is trusted in this fixture.
        return self._success(request_id, {
            "state": "unsupported", "surface": "qml", "reason": "RPC_RUNTIME_UNVERIFIED"
        })

    @staticmethod
    def _valid_bot_param(params: dict[str, Any]) -> bool:
        return isinstance(params.get("botId"), str) and bool(_ID_RE.fullmatch(params["botId"]))

    @staticmethod
    def _valid_id(value: Any) -> bool:
        if not isinstance(value, str) or not value:
            return False
        try:
            if len(value.encode("utf-8")) > MAX_ID_BYTES:
                return False
        except UnicodeEncodeError:
            return False
        return bool(_ID_RE.fullmatch(value))

    @staticmethod
    def _within_depth(value: Any) -> bool:
        stack = [(value, 1)]
        while stack:
            current, depth = stack.pop()
            if depth > MAX_JSON_DEPTH:
                return False
            if isinstance(current, dict):
                stack.extend((item, depth + 1) for item in current.values())
            elif isinstance(current, list):
                stack.extend((item, depth + 1) for item in current)
        return True

    @classmethod
    def _has_forbidden_key(cls, value: Any) -> bool:
        if isinstance(value, dict):
            return any(key in _FORBIDDEN_KEYS or cls._has_forbidden_key(item) for key, item in value.items())
        if isinstance(value, list):
            return any(cls._has_forbidden_key(item) for item in value)
        return False

    @staticmethod
    def _bot_view(bot: RosterBot) -> dict[str, Any]:
        return {
            "id": bot.id,
            "source": "fixture",
            "displayName": _safe_text(bot.display_name, bot.id),
            "role": _safe_text(bot.role, ""),
            "avatar": {"kind": bot.avatar_kind, "ref": "fixture-avatar-" + bot.id,
                       "label": "Avatar de " + _safe_text(bot.display_name, bot.id)},
            "capabilities": {"openChat": False, "delegateTask": "unsupported",
                             "streaming": "unsupported", "approval": "unsupported",
                             "trackCompletion": "unsupported"},
            "availability": "unknown", "hidden": False,
        }

    @staticmethod
    def _success(request_id: str, result: dict[str, Any]) -> dict[str, Any]:
        return {"version": PROTOCOL_VERSION, "requestId": request_id, "ok": True, "result": result}

    @staticmethod
    def _error(request_id: str, code: str, message: str, retryable: bool) -> dict[str, Any]:
        return {"version": PROTOCOL_VERSION, "requestId": request_id, "ok": False,
                "error": {"code": code, "message": _safe_text(message, "Erro."), "retryable": retryable}}


def _safe_text(value: Any, fallback: str) -> str:
    if not isinstance(value, str):
        return fallback
    clean = "".join(char for char in value if char in "\n\t" or ord(char) >= 0x20)
    clean = clean.strip()
    return clean[:256] or fallback
