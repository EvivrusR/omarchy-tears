const test = require("node:test");
const assert = require("node:assert/strict");
const S = require("../widgets/Series.js");
const M = require("../widgets/Monitor.js");

test("Series trims to the window and reports latest/max/avg", () => {
  const s = S.create(60);
  for (let t = 0; t <= 120; t += 10) S.push(s, t, t / 2);
  assert.equal(s.points[0].t, 60); assert.equal(s.points.length, 7);
  assert.equal(S.latest(s), 60); assert.equal(S.maxOf(s), 60); assert.equal(S.avgOf(s), 45);
  S.push(s, 130, null); assert.equal(s.points.length, 7);
  assert.equal(S.latest(S.create(5)), null); assert.equal(S.avgOf(S.create(5)), null);
});

test("Series polyline normalises x across the window and y to max", () => {
  const s = S.create(100);
  S.push(s, 0, 25); S.push(s, 50, 50); S.push(s, 100, 200);
  assert.deepEqual(S.polyline(s, 100, 100), [{ x: 0, y: 0.25 }, { x: 0.5, y: 0.5 }, { x: 1, y: 1 }]);
  assert.deepEqual(S.polyline(s, 100, null)[2], { x: 1, y: 1 });          // autoscale to series max
  assert.equal(S.polyline(s, 100, null)[0].y, 0.125);
  assert.deepEqual(S.polyline(S.create(10), 5, null), []);
});

test("netRate from counters, null on reset/iface change/no time", () => {
  const a = { t: 100, net: { iface: "w", rx: 1000, tx: 500 } }, b = { t: 110, net: { iface: "w", rx: 21000, tx: 1500 } };
  assert.deepEqual(M.netRate(a, b), { down: 2000, up: 100 });
  assert.equal(M.netRate(b, a), null);
  assert.equal(M.netRate(a, { t: 110, net: { iface: "e", rx: 5, tx: 5 } }), null);
  assert.equal(M.netRate(a, { t: 100, net: a.net }), null);
  assert.equal(M.netRate(null, b), null);
});

test("formatting helpers", () => {
  assert.equal(M.fmtRate(0), "0 B/s"); assert.equal(M.fmtRate(1536), "1.5 KB/s"); assert.equal(M.fmtRate(2500000), "2.5 MB/s"); assert.equal(M.fmtRate(null), "…");
  assert.equal(M.fmtHours(1.5), "1h 30m"); assert.equal(M.fmtHours(0.25), "15m"); assert.equal(M.fmtHours(null), ""); assert.equal(M.fmtHours(2.083), "2h 05m");
  assert.equal(M.fmtPct(12.6), "13%"); assert.equal(M.fmtTemp(63.2), "63°");
  assert.equal(M.batteryGlyph(38, false, "pixel"), "[██░░░]"); assert.equal(M.batteryGlyph(100, true, "pixel"), "[█████]⚡");
  assert.equal(M.batteryGlyph(38, true, "text"), "⚡38%"); assert.equal(M.batteryGlyph(100, false, "outline"), "󰁹"); assert.equal(M.batteryGlyph(0, true, "outline"), "󰢟");
});

test("rowValue reads the sample per row key", () => {
  const smp = { cpu: { pct: 12 }, mem: { pct: 34 }, gpu: null, temp: { c: 61 }, load: [1.5, 1, 1], net: {} };
  assert.equal(M.rowValue("cpu", smp), 12); assert.equal(M.rowValue("gpu", smp), null); assert.equal(M.rowValue("temp", smp), 61);
  assert.equal(M.rowValue("load", smp), 1.5); assert.equal(M.rowValue("net-down", smp, { down: 9, up: 1 }), 9); assert.equal(M.rowValue("net-up", smp, null), null);
  assert.ok(M.ROWS.cpu.max === 100 && M.ROWS["net-down"].max === null);
});
