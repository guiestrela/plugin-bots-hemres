# Hermes Bots

**Hermes Bots** is an alpha/prototype Omarchy `bar-widget` for a future,
panel-only interface to Hermes bots. It is designed for the Quickshell-based
Omarchy shell and the Glass Bar ecosystem, but it does not currently connect to
Hermes or send tasks.

The project deliberately keeps the current bar entry point inert. The runtime
RPC path, service lifecycle, and end-to-end Hermes behavior have not been
verified. There is no automatic activation, no automatic task submission, and
no fallback to a terminal or launcher.

## Status

**Alpha / prototype — not integrated.**

The repository contains an isolated QML harness and an offline Python adapter
fixture for contract-oriented tests. `ui/Main.qml` is a standalone
`ApplicationWindow` harness, not a bar-widget entry point. `BarWidget.qml` is a
minimal compatibility wrapper that renders a compact, non-interactive marker
and explicitly does not open a panel or use RPC.

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

## Installation (future, after explicit approval)

Do **not** install or enable this prototype in the active shell yet. It has not
been approved for activation and its RPC runtime is unsupported.

After the integration contract, runtime bridge, rollback plan, and coexistence
with Glass Bar and Hermes Deck have been reviewed, an operator may use the
standard Omarchy plugin workflow for the reviewed repository, for example:

```sh
omarchy plugin add <reviewed-repository-url>
omarchy plugin enable io.github.guiestrela.hermes-bots
```

Those commands are documentation for a future, separately authorized change;
they were not run for this task. Installation must not be treated as proof of
RPC support. Do not edit `~/.config/omarchy`, Glass Bar, Hermes Deck, the
Hermes gateway, or credentials as part of development or validation.

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
- explicit `openChat` and `delegateTask` `unsupported` responses;
- protection against prompt or secret leakage in responses.

Passing these tests does **not** validate the Hermes RPC runtime, a live
Quickshell host, Glass Bar's service bridge, panel focus/layer-shell behavior,
streaming, approvals, or real task delivery.

## Architecture

The intended future shape is:

```text
Glass Bar / Omarchy shell
        |
        v
BarWidget.qml (compact trigger)
        |
        v
Panel-only QML UI (future)
        |
        v
Allowlisted local adapter (future)
        |
        v
Hermes Gateway / runtime (not verified)
```

The proposed RPC boundary is documented in `docs/rpc-contract.md`. The QML
surface must not receive shell commands, profile paths, history, tokens, or
credentials. The adapter, once separately implemented and verified, must own
transport, allowlists, validation, redaction, correlation, and uncertainty
handling.

The UI discovery and host findings are recorded in `docs/ui-discovery.md`.
They document Quickshell/Omarchy behavior, Glass Bar compatibility concerns,
panel-only requirements, and the distinction between documented protocol
methods and a verified runtime.

## Security

- This plugin is QML code running in the desktop shell process; it is not a
  security sandbox.
- No credentials, Hermes profiles, gateway tokens, or private history are read
  by the bar wrapper.
- No shell command, subprocess, network endpoint, or RPC call is started by
  `BarWidget.qml`.
- Future task text must remain structured data, must not be placed in shell
  argv or logs, and must require explicit user confirmation.
- Secrets and sudo requests must never be captured by the panel.
- Plugin IDs and entry points must remain relative, validated, and non-
  conflicting with existing Omarchy plugins.

## Limitations

- The current bar widget is intentionally inert and has no panel yet.
- Hermes runtime RPC and end-to-end task submission are **unsupported** because
  they have not been verified.
- `openChat`, streaming, approvals, clarify flows, cancellation, and completion
  tracking are not implemented.
- The offline adapter fixture is not a live Hermes adapter.
- The standalone QML harness is not the bar entry point and does not prove live
  layer-shell, theme, multi-monitor, focus, AT-SPI, or Glass Bar behavior.
- No automatic activation or task submission occurs.

## Roadmap

1. Review and freeze the PBH RPC contract and security boundary.
2. Implement a panel-only QML surface with explicit loading, empty, error,
   unsupported, and delivery-uncertain states.
3. Implement a minimal allowlisted local adapter without exposing credentials
   or arbitrary Hermes methods.
4. Verify the RPC runtime offline first, then perform separately authorized
   integration tests with a non-sensitive fixture.
5. Test coexistence with Glass Bar and Hermes Deck without duplicate services or
   automatic sends.
6. Only after review, enable installation with a documented rollback path.

Until those steps are complete, this repository is a prototype manifest and an
inert bar-widget entry point, not a finished Hermes integration.

## License

MIT. See the repository license file when distributed as a complete project.
