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
  for (const [name, src] of [["CODE_LUA", file("Code.lua")], ["TRACKER_LUA", file("Tracker.lua")], ["UI_LUA", file("Snitchbot.lua")]]) {
    lua.lua_pushstring(L, to_luastring(src));
    lua.lua_setglobal(L, to_luastring(name));
  }
  const prelude = `
    ns = {}
    assert(load(CODE_LUA, "Code.lua"))("Snitchbot", ns)
    assert(load(TRACKER_LUA, "Tracker.lua"))("Snitchbot", ns)
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
    return table.concat({ #list.items, SnitchbotFrame.status.text, SAID[#SAID], SnitchbotFrame.ready.text, SnitchbotFrame.pct.text, SnitchbotFrame.who.text }, "|")
  `, { ui: true });
  assert.match(out, /^3\|/);
  assert.match(out, /\|2 of 3 ready for raid night\|67%\|Vitoc War$/);
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

test("XP gained across readings and level-ups", () => {
  const out = run(`
    local g = {}
    local function step(prev, cur) local n, nxt = ns.XPGain(prev, cur); g[#g + 1] = n; return nxt end
    local a = { level = 20, xp = 1000, max = 5000 }
    local b = step(a, { level = 20, xp = 1300, max = 5000 })      -- +300
    local c = step(b, { level = 21, xp = 200, max = 6000 })       -- ding: 3700 + 200
    -- The XP drops before the level changes: still a ding, counted once.
    local d = step({ level = 21, xp = 5900, max = 6000 }, { level = 21, xp = 50, max = 6000 }) -- 100 + 50
    local e = step(d, { level = 22, xp = 80, max = 7000 })        -- +30, no second ding
    return table.concat(g, ",")
  `);
  assert.equal(out, "300,3900,150,30");
});

test("reads kill lines with the game's own format", () => {
  const out = run(`
    local p = ns.KillPattern("%s dies, you gain %d experience.")
    local a, ax = ns.ParseKill("Defias Thug dies, you gain 135 experience.", p)
    local b, bx = ns.ParseKill("Kobold Vermin dies, you gain 45 experience. (+45 exp Rested bonus)", p)
    local c = ns.ParseKill("You gain 850 experience.", p)
    return table.concat({ a, ax, b, bx, tostring(c) }, "|")
  `);
  assert.equal(out, "Defias Thug|135|Kobold Vermin|45|nil");
});

test("rates, time to level and summaries", () => {
  const out = run(`
    local rate = ns.Rate(3000, 1800)
    return table.concat({
      ns.Num(rate), ns.Duration(ns.TimeToLevel(12000, rate)), ns.Duration(2460), ns.Duration(35), ns.Num(1234567),
      tostring(ns.Rate(100, 30)),
      ns.RunSummary({ name = "The Deadmines", started = 0, ended = 2460, kills = 55, xp = 9800, deaths = 1 }),
    }, "|")
  `);
  assert.equal(out, "6,000|2h 00m|41m|35s|1,234,567|nil|The Deadmines: 41m, 55 kills, 9,800 XP, 14,341 XP/h, 1 death.");
});

test("a dungeon run starts on entering, counts kills and XP, and ends on leaving", () => {
  const out = run(`
    CLOCK, INSIDE, LEVEL, XP = 1000, false, 20, 1000
    time = function() return CLOCK end
    IsInInstance = function() if INSIDE then return true, "party" end return false, "none" end
    GetInstanceInfo = function() return "The Deadmines", "party", 1, "Normal", 5, 0, false, 36 end
    UnitLevel = function() return LEVEL end
    UnitXP = function() return XP end
    UnitXPMax = function() return 5000 end
    UnitIsDeadOrGhost = function() return false end
    LOGGING = false
    MONEY = 10000
    GetMoney = function() return MONEY end
    IsInGroup = function() return true end
    IsInRaid = function() return false end
    UnitName = function(u) if u == "party1" then return "Kesh-Realm" end if u == "player" then return "Vitoc War" end return nil end
    UnitClass = function(u) return "Rogue", "ROGUE" end
    CHAT = {}
    SendChatMessage = function(msg, channel) CHAT[#CHAT + 1] = channel .. ":" .. msg end
    LoggingCombat = function(on) if on ~= nil then LOGGING = on end return LOGGING end
    local e = SnitchbotEvents
    e.scripts.OnEvent(e, "PLAYER_LOGIN")
    INSIDE = true
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    local logged = LOGGING
    CLOCK = CLOCK + 600
    XP = 1135
    e.scripts.OnEvent(e, "CHAT_MSG_COMBAT_XP_GAIN", "Defias Thug dies, you gain 135 experience.")
    e.scripts.OnEvent(e, "ENCOUNTER_START", 1, "Rhahk'Zor", 1, 5)
    CLOCK = CLOCK + 45
    e.scripts.OnEvent(e, "ENCOUNTER_END", 1, "Rhahk'Zor", 1, 5, 1)
    e.scripts.OnEvent(e, "CHAT_MSG_LOOT", "Kesh receives loot: |cff0070dd|Hitem:5187::::::::17:::::|h[Rhahk'Zor's Hammer]|h|r.", "Kesh-Realm")
    e.scripts.OnEvent(e, "CHAT_MSG_LOOT", "You receive loot: |cff9d9d9d|Hitem:2140::::::::17:::::|h[Carving Knife]|h|r.", "Vitoc War")
    MONEY = 54321
    e.scripts.OnEvent(e, "PLAYER_MONEY")
    CLOCK = CLOCK - 45
    e.scripts.OnEvent(e, "PLAYER_XP_UPDATE", "player")
    CLOCK = CLOCK + 1800
    INSIDE = false
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    local r = SnitchbotDB.runs[1]
    local extra = table.concat({ #r.bosses, r.bosses[1].name, tostring(r.bosses[1].kill), r.bosses[1].seconds, #r.loot, r.loot[1].who, r.loot[1].q, r.money, r.group["Kesh"], CHAT[1] }, ";")
    return table.concat({ tostring(logged), tostring(LOGGING), r.name, r.kills, r.xp, r.mobs["Defias Thug"], SnitchbotDB.session.kills, tostring(SnitchbotDB.run), SAID[#SAID - 1], SAID[#SAID], extra }, "|")
  `, { ui: true });
  assert.match(out, /\|1;Rhahk'Zor;true;45;1;Kesh;3;44321;Rogue;PARTY:I'm using the snitchbot\.app addon to track this run\.$/);
  assert.match(out, /^true\|false\|The Deadmines\|1\|135\|1\|1\|nil\|/);
  assert.match(out, /The Deadmines: 40m, 1 kills, 1 boss, 135 XP, 203 XP\/h, \+4g 43s\.\|.*Combat log off\.\|/);
});

test("one window: remembers it was open, switches tabs, and × keeps it shut", () => {
  const out = run(`
    UnitLevel = function() return 23 end
    UnitXP = function() return 1000 end
    UnitXPMax = function() return 4000 end
    SnitchbotDB = { lists = {}, settings = { open = true, tab = "xp" } }
    SnitchbotEvents.scripts.OnEvent(SnitchbotEvents, "PLAYER_LOGIN")
    local f = SnitchbotFrame
    local openAtLogin, level, pct = tostring(f.shown), f.x.level.text, f.x.pct.text
    SlashCmdList.SNITCHBOT("runs")
    local runsTitle, empty = f.r.title.text, tostring(f.r.empty.shown)
    f.close.scripts.OnClick()
    return table.concat({ openAtLogin, level, pct, runsTitle, empty, tostring(f.shown), tostring(SnitchbotDB.settings.open), SnitchbotDB.settings.tab }, "|")
  `, { ui: true });
  assert.equal(out, "true|Level 23|25.0%|Dungeon runs|true|false|false|runs");
});

test("loot lines, money and bosses", () => {
  const out = run(`
    local a = { ns.ParseLoot("You receive loot: |cff0070dd|Hitem:10399::::::::20:::::|h[Blackened Defias Armor]|h|r.") }
    local b = { ns.ParseLoot("Kesh receives loot: |cff1eff00|Hitem:2840::::::::20:::::|h[Copper Bar]|h|rx3.") }
    local c = ns.ParseLoot("You receive currency: 5 Badges.")
    local run = { name = "The Deadmines", started = 0, ended = 2460, kills = 55, xp = 9800, money = 123456,
      bosses = { { name = "Rhahk'Zor", kill = true }, { name = "Sneed", kill = false }, { name = "Sneed", kill = true } } }
    return table.concat({ a[1], a[2], a[3], a[4], b[1], b[3], b[4], tostring(c),
      ns.Money(123456), ns.Money(4005), ns.Money(-1210), ns.Money(7), ns.RunSummary(run, 0) }, "|")
  `);
  assert.equal(out, "10399|Blackened Defias Armor|3|1|2840|2|3|nil|12g 34s|40s 5c|-12s 10c|7c|The Deadmines: 41m, 55 kills, 2 bosses, 9,800 XP, 14,341 XP/h, +12g 34s.");
});

test("loot: only 'receives loot' lines count, not Need, Greed or roll lines", () => {
  const out = run(`
    local P = ns.LootPatterns({})
    local link = "|cnIQ2:|Hitem:6557::::::::21:::::|h[Bard's Boots of Spirit]|h|r"
    local roll = "|HlootHistory:12|h[Loot]|h: Lill has selected Greed for: " .. link
    local won = "|HlootHistory:12|h[Loot]|h: Nonut won: " .. link
    local a = ns.ParseLootLine("Nonut receives loot: " .. link .. ".", P)
    local b = ns.ParseLootLine("You receive loot: |cff1eff00|Hitem:2840::::::::20:::::|h[Copper Bar]|h|rx3.", P)
    local c = { ns.ParseLoot(roll) }
    return table.concat({ tostring(ns.ParseLootLine(roll, P)), tostring(ns.ParseLootLine(won, P)),
      a.who, a.id, a.name, a.quality, a.count, tostring(a.self), tostring(b.self), b.name, b.count, b.quality, c[2] }, "|")
  `);
  assert.equal(out, "nil|nil|Nonut|6557|Bard's Boots of Spirit|2|1|false|true|Copper Bar|3|2|Bard's Boots of Spirit");
});

test("a run survives a death, a revive at the door and a difficulty flip; leaving alive ends it", () => {
  const out = run(`
    CLOCK, INSIDE, DEAD, DIFF = 1000, true, false, 0
    time = function() return CLOCK end
    IsInInstance = function() if INSIDE then return true, "party" end return false, "none" end
    GetInstanceInfo = function() return "The Deadmines", "party", DIFF, DIFF == 1 and "Normal" or "", 5, 0, false, 36 end
    UnitIsDeadOrGhost = function() return DEAD end
    LoggingCombat = function(on) if on ~= nil then LOGGING = on end return LOGGING end
    UnitName = function(u) if u == "party1" then return "Nonut" end if u == "player" then return "Vitoc War" end return nil end
    UnitClass = function() return "Rogue", "ROGUE" end
    IsInGroup = function() return true end
    IsInRaid = function() return false end
    SnitchbotDB = { lists = {}, runs = { { name = "Old", started = 0, ended = 60, kills = 0, loot = {
      { id = 1, name = "Loot", q = 2, who = "Lill" }, { id = 2, name = "Ogre Loincloth", q = 3, who = "Lill" } } } } }
    local e = SnitchbotEvents
    e.scripts.OnEvent(e, "PLAYER_LOGIN")
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    local started = SnitchbotDB.run.started
    e.scripts.OnEvent(e, "CHAT_MSG_LOOT", "|HlootHistory:3|h[Loot]|h: Nonut has selected Need for: |cff1eff00|Hitem:6557::::|h[Bard's Boots of Spirit]|h|r", "Vitoc War")
    e.scripts.OnEvent(e, "CHAT_MSG_LOOT", "Nonut receives loot: |cff1eff00|Hitem:6557::::|h[Bard's Boots of Spirit]|h|r.", "Nonut Novemba")
    CLOCK = CLOCK + 60
    DEAD = true
    e.scripts.OnEvent(e, "PLAYER_DEAD")
    DIFF = 1
    e.scripts.OnEvent(e, "ZONE_CHANGED_NEW_AREA")
    INSIDE = false
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    CLOCK = CLOCK + 120
    DEAD = false
    e.scripts.OnEvent(e, "PLAYER_ALIVE")
    local afterRevive = tostring(SnitchbotDB.run ~= nil)
    INSIDE = true
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    local same = tostring(SnitchbotDB.run.started == started)
    CLOCK = CLOCK + 300
    INSIDE = false
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    local r = SnitchbotDB.runs[1]
    local old = SnitchbotDB.runs[2]
    return table.concat({ afterRevive, same, tostring(SnitchbotDB.run), #SnitchbotDB.runs, r.deaths, #r.loot, r.loot[1].who, r.loot[1].name, r.ended - r.started, #old.loot, old.loot[1].name }, "|")
  `, { ui: true });
  assert.equal(out, "true|true|nil|2|1|1|Nonut|Bard's Boots of Spirit|480|1|Ogre Loincloth");
});
