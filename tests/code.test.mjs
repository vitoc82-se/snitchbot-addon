// Runs the addon's real Lua (Snitchbot/*.lua) in fengari against a fake game.
// fengari is Lua 5.3 and WoW is 5.1: the addon sticks to what both have.
import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";
import fengari from "fengari";

const { lauxlib, lua, lualib, to_jsstring, to_luastring } = fengari;
const file = (f) => readFileSync(new URL(`../Snitchbot/${f}`, import.meta.url), "utf8");

/** Runs Lua `script` after loading the addon's files; returns what the script returns, as a string. */
function run(script, { ui = false } = {}) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  for (const [name, src] of [["CODE_LUA", file("Code.lua")], ["UI_LUA", file("Snitchbot.lua")]]) {
    lua.lua_pushstring(L, to_luastring(src));
    lua.lua_setglobal(L, to_luastring(name));
  }
  const prelude = `
    ns = {}
    assert(load(CODE_LUA, "Code.lua"))("Snitchbot", ns)
    ${ui ? `${FAKE_UI}\n assert(load(UI_LUA, "Snitchbot.lua"))("Snitchbot", ns)` : ""}
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(`${prelude}\n${script}`)) !== lua.LUA_OK) {
    throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  }
  return lua.lua_isnil(L, -1) ? null : to_jsstring(lua.lua_tostring(L, -1));
}

// Enough of WoW's UI for Snitchbot.lua: every widget method exists and does
// nothing, except scripts, text and shown state, which are kept.
const FAKE_UI = `
  local function widget()
    local w = { scripts = {}, shown = true }
    return setmetatable(w, { __index = function(_, k)
      if k == "SetScript" then return function(self, name, fn) self.scripts[name] = fn end end
      if k == "SetText" then return function(self, t) self.text = t end end
      if k == "GetText" then return function(self) return self.text end end
      if k == "Show" then return function(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end end
      if k == "Hide" then return function(self) self.shown = false end end
      if k == "IsShown" then return function(self) return self.shown end end
      if k == "CreateFontString" or k == "CreateTexture" then return function() return widget() end end
      if k == "RegisterEvent" then return function(self, e) if e == "NOT_AN_EVENT" then error("unknown event") end end end
      return function() end
    end })
  end
  FRAMES = {}
  CreateFrame = function(_, name) local w = widget(); FRAMES[#FRAMES + 1] = w; if name then _G[name] = w end; return w end
  UIParent, UISpecialFrames, SlashCmdList = widget(), {}, {}
  C_Timer = { After = function(_, fn) fn() end }
  BAGS = { [13510] = 1, [13444] = 2 }
  BANK = { [13444] = 3 }
  -- Like Forever (probe 2026-11-15): only the C_Item versions exist.
  C_Item = {
    GetItemCount = function(id, bank) return (BAGS[id] or 0) + (bank and (BANK[id] or 0) or 0) end,
    GetItemInfo = function(id) if id == 13510 then return "Flask of the Titans", "|Hitem:13510|h[Flask of the Titans]|h" end end,
    GetItemIconByID = function() return 1 end,
  }
  IsModifiedClick = function() return true end
  ChatEdit_InsertLink = function(link) LINKED = link end
  UnitName = function() return "Vitoc War" end
  GetBuildInfo = function() return "1.60.1", "12345", "Nov 1 2026", 16001 end
  WOW_PROJECT_ID = 99
  SAID = {}
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) SAID[#SAID + 1] = msg end }`;

const CODE = "SNITCHBOT:SHOP:1;Boomers Forever;Vitoc War;40;Onyxia%27s Lair;13510.1,13444.3.17531,13457.2;END";

test("reads a shopping code", () => {
  const out = run(`
    local l = assert(ns.ParseShop("  ${CODE}\\n"))
    return table.concat({ l.guild, l.character, l.size, l.raid, #l.items, l.items[2].id, l.items[2].need, l.items[2].spell, ns.RaidLabel(l) }, "|")
  `);
  assert.equal(out, "Boomers Forever|Vitoc War|40|Onyxia's Lair|3|13444|3|17531|Onyxia's Lair (40)");
});

test("refuses bad codes with a reason", () => {
  const why = (code) => run(`local l, why = ns.ParseShop(${JSON.stringify(code)}); return why`);
  assert.match(why("hello"), /not a Snitchbot shopping code/);
  assert.match(why("SNITCHBOT:SHOP:2;a;b;40;c;1.1;END"), /newer Snitchbot addon/);
  assert.match(why("SNITCHBOT:SHOP:1;a;b;40;c;1.1"), /cut off/);
  assert.match(why("SNITCHBOT:SHOP:1;a;b;40;c;x.y;END"), /no items/);
});

test("ignores repeated items and parts it doesn't know", () => {
  const out = run(`local l = ns.ParseShop("SNITCHBOT:SHOP:1;;;10;;5.2.0.99,5.9,6.1;END"); return #l.items .. "|" .. l.items[1].need`);
  assert.equal(out, "2|2");
});

test("counts bags and bank against what's needed", () => {
  const out = run(`
    local bags = { [13510] = 1, [13444] = 2 }
    local bank = { [13444] = 3 }
    local rows, short = ns.Progress(ns.ParseShop("${CODE}"), function(id, withBank)
      return (bags[id] or 0) + (withBank and (bank[id] or 0) or 0)
    end)
    local out = { short }
    for _, r in ipairs(rows) do out[#out + 1] = r.id .. ":" .. r.bags .. "/" .. r.total .. "-" .. r.missing end
    return table.concat(out, " ")
  `);
  assert.equal(out, "1 13510:1/1-0 13444:2/5-0 13457:0/0-2");
});

test("probe lists functions and events as one line", () => {
  const out = run(`
    local fake = { GetItemCount = function() end, C_Item = { GetItemCount = function() end } }
    local function get(path)
      local v = fake
      for k in path:gmatch("[^.]+") do if type(v) ~= "table" then return nil end v = v[k] end
      return v
    end
    return ns.ProbeCode(get, function(e) return e == "ENCOUNTER_START" end, { version = "1.60.1", build = "1", interface = 16001, project = 99 })
  `);
  assert.match(out, /^SNITCHBOT:PROBE:1;version=1\.60\.1;build=1;interface=16001;project=99;/);
  assert.match(out, /;C_Item\.GetItemCount=1;GetItemCount=1;/);
  assert.match(out, /;C_Container\.GetContainerItemInfo=0;/);
  assert.match(out, /;C_Item=t|;ENCOUNTER_START=1;ENCOUNTER_END=0;/);
  assert.match(out, /;END$/);
});

test("the UI loads, pastes a list and shows what's short", () => {
  const out = run(`
    local e = SnitchbotEvents
    e.scripts.OnEvent(e, "PLAYER_LOGIN")
    SlashCmdList.SNITCHBOT("paste")
    SnitchbotPasteFrame.edit.text = "${CODE}"
    SnitchbotPasteFrame.ok.scripts.OnClick()
    local list = SnitchbotDB.lists["Vitoc War"]
    return table.concat({ #list.items, SnitchbotFrame.status.text, SAID[#SAID] }, "|")
  `, { ui: true });
  assert.match(out, /^3\|/);
  assert.match(out, /1 of 3 items short/);
  assert.match(out, /Raid list for Vitoc War saved: 3 items for Onyxia's Lair \(40\)/);
});

test("shift-click puts the item link in chat with Forever's C_Item", () => {
  const out = run(`
    SnitchbotDB = { lists = { ["Vitoc War"] = ns.ParseShop("${CODE}") } }
    SnitchbotEvents.scripts.OnEvent(SnitchbotEvents, "PLAYER_LOGIN")
    SlashCmdList.SNITCHBOT("")
    -- The first row is Flask of the Titans: find its button among the frames made.
    for _, f in pairs(FRAMES) do
      if f.itemId == 13510 and f.scripts.OnClick then f.scripts.OnClick(f) end
    end
    return LINKED
  `, { ui: true });
  assert.equal(out, "|Hitem:13510|h[Flask of the Titans]|h");
});

test("the UI says what's short at login and makes a probe line", () => {
  const out = run(`
    SnitchbotDB = { lists = { ["Vitoc War"] = ns.ParseShop("${CODE}") } }
    SnitchbotEvents.scripts.OnEvent(SnitchbotEvents, "PLAYER_LOGIN")
    SlashCmdList.SNITCHBOT("probe")
    return SAID[#SAID] .. "|" .. SnitchbotDB.probe
  `, { ui: true });
  assert.match(out, /1 raid items short for Onyxia's Lair \(40\)/);
  assert.match(out, /\|SNITCHBOT:PROBE:1;version=1\.60\.1;build=12345;interface=16001;project=99;/);
  assert.match(out, /;C_Item\.GetItemCount=1;GetItemCount=0;/);
  assert.match(out, /;READY_CHECK=1;/);
});
