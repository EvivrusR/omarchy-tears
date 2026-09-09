const test = require("node:test");
const assert = require("node:assert/strict");
const A = require("../widgets/Agents.js");

const RECORD = {
  id: "claude", name: "Claude Code", tierLabel: "Max 5x", ready: true,
  limits: [
    { label: "Session (5-hour)", percent: 0.23, resetsAt: "2026-09-09T13:59:59.786923+00:00" },
    { label: "Weekly (7-day)", percent: 0.32, resetsAt: "2026-09-13T05:59:59.786949+00:00" },
    { label: "Fable Weekly", percent: 0.34, resetsAt: "2026-09-13T05:59:59.787178+00:00", title: "Fable Weekly" },
  ],
};

test("sessionWindow picks the short rolling window", () => {
  const w = A.sessionWindow(RECORD);
  assert.equal(w.title, "Session");
  assert.equal(w.percent, 0.23);
  assert.equal(w.resetAt, "2026-09-09T13:59:59.786923+00:00");
});

test("weeklyWindow picks the 7-day window, not the model-scoped one", () => {
  const w = A.weeklyWindow(RECORD);
  assert.equal(w.title, "Weekly");
  assert.equal(w.percent, 0.32);
});

test("windows tolerate missing or malformed records", () => {
  assert.equal(A.sessionWindow(null), null);
  assert.equal(A.sessionWindow({ limits: [] }), null);
  assert.equal(A.sessionWindow({ limits: [{ label: "Session (5-hour)", percent: -1 }] }), null);
});

test("formatDuration is compact like the bar panel", () => {
  assert.equal(A.formatDuration(3 * 3600e3 + 31 * 60e3), "3h 31m");
  assert.equal(A.formatDuration(45 * 60e3), "45m");
  assert.equal(A.formatDuration(59e3), "1m");
  assert.equal(A.formatDuration(0), "");
  assert.equal(A.formatDuration(-5), "");
  assert.equal(A.formatDuration(2 * 86400e3 + 3600e3), "2d 1h");
});

test("resetSummary combines countdown and local clock time", () => {
  const now = Date.parse("2026-09-09T10:28:00Z");
  const s = A.resetSummary("2026-09-09T13:59:59Z", now, (d) => "23:59");
  assert.equal(s, "ends in 3h 31m · 23:59");
  assert.equal(A.resetSummary("2026-09-09T10:00:00Z", now, () => "20:00"), "resetting…");
  assert.equal(A.resetSummary("", now, () => "x"), "");
  assert.equal(A.resetSummary("garbage", now, () => "x"), "");
});
