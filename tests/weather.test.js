const test = require("node:test");
const assert = require("node:assert/strict");
const W = require("../widgets/Weather.js");

test("effectFor maps groups, day/night, and wind slant", () => {
  assert.equal(W.effectFor("clear", true).name, "clear"); assert.equal(W.effectFor("clear", false).name, "night");
  assert.equal(W.effectFor("rain", true, 5).dx, 0); assert.equal(W.effectFor("rain", true, 30).dx, 0.5); assert.equal(W.effectFor("rain", true, 50).dx, 1);
  assert.equal(W.effectFor("bogus", true).kind, "none"); assert.equal(W.effectFor("storm", true).flash.length, 2);
});

test("init sizes the field by density and step keeps particles in bounds", () => {
  const rand = W.makeRand(42);
  const e = W.effectFor("rain", true, 0);
  const st = W.init(e, 100, 50, 1, rand);
  assert.equal(st.particles.length, 300);            // 6 per 100 cells × 5000 cells
  assert.equal(W.init(e, 100, 50, 0.5, rand).particles.length, 150);
  for (let i = 0; i < 200; i++) W.step(st, e, rand, 6);
  for (const p of st.particles) { assert.ok(p.r < 50 && p.r >= -1); assert.ok(p.c >= 0 && p.c < 100); }
  const rows = W.render(st, e);
  assert.equal(rows.length, 50); assert.ok(rows.some((r) => r.length > 0)); assert.ok(rows.every((r) => r.length <= 100));
});

test("clouds drift and wrap; twinkle changes glyphs; storm flashes", () => {
  const rand = W.makeRand(7);
  const c = W.effectFor("overcast", true, 0);
  const st = W.init(c, 80, 30, 1, rand);
  assert.equal(st.sprites.length, 9); assert.equal(st.particles.length, 0);
  const before = st.sprites.map((s) => s.c);
  W.step(st, c, rand, 6);
  assert.ok(st.sprites.every((s, i) => s.c > before[i] || s.c === -12));
  assert.ok(W.sprites(st).every((s) => s.lines.length === 3));
  const t = W.effectFor("clear", false, 0); const ts = W.init(t, 40, 20, 1, rand);
  const g = ts.particles.map((p) => p.g).join(","); for (let i = 0; i < 20; i++) W.step(ts, t, rand, 6);
  assert.notEqual(ts.particles.map((p) => p.g).join(","), g);
  const s = W.effectFor("storm", true, 0); const ss = W.init(s, 40, 20, 1, rand);
  let flashed = false; for (let i = 0; i < 40 * 6; i++) { W.step(ss, s, rand, 6); if (ss.flash > 0) flashed = true; }
  assert.ok(flashed);
  assert.equal(W.init(W.effectFor("none"), 10, 10, 1, rand).particles.length, 0);
});

test("makeRand is deterministic and in [0,1)", () => {
  const a = W.makeRand(3), b = W.makeRand(3);
  for (let i = 0; i < 100; i++) { const x = a(); assert.equal(x, b()); assert.ok(x >= 0 && x < 1); }
});
