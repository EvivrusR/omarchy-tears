const test = require("node:test");
const assert = require("node:assert/strict");
const S = require("../widgets/Stats.js");

const SAMPLE = [
  "cpu  1142863 9201 281834 21755403 416438 139883 41850 0 0 0",
  "mem 15759508 9260644",
  "disk 65%",
  "batt 76 Discharging",
].join("\n");

test("parseSample reads every section", () => {
  const s = S.parseSample(SAMPLE);
  assert.equal(s.cpu.total, 1142863 + 9201 + 281834 + 21755403 + 416438 + 139883 + 41850);
  assert.equal(s.cpu.idle, 21755403 + 416438);
  assert.deepEqual(s.mem, { total: 15759508, avail: 9260644 });
  assert.equal(s.disk, 65);
  assert.deepEqual(s.batt, { pct: 76, status: "Discharging" });
});

test("parseSample tolerates missing sections and junk", () => {
  const s = S.parseSample("mem 100 25\nnonsense here\n");
  assert.equal(s.cpu, null);
  assert.deepEqual(s.mem, { total: 100, avail: 25 });
  assert.equal(s.disk, null);
  assert.equal(s.batt, null);
  assert.deepEqual(S.parseSample(""), { cpu: null, mem: null, disk: null, batt: null });
});

test("cpuPercent uses the delta between samples", () => {
  const prev = { total: 1000, idle: 800 };
  const cur = { total: 1400, idle: 1100 };
  assert.equal(S.cpuPercent(prev, cur), 25);
  assert.equal(S.cpuPercent(null, cur), null);
  assert.equal(S.cpuPercent(cur, cur), null);
  assert.equal(S.cpuPercent(prev, null), null);
});

test("cpuPercent is clamped to 0..100", () => {
  assert.equal(S.cpuPercent({ total: 0, idle: 0 }, { total: 100, idle: -5 }), 100);
  assert.equal(S.cpuPercent({ total: 0, idle: 0 }, { total: 100, idle: 150 }), 0);
});

test("memPercent is used memory as a whole percent", () => {
  assert.equal(S.memPercent({ total: 1000, avail: 250 }), 75);
  assert.equal(S.memPercent({ total: 0, avail: 0 }), null);
  assert.equal(S.memPercent(null), null);
});

test("batteryGlyph reflects charge and state", () => {
  assert.equal(S.batteryLabel({ pct: 76, status: "Discharging" }), "76%");
  assert.equal(S.batteryLabel({ pct: 76, status: "Charging" }), "76%+");
  assert.equal(S.batteryLabel({ pct: 100, status: "Full" }), "100%");
  assert.equal(S.batteryLabel(null), "");
});
