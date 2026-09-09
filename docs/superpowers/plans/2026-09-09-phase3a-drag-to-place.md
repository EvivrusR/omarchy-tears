# Desktop Widgets Phase 3a: Armed Drag-to-Place — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An explicitly armed "arrange" mode in which every widget shows a dashed frame and can be dragged with the mouse; dropping snaps it to the nearest corner and saves `corner`/`x`/`y` through the CLI. Disarmed (the default), nothing on the desktop is draggable.

**Architecture:** The service owns the arming state. While armed it mounts one full-screen `ArrangeOverlay` window per screen on the Top layer (above app windows) that draws frames at each widget's reported geometry and handles the drag. During a drag the overlay writes a *placement override* into the service, so the real widget window re-anchors live; on release the overlay saves the whole document via `desktop-widgets write` and clears the override. Widget windows themselves never take pointer input (`mask: Region {}`), so no drag can start when disarmed. Entry points: editor button, keybind, CLI `arrange`, IPC, and an optional bar companion icon that only appears while armed.

**Tech Stack:** Quickshell 0.3.1 (`PanelWindow`, `Region`, `Process` stdin), `QtQuick.Shapes` for dashed frames, `widgets/Arrange.js` (node-tested placement maths), existing CLI `write`.

**Spec:** `docs/ROADMAP.md` → "Phase 3 — Edit mode on the desktop — armed, never always-on" (Michael's constraint, 2026-09-09).

## Status (handoff block — update after every task)

**PHASE 3a COMPLETE 2026-09-09** except one human check: Michael to try a real mouse drag (SUPER+ALT+A, drag a frame, Esc). Remaining Phase 3: `template` widget type, drop-in types (DQ-025). Phase 4 (share) awaits go.

| Task | State | Commit | Notes |
|---|---|---|---|
| 1 Arrange.js maths + service arming/geometry/overrides + IPC + CLI `arrange` | done | c70e4ed | scripted drags verified; geometry-forget race fixed |
| 2 ArrangeOverlay: frames, drag, snap, save, Esc, idle disarm, hint strip | done | (prev commit) | scripted drag through the overlay path verified; **real mouse drag not yet tried by a human** |
| 3 Entry points: editor button, keybind, menu row, bar companion, docs, vault | done | 4aabf49 | companion needs a manual shell.json bar entry (Omarchy tooling quirk for mixed-kind plugins) |

**How to resume:** read this file and `docs/ROADMAP.md` Phase 3; run `node --test tests/*.test.js` and `python3 -m unittest discover -s tests -p 'test_*.py'`; continue at the first task not done. Code changes need `omarchy restart shell`. Arm from a terminal with `desktop-widgets arrange on`; watch `journalctl --user _COMM=quickshell -f | grep desktop-widgets`.

## Global Constraints

- Same as Phases 1–2. Additionally: **disarmed widget windows must have an empty input region** (`mask: Region {}`); arming must be explicit; arming state must never persist across a shell restart.
- Every position change is saved through `desktop-widgets write` (validated, `.bak`). No other writer.
- Coordinates are logical pixels of the output (`screen.width`/`screen.height`), the same space layer-shell margins use with `exclusionMode: Ignore`.

---

## File structure

| File | Responsibility |
|---|---|
| `widgets/Arrange.js` | pure: `rectFor(corner,x,y,w,h,sw,sh)`, `placeFor(rect,sw,sh)` (nearest corner + offsets), `moveRect(rect,dx,dy,sw,sh)` (clamped) |
| `tests/arrange.test.js` | node tests for the above |
| `Service.qml` | `arranging`, `setArranging()`, `geometries` (per window), `overrides` (live placement), `saveDoc(doc)`, `drag()` test hook, `IpcHandler { target: "desktop-widgets" }`; widget windows get `mask: Region {}` and read overrides; mounts `ArrangeOverlay` per screen while armed |
| `arrange/ArrangeOverlay.qml` | full-screen Top-layer window per screen: dashed frames + labels, drag handling, hint strip, Esc |
| `bin/desktop-widgets` | `arrange [on|off|toggle]` |
| `Editor.qml` | "Arrange on desktop" button |
| `Companion.qml` + `manifest.json` | optional bar widget, visible only while arming |
| `README.md`, vault guide | docs |

---

### Task 1: Placement maths, service state, IPC, CLI

**Files:** Create `widgets/Arrange.js`, `tests/arrange.test.js`; Modify `Service.qml`, `bin/desktop-widgets`, `tests/test_cli.py`.

**Interfaces:**
- `Arrange.rectFor(corner, x, y, w, h, sw, sh) -> {x,y,w,h}` (screen-space rect of a widget anchored at `corner` with margins `x`,`y`).
- `Arrange.placeFor(rect, sw, sh) -> {corner, x, y}` (nearest corner by rect centre; offsets clamped ≥ 0 and rounded).
- `Arrange.moveRect(rect, dx, dy, sw, sh) -> rect` (translated, clamped inside the screen).
- Service: `property bool arranging`; `function setArranging(on)`; `property var geometries` (`{key: {index, screen, rect}}`), `function reportGeometry(key, index, screenName, rect)`; `property var overrides` (`{key: {corner,x,y}}`), `function setOverride(key, place)`, `function clearOverride(key)`; `function saveDoc(doc, onDone)` running `desktop-widgets write`; `function drag(index, dx, dy)` test hook (uses the first geometry for that index); IPC target `desktop-widgets` with `arrange(state: string): string` (`on|off|toggle` → returns `on`/`off`) and `drag(index: string, dx: string, dy: string): string`.
- CLI: `arrange [on|off|toggle]` → `omarchy-shell desktop-widgets arrange <state>`.

- [ ] **Step 1: tests for Arrange.js** (`tests/arrange.test.js`)

```js
const test = require("node:test");
const assert = require("node:assert/strict");
const A = require("../widgets/Arrange.js");
const SW = 1920, SH = 1080;

test("rectFor anchors at each corner", () => {
  assert.deepEqual(A.rectFor("top-left", 10, 20, 100, 50, SW, SH), { x: 10, y: 20, w: 100, h: 50 });
  assert.deepEqual(A.rectFor("top-right", 10, 20, 100, 50, SW, SH), { x: 1810, y: 20, w: 100, h: 50 });
  assert.deepEqual(A.rectFor("bottom-left", 10, 20, 100, 50, SW, SH), { x: 10, y: 1010, w: 100, h: 50 });
  assert.deepEqual(A.rectFor("bottom-right", 10, 20, 100, 50, SW, SH), { x: 1810, y: 1010, w: 100, h: 50 });
});

test("placeFor picks the nearest corner by centre and round-trips offsets", () => {
  assert.deepEqual(A.placeFor({ x: 10, y: 20, w: 100, h: 50 }, SW, SH), { corner: "top-left", x: 10, y: 20 });
  assert.deepEqual(A.placeFor({ x: 1810, y: 1010, w: 100, h: 50 }, SW, SH), { corner: "bottom-right", x: 10, y: 20 });
  assert.deepEqual(A.placeFor({ x: 1200, y: 100, w: 100, h: 50 }, SW, SH), { corner: "top-right", x: 620, y: 100 });
  assert.deepEqual(A.placeFor({ x: 100.6, y: 900.2, w: 100, h: 50 }, SW, SH), { corner: "bottom-left", x: 101, y: 130 });
  for (const c of ["top-left", "top-right", "bottom-left", "bottom-right"]) {
    const r = A.rectFor(c, 33, 44, 200, 80, SW, SH);
    assert.deepEqual(A.placeFor(r, SW, SH), { corner: c, x: 33, y: 44 });
  }
});

test("placeFor never returns negative offsets", () => {
  assert.deepEqual(A.placeFor({ x: -30, y: -5, w: 100, h: 50 }, SW, SH), { corner: "top-left", x: 0, y: 0 });
});

test("moveRect translates and clamps to the screen", () => {
  assert.deepEqual(A.moveRect({ x: 10, y: 20, w: 100, h: 50 }, 5, -30, SW, SH), { x: 15, y: 0, w: 100, h: 50 });
  assert.deepEqual(A.moveRect({ x: 1800, y: 1000, w: 100, h: 50 }, 500, 500, SW, SH), { x: 1820, y: 1030, w: 100, h: 50 });
});
```

- [ ] **Step 2: run → fails (module missing).**

- [ ] **Step 3: Arrange.js**

```js
// Placement maths for arrange mode. Screen-space logical pixels; corners as
// in the registry. Shared by the overlay (QML) and node tests.
function rectFor(corner, x, y, w, h, sw, sh) {
  var right = String(corner).indexOf("right") !== -1
  var bottom = String(corner).indexOf("bottom") === 0
  return { x: right ? sw - x - w : x, y: bottom ? sh - y - h : y, w: w, h: h }
}

function placeFor(rect, sw, sh) {
  var cx = rect.x + rect.w / 2, cy = rect.y + rect.h / 2
  var right = cx > sw / 2, bottom = cy > sh / 2
  var corner = (bottom ? "bottom" : "top") + "-" + (right ? "right" : "left")
  var x = right ? sw - rect.x - rect.w : rect.x
  var y = bottom ? sh - rect.y - rect.h : rect.y
  return { corner: corner, x: Math.max(0, Math.round(x)), y: Math.max(0, Math.round(y)) }
}

function moveRect(rect, dx, dy, sw, sh) {
  var x = Math.min(Math.max(0, rect.x + dx), Math.max(0, sw - rect.w))
  var y = Math.min(Math.max(0, rect.y + dy), Math.max(0, sh - rect.h))
  return { x: x, y: y, w: rect.w, h: rect.h }
}

if (typeof module !== "undefined") module.exports = { rectFor, placeFor, moveRect }
```

- [ ] **Step 4: Service.qml changes**

Add after the registry properties:

```qml
  // ---- arrange mode (Phase 3a). Never persisted; false on every shell start.
  property bool arranging: false
  property var geometries: ({})   // key -> { index, screen, rect: {x,y,w,h} }
  property var overrides: ({})    // key -> { corner, x, y } applied live while dragging
  property double lastArrangeActivity: 0

  function setArranging(on) {
    var next = on === true
    if (next === arranging) return
    arranging = next
    lastArrangeActivity = Date.now()
    if (!next) overrides = ({})
    log("arrange mode " + (next ? "ON" : "off"))
  }
  function touchArrange() { lastArrangeActivity = Date.now() }
  function reportGeometry(key, index, screenName, rect) {
    var next = ({})
    for (var k in geometries) next[k] = geometries[k]
    next[key] = { index: index, screen: screenName, rect: rect }
    geometries = next
  }
  function forgetGeometry(key) {
    var next = ({})
    for (var k in geometries) if (k !== key) next[k] = geometries[k]
    geometries = next
  }
  function setOverride(key, place) {
    var next = ({})
    for (var k in overrides) next[k] = overrides[k]
    next[key] = place
    overrides = next
    touchArrange()
  }
  function clearOverride(key) {
    var next = ({})
    for (var k in overrides) if (k !== key) next[k] = overrides[k]
    overrides = next
  }

  // Save a whole document through the CLI (validated, .bak kept). onDone(ok, message).
  property var saveCallback: null
  function saveDoc(doc, onDone) {
    if (writer.running) { log("saveDoc: writer busy, dropped"); if (onDone) onDone(false, "busy"); return }
    saveCallback = onDone || null
    writer.pendingText = JSON.stringify({ version: 1, widgets: doc }, null, 2) + "\n"
    writer.running = true
  }
  Process {
    id: writer
    property string pendingText: ""
    command: [String(Qt.resolvedUrl("bin/desktop-widgets")).replace(/^file:\/\//, ""), "write"]
    stdinEnabled: true
    onStarted: { writer.write(writer.pendingText); writer.stdinEnabled = false }
    stderr: StdioCollector { id: writerErr }
    onExited: function(code) {
      writer.stdinEnabled = true
      var msg = String(writerErr.text || "").trim().split("\n")[0]
      if (code !== 0) root.log("write failed: " + msg)
      var cb = root.saveCallback; root.saveCallback = null
      if (cb) cb(code === 0, msg)
    }
  }

  // Place widget `index` from its current geometry moved by dx,dy and save —
  // the same path the overlay's drag uses, callable without a mouse.
  function drag(index, dx, dy) {
    var key = null
    for (var k in geometries) if (geometries[k].index === index) { key = k; break }
    if (key === null) return "no geometry for widget " + index
    var g = geometries[key]
    var screen = null
    for (var s = 0; s < Quickshell.screens.length; s++) if (Quickshell.screens[s].name === g.screen) screen = Quickshell.screens[s]
    if (!screen) return "screen gone"
    var rect = Arrange.moveRect(g.rect, dx, dy, screen.width, screen.height)
    var place = Arrange.placeFor(rect, screen.width, screen.height)
    return commitPlace(key, index, place)
  }
  function commitPlace(key, index, place) {
    setOverride(key, place)
    var doc = JSON.parse(JSON.stringify(rawWidgets))
    if (!doc[index]) return "no widget " + index
    doc[index].corner = place.corner; doc[index].x = place.x; doc[index].y = place.y
    saveDoc(doc, function(ok, msg) { if (ok) clearOverride(key) })
    return "ok " + place.corner + " " + place.x + "," + place.y
  }

  IpcHandler {
    target: "desktop-widgets"
    function arrange(state: string): string {
      var s = String(state || "toggle")
      root.setArranging(s === "on" ? true : s === "off" ? false : !root.arranging)
      return root.arranging ? "on" : "off"
    }
    function drag(index: string, dx: string, dy: string): string { return root.drag(Number(index), Number(dx), Number(dy)) }
    function state(): string { return JSON.stringify({ arranging: root.arranging, widgets: root.widgets.length, geometries: Object.keys(root.geometries).length, overrides: Object.keys(root.overrides).length }) }
  }
```

Add `import "widgets/Arrange.js" as Arrange` at the top. In the widget `PanelWindow` delegate: read overrides and report geometry, and block input:

```qml
      readonly property var override: root.overrides[modelData.key] || null
      readonly property string corner: String(override ? override.corner : (widget.corner || "top-right"))
      readonly property int offsetX: Number(override ? override.x : (widget.x !== undefined ? widget.x : 48))
      readonly property int offsetY: Number(override ? override.y : (widget.y !== undefined ? widget.y : 48))
      mask: Region {}   // never takes pointer input; arrange mode uses its own overlay
      function report() {
        if (!visible || implicitWidth <= 1 || implicitHeight <= 1) return
        root.reportGeometry(modelData.key, widget.__index, modelData.screen.name,
          Arrange.rectFor(corner, offsetX, offsetY, implicitWidth, implicitHeight, modelData.screen.width, modelData.screen.height))
      }
      onImplicitWidthChanged: report()
      onImplicitHeightChanged: report()
      onCornerChanged: report()
      onOffsetXChanged: report()
      onOffsetYChanged: report()
      onVisibleChanged: report()
      Component.onCompleted: report()
      Component.onDestruction: root.forgetGeometry(modelData.key)
```

(`mask: Region {}` — confirm the double-click on the desktop still opens the wallpaper switcher through a widget's area after this change; it should, since the region is empty.)

- [ ] **Step 5: CLI `arrange`** — add to `bin/desktop-widgets`:

```python
def cmd_arrange(args, ctx):
    """Arm/disarm drag-to-place in the running shell."""
    out = run_quiet(["omarchy-shell", "desktop-widgets", "arrange", args.state])
    print(out.strip() or "no answer from the shell (plugin enabled?)")
    return 0 if out.strip() in ("on", "off") else 2
```
parser: `ar = sub.add_parser("arrange", help="arm/disarm drag-to-place on the desktop"); ar.add_argument("state", nargs="?", default="toggle", choices=["on","off","toggle"]); ar.set_defaults(fn=cmd_arrange)`.
Test (`tests/test_cli.py`): monkeypatch `dw.run_quiet` to return `"on\n"` and assert exit 0 and output `on`; return `""` → exit 2.

- [ ] **Step 6: Live check**: restart shell; `desktop-widgets arrange on` prints `on`, journal `arrange mode ON`; `omarchy-shell desktop-widgets state` shows 4 geometries; `omarchy-shell desktop-widgets drag 0 -200 0` moves the clock left by 200 px and the file's clock entry changes (`desktop-widgets list`); `.bak` present; drag it back; double-click on the desktop still opens the wallpaper switcher (Michael to confirm, or trust `mask`). `desktop-widgets arrange off`.

- [ ] **Step 7: Commit** `"Arrange mode: placement maths, service arming/geometry/overrides, IPC target, CLI arrange"`; update Status.

---

### Task 2: ArrangeOverlay

**Files:** Create `arrange/ArrangeOverlay.qml`; Modify `Service.qml` (mount overlays while arranging).

**Interfaces:** `ArrangeOverlay { required property var service; required property var screen }` — reads `service.geometries`, calls `service.setOverride`, `service.commitPlace`, `service.setArranging(false)`, `service.touchArrange`.

- [ ] **Step 1: overlay**

```qml
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "../widgets/Arrange.js" as Arrange

PanelWindow {
  id: win
  required property var service
  required property var screenRef
  screen: screenRef
  visible: service.arranging
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  WlrLayershell.namespace: "homelab-desktop-widgets-arrange"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  exclusionMode: ExclusionMode.Ignore

  readonly property var frames: {
    var out = []
    var g = service.geometries
    for (var k in g) if (g[k].screen === screenRef.name) out.push({ key: k, index: g[k].index, rect: g[k].rect })
    return out
  }
  property var drag: null   // { key, index, startRect, pressX, pressY, rect }

  function frameAt(px, py) {
    for (var i = frames.length - 1; i >= 0; i--) {
      var r = frames[i].rect
      if (px >= r.x && px <= r.x + r.w && py >= r.y && py <= r.y + r.h) return frames[i]
    }
    return null
  }

  Item {
    anchors.fill: parent
    focus: true
    Keys.onPressed: function(e) { if (e.key === Qt.Key_Escape || e.key === Qt.Key_Return) { win.service.setArranging(false); e.accepted = true } }
  }

  Repeater {
    model: win.frames
    delegate: Item {
      required property var modelData
      readonly property bool active: win.drag && win.drag.key === modelData.key
      x: active ? win.drag.rect.x : modelData.rect.x
      y: active ? win.drag.rect.y : modelData.rect.y
      width: modelData.rect.w; height: modelData.rect.h
      Rectangle { anchors.fill: parent; color: Util.alpha(Color.accent, active ? 0.18 : 0.08); radius: Style.cornerRadius }
      Shape {
        anchors.fill: parent
        ShapePath {
          strokeColor: Color.accent; strokeWidth: 2; fillColor: "transparent"
          strokeStyle: ShapePath.DashLine; dashPattern: [4, 3]
          startX: 1; startY: 1
          PathLine { x: width - 1; y: 1 } PathLine { x: width - 1; y: height - 1 } PathLine { x: 1; y: height - 1 } PathLine { x: 1; y: 1 }
        }
      }
      Text {
        anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Style.space(4)
        text: "#" + modelData.index + " · " + String(win.service.widgets.filter(function(w) { return w.__index === modelData.index })[0]?.type || "")
        color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.caption
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: win.drag ? Qt.ClosedHandCursor : (win.frameAt(mouseX, mouseY) ? Qt.OpenHandCursor : Qt.ArrowCursor)
    hoverEnabled: true
    onPressed: function(m) {
      var f = win.frameAt(m.x, m.y)
      if (!f) return
      win.drag = { key: f.key, index: f.index, startRect: f.rect, pressX: m.x, pressY: m.y, rect: f.rect }
      win.service.touchArrange()
    }
    onPositionChanged: function(m) {
      if (!win.drag) return
      var rect = Arrange.moveRect(win.drag.startRect, m.x - win.drag.pressX, m.y - win.drag.pressY, win.width, win.height)
      var d = win.drag; d.rect = rect; win.drag = d
      win.service.setOverride(d.key, Arrange.placeFor(rect, win.width, win.height))
    }
    onReleased: function(m) {
      if (!win.drag) return
      var d = win.drag; win.drag = null
      win.service.commitPlace(d.key, d.index, Arrange.placeFor(d.rect, win.width, win.height))
    }
  }

  Rectangle {   // hint strip
    anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(24)
    width: hint.implicitWidth + Style.space(28); height: hint.implicitHeight + Style.space(14)
    radius: Style.cornerRadius; color: Color.popups.background; border.width: 1; border.color: Color.popups.border
    Text { id: hint; anchors.centerIn: parent; text: "Arrange mode — drag a widget, it snaps to the nearest corner · Esc or Enter to finish"; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body }
  }
}
```

Note: the geometry a moving widget reports during the drag comes from the *override* placement, so `frames` follows the real window. The drag rect is kept locally to avoid feedback lag.

- [ ] **Step 2: mount from Service.qml**

```qml
  Variants {
    model: root.arranging ? Quickshell.screens : []
    ArrangeOverlay { required property var modelData; service: root; screenRef: modelData }
  }
  Timer { interval: 5000; running: root.arranging; repeat: true
    onTriggered: if (Date.now() - root.lastArrangeActivity > 60000) root.setArranging(false) }
```
plus `import "arrange"`.

- [ ] **Step 3: Live check**: `desktop-widgets arrange on` → dashed frames on every widget, hint strip; `omarchy-shell desktop-widgets drag 2 0 -300` moves the uptime widget up 300 px live and the file updates; Esc disarms (frames vanish); arm again, wait 60 s idle → disarms itself; Michael tries a real mouse drag (the one thing a script can't).

- [ ] **Step 4: Commit** `"Arrange overlay: dashed frames, drag with live preview, snap to corner, Esc/idle disarm"`; update Status.

---

### Task 3: Entry points, companion, docs

- [ ] Editor: `Button { text: "Arrange on desktop"; bordered: true; enabled: !!root.service; onClicked: { root.service.setArranging(true); root.dismiss() } }` in the header row (before the hint text). Add IPC op `arrange` to `call`.
- [ ] Keybind `SUPER + ALT + A` → `omarchy-shell desktop-widgets arrange toggle` in `bindings.lua` (check `hyprctl binds -j` for modmask 72 + key A first). Menu row `household.widgets.arrange` (icon 󰆾, action `omarchy-shell desktop-widgets arrange toggle`, `checked` = `[[ "$(omarchy-shell desktop-widgets state 2>/dev/null)" == *'"arranging":true'* ]]`).
- [ ] Companion bar widget: `Companion.qml`

```qml
import QtQuick
import qs.Commons
import qs.Ui

// Bar icon that exists only while arrange mode is armed. Click disarms,
// right-click opens the editor. Optional: add with
// `omarchy plugin enable homelab.desktop-widgets right`.
BarWidget {
  id: root
  moduleName: "homelab.desktop-widgets"
  readonly property var svc: bar && bar.shell && typeof bar.shell.serviceFor === "function" ? bar.shell.serviceFor("homelab.desktop-widgets") : null
  readonly property bool armed: !!svc && svc.arranging === true
  visible: armed
  implicitWidth: armed ? icon.implicitWidth + Style.space(12) : 0
  implicitHeight: barSize
  Text { id: icon; anchors.centerIn: parent; text: "󰆾"; color: bar ? bar.urgent : Color.urgent; font.family: Style.font.family; font.pixelSize: Style.font.icon }
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(m) {
      if (m.button === Qt.RightButton) { if (bar && bar.shell) bar.shell.toggle("homelab.desktop-widgets", "{}") }
      else if (root.svc) root.svc.setArranging(false)
    }
  }
}
```
Manifest: `kinds: ["service","panel","bar-widget"]`, `entryPoints.barWidget: "Companion.qml"`, `barWidget: { displayName: "Desktop widgets (arrange)", description: "...", category: "Desktop", allowMultiple: false, defaultSection: "right", defaults: {}, schema: [] }`. Back up `shell.json`, run `omarchy plugin enable homelab.desktop-widgets right`, confirm the service is still enabled (`desktop-widgets status`) and the icon appears only while armed; check `BarWidget` base for the exact `bar`/`moduleName` contract (`Ui/BarWidget.qml`) before relying on `bar.shell`.
- [ ] README "Arrange mode" section + screenshot `docs/arrange.png`; vault guide; memory; board; plan status; DQ-025 note (drag-to-place done, others still open).
- [ ] Commit `"Arrange mode: editor button, keybind, menu row, optional bar companion, docs — Phase 3a complete"`; push.

## Self-review

- Roadmap coverage: disarmed = no input region (T1 `mask`), explicit arming from editor/keybind/CLI/IPC (T1, T3), dashed accent frames (T2), live move + snap + save through `write` (T1 `commitPlace`, T2), disarm on Esc/Save/close/idle (T2 Esc + idle timer; editor's Save is a separate path — arming from the editor closes it, so "on Save" reduces to Esc/idle), optional bar companion hidden while disarmed (T3).
- Names: `service.arranging`, `setArranging`, `geometries`, `reportGeometry`, `forgetGeometry`, `overrides`, `setOverride`, `clearOverride`, `saveDoc`, `drag`, `commitPlace`, `touchArrange`, `lastArrangeActivity`; `Arrange.rectFor/placeFor/moveRect`; overlay `frames`, `frameAt`, `drag`.
- Risk: `Variants` recreating widget windows on every config save makes the dropped widget blink once; acceptable now, noted for later (diff-apply instead of rebuild).
