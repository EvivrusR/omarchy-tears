const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const R = require("../widgets/Registry.js");

const registry = JSON.parse(fs.readFileSync(path.join(__dirname, "../widgets/registry.json"), "utf8"));
const fixDir = path.join(__dirname, "fixtures/validate");

for (const name of fs.readdirSync(fixDir).filter((f) => f.endsWith(".json")).sort()) {
  test(`validate fixture ${name}`, () => {
    const fx = JSON.parse(fs.readFileSync(path.join(fixDir, name), "utf8"));
    const out = R.validateConfig(fx.config, registry);
    const errors = out.messages.filter((m) => m.level === "error");
    const warnings = out.messages.filter((m) => m.level === "warning");
    assert.equal(out.widgets === null ? null : out.widgets.length, fx.expect.widgets, "widget count");
    assert.equal(errors.length, fx.expect.errors, "errors: " + JSON.stringify(out.messages));
    assert.equal(warnings.length, fx.expect.warnings, "warnings: " + JSON.stringify(out.messages));
    const texts = out.messages.map((m) => (m.widget >= 0 ? `widget ${m.widget}: ` : "") + m.message);
    for (const want of fx.expect.messages || []) assert.ok(texts.includes(want), `missing "${want}" in ${JSON.stringify(texts)}`);
  });
}

test("applyDefaults fills common and type fields without overwriting", () => {
  const e = R.applyDefaults({ type: "clock", x: 10, timeFormat: "H" }, registry);
  assert.equal(e.x, 10);
  assert.equal(e.y, 48);
  assert.equal(e.corner, "top-right");
  assert.equal(e.timeFormat, "H");
  assert.equal(e.dateFormat, "dddd d MMMM");
  assert.equal(e.align, "auto");
  assert.deepEqual(R.applyDefaults({ type: "stats" }, registry).show, ["cpu", "mem", "disk", "battery"]);
  assert.deepEqual(R.applyDefaults({ type: "nope" }, registry), { type: "nope" });
});

test("fieldsFor lists common then type fields", () => {
  const f = R.fieldsFor("agents", registry).map((x) => x.key);
  assert.equal(f[0], "type");
  assert.ok(f.includes("corner") && f.includes("agent") && f.includes("showWeekly"));
  assert.ok(f.indexOf("corner") < f.indexOf("agent"));
  assert.deepEqual(R.fieldsFor("nope", registry), []);
});

test("hasErrors is per widget index", () => {
  const msgs = [{ level: "error", widget: 1, key: "x", message: "m" }, { level: "warning", widget: 0, key: "y", message: "w" }];
  assert.equal(R.hasErrors(msgs, 1), true);
  assert.equal(R.hasErrors(msgs, 0), false);
});

test("shape type omits text-only common fields and has its own defaults", () => {
  const keys = R.fieldsFor("shape", registry).map((x) => x.key);
  assert.ok(keys.includes("corner") && keys.includes("z") && keys.includes("kind") && keys.includes("fill"));
  for (const k of ["color", "mutedColor", "outline", "halo", "align", "backdrop"]) assert.ok(!keys.includes(k), k + " should be omitted");
  const e = R.applyDefaults({ type: "shape" }, registry);
  assert.equal(e.kind, "rect"); assert.equal(e.fill, "background"); assert.equal(e.alpha, 0.4); assert.equal(e.z, 0);
  assert.equal(e.color, undefined);
  assert.equal(R.applyDefaults({ type: "clock" }, registry).z, 0);
});

test("stackOrder sorts by z then keeps list order", () => {
  const list = [{ type: "clock", z: 2 }, { type: "shape", z: -1 }, { type: "stats" }, { type: "shape", z: -1 }, { type: "agents", z: 0 }];
  assert.deepEqual(R.stackOrder(list), [1, 3, 2, 4, 0]);
  assert.deepEqual(R.stackOrder([{ type: "a" }, { type: "b" }]), [0, 1]);
  assert.deepEqual(R.stackOrder([]), []);
});
