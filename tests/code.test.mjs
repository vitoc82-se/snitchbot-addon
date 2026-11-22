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
  for (const [name, src] of [["CODE_LUA", file("Code.lua")], ["TRACKER_LUA", file("Tracker.lua")], ["STATS_LUA", file("Stats.lua")], ["UI_LUA", file("Snitchbot.lua")]]) {
    lua.lua_pushstring(L, to_luastring(src));
    lua.lua_setglobal(L, to_luastring(name));
  }
  const prelude = `
    ns = {}
    assert(load(CODE_LUA, "Code.lua"))("Snitchbot", ns)
    assert(load(TRACKER_LUA, "Tracker.lua"))("Snitchbot", ns)
    assert(load(STATS_LUA, "Stats.lua"))("Snitchbot", ns)
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

test("a dungeon run starts on entering, counts kills and XP, and ends 15 minutes after leaving", () => {
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
    local still = tostring(SnitchbotDB.run ~= nil)
    CLOCK = CLOCK + 901
    e.scripts.OnEvent(e, "ZONE_CHANGED_NEW_AREA")
    local r = SnitchbotDB.runs[1]
    local extra = table.concat({ #r.bosses, r.bosses[1].name, tostring(r.bosses[1].kill), r.bosses[1].seconds, #r.loot, r.loot[1].who, r.loot[1].q, r.money, r.group["Kesh"], CHAT[1] }, ";")
    return table.concat({ tostring(logged), tostring(LOGGING), r.name, r.kills, r.xp, r.mobs["Defias Thug"], SnitchbotDB.session.kills, tostring(SnitchbotDB.run), SAID[#SAID - 1], SAID[#SAID], extra, still }, "|")
  `, { ui: true });
  assert.match(out, /\|1;Rhahk'Zor;true;45;1;Kesh;3;44321;Rogue;PARTY:I'm using the snitchbot\.app addon to track this run\.\|true$/);
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

test("one run across a wipe, a corpse run and waiting at the door; split runs from before are joined", () => {
  const out = run(`
    CLOCK, INSIDE, DEAD, DIFF = 10000, true, false, 0
    time = function() return CLOCK end
    IsInInstance = function() if INSIDE then return true, "party" end return false, "none" end
    GetInstanceInfo = function() return "Deadmines", "party", DIFF, DIFF == 1 and "Normal" or "", 5, 0, false, 36 end
    UnitIsDeadOrGhost = function() return DEAD end
    LoggingCombat = function(on) if on ~= nil then LOGGING = on end return LOGGING end
    UnitName = function(u) if u == "party1" then return "Nonut" end if u == "player" then return "Vitoc War" end return nil end
    UnitClass = function() return "Rogue", "ROGUE" end
    IsInGroup = function() return true end
    IsInRaid = function() return false end
    local split = function(started, ended, key, kills) return { name = "Deadmines", key = key, character = "Vitoc War",
      started = started, ended = ended, kills = kills, xp = kills * 10, deaths = 0, money = 100, mobs = { Rat = kills },
      bosses = { { name = "Boss" .. kills } }, loot = { { id = 1, name = "Loot", q = 2, who = "Vitoc War" } }, group = { Nonut = "Rogue" } } end
    -- 0.1.5 saved one visit as three runs (newest first), and an older, separate run.
    SnitchbotDB = { lists = {}, runs = { split(5000, 5400, "36:0", 1), split(4900, 4950, "36:1", 2), split(2500, 4900, "36:0", 3), split(100, 1000, "36:0", 4) } }
    local e = SnitchbotEvents
    e.scripts.OnEvent(e, "PLAYER_LOGIN")
    local joined = #SnitchbotDB.runs .. ";" .. SnitchbotDB.runs[1].started .. "-" .. SnitchbotDB.runs[1].ended .. ";" .. SnitchbotDB.runs[1].kills .. ";" .. #SnitchbotDB.runs[1].bosses .. ";" .. #SnitchbotDB.runs[1].loot

    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    local started = SnitchbotDB.run.started
    e.scripts.OnEvent(e, "CHAT_MSG_LOOT", "Nonut receives loot: |cff1eff00|Hitem:6557::::|h[Bard's Boots of Spirit]|h|r.", "Nonut Novemba")
    -- Wipe, release, run back, revive at the door, wait for the group to leave combat.
    CLOCK = CLOCK + 60; DEAD = true
    e.scripts.OnEvent(e, "PLAYER_DEAD")
    DIFF = 1
    e.scripts.OnEvent(e, "ZONE_CHANGED_NEW_AREA")
    INSIDE = false
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    CLOCK = CLOCK + 120; DEAD = false
    e.scripts.OnEvent(e, "PLAYER_ALIVE")
    CLOCK = CLOCK + 400
    e.scripts.OnEvent(e, "ZONE_CHANGED_NEW_AREA")
    local waiting = tostring(SnitchbotDB.run ~= nil)
    -- In again to loot the last boss, then out for good.
    INSIDE = true
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    local same = tostring(SnitchbotDB.run.started == started)
    CLOCK = CLOCK + 300; INSIDE = false
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    CLOCK = CLOCK + 901
    e.scripts.OnEvent(e, "ZONE_CHANGED_NEW_AREA")
    local r = SnitchbotDB.runs[1]
    return table.concat({ joined, waiting, same, tostring(SnitchbotDB.run), #SnitchbotDB.runs, r.deaths, #r.loot, r.loot[1].who, r.ended - r.started }, "|")
  `, { ui: true });
  // 0.1.6+ runs: the visit is one run of 880s (in at 10000, out for good at 10880).
  assert.equal(out, "2;2500-5400;6;3;0|true|true|nil|3|1|1|Nonut|880");
});

test("a dungeon reset makes the next visit a new run", () => {
  const out = run(`
    CLOCK, INSIDE = 1000, true
    time = function() return CLOCK end
    IsInInstance = function() if INSIDE then return true, "party" end return false, "none" end
    GetInstanceInfo = function() return "Deadmines", "party", 1, "Normal", 5, 0, false, 36 end
    UnitIsDeadOrGhost = function() return false end
    LoggingCombat = function(on) if on ~= nil then LOGGING = on end return LOGGING end
    local e = SnitchbotEvents
    e.scripts.OnEvent(e, "PLAYER_LOGIN")
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    CLOCK = CLOCK + 600; INSIDE = false
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    e.scripts.OnEvent(e, "CHAT_MSG_SYSTEM", "Deadmines has been reset.")
    local ended = tostring(SnitchbotDB.run)
    CLOCK = CLOCK + 60; INSIDE = true
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    CLOCK = CLOCK + 600; INSIDE = false
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    CLOCK = CLOCK + 901
    e.scripts.OnEvent(e, "ZONE_CHANGED_NEW_AREA")
    return ended .. "|" .. #SnitchbotDB.runs
  `, { ui: true });
  assert.equal(out, "nil|2");
});

test("another copy of the same dungeon is a new run, even back within 15 minutes", () => {
  const out = run(`
    CLOCK, INSIDE, COPY, MATE = 1000, true, "37452", "Lana"
    time = function() return CLOCK end
    IsInInstance = function() if INSIDE then return true, "party" end return false, "none" end
    GetInstanceInfo = function() return "Blackrock Depths", "party", 1, "Normal", 5, 0, false, 230 end
    UnitIsDeadOrGhost = function() return false end
    LoggingCombat = function() end
    UnitGUID = function(u) if u == "player" then return "Player-6949-001EE7C2" end return "Creature-0-6947-230-" .. COPY .. "-8983-0000123456" end
    UnitName = function(u) if u == "party1" then return MATE end if u == "player" then return "Vitoc" end return "Dark Iron Watchman" end
    UnitClass = function() return "Priest", "PRIEST" end
    IsInGroup = function() return true end
    IsInRaid = function() return false end
    local e = SnitchbotEvents
    e.scripts.OnEvent(e, "PLAYER_LOGIN")
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    e.scripts.OnEvent(e, "NAME_PLATE_UNIT_ADDED", "nameplate1")
    -- A wipe: out and back in the same copy is still the same run.
    CLOCK = CLOCK + 600; INSIDE = false
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    CLOCK = CLOCK + 120; INSIDE = true
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    e.scripts.OnEvent(e, "PLAYER_TARGET_CHANGED")
    local same = tostring(SnitchbotDB.run.started == 1000)
    -- Out at 2000, a new group, back at 2600 in another copy.
    CLOCK = 2000; INSIDE = false
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    CLOCK = 2600; INSIDE = true; MATE = "Severus"
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    e.scripts.OnEvent(e, "GROUP_ROSTER_UPDATE")
    CLOCK = 2605; COPY = "38151"
    e.scripts.OnEvent(e, "NAME_PLATE_UNIT_ADDED", "nameplate2")
    local cur, old = SnitchbotDB.run, SnitchbotDB.runs[1]
    -- A /reload later joins runs again: but not these two.
    e.scripts.OnEvent(e, "PLAYER_LOGIN")
    return table.concat({ same, #SnitchbotDB.runs, old.started, old.ended, old.copy, tostring(old.group.Severus), cur.started, cur.copy, tostring(cur.group.Lana) }, "|")
  `, { ui: true });
  assert.equal(out, "true|1|1000|2000|37452|nil|2600|38151|nil");
});

test("at max level a kill is an enemy you see die, once each", () => {
  const out = run(`
    CLOCK, LEVEL = 1000, 60
    time = function() return CLOCK end
    IsInInstance = function() return true, "party" end
    GetInstanceInfo = function() return "Scholomance", "party", 1, "Normal", 5, 0, false, 289 end
    UnitIsDeadOrGhost = function() return false end
    LoggingCombat = function() end
    GetMaxPlayerLevel = function() return 60 end
    UNITS = {
      nameplate1 = { guid = "Creature-0-6947-289-40001-10475-01", name = "Scholomance Student", dead = true, reaction = 2 },
      nameplate2 = { guid = "Creature-0-6947-289-40001-10476-02", name = "Scholomance Acolyte", dead = false, reaction = 2 },
      nameplate3 = { guid = "Creature-0-6947-289-40001-10477-03", name = "Tagged", dead = true, reaction = 2, denied = true },
      nameplate4 = { guid = "Creature-0-6947-289-40001-10478-04", name = "Friend", dead = true, reaction = 5 },
      party1 = { guid = "Player-6949-001", name = "Wyn", dead = true, player = true },
    }
    UnitLevel = function(u) if u == "player" then return LEVEL end return 58 end
    UnitGUID = function(u) return UNITS[u] and UNITS[u].guid end
    UnitName = function(u) if u == "player" then return "Vitoc" end return UNITS[u] and UNITS[u].name end
    UnitIsDead = function(u) return UNITS[u] and UNITS[u].dead end
    UnitIsPlayer = function(u) return UNITS[u] and UNITS[u].player end
    UnitIsTapDenied = function(u) return UNITS[u] and UNITS[u].denied end
    UnitReaction = function(u) return UNITS[u] and UNITS[u].reaction end
    local e = SnitchbotEvents
    e.scripts.OnEvent(e, "PLAYER_LOGIN")
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    for _, u in ipairs({ "nameplate1", "nameplate1", "nameplate2", "nameplate3", "nameplate4", "party1" }) do e.scripts.OnEvent(e, "UNIT_HEALTH", u) end
    e.scripts.OnEvent(e, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
    UNITS.nameplate2.dead = true
    e.scripts.OnEvent(e, "NAME_PLATE_UNIT_REMOVED", "nameplate2")
    local atMax = SnitchbotDB.run.kills
    -- Below max level the XP lines count kills, so this counts nothing.
    LEVEL = 59
    UNITS.nameplate5 = { guid = "Creature-0-6947-289-40001-10479-05", name = "Rat", dead = true, reaction = 2 }
    e.scripts.OnEvent(e, "UNIT_HEALTH", "nameplate5")
    return table.concat({ atMax, SnitchbotDB.run.kills, SnitchbotDB.run.mobs["Scholomance Student"], SnitchbotDB.run.mobs["Scholomance Acolyte"], tostring(SnitchbotDB.run.mobs.Tagged) }, "|")
  `, { ui: true });
  assert.equal(out, "2|2|1|1|nil");
});

test("values the game hides in a dungeon (secret values) are dropped, not read", () => {
  const out = run(`
    -- A secret value: any use of it is an error, as in the game (Stratholme, 2026-11-22).
    SECRET = setmetatable({}, {
      __index = function() error("attempt to index a secret string value") end,
      __tostring = function() error("attempt to convert a secret value") end,
      __eq = function() error("attempt to compare a secret value") end,
    })
    issecretvalue = function(v) return rawequal(v, SECRET) end
    CLOCK = 1000
    time = function() return CLOCK end
    IsInInstance = function() return true, "party" end
    GetInstanceInfo = function() return "Stratholme", "party", 1, "Normal", 5, 0, false, 329 end
    UnitIsDeadOrGhost = function() return false end
    LoggingCombat = function() end
    GetMaxPlayerLevel = function() return 60 end
    UnitLevel = function(u) if u == "player" then return 60 end return 58 end
    UnitGUID = function(u) if u == "player" then return "Player-6949-001" end return SECRET end
    UnitName = function(u) if u == "player" then return "Vitoc" end return SECRET end
    UnitIsDead = function() return true end
    UnitIsPlayer = function() return false end
    UnitIsTapDenied = function() return false end
    UnitReaction = function() return 2 end
    local e = SnitchbotEvents
    e.scripts.OnEvent(e, "PLAYER_LOGIN")
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    for i = 1, 5 do
      e.scripts.OnEvent(e, "NAME_PLATE_UNIT_ADDED", "nameplate" .. i)
      e.scripts.OnEvent(e, "UNIT_HEALTH", "nameplate" .. i)
      e.scripts.OnEvent(e, "NAME_PLATE_UNIT_REMOVED", "nameplate" .. i)
    end
    e.scripts.OnEvent(e, "PLAYER_TARGET_CHANGED")
    e.scripts.OnEvent(e, "CHAT_MSG_LOOT", SECRET)
    return table.concat({ tostring(ns.InstanceCopy(SECRET)), tostring(ns.safe(UnitGUID, "target")), SnitchbotDB.run.name or "?", SnitchbotDB.run.kills or 0 }, "|")
  `, { ui: true });
  assert.equal(out, "nil|nil|Stratholme|0");
});

test("the combat log goes by what Snitchbot did: Forever always says it is off", () => {
  const out = run(`
    CLOCK, INSIDE, CALLS = 1000, true, {}
    time = function() return CLOCK end
    IsInInstance = function() if INSIDE then return true, "party" end return false, "none" end
    GetInstanceInfo = function() return "Blackrock Spire", "party", 1, "Normal", 5, 0, false, 229 end
    UnitIsDeadOrGhost = function() return false end
    LoggingCombat = function(on) if on ~= nil then CALLS[#CALLS + 1] = tostring(on) end return nil end
    SAID = {}
    local add = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage
    local e = SnitchbotEvents
    e.scripts.OnEvent(e, "PLAYER_LOGIN")
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD", true, false)
    CLOCK = CLOCK + 30
    e.scripts.OnEvent(e, "ZONE_CHANGED_NEW_AREA") -- like the 30-second check: no second start
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD", false, true) -- a /reload keeps it on
    local inRun = table.concat(CALLS, ",") .. ";" .. tostring(SnitchbotDB.run.logFailed)
    INSIDE = false
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    CLOCK = CLOCK + 901
    e.scripts.OnEvent(e, "ZONE_CHANGED_NEW_AREA")
    local after = table.concat(CALLS, ",") .. ";" .. tostring(SnitchbotDB.startedLog)
    -- Logged out inside and back: the game turned the log off, so it starts again.
    INSIDE = true
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD", true, false)
    SnitchbotDB.startedLog = true
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD", true, false)
    return inRun .. "|" .. after .. "|" .. table.concat(CALLS, ",")
  `, { ui: true });
  assert.equal(out, "true;nil|true,false;nil|true,false,true,true");
});

test("the window comes back where you dragged it", () => {
  const out = run(`
    local made = CreateFrame
    CreateFrame = function(kind, name, ...)
      local w = made(kind, name, ...)
      if name == "SnitchbotFrame" then rawset(w, "SetPoint", function(self, ...) self.at = { ... } end) end
      return w
    end
    SnitchbotDB = { lists = {} }
    SnitchbotEvents.scripts.OnEvent(SnitchbotEvents, "PLAYER_LOGIN")
    local f = SnitchbotFrame
    local first = f.at[1] .. "," .. f.at[4] .. "," .. f.at[5]
    rawset(f, "GetPoint", function() return "TOPLEFT", UIParent, "TOPLEFT", 120.4, -80.6 end)
    f.header.scripts.OnDragStop()
    local saved = table.concat(SnitchbotDB.settings.pos.SnitchbotFrame, ",")
    SnitchbotEvents.scripts.OnEvent(SnitchbotEvents, "PLAYER_LOGIN") -- as after a /reload
    local again = SnitchbotFrame.at[1] .. "," .. SnitchbotFrame.at[3] .. "," .. SnitchbotFrame.at[4] .. "," .. SnitchbotFrame.at[5]
    return table.concat({ first, saved, again }, "|")
  `, { ui: true });
  assert.equal(out, "CENTER,300,40|TOPLEFT,TOPLEFT,120,-81|TOPLEFT,TOPLEFT,120,-81");
});

test("stats: prices code, bests, verdicts, group history and boss loot", () => {
  const out = run(`
    local p = ns.ParsePrices("SNITCHBOT:PRICES:1;EU-NORMAL-HORDE;1794800000;" .. ns.B36(6557) .. "." .. ns.B36(12345) .. ",2s.1;END")
    local bad = select(2, ns.ParsePrices("SNITCHBOT:PRICES:1;EU;1;2s.1"))
    local function r(started, secs, xp, bosses, group, loot)
      local b = {}
      for i = 1, bosses do b[i] = { name = "Boss" .. i, kill = true } end
      return { name = "Deadmines", key = "36", started = started, ended = started + secs, xp = xp, kills = 10, bosses = b, group = group, loot = loot or {} }
    end
    local old = r(1000, 2400, 6000, 6, { Nonut = "Rogue", Von = "Warrior" }, { { id = 6557, name = "Bard's Boots", q = 2, boss = "Boss2" } })
    local partial = r(5000, 600, 3000, 3, { Nonut = "Rogue" })
    local fast = r(9000, 2100, 6000, 6, { Finwea = "Hunter" }, { { id = 6557, name = "Bard's Boots", q = 2, boss = "Boss2" }, { id = 1, name = "Gloves", q = 3, boss = "Boss2" } })
    local list = { fast, partial, old }
    local bests, order = ns.Bests(list)
    local b = bests["36"]
    local slow = r(12000, 2700, 3000, 6, {})
    local g = ns.GroupHistory(list)
    local loot = ns.BossLoot(list)
    return table.concat({ p.house, p.at, p.count, p.prices[6557], tostring(bad), #order, b.runs, b.bosses, b.fastest == fast and "fast" or "?",
      math.floor(b.rate), ns.RunVerdict(fast, { fast, partial, old }), ns.RunVerdict(slow, { slow, fast, partial, old }),
      g[1].name .. g[1].runs, g[2].name, loot[1].boss, loot[2].boss, #loot[2].items, loot[2].items[1].name, loot[2].items[2].n }, "|")
  `);
  assert.equal(out, "EU-NORMAL-HORDE|1794800000|2|12345|The price code is cut off. Copy it again.|1|3|6|fast|18000|New best for Deadmines: 35m (was 40m).|10m slower than last time.|Nonut2|Finwea|Boss1|Boss2|2|Gloves|2");
});

test("stats: XP bonus, exploring, reputation, gold sources, durability", () => {
  const out = run(`
    local ctx = { open = nil, recent = "taxi", recentAt = 100, questAt = 50, repairAt = 10 }
    local slots = { { cur = 30, max = 100 }, { cur = 0, max = 50 }, { cur = 80, max = 80 } }
    local low, broken = ns.Durability(slots)
    local name, n = ns.ParseRep("Reputation with Stormwind increased by 25.")
    local name2, n2 = ns.ParseRep("Your Gelkis Clan Centaur reputation has decreased by 10.", "Your %s reputation has increased by %d.", "Your %s reputation has decreased by %d.")
    local src = ns.XPSources(1000, { kills = 600, quests = 300 })
    return table.concat({ ns.XPBonus("Defias Thug dies, you gain 135 experience. (+45 exp Rested bonus, +12 group bonus)"),
      ns.ExploreXP("Discovered Westfall: 120 experience gained"), name, n, name2, n2,
      ns.GoldSource(ctx, -500, 101), ns.GoldSource(ctx, 200, 51), ns.GoldSource({ repairAt = 10 }, -300, 11), ns.GoldSource({}, 40, 500),
      ns.GoldSource({ open = "merchant" }, 900, 1), ns.GoldSource({}, -40, 500), low, broken, #src, src[3].key, src[3].xp }, "|")
  `);
  assert.equal(out, "57|120|Stormwind|25|Gelkis Clan Centaur|-10|flights|quests|repairs|loot|vendor|other|0.0|1|3|other|100");
});

test("stats: level plan, played per day, buff check and the character code", () => {
  const out = run(`
    local levels = { [18] = { played = 3600, ended = 1, started = 0 }, [19] = { played = 3600 * 1.5, ended = 2, started = 1 },
      [20] = { played = 1800, partial = true, ended = 3 }, [21] = { played = 600, started = 3 } }
    local plan = ns.LevelPlan(levels, 21, 23, 7200)
    local day = 1794800000 / 86400
    local perDay = ns.PlayedPerDay({ [math.floor(day)] = 3600, [math.floor(day) - 2] = 1800, [math.floor(day) - 30] = 99999 }, 1794800000)
    local a = ns.BuffCheck({ { spellId = 17626, name = "Flask of the Titans" }, { spellId = 1, name = "Well Fed" }, { spellId = 22888 } })
    local b = ns.BuffCheck({ { spellId = 17538, name = "Elixir of the Mongoose" } })
    local report = ns.BuffReport({ { name = "Lill", buffs = a }, { name = "Nonut", buffs = b }, { name = "Von", away = true } })
    local code = ns.CharCode({ region = "eu", name = "Lill Slampan", class = "WARRIOR", level = 21, now = 1794800000,
      levels = { [20] = { played = 3600, started = 1794700000 } },
      runs = { { name = "The Deadmines", started = 1794790000, ended = 1794792460, kills = 156, xp = 6685, money = -50, deaths = 1,
        bosses = { { kill = true }, { kill = false } }, loot = { {} }, value = 999 } },
      gold = { loot = 500, repairs = -120 }, xp = { kills = 6000 }, rep = { ["Stormwind"] = 25 } })
    return table.concat({ math.floor(plan.average), plan.measured, math.floor(plan.played), string.format("%.2f", plan.days), math.floor(perDay),
      tostring(a.flask), a.food and "fed" or "-", a.world, b.elixirs, report[2], report[3], report[4], report[6] }, "|") .. "\\n" .. code
  `);
  const [first, code] = out.split("\n");
  // 2 levels measured (18, 19): 4,500s on average at level 18.5; levels 21 and 22 scaled by level, minus the 600s already played at 21.
  assert.equal(first, "4500|2|9859|1.37|1800|true|fed|1|1|No flask (1): Nonut|No flask or elixir: everyone|Not well fed (1): Nonut|Too far away to check: Von");
  assert.equal(code, "SNITCHBOT:CHAR:1;eu;Lill Slampan;WARRIOR;21;1794800000;20.3600.1794700000;The Deadmines.1794790000.2460.156.6685.-50.1.1.2.1.999;loot.500,repairs.-120;kills.6000;Stormwind.25;END");
});

test("the addon tallies gold, XP and loot value, ends a run on request, and fills the Stats tab", () => {
  const out = run(`
    CLOCK, INSIDE, LEVEL, XP, MONEY = 1794800000, true, 21, 1000, 10000
    time = function() return CLOCK end
    IsInInstance = function() if INSIDE then return true, "party" end return false, "none" end
    GetInstanceInfo = function() return "Deadmines", "party", 1, "Normal", 5, 0, false, 36 end
    UnitLevel = function() return LEVEL end
    UnitXP = function() return XP end
    UnitXPMax = function() return 5000 end
    UnitIsDeadOrGhost = function() return false end
    GetMoney = function() return MONEY end
    LoggingCombat = function(on) if on ~= nil then LOGGING = on end return LOGGING end
    GetInventoryItemDurability = function(slot) if slot == 5 then return 10, 100 end end
    C_Item.GetItemInfo = function(id) if id == 2589 then return "Linen Cloth", nil, 1, nil, nil, nil, nil, nil, nil, nil, 13 end end
    SnitchbotDB = { lists = {}, settings = { tab = "stats", open = true } }
    local e = SnitchbotEvents
    e.scripts.OnEvent(e, "PLAYER_LOGIN")
    e.scripts.OnEvent(e, "PLAYER_ENTERING_WORLD")
    local gearWarning = SAID[#SAID - 1]
    -- prices pasted: Bard's Boots at 1g
    SnitchbotFrame.scripts.OnShow()
    SlashCmdList.SNITCHBOT("prices")
    SnitchbotPasteFrame.edit.text = "SNITCHBOT:PRICES:1;EU-NORMAL-HORDE;" .. CLOCK .. ";" .. ns.B36(6557) .. "." .. ns.B36(10000) .. ";END"
    SnitchbotPasteFrame.ok.scripts.OnClick()
    e.scripts.OnEvent(e, "CHAT_MSG_COMBAT_XP_GAIN", "Defias Thug dies, you gain 135 experience. (+20 exp Rested bonus)")
    XP = 1155
    e.scripts.OnEvent(e, "PLAYER_XP_UPDATE", "player")
    e.scripts.OnEvent(e, "ENCOUNTER_START", 1, "Rhahk'Zor", 1, 5)
    CLOCK = CLOCK + 50
    e.scripts.OnEvent(e, "ENCOUNTER_END", 1, "Rhahk'Zor", 1, 5, 1)
    e.scripts.OnEvent(e, "CHAT_MSG_LOOT", "You receive loot: |cff1eff00|Hitem:6557::::|h[Bard's Boots of Spirit]|h|r.", "Vitoc War")
    e.scripts.OnEvent(e, "CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:2589::::|h[Linen Cloth]|h|rx2.", "Vitoc War")
    MONEY = 10500
    e.scripts.OnEvent(e, "PLAYER_MONEY")
    e.scripts.OnEvent(e, "MERCHANT_SHOW")
    MONEY = 12000
    e.scripts.OnEvent(e, "PLAYER_MONEY")
    e.scripts.OnEvent(e, "MERCHANT_CLOSED")
    e.scripts.OnEvent(e, "QUEST_TURNED_IN", 123, 400, 2500)
    MONEY = 14500
    e.scripts.OnEvent(e, "PLAYER_MONEY")
    XP = 1555
    e.scripts.OnEvent(e, "PLAYER_XP_UPDATE", "player")
    e.scripts.OnEvent(e, "CHAT_MSG_COMBAT_FACTION_CHANGE", "Reputation with Stormwind increased by 25.")
    CLOCK = CLOCK + 3600 -- no 30s ticker in the fake game: played time counts at most 2 minutes per gap
    e.scripts.OnEvent(e, "PLAYER_LEVEL_UP", 22)
    LEVEL = 22
    local s = SnitchbotDB.session
    local run = SnitchbotDB.run
    local summary = table.concat({ s.gold.loot, s.gold.vendor, s.gold.quests, s.xpBy.kills, s.xpBy.quests, s.rep.Stormwind, s.value, run.value,
      run.loot[1].boss, SnitchbotDB.chars["Vitoc War"].levels[21].ended - 1794800000, tostring(SnitchbotDB.chars["Vitoc War"].levels[22] ~= nil) }, ",")
    -- End run: over now, and no new run while still inside.
    SnitchbotFrame.x.endRun.scripts.OnClick()
    e.scripts.OnEvent(e, "ZONE_CHANGED_NEW_AREA")
    local afterEnd = tostring(SnitchbotDB.run) .. "," .. #SnitchbotDB.runs
    SlashCmdList.SNITCHBOT("stats")
    local rows = 0
    for _, r in ipairs(SnitchbotFrame.st.rows) do if r.shown then rows = rows + 1 end end
    SlashCmdList.SNITCHBOT("export")
    local code = SnitchbotPasteFrame.edit.text
    return table.concat({ gearWarning, summary, afterEnd, tostring(rows > 10), code:sub(1, 52) }, "|")
  `, { ui: true });
  assert.equal(out, "|cffe0b04aSnitchbot:|r Your gear is at 10% durability. Repair before you pull.|500,1500,2500,155,400,25,10026,10026,Rhahk'Zor,3650,true|nil,1|true|SNITCHBOT:CHAR:1;eu;Vitoc War;;22;1794803650;21.120.");
});
