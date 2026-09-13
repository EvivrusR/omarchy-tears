// Kit contract: tests/fixtures/kit/api-<n>.json lists the surface a drop-in
// is written against (kit properties/functions, the import path, the field
// types, the injected properties). Renaming or removing any of it must bump
// registry.json "api" and add a new fixture — this test is what fails otherwise.
// tests/test_cli.py runs the same checks from Python.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.join(__dirname, "..");
const read = (...p) => fs.readFileSync(path.join(ROOT, ...p), "utf8");
const registry = JSON.parse(read("widgets", "registry.json"));
const manifest = JSON.parse(read("manifest.json"));
const fixturePath = path.join(__dirname, "fixtures", "kit", `api-${registry.api}.json`);

test("registry api has a contract fixture", () => {
  assert.ok(fs.existsSync(fixturePath), `missing ${fixturePath}: a new api number needs a new fixture`);
  const fx = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
  assert.equal(fx.api, registry.api);
});

const fx = JSON.parse(fs.readFileSync(fixturePath, "utf8"));

const propertyNames = (qml) => [...qml.matchAll(/^\s*(?:readonly\s+)?(?:default\s+)?property\s+\S+\s+(\w+)/gm)].map((m) => m[1]);
const functionNames = (qml) => [...qml.matchAll(/function\s+(\w+)\s*\(/g)].map((m) => m[1]);

for (const [file, want] of Object.entries(fx.files)) {
  test(`kit file ${file} still declares its api-${fx.api} surface`, () => {
    const qml = read("widgets", file);
    const props = propertyNames(qml), funcs = functionNames(qml);
    for (const p of want.properties) assert.ok(props.includes(p), `${file}: property ${p} gone (have ${props.join(", ")})`);
    for (const f of want.functions) assert.ok(funcs.includes(f), `${file}: function ${f} gone (have ${funcs.join(", ")})`);
  });
}

test("drop-in import path resolves to this plugin's widgets dir", () => {
  const hello = read("examples", "drop-in", "hello", "Widget.qml");
  assert.ok(hello.includes(`import "${fx.importPath}"`), "hello example must import the kit by the contract path");
  const parts = fx.importPath.split("/");
  assert.equal(parts[parts.length - 2], manifest.id, "path segment before the kit dir is the plugin id");
  assert.ok(fs.statSync(path.join(ROOT, parts[parts.length - 1])).isDirectory(), "kit dir exists");
});

test("field types: every contract type is validated, every registry type is in the contract", () => {
  const src = read("widgets", "Registry.js");
  const body = src.slice(src.indexOf("function checkField"), src.indexOf("function validateEntry"));
  for (const t of fx.fieldTypes) assert.ok(body.includes(`case "${t}"`), `Registry.js checkField no longer handles "${t}"`);
  const special = new Set(["type", "petdex"]);   // editor-only / structural, not for drop-ins
  const used = new Set();
  const walk = (fields) => { for (const f of fields || []) if (!special.has(f.type)) used.add(f.type); };
  walk(registry.common);
  for (const t of Object.values(registry.types)) walk(t.fields);
  for (const t of used) assert.ok(fx.fieldTypes.includes(t), `registry uses field type "${t}" missing from the contract`);
});

test("service still injects the contract properties", () => {
  const service = read("Service.qml");
  for (const p of fx.injected) assert.ok(service.includes(`item.${p} = `), `Service.qml no longer injects ${p}`);
});
