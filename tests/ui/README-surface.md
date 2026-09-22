# PBH-014A — isolated surface regression

Run from the repository root. Requires the installed Qt6 Quickshell and
`/usr/share/omarchy/shell/{Ui,Commons}`. Python uses only its standard library.
The harness uses the **real host** PopupCard, WidgetButton and BarWidget, with a
minimal synthetic bar coordinator. It does not instantiate the live shell.
Gateway URL stays empty, shell/service stay null, no backend is contacted.
A live local Hermes gateway must not leak real profiles into the fixture: the
widget is created with `autoRefreshRoster: false` and the synthetic
`rosterProfiles` injected above override the network subjects by design.

```sh
# RED: read the old QML into a temporary harness (expected exit 1)
PBH_BASELINE_REF=0a103c0 PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/ui -p test_surface.py -v
# GREEN: current working tree (expected exit 0)
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/ui -v
qmllint BarWidget.qml ui/BotPanel.qml ui/service.qml
git diff --check
```

Observed RED before production changes (also reproduced from 0a103c0):
- host trigger opens panel: PASS
- independent window: FAIL; bar height 26, panel window height 26
- complete synthetic rows: FAIL; list height 24, rows height 72 at y=0/80
- delegation disabled and both close paths: PASS
- `PBH_RESULT 2`

Observed GREEN:
- independent window: PASS; bar height 26, panel window height 397
- complete synthetic rows: PASS; list height 152, rows height 72 at y=0/80
- trigger opens, trigger closes after animation, native close synchronizes owner: PASS
- delegation starts idle: PASS; empty input rejected at click time
- `PBH_RESULT 0`; full suite 59 tests OK (adapter 29, delegate+service 12, UI 18)
- qmllint and diff check: exit 0

Rows are visibly named `SYNTHETIC A/B — not a real bot`; they are not evidence
of a connected roster. Tests invoke the host's `triggerPress(Qt.LeftButton)`
route, not a desktop mouse click. Offscreen warnings about window masks,
wl_display and HyprlandFocusGrab are expected: outside-click dismissal,
compositor placement, real focus/keyboard routing, multiple monitors and the
active bar are **not** verified. The native `close()` lifecycle is verified.
GTK platform theme must be disabled for offscreen; the runner does this.
Temporary files are cleaned; Quickshell keeps its normal per-run logs.

The SVG is a vector tracing of the supplied 40x25 reference: mint `#c9dbcb`,
dark `#0a130b`, polygon head and two slanted eyes, transparent background.
Reference background is deliberately excluded. Palette/shape contract test
is not a pixel-identical raster comparison or user visual approval.
No transport, manifest, installation, configuration, credential or gateway
changes are included. No send/stream/approval capability has been enabled.
