import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "widgets/Jsonc.js" as Jsonc
import "widgets/Registry.js" as Registry
import "widgets/Arrange.js" as Arrange
import "widgets/Pet.js" as Pet
import "arrange"

// Desktop widgets service. One PanelWindow per (widget entry × screen) on the
// Bottom layer: above the wallpaper, below every app window. The layout is
// read from ~/.config/omarchy/desktop-widgets.json and hot-reloads on save.
// Code changes need `omarchy plugin disable` + `enable` (the shell keeps a
// loaded service instance across rescans).
Item {
  id: root

  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/desktop-widgets.json"
  readonly property string registryPath: String(Qt.resolvedUrl("widgets/registry.json")).replace(/^file:\/\//, "")
  property var registry: null
  property string pendingConfigText: ""
  property bool haveConfigText: false
  // For the editor panel: the user's entries as written (validated, not
  // default-filled, not filtered), the validation messages, and whether the
  // file carries comments a JSON rewrite would drop.
  property var rawWidgets: []
  property var messages: []
  // Top-level settings (everything but version/widgets), carried over by saveDoc.
  property var settings: ({})
  readonly property var grid: Registry.gridOf({ grid: settings.grid })
  function setGrid(enabled, size) {
    var g = Registry.gridOf({ grid: { enabled: enabled, size: size } })
    var next = ({})
    for (var k in settings) next[k] = settings[k]
    next.grid = g
    saveDoc(JSON.parse(JSON.stringify(rawWidgets)), null, next)
  }
  property bool configHasComments: false
  property bool configParseFailed: false

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
    // Windows are rebuilt on every config reload; the replacement reports the
    // same key before the old one is destroyed, so only forget keys that are
    // no longer placed at all.
    for (var i = 0; i < placements.length; i++) if (placements[i].key === key) return
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

  // Pets publish their state for each other's rules (pets.<name>.state / say / watch).
  property var petStates: ({})
  function publishPet(name, info) {
    var next = ({})
    for (var k in petStates) next[k] = petStates[k]
    next[String(name)] = info
    petStates = next
  }
  // pets.<name> keys: a second pet on the same sheet folder publishes as name_2 (not over the first).
  readonly property var petNames: Pet.uniqueNames(widgets)
  function petNameFor(index) { var n = petNames[Number(index)]; return n || null }

  // Save a whole document through the CLI (validated, .bak kept). onDone(ok, message).
  property var saveCallback: null
  function saveDoc(doc, onDone, withSettings) {
    if (writer.running) { log("saveDoc: writer busy, dropped"); if (onDone) onDone(false, "busy"); return }
    saveCallback = onDone || null
    var out = ({})
    var st = withSettings || settings
    for (var k in st) out[k] = st[k]
    out.version = 1
    out.widgets = doc
    writer.pendingText = JSON.stringify(out, null, 2) + "\n"
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
  function snap(place) { return grid.enabled ? Arrange.snapPlace(place, grid.size) : place }
  function commitPlace(key, index, place) {
    place = snap(place)
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
    function rescan(): string { root.loadRegistry(); return "ok" }
    // grid on|off|toggle|<px>; anything else just reports.
    function grid(value: string): string {
      var v = String(value || "").trim().toLowerCase()
      var g = root.grid
      if (v === "on" || v === "off" || v === "toggle") root.setGrid(v === "on" ? true : v === "off" ? false : !g.enabled, g.size)
      else if (v && !isNaN(Number(v))) root.setGrid(true, Number(v))
      return JSON.stringify(root.grid)
    }
    function state(): string { return JSON.stringify({ arranging: root.arranging, widgets: root.widgets.length, geometries: Object.keys(root.geometries).length, overrides: Object.keys(root.overrides).length, grid: root.grid }) }
  }

  // Last good layout. A malformed edit keeps the previous one on screen.
  property var widgets: []
  property bool everLoaded: false

  function log(msg) { console.log("[desktop-widgets] " + msg) }

  function loadConfig(raw) {
    pendingConfigText = String(raw || "")
    haveConfigText = true
    // Refresh the registry first so a drop-in added since the last load is
    // known before validation; the Process's exit applies the config.
    if (registryFromCli) { loadRegistry(); return }
    if (registry) applyConfig()
  }

  function applyConfig() {
    var text = pendingConfigText.trim()
    if (!text) {
      if (!everLoaded) log("no config at " + configPath + " — nothing to draw; run `desktop-widgets init` (or `install`), or open the editor")
      widgets = []
      rawWidgets = []
      messages = []
      everLoaded = true
      return
    }
    var parsed
    var stripped = Jsonc.strip(text)
    configHasComments = stripped !== text
    try {
      parsed = JSON.parse(stripped)
    } catch (e) {
      configParseFailed = true
      log("config parse error, keeping last good layout: " + e)
      return
    }
    configParseFailed = false
    settings = Registry.settingsOf(parsed)
    var result = Registry.validateConfig(parsed, registry)
    rawWidgets = result.widgets ? JSON.parse(JSON.stringify(result.widgets)) : []
    messages = result.messages
    for (var m = 0; m < result.messages.length; m++) {
      var msg = result.messages[m]
      log((msg.level === "error" ? "ERROR " : "warn  ") + (msg.widget >= 0 ? "widget " + msg.widget + ": " : "") + msg.message)
    }
    if (!result.widgets) { log("keeping last good layout"); return }
    var next = []
    for (var i = 0; i < result.widgets.length; i++) {
      if (Registry.hasErrors(result.messages, i)) continue
      var entry = Registry.applyDefaults(result.widgets[i], registry)
      if (entry.enabled === false) continue
      entry.__index = i
      next.push(entry)
    }
    widgets = next
    everLoaded = true
    // Stacking is creation order and Variants reuses windows, so when the
    // ordered key list changes in a way appending cannot express, bump `gen`
    // (part of every placement) to recreate all windows in the right order.
    var keys = orderedKeys(next)
    if (Registry.needsRebuild(lastKeys, keys)) { gen += 1; log("stacking changed, rebuilding windows") }
    lastKeys = keys
    log("loaded " + next.length + " widget(s)" + (next.length !== result.widgets.length ? " (" + (result.widgets.length - next.length) + " skipped)" : ""))
  }

  // Registry: assembled by the CLI (built-in types + drop-ins under
  // ~/.config/omarchy/desktop-widgets.d/). Falls back to the built-in file
  // if the CLI cannot run. Re-run on every config reload and on IPC rescan.
  readonly property string cliPath: String(Qt.resolvedUrl("bin/desktop-widgets")).replace(/^file:\/\//, "")
  property bool registryFromCli: false
  function loadRegistry() { if (!registryProc.running) registryProc.running = true }
  Process {
    id: registryProc
    command: [root.cliPath, "registry", "--json"]
    stdout: StdioCollector { id: registryOut }
    onExited: function(code) {
      var text = String(registryOut.text || "").trim()
      if (code === 0 && text) {
        try {
          var reg = JSON.parse(text)
          var problems = reg.problems || []
          for (var i = 0; i < problems.length; i++) root.log("drop-in problem: " + problems[i])
          root.registry = reg
          root.registryFromCli = true
          if (root.haveConfigText) root.applyConfig()
          return
        } catch (e) { root.log("registry from CLI unparsable: " + e) }
      } else root.log("registry via CLI failed (" + code + "), using built-in file")
      if (!root.registry) registryFile.reload()
    }
  }
  FileView {
    id: registryFile
    path: root.registryPath
    blockLoading: false
    preload: false
    onLoaded: {
      try { root.registry = JSON.parse(text()) } catch (e) { root.log("registry parse error: " + e); root.registry = null }
      if (root.registry && root.haveConfigText) root.applyConfig()
    }
    onLoadFailed: function(error) { root.log("registry read failed: " + error) }
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    blockLoading: false
    onLoaded: root.loadConfig(text())
    onFileChanged: reload()
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound) root.loadConfig("")
      else root.log("config read failed: " + error)
    }
  }

  // Pairs every widget with every screen it targets, in stacking order.
  // Creation order is stacking order (compositor stacks same-layer surfaces
  // by creation), so walk the widgets by ascending z. A weather widget with
  // its effect on gets a second, full-screen window; back/front pin it
  // below/above everything, custom uses the widget's z.
  property int gen: 0
  property var lastKeys: []
  function orderedPlacements(list) {
    var out = []
    var screens = Quickshell.screens
    var items = []
    for (var i = 0; i < list.length; i++) {
      var wi = list[i]
      items.push({ w: wi, z: Number(wi.z) || 0, effect: false })
      if (String(wi.type) === "weather" && wi.effect === true) {
        var pl = String(wi.effectPlacement || "back")
        items.push({ w: wi, z: pl === "back" ? -1e9 : pl === "front" ? 1e9 : (Number(wi.z) || 0), effect: true })
      }
    }
    var order = Registry.stackOrder(items)
    for (var o = 0; o < order.length; o++) {
      var it = items[order[o]], w = it.w
      for (var s = 0; s < screens.length; s++) {
        if (w.screen && String(w.screen) !== screens[s].name) continue
        out.push({ widget: w, screen: screens[s], effect: it.effect, key: w.__index + "@" + screens[s].name + (it.effect ? "#effect" : "") })
      }
    }
    return out
  }
  function orderedKeys(list) { return orderedPlacements(list).map(function(p) { return p.key }) }
  readonly property var placements: {
    var out = orderedPlacements(widgets)
    for (var i = 0; i < out.length; i++) out[i].gen = gen
    return out
  }

  Variants {
    model: root.placements

    PanelWindow {
      id: win
      required property var modelData
      readonly property var widget: modelData.widget
      readonly property bool isEffect: modelData.effect === true
      readonly property var override: root.overrides[modelData.key] || null
      readonly property string corner: String(override ? override.corner : (widget.corner || "top-right"))
      readonly property int offsetX: Number(override ? override.x : (widget.x !== undefined ? widget.x : 48))
      readonly property int offsetY: Number(override ? override.y : (widget.y !== undefined ? widget.y : 48))
      // No pointer input unless the registry type asks for it (`input: true`,
      // the dock); arrange mode uses its own overlay window regardless.
      readonly property bool wantsInput: !isEffect && !!(root.registry && root.registry.types && root.registry.types[String(widget.type)] && root.registry.types[String(widget.type)].input)
      Region { id: noInput }
      mask: wantsInput ? null : noInput
      function report() {
        if (isEffect || !visible || implicitWidth <= 1 || implicitHeight <= 1) return
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

      screen: modelData.screen
      color: "transparent"
      WlrLayershell.namespace: "homelab-desktop-widgets"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      visible: loader.status === Loader.Ready

      // A *-center corner anchors neither side, which layer-shell centres.
      anchors {
        top: isEffect || corner.indexOf("top") === 0
        bottom: isEffect || corner.indexOf("bottom") === 0
        left: isEffect || corner.indexOf("left") !== -1
        right: isEffect || corner.indexOf("right") !== -1
      }
      margins {
        top: !isEffect && anchors.top ? offsetY : 0
        bottom: !isEffect && anchors.bottom ? offsetY : 0
        left: !isEffect && anchors.left ? offsetX : 0
        right: !isEffect && anchors.right ? offsetX : 0
      }

      implicitWidth: isEffect ? modelData.screen.width : Math.max(1, Math.ceil(loader.implicitWidth))
      implicitHeight: isEffect ? modelData.screen.height : Math.max(1, Math.ceil(loader.implicitHeight))

      Loader {
        id: loader
        anchors.fill: win.isEffect ? parent : undefined
        source: {
          if (win.isEffect) return "widgets/WeatherEffect.qml"
          switch (String(win.widget.type)) {
            case "clock": return "widgets/ClockWidget.qml"
            case "stats": return "widgets/StatsWidget.qml"
            case "command": return "widgets/CommandWidget.qml"
            case "agents": return "widgets/AgentsWidget.qml"
            case "template": return "widgets/TemplateWidget.qml"
            case "shape": return "widgets/ShapeWidget.qml"
            case "battery": return "widgets/BatteryWidget.qml"
            case "sysinfo": return "widgets/SysinfoWidget.qml"
            case "monitor": return "widgets/MonitorWidget.qml"
            case "weather": return "widgets/WeatherWidget.qml"
            case "dock": return "widgets/DockWidget.qml"
            case "pet": return "widgets/PetWidget.qml"
            default: {
              var t = root.registry && root.registry.types ? root.registry.types[String(win.widget.type)] : null
              return t && t.source ? "file://" + t.source : ""
            }
          }
        }
        onLoaded: { item.config = win.widget; if ("service" in item) item.service = root }
        onStatusChanged: {
          if (status === Loader.Error)
            root.log("widget " + win.widget.__index + " (" + win.widget.type + ") failed to load")
        }
      }
    }
  }

  // Arrange overlays: one per screen, only while armed. Idle disarm after 60 s.
  Variants {
    model: root.arranging ? Quickshell.screens : []
    ArrangeOverlay { required property var modelData; service: root; screenRef: modelData }
  }
  Timer {
    interval: 5000; running: root.arranging; repeat: true
    onTriggered: if (Date.now() - root.lastArrangeActivity > 60000) root.setArranging(false)
  }

  Component.onCompleted: { log("service up, watching " + configPath); loadRegistry() }
}
