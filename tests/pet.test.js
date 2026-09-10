const test = require("node:test");
const assert = require("node:assert/strict");
const P = require("../widgets/Pet.js");
const sig = { claude: { session: 66, weekly: 46, resetInMin: 118 }, battery: { pct: 15, status: "Discharging", charging: false, discharging: true, full: false }, agents: { active: 2 }, cpu: 12.5, mem: 70, gpu: null, hour: 9 };

test("evalExpr handles paths, comparisons, logic, null and errors", () => {
  assert.equal(P.evalExpr("claude.session >= 50", sig), true);
  assert.equal(P.evalExpr("battery.discharging && battery.pct < 20", sig), true);
  assert.equal(P.evalExpr("agents.active == 0 || cpu > 90", sig), false);
  assert.equal(P.evalExpr("!battery.charging", sig), true);
  assert.equal(P.evalExpr("gpu == null", sig), true); assert.equal(P.evalExpr("gpu >= 30", sig), false);
  assert.equal(P.evalExpr("(cpu > 10 && mem > 60) || false", sig), true);
  assert.equal(P.evalExpr("nope.deeper > 1", sig), false);
  assert.throws(() => P.evalExpr("cpu >> 3", sig)); assert.throws(() => P.evalExpr("(cpu > 1", sig)); assert.throws(() => P.evalExpr("cpu > 1 2", sig));
});

test("step: first matching when wins, on rules beat on rising edge and expire", () => {
  const rules = P.rulesFor("battery");
  let s = P.step(rules, sig, null, 1000);
  assert.equal(s.state, "waiting"); assert.equal(s.say, "15%");
  const full = { ...sig, battery: { pct: 100, status: "Full", charging: false, discharging: false, full: true } };
  s = P.step(rules, full, s, 2000);
  assert.equal(s.state, "waving"); assert.equal(s.say, "full!"); assert.equal(s.beatUntil, 4200);
  s = P.step(rules, full, s, 3000); assert.equal(s.state, "waving");          // still beating
  s = P.step(rules, full, s, 5000); assert.equal(s.state, "idle");             // beat over, no steady rule matches Full
  s = P.step(rules, full, s, 6000); assert.equal(s.state, "idle");             // no re-trigger without a falling edge
  assert.equal(P.step([], sig, null, 1).state, "idle");
  assert.equal(P.step([{ kind: "when", if: "garbage >>", state: "failed" }], sig, null, 1).state, "idle");
});

test("watch presets exist for the agreed signals and custom passes rules through", () => {
  for (const k of ["claude", "battery", "agents", "cpu", "mem", "gpu"]) assert.ok(P.WATCH[k].length > 0, k);
  assert.equal(P.step(P.rulesFor("claude"), sig, null, 1).state, "running");                 // agents active outranks review
  assert.equal(P.step(P.rulesFor("claude"), { ...sig, agents: { active: 0 } }, null, 1).state, "review");
  assert.equal(P.step(P.rulesFor("cpu"), { ...sig, cpu: 97 }, null, 1).state, "failed");
  assert.equal(P.step(P.rulesFor("gpu"), sig, null, 1).say, "no gpu here");
  assert.deepEqual(P.rulesFor("custom", [{ kind: "when", if: "hour >= 22", state: "waiting" }]).length, 1);
  assert.deepEqual(P.rulesFor("custom", "nope"), []); assert.deepEqual(P.rulesFor("bogus"), []);
  assert.equal(P.fill("cpu {cpu}% {missing}", sig), "cpu 13% …");
});

test("sheet rows: codex 9-row and legacy 8-row mapping, trim counts", () => {
  assert.equal(P.rowFor("idle", 1872), 0); assert.equal(P.rowFor("running", 1872), 7); assert.equal(P.rowFor("running", 1872, true), 2);
  assert.equal(P.rowFor("run", 1872), 7); assert.equal(P.rowFor("waving", 1872), 3); assert.equal(P.rowFor("jump", 1872), 4); assert.equal(P.rowFor("review", 1872), 8);
  assert.equal(P.rowFor("running", 1664), 2); assert.equal(P.rowFor("waving", 1664), 1); assert.equal(P.rowFor("nonsense", 1872), 0);
  const alpha = []; for (let r = 0; r < 9; r++) for (let c = 0; c < 8; c++) alpha.push(r === 1 ? (c < 4 ? 200 : 3) : (c < 6 ? 255 : 0));
  const counts = P.trimCounts(alpha, 9);
  assert.equal(counts[0], 6); assert.equal(counts[1], 4); assert.equal(P.trimCounts([], 2).join(","), "1,1");
});
