// WoW runs Lua 5.1: parse every addon file as 5.1, so nothing newer slips in.
import { readFileSync, readdirSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";
import luaparse from "luaparse";

const dir = new URL("../Snitchbot/", import.meta.url);
for (const f of readdirSync(dir).filter((n) => n.endsWith(".lua"))) {
  test(`${f} is valid Lua 5.1`, () => {
    assert.doesNotThrow(() => luaparse.parse(readFileSync(new URL(f, dir), "utf8"), { luaVersion: "5.1" }));
  });
}

test("the TOC lists every Lua file", () => {
  const toc = readFileSync(new URL("Snitchbot.toc", dir), "utf8");
  for (const f of readdirSync(dir).filter((n) => n.endsWith(".lua"))) assert.match(toc, new RegExp(`^${f}$`, "m"));
});
