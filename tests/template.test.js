const test = require("node:test");
const assert = require("node:assert/strict");
const T = require("../widgets/Template.js");

test("parseOutput keeps JSON objects and adds output/lines", () => {
  const d = T.parseOutput('{"a":1,"b":{"c":[10,20]}}\n');
  assert.equal(d.a, 1); assert.equal(d.b.c[1], 20);
  assert.equal(d.output, '{"a":1,"b":{"c":[10,20]}}');
  assert.deepEqual(d.lines, ['{"a":1,"b":{"c":[10,20]}}']);
});

test("parseOutput wraps non-JSON and non-object JSON", () => {
  assert.deepEqual(T.parseOutput("up 3 hours\nsecond\n"), { output: "up 3 hours\nsecond", lines: ["up 3 hours", "second"] });
  assert.deepEqual(T.parseOutput("[1,2]"), { output: "[1,2]", lines: ["[1,2]"] });
  assert.deepEqual(T.parseOutput(""), { output: "", lines: [] });
});

test("get walks dotted paths and indices", () => {
  const d = { a: { b: [{ n: "x" }] }, lines: ["l0", "l1"] };
  assert.equal(T.get(d, "a.b.0.n"), "x");
  assert.equal(T.get(d, "lines.1"), "l1");
  assert.equal(T.get(d, "a.zz"), undefined);
  assert.equal(T.get(null, "a"), undefined);
});

test("render substitutes, applies filters, and handles missing values", () => {
  const d = { rated: 1181, loved: 635, rate: 0.5376, big: 1234567, t: 3725, name: "teto" };
  assert.equal(T.render("{rated} rated · {loved} loved", d), "1181 rated · 635 loved");
  assert.equal(T.render("{rate|pct}", d), "54%");
  assert.equal(T.render("{rate|fixed:1}", d), "0.5");
  assert.equal(T.render("{rate|round}", d), "1");
  assert.equal(T.render("{rate|int}", d), "0");
  assert.equal(T.render("{name|upper} {name|lower}", d), "TETO teto");
  assert.equal(T.render("{big|human}", d), "1.2M");
  assert.equal(T.render("{t|secs}", d), "1h 02m");
  assert.equal(T.render("{missing}", d), "—");
  assert.equal(T.render("{missing|default:none}", d), "none");
  assert.equal(T.render("{{literal}} {rated}", d), "{literal} 1181");
  assert.equal(T.render("plain", d), "plain");
});

test("number and barFraction", () => {
  const d = { l1: 1.5, cpus: 4, pct: 87 };
  assert.equal(T.number("{l1}", d, 0), 1.5);
  assert.equal(T.number("{nope}", d, 7), 7);
  assert.equal(T.number("12", d, 0), 12);
  assert.equal(T.barFraction({ value: "{l1}", max: "{cpus}" }, d), 0.375);
  assert.equal(T.barFraction({ value: "{pct}" }, d), 0.87);
  assert.equal(T.barFraction({ value: "{pct}", min: "80", max: "90" }, d), 0.7);
  assert.equal(T.barFraction({ value: "{nope}" }, d), -1);
  assert.equal(T.barFraction({ value: "{pct}", max: "50" }, d), 1);
});
