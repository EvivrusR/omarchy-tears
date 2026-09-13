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

test("string literals and other pets' states in rules; layer specs; pet names", () => {
  const sig = { pets: { jill: { state: "failed", say: "cap" } }, cpu: 5 };
  assert.equal(P.evalExpr("pets.jill.state == 'failed'", sig), true);
  assert.equal(P.evalExpr('pets.jill.state == "idle" || cpu < 10', sig), true);
  assert.equal(P.evalExpr("pets.nobody.state == 'idle'", sig), false);
  const s = P.step([{ kind: "on", if: "pets.jill.state == 'failed'", state: "waving", beat: 1, say: "you ok?" }], sig, { edges: { 0: false } }, 100);
  assert.equal(s.state, "waving"); assert.equal(s.say, "you ok?");
  assert.deepEqual(P.layerSpec({ kind: "image", image: "/p/rug.png", z: "back", x: -10, y: 4 }), { kind: "image", source: "/p/rug.png", front: false, x: -10, y: 4, scale: 1, follow: "idle" });
  assert.equal(P.layerSpec({ kind: "sheet", sheet: "/o/coat.webp" }).front, true); assert.equal(P.layerSpec({ kind: "image" }), null);
  assert.equal(P.layerSpecs([{ image: "/a.png" }, {}, { sheet: "/b.webp", scale: 0 }]).length, 2);
  assert.equal(P.petName({ sheet: "/x/pets/Jill Stingray/spritesheet.webp" }), "jill_stingray"); assert.equal(P.petName({ name: "Girl!", sheet: "/y" }), "girl_"); assert.equal(P.petName({}), "pet");
});

test("bounds grows to the union of body and layers and reports the offset", () => {
  const layers = P.layerSpecs([{ image: "/rug.png", z: "back", x: -14, y: 150, scale: 1.1 }, { image: "/stool.png", x: 120, y: 80 }, { sheet: "/coat.webp" }]);
  const b = P.bounds(layers, 118, 128, 128 / 208, { 0: { w: 220, h: 70 }, 1: { w: 90, h: 120 } });
  assert.ok(b.x < 0 && b.y === 0); assert.ok(b.w > 118 && b.h > 128);
  assert.deepEqual(P.bounds([], 118, 128, 1, {}), { x: 0, y: 0, w: 118, h: 128 });
  assert.deepEqual(P.bounds(layers.slice(2), 118, 128, 1, {}), { x: 0, y: 0, w: 118, h: 128 });   // a sheet layer adds nothing
});

test("trimInfo reports frames and presence per row; looks collapses running rows and keeps extras", () => {
  // 9-row codex sheet: row 4 (jumping) fully blank, row 2 (running-left) blank, row 7 (running) has 6 frames
  const alpha = []; for (let r = 0; r < 9; r++) for (let c = 0; c < 8; c++) alpha.push((r === 4 || r === 2) ? 0 : (c < 6 ? 255 : 0));
  const info = P.trimInfo(alpha, 9);
  assert.deepEqual(info.counts, P.trimCounts(alpha, 9));
  assert.equal(info.present[4], false); assert.equal(info.present[0], true); assert.equal(info.present[2], false);
  const L = P.looks(1872, info);
  assert.deepEqual(L.map((l) => l.name), ["idle", "running", "waving", "jumping", "failed", "waiting", "review"]);
  const byName = Object.fromEntries(L.map((l) => [l.name, l]));
  assert.equal(byName.jumping.present, false); assert.equal(byName.running.present, true); assert.equal(byName.running.frames, 6); assert.equal(byName.running.row, 7);
  assert.equal(L.filter((l) => l.present).length, 6);
  // legacy 8-row sheet keeps extra1/extra2
  const a8 = []; for (let r = 0; r < 8; r++) for (let c = 0; c < 8; c++) a8.push(c < 4 ? 255 : 0);
  assert.deepEqual(P.looks(1664, P.trimInfo(a8, 8)).map((l) => l.name), ["idle", "waving", "running", "failed", "review", "jumping", "extra1", "extra2"]);
  // 11-row ChatGPT export: rows past 9 are extras
  const a11 = []; for (let r = 0; r < 11; r++) for (let c = 0; c < 8; c++) a11.push(255);
  assert.deepEqual(P.looks(2288, P.trimInfo(a11, 11)).map((l) => l.name).slice(7), ["extra10", "extra11"]);
});

test("rowFor falls back along the chain when a look is missing, and resolveLook names what is shown", () => {
  const present = [true, true, false, true, false, true, false, true, true];   // jumping (4) and waiting (6) absent
  assert.equal(P.rowFor("jumping", 1872, false, present), 3);                  // → waving
  assert.equal(P.rowFor("waiting", 1872, false, present), 8);                  // → review
  assert.equal(P.rowFor("failed", 1872, false, present), 5);                   // present, unchanged
  assert.equal(P.rowFor("jumping", 1872), 4);                                  // no presence info: old behaviour
  const noWave = present.slice(); noWave[3] = false;
  assert.equal(P.rowFor("jumping", 1872, false, noWave), 0);                   // waving gone too → idle
  assert.equal(P.rowFor("running", 1872, true, [true, false, false, true, true, true, true, true, true]), 7); // running-left absent → row 7 (flip handles direction)
  assert.equal(P.resolveLook("jumping", ["idle", "waving"]), "waving");
  assert.equal(P.resolveLook("failed", ["idle"]), "idle");
  assert.equal(P.resolveLook("waving", ["idle", "waving"]), "waving");
});

test("uniqueNames gives later pets on the same sheet a numbered name", () => {
  const cfgs = [{ type: "pet", sheet: "/p/teto/spritesheet.webp" }, { type: "clock" }, { type: "pet", sheet: "/q/teto/spritesheet.webp" }, { type: "pet", name: "teto" }, { type: "pet", name: "Jill" }];
  assert.deepEqual(P.uniqueNames(cfgs), ["teto", null, "teto_2", "teto_3", "jill"]);
  assert.deepEqual(P.uniqueNames([]), []);
});
