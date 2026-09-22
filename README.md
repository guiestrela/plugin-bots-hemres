# Hermes Bots

**Hermes Bots** is an alpha Omarchy service/bar widget for a Hermes bot roster
and explicit task delegation. It is designed for the Quickshell-based Omarchy
shell and the Glass Bar ecosystem. It connects only to an explicitly configured
local Hermes gateway, discovering its active loopback port automatically when
the configured port is unavailable.

The bar entry point opens a bot panel with loading, error, empty, roster,
selection, avatar-placeholder, and task-submission states. There is no automatic
gateway activation and no fallback to a terminal or launcher.

## Status

**Alpha — live roster and one-shot task submission enabled.**

The repository contains an isolated QML harness, an offline adapter fixture,
and a live WebSocket adapter. `ui/Main.qml` remains a standalone
`ApplicationWindow` harness, while `BarWidget.qml` is the compact panel trigger.
`Service.qml` invokes the allowlisted roster helper and exposes the result to
the panel.

Hermes Deck is an existing, separate Omarchy plugin. This plugin uses the
non-conflicting ID `io.github.guiestrela.hermes-bots` and must not replace,
modify, or assume the behavior of Hermes Deck.

## Requirements

- Omarchy with its Quickshell-based shell and plugin manifest support.
- Glass Bar, if the user chooses to host third-party widgets in that bar.
- Qt Quick/QML tooling for local checks (`qmllint`; `qmlscene6` may be useful
  for the isolated harness).
- Python 3 for the offline adapter tests.

The current repository was designed around Omarchy/Quickshell conventions. It
is not a Waybar plugin.

## Installation

The reviewed plugin can be installed with the standard Omarchy workflow:

```sh
omarchy plugin add https://github.com/guiestrela/plugin-bots-hemres.git --yes
omarchy plugin enable io.github.guiestrela.hermes-bots
```

The widget can use a loopback URL as a preference, but this is optional. If the
configured port is stale or unavailable, active local Hermes gateways are
discovered automatically:

```sh
omarchy bar set io.github.guiestrela.hermes-bots gatewayUrl \
  ws://127.0.0.1:9119/api/ws
```

The Hermes gateway must already be running locally; the plugin does not start
it. The Python environment used by the widget must provide `websockets`.

## Development

Work from the repository checkout:

```sh
cd "/home/guiestrela/Work/Plugin Bots Hemres"

# Validate the manifest without installing or enabling the plugin.
omarchy plugin validate .

# Lint the bar entry point.
qmllint BarWidget.qml

# Run the available offline adapter and UI harness tests.
python3 -m unittest -v tests/adapter/test_pbh_adapter.py tests/ui/test_harness.py
```

`ui/Main.qml` can be exercised separately as an isolated harness when Qt Quick
Controls are available. It contains local fixture data only; it does not prove
layer-shell behavior, Glass Bar loading, Hermes connectivity, or accessibility
support in a live shell.

## Validation and tests

The manifest follows schema version 1 and the Glass Bar/Omarchy conventions:
`bar-widget` is declared in `kinds`, `entryPoints.barWidget` points to the
existing `BarWidget.qml`, and the widget metadata provides a display name,
category, placement, and non-multiple-instance policy.

The available real tests cover the offline adapter contract, including:

- roster and avatar fixture responses;
- request envelope and size-limit validation;
- stable bot IDs and sanitized errors;
- duplicate request handling;
- explicit task submission and delivery-uncertain states;
- protection against prompt or secret leakage in responses.

Passing these tests does **not** validate the Hermes RPC runtime, a live
Quickshell host, Glass Bar's service bridge, panel focus/layer-shell behavior,
streaming, approvals, or real task delivery.

## Architecture

The current integration shape is:

```text
Glass Bar / Omarchy shell
        |
        v
BarWidget.qml (compact trigger)
        |
        v
Panel-only QML UI
        |
        v
Allowlisted local adapter
        |
        v
Hermes Gateway / runtime
```

The proposed RPC boundary, UI discovery, and host findings are maintained
outside this repository as project working notes. The QML surface must not
receive shell commands, profile paths, history, tokens, or credentials. The
adapter, once separately implemented and verified, must own transport,
allowlists, validation, redaction, correlation, and uncertainty handling.

## Security

- This plugin is QML code running in the desktop shell process; it is not a
  security sandbox.
- No credentials, Hermes profiles, gateway tokens, or private history are read
  by the bar wrapper.
- Network access is limited to validated loopback Hermes WebSocket gateways.
- Future task text must remain structured data, must not be placed in shell
  argv or logs, and must require explicit user confirmation.
- Secrets and sudo requests must never be captured by the panel.
- Plugin IDs and entry points must remain relative, validated, and non-
  conflicting with existing Omarchy plugins.

## Limitations

- The current bar widget uses a one-shot task submission flow; completion
  streaming and approval UI are not implemented.
- `openChat`, streaming, approvals, clarify flows, cancellation, and completion
  tracking are not implemented.
- The offline adapter fixture is not a live Hermes adapter.
- The standalone QML harness is not the bar entry point and does not prove live
  layer-shell, theme, multi-monitor, focus, AT-SPI, or Glass Bar behavior.
- The plugin does not automatically start Hermes or submit tasks.

## Roadmap

1. Review and freeze the PBH RPC contract and security boundary.
2. Implemented a panel-only QML surface with explicit loading, empty, error,
   and roster states.
3. Implemented a minimal allowlisted local adapter without exposing credentials
   or arbitrary Hermes methods.
4. Verified the read-only roster path against a local gateway with six profiles.
5. Test coexistence with Glass Bar and Hermes Deck without duplicate services or
   automatic sends.
6. Only after review, enable installation with a documented rollback path.

Task submission, streaming, approvals, cancellation, and delivery uncertainty
remain blocked until their contracts and security tests are implemented.

## License

MIT. See the repository license file when distributed as a complete project.
