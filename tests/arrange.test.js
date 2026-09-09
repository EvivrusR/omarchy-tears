const test = require("node:test");
const assert = require("node:assert/strict");
const A = require("../widgets/Arrange.js");
const SW = 1920, SH = 1080;

test("rectFor anchors at each corner", () => {
  assert.deepEqual(A.rectFor("top-left", 10, 20, 100, 50, SW, SH), { x: 10, y: 20, w: 100, h: 50 });
  assert.deepEqual(A.rectFor("top-right", 10, 20, 100, 50, SW, SH), { x: 1810, y: 20, w: 100, h: 50 });
  assert.deepEqual(A.rectFor("bottom-left", 10, 20, 100, 50, SW, SH), { x: 10, y: 1010, w: 100, h: 50 });
  assert.deepEqual(A.rectFor("bottom-right", 10, 20, 100, 50, SW, SH), { x: 1810, y: 1010, w: 100, h: 50 });
});

test("placeFor picks the nearest corner by centre and round-trips offsets", () => {
  assert.deepEqual(A.placeFor({ x: 10, y: 20, w: 100, h: 50 }, SW, SH), { corner: "top-left", x: 10, y: 20 });
  assert.deepEqual(A.placeFor({ x: 1810, y: 1010, w: 100, h: 50 }, SW, SH), { corner: "bottom-right", x: 10, y: 20 });
  assert.deepEqual(A.placeFor({ x: 1200, y: 100, w: 100, h: 50 }, SW, SH), { corner: "top-right", x: 620, y: 100 });
  assert.deepEqual(A.placeFor({ x: 100.6, y: 900.2, w: 100, h: 50 }, SW, SH), { corner: "bottom-left", x: 101, y: 130 });
  for (const c of ["top-left", "top-right", "bottom-left", "bottom-right"]) {
    const r = A.rectFor(c, 33, 44, 200, 80, SW, SH);
    assert.deepEqual(A.placeFor(r, SW, SH), { corner: c, x: 33, y: 44 });
  }
});

test("placeFor never returns negative offsets", () => {
  assert.deepEqual(A.placeFor({ x: -30, y: -5, w: 100, h: 50 }, SW, SH), { corner: "top-left", x: 0, y: 0 });
});

test("moveRect translates and clamps to the screen", () => {
  assert.deepEqual(A.moveRect({ x: 10, y: 20, w: 100, h: 50 }, 5, -30, SW, SH), { x: 15, y: 0, w: 100, h: 50 });
  assert.deepEqual(A.moveRect({ x: 1800, y: 1000, w: 100, h: 50 }, 500, 500, SW, SH), { x: 1820, y: 1030, w: 100, h: 50 });
});
