const test = require("node:test");
const assert = require("node:assert/strict");
const S = require("../widgets/Stream.js");

test("plan: nothing to sample without monitor/battery/pet", () => {
  assert.deepEqual(S.plan([{ type: "clock" }, { type: "sysinfo" }]), { interval: 0, ifaces: [], commands: [], signals: false });
  assert.deepEqual(S.args(S.plan([])), []);
});

test("plan: fastest interval wins, defaults per type, minimums hold", () => {
  assert.equal(S.plan([{ type: "battery" }]).interval, 30);
  assert.equal(S.plan([{ type: "battery" }, { type: "monitor" }]).interval, 10);
  assert.equal(S.plan([{ type: "battery" }, { type: "monitor" }, { type: "pet" }]).interval, 5);
  assert.equal(S.plan([{ type: "monitor", intervalSec: 1 }]).interval, 2);
  assert.equal(S.plan([{ type: "battery", intervalSec: 2 }]).interval, 5);
  assert.equal(S.plan([{ type: "pet", intervalSec: 5, enabled: false }, { type: "monitor" }]).interval, 10);
});

test("plan: signals only for pets, commands and ifaces deduplicated", () => {
  const p = S.plan([
    { type: "pet", signals: [{ key: "vpn", command: "a" }, { key: "vpn", command: "b" }, { key: "", command: "x" }] },
    { type: "pet", signals: [{ key: "load", command: "c" }] },
    { type: "monitor", iface: "eth0" }, { type: "monitor", iface: "eth0" }, { type: "monitor" },
  ]);
  assert.equal(p.signals, true);
  assert.deepEqual(p.commands, ["vpn=a", "load=c"]);
  assert.deepEqual(p.ifaces, ["eth0"]);
  assert.deepEqual(S.args(p), ["--interval", "5", "--iface", "eth0", "--signals", "--command", "vpn=a", "--command", "load=c"]);
  assert.equal(S.plan([{ type: "monitor" }]).signals, false);
});

test("due: first sample always, then by interval with half a stream tick of slack", () => {
  assert.equal(S.due(0, 100, 10, 5), true);
  assert.equal(S.due(100, 105, 10, 5), false);
  assert.equal(S.due(100, 110, 10, 5), true);
  assert.equal(S.due(100, 107.6, 10, 5), true);        // jittered stream still lands every second tick
  assert.equal(S.due(100, 130, 30, 30), true);
  assert.equal(S.due(100, 129, 30, 0), false);
});
