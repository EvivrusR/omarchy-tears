const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const J = require("../widgets/Jsonc.js");

const dir = path.join(__dirname, "fixtures/jsonc");
for (const name of fs.readdirSync(dir).filter((f) => f.endsWith(".jsonc")).sort()) {
  test(`strip ${name}`, () => {
    const input = fs.readFileSync(path.join(dir, name), "utf8");
    const expected = JSON.parse(fs.readFileSync(path.join(dir, name.replace(/\.jsonc$/, ".json")), "utf8"));
    assert.deepEqual(JSON.parse(J.strip(input)), expected);
  });
}

test("plain JSON is unchanged", () => {
  const s = '{"a":[1,2,{"b":"x"}]}';
  assert.equal(J.strip(s), s);
});
