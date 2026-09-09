const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const M = require("../widgets/EditorModel.js");
const registry = JSON.parse(fs.readFileSync(path.join(__dirname, "../widgets/registry.json"), "utf8"));

test("newEntry is minimal: type plus corner", () => {
  assert.deepEqual(M.newEntry("clock", registry), { type: "clock", corner: "top-right" });
  assert.deepEqual(M.newEntry("stats", registry, "bottom-left"), { type: "stats", corner: "bottom-left" });
});

test("setValue strips values equal to the registry default", () => {
  const e = { type: "clock", x: 10 };
  M.setValue(e, "x", 48, registry);
  assert.equal("x" in e, false);
  M.setValue(e, "timeFormat", "H", registry);
  assert.equal(e.timeFormat, "H");
  M.setValue(e, "timeFormat", "HH:mm", registry);
  assert.equal("timeFormat" in e, false);
  M.setValue(e, "show", ["cpu", "mem", "disk", "battery"], registry);   // not a clock field: kept verbatim
  assert.deepEqual(e.show, ["cpu", "mem", "disk", "battery"]);
  M.setValue(e, "enabled", false, registry);
  assert.equal(e.enabled, false);
  M.setValue(e, "enabled", true, registry);
  assert.equal("enabled" in e, false);
});

test("valueOf returns the entry value or the default", () => {
  assert.equal(M.valueOf({ type: "clock" }, "x", registry), 48);
  assert.equal(M.valueOf({ type: "clock", x: 5 }, "x", registry), 5);
  assert.deepEqual(M.valueOf({ type: "stats" }, "show", registry), ["cpu", "mem", "disk", "battery"]);
  assert.equal(M.valueOf({ type: "clock" }, "nope", registry), undefined);
});

test("moveEntry swaps neighbours and clamps at the ends", () => {
  const l = [{ type: "a" }, { type: "b" }, { type: "c" }];
  assert.equal(M.moveEntry(l, 0, -1), 0);
  assert.equal(M.moveEntry(l, 0, 1), 1);
  assert.deepEqual(l.map((e) => e.type), ["b", "a", "c"]);
  assert.equal(M.moveEntry(l, 2, 1), 2);
});

test("entryLabel prefers title, then display name", () => {
  assert.equal(M.entryLabel({ type: "clock" }, registry), "Clock");
  assert.equal(M.entryLabel({ type: "command", title: "UPTIME" }, registry), "UPTIME");
  assert.equal(M.entryLabel({ type: "weather" }, registry), "weather");
  assert.equal(M.entryLabel({}, registry), "(no type)");
});

test("firstError and dirty", () => {
  const msgs = [{ level: "warning", widget: 0, message: "w" }, { level: "error", widget: 1, message: "bad" }];
  assert.equal(M.firstError(msgs, 1), "bad");
  assert.equal(M.firstError(msgs, 0), "");
  assert.equal(M.dirty([{ type: "clock" }], [{ type: "clock" }]), false);
  assert.equal(M.dirty([{ type: "clock", x: 1 }], [{ type: "clock" }]), true);
});

test("fieldsFor honours omitCommon", () => {
  const keys = M.fieldsFor("shape", registry).map((x) => x.key);
  assert.ok(keys.includes("z") && keys.includes("kind") && !keys.includes("color"));
});
