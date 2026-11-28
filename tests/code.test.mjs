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
  for (const [name, src] of [["CODE_LUA", file("Code.lua")], ["TRACKER_LUA", file("Tracker.lua")], ["STATS_LUA", file("Stats.lua")], ["CRAFT_LUA", file("Craft.lua")], ["UI_LUA", file("Snitchbot.lua")]]) {
    lua.lua_pushstring(L, to_luastring(src));
    lua.lua_setglobal(L, to_luastring(name));
  }
  const prelude = `
    ns = {}
    assert(load(CODE_LUA, "Code.lua"))("Snitchbot", ns)
    assert(load(TRACKER_LUA, "Tracker.lua"))("Snitchbot", ns)
    assert(load(STATS_LUA, "Stats.lua"))("Snitchbot", ns)
    assert(load(CRAFT_LUA, "Craft.lua"))("Snitchbot", ns)
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

test("craft plan: crafts left from your skill, parts made from stone, what you have, the price and the rank to train", () => {
  const out = run(`
    local plan = ns.CRAFT_PLANS[164]
    -- Skill 85: half of 80-90 Rough Bronze Leggings is left (5 of 10).
    local HAVE = { [2841] = 100, [3478] = 10, [5956] = 1 }
    local PRICE = { [2841] = 175, [2836] = 200, [12359] = 2187 }
    local p = ns.CraftPlan(plan, 85, function(id) return HAVE[id] or 0 end, function(id) return PRICE[id] end, function(spell) return spell == 10013 end, 150)
    local by = {}
    for _, r in ipairs(p.rows) do by[r.id] = r end
    local first = p.steps[1]
    local r = {
      first.name, first.crafts, tostring(first.current), #p.steps,
      -- Bronze: 30 (80-90 half) + 90 + 88 + 85 = 293, 100 in bags.
      by[2841].need, by[2841].have, by[2841].missing, by[2841].cost,
      -- Coarse Grinding Stone: 34 needed, 10 in bags, 24 made from 48 Coarse Stone.
      tostring(by[3478].made), by[3478].missing, by[2836].need, by[2836].cost,
      -- The hammer is in your bags; Ebon Shiv plans are known, the other two aren't.
      by[5956].missing, tostring(by[8030] ~= nil), tostring(by[251468] ~= nil), by[251468].plans.npc,
      p.rank.name, p.rank.at, tostring(p.unpriced > 0),
    }
    local done = ns.CraftPlan(plan, 300)
    r[#r + 1] = tostring(done.done) .. "/" .. #done.rows .. "/" .. #done.steps
    local fresh = ns.CraftPlan(plan, 1)
    r[#r + 1] = fresh.crafts
    return table.concat(r, "|")
  `);
  assert.equal(out, [
    "Rough Bronze Leggings", 5, "true", 26,
    293, 100, 193, 193 * 175,
    "true", 24, 48, 48 * 200,
    0, "false", "true", "Pexmit",
    "Expert", 150, "true",
    "true/0/0",
    401, // the guide's 30 steps add up to 401 crafts
  ].join("|"));
});

test("craft plan to a goal: stops at the goal, cuts the step it falls in, and asks for no rank past it", () => {
  const out = run(`
    local plan = ns.CRAFT_PLANS[164]
    -- Skill 80 to 250: the last steps are 215-225 Heavy Mithril Breastplate (10), 225-235 Dense Weightstone (15),
    -- 235-240 Mithril Coif (12), 240-246 Heavy Mithril Boots (17), 246-250 Big Black Mace (12).
    local p = ns.CraftPlan(plan, 80, nil, nil, nil, 225, 250)
    local last = p.steps[#p.steps]
    local by = {}
    for _, r in ipairs(p.rows) do by[r.id] = r end
    local full = ns.CraftPlan(plan, 80)
    -- A goal inside a step: 205-210 Mithril Plate Pants, 5 crafts, to 208 is 3 of them.
    local mid = ns.CraftPlan(plan, 206, nil, nil, nil, nil, 208)
    local r = {
      p.max, last.name, last.to, p.crafts, full.crafts - p.crafts,
      -- No Arcanite or Thorium below 250, no plans from Magnus or Pexmit.
      tostring(by[12360] == nil), tostring(by[12359] == nil), tostring(by[8030] == nil), tostring(by[251468] == nil),
      p.rank.name, mid.steps[1].name, mid.steps[1].to, mid.steps[1].crafts, #mid.steps,
      tostring(ns.CraftPlan(plan, 250, nil, nil, nil, nil, 250).done), tostring(ns.CraftPlan(plan, 150, nil, nil, nil, 150, 150).rank == nil),
      ns.CraftGoal(plan, 999), ns.CraftGoal(plan, nil), ns.CraftGoal(plan, 0),
    }
    return table.concat(r, "|")
  `);
  const [max, name, to, crafts, rest, ...more] = out.split("|");
  assert.equal(max, "250");
  assert.equal(name, "Big Black Mace");
  assert.equal(to, "250");
  // 250-300 is 10 + 20 + 5 + 4 + 24 = 63 crafts.
  assert.equal(Number(rest), 63);
  assert.equal(Number(crafts), 312 - 63);
  assert.deepEqual(more, ["true", "true", "true", "true", "Artisan", "Mithril Plate Pants", "208", "2", "1", "true", "true", "300", "300", "1"]);
});

test("rolls: Need, Greed and Disenchant lines with or without a [Loot] link, wins, and the averages", () => {
  const out = run(`
    local P = ns.RollPatterns({})
    local boots = "|cff1eff00|Hitem:6557::::|h[Bard's Boots]|h|r"
    local knife = "|cff9d9d9d|Hitem:2140::::|h[Carving Knife]|h|r"
    local function show(r) if not r then return "nil" end return table.concat({ r.kind, tostring(r.roll), tostring(r.who), r.id, r.name }, ",") end
    local r = {
      show(ns.ParseRoll("|Hlootroll:12|h|cff00ccff[Loot]|r|h: Need Roll - 87 for " .. boots .. " by Vitoc", P)),
      show(ns.ParseRoll("Greed Roll - 12 for " .. knife .. " by Kesh-Realm", P)),
      show(ns.ParseRoll("Need Roll - 40 for " .. boots .. " by Kesh + Role Bonus", P)),
      show(ns.ParseRoll("Disenchant Roll - 5 for " .. knife .. " by Vitoc", P)),
      show(ns.ParseRoll("You won: " .. boots, P)),
      show(ns.ParseRoll("You receive loot: " .. boots .. ".", P)),
    }
    local book = {}
    ns.AddRoll(book, "need", 87, 6557, "Bard's Boots", 100)
    ns.AddRoll(book, "need", 20, 2140, "Carving Knife", 110)
    ns.AddRoll(book, "greed", 50, 2140, "Carving Knife", 120)
    r[#r + 1] = tostring(ns.WonRoll(book, 6557, 200))
    r[#r + 1] = tostring(ns.WonRoll(book, 6557, 210)) -- won once
    r[#r + 1] = tostring(ns.WonRoll(book, 2140, 5000)) -- too late
    r[#r + 1] = table.concat({ ns.RollAverage(book.need), book.need.hi, book.need.lo, book.need.won, #book.recent, book.recent[1].name }, ",")
    r[#r + 1] = tostring(ns.RollAverage(book.de))
    -- WoW Forever's own strings: a loot history link with a number in front (seen 2026-11-27).
    local F = ns.RollPatterns({
      LOOT_ROLL_ROLLED_NEED = "|HlootHistory:%d|h[Loot]|h: Need Roll - %d for %s by %s",
      LOOT_ROLL_ROLLED_GREED = "|HlootHistory:%d|h[Loot]|h: Greed Roll - %d for %s by %s",
      LOOT_ROLL_YOU_WON = "|HlootHistory:%d|h[Loot]|h: You won: %s",
      LOOT_ROLL_ROLLED_DE = "%3$s rolls %1$d (Disenchant) for %2$s",
    })
    r[#r + 1] = show(ns.ParseRoll("|HlootHistory:12|h[Loot]|h: Need Roll - 87 for " .. boots .. " by Vitoc", F))
    r[#r + 1] = show(ns.ParseRoll("|HlootHistory:3|h[Loot]|h: Greed Roll - 1 for " .. knife .. " by Kesh", F))
    r[#r + 1] = show(ns.ParseRoll("|HlootHistory:12|h[Loot]|h: You won: " .. boots, F))
    r[#r + 1] = show(ns.ParseRoll("Vitoc rolls 64 (Disenchant) for " .. knife, F))
    return table.concat(r, "~")
  `);
  assert.deepEqual(out.split("~"), [
    "need,87,Vitoc,6557,Bard's Boots",
    "greed,12,Kesh-Realm,2140,Carving Knife",
    "need,40,Kesh,6557,Bard's Boots",
    "de,5,Vitoc,2140,Carving Knife",
    "won,nil,nil,6557,Bard's Boots",
    "nil",
    "need", "nil", "nil",
    "53.5,87,20,1,3,Carving Knife",
    "nil",
    "need,87,Vitoc,6557,Bard's Boots",
    "greed,1,Kesh,2140,Carving Knife",
    "won,nil,nil,6557,Bard's Boots",
    "de,64,Vitoc,2140,Carving Knife",
  ]);
});

test("at max level the XP tab is Today: gold, loot, runs and your rolls; Stats drops leveling and lists rolls", () => {
  const out = run(`
    CLOCK, MONEY = 100000, 50000
    time = function() return CLOCK end
    GetMoney = function() return MONEY end
    UnitLevel = function() return 60 end
    UnitXPMax = function() return 0 end
    UnitName = function() return "Vitoc" end
    local e = SnitchbotEvents
    local function go(event, ...) e.scripts.OnEvent(e, event, ...) end
    go("PLAYER_LOGIN")
    SlashCmdList.SNITCHBOT("today")
    local boots = "|cff1eff00|Hitem:6557::::|h[Bard's Boots]|h|r"
    local x = SnitchbotFrame.x
    local r = { x.level.text, x.xp.text }
    go("CHAT_MSG_LOOT", "|HlootHistory:12|h[Loot]|h: Need Roll - 87 for " .. boots .. " by Vitoc")
    go("CHAT_MSG_LOOT", "|HlootHistory:12|h[Loot]|h: Need Roll - 99 for " .. boots .. " by Kesh")
    go("CHAT_MSG_LOOT", "Kesh won: " .. boots)
    go("CHAT_MSG_LOOT", "Greed Roll - 30 for " .. boots .. " by Vitoc")
    MONEY = 62500
    CLOCK = CLOCK + 30
    SlashCmdList.SNITCHBOT("today")
    r[#r + 1] = x.xp.text
    r[#r + 1] = x.rateLabel.text .. "=" .. x.rate.text
    r[#r + 1] = x.goldLabel.text .. "=" .. x.gold.text
    r[#r + 1] = tostring(x.reset.shown)
    SlashCmdList.SNITCHBOT("stats")
    local lines = {}
    for _, row in ipairs(SnitchbotFrame.st.rows) do
      if row.shown then lines[#lines + 1] = (row.left.text or "") .. "=" .. (row.right.text or "") end
    end
    local all = table.concat(lines, "|")
    r[#r + 1] = tostring(all:find("LEVELING", 1, true) ~= nil)
    r[#r + 1] = tostring(all:find("YOUR ROLLS", 1, true) ~= nil)
    r[#r + 1] = all:match("Need: average [^|]*") or "none"
    r[#r + 1] = all:match("Greed: average [^|]*") or "none"
    return table.concat(r, "~")
  `, { ui: true });
  const r = out.split("~");
  assert.equal(r[0], "Today");
  assert.equal(r[1], "No Need or Greed rolls yet today.");
  assert.equal(r[2], "Your rolls: Need 87 (1)  ·  Greed 30 (1)");
  assert.equal(r[3], "Dungeon runs=0");
  assert.match(r[4], /^Gold=\+/);
  assert.equal(r[5], "false");
  assert.equal(r[6], "false");
  assert.equal(r[7], "true");
  assert.equal(r[8], "Need: average 87.0=1 roll  ·  won 0");
  assert.equal(r[9], "Greed: average 30.0=1 roll  ·  won 0");
});

test("rolls you lose come from the loot history, the winner's line counts once, and a classic history works too", () => {
  const out = run(`
    CLOCK = 100000
    time = function() return CLOCK end
    UnitLevel = function() return 60 end
    UnitXPMax = function() return 0 end
    UnitName = function() return "Vitoc" end
    local e = SnitchbotEvents
    local function go(event, ...) e.scripts.OnEvent(e, event, ...) end
    go("PLAYER_LOGIN")
    local arm = "|cnIQ3:|Hitem:9459::::::::34:1491::1::1:28:5242:::::|h[Thermaplugg's Left Arm]|h|r"
    local axe = "|cnIQ3:|Hitem:274598::::::::37:1491::1::1:28:4522:::::|h[Bloodslash Axe]|h|r"
    DROPS = {
      ["1:1"] = { itemHyperlink = axe, rollInfos = { { playerName = "Kesh", roll = 91, state = 0, isWinner = true }, { playerName = "Vitoc", roll = 16, state = 0, isSelf = true } } },
      ["1:2"] = { itemHyperlink = arm, rollInfos = { { playerName = "Vitoc", roll = 77, state = 3, isSelf = true, isWinner = true } } },
    }
    C_LootHistory = { GetSortedInfoForDrop = function(a, b) return DROPS[a .. ":" .. b] end }
    go("LOOT_HISTORY_UPDATE_DROP", 1, 1)
    go("LOOT_HISTORY_UPDATE_DROP", 1, 1) -- the same drop again: no second roll
    go("LOOT_HISTORY_UPDATE_DROP", 1, 2)
    CLOCK = CLOCK + 5
    go("CHAT_MSG_LOOT", "|HlootHistory:4|h[Loot]|h: You (Greed - 77) Won: " .. arm)
    local book = SnitchbotDB.chars.Vitoc.rolls
    local r = { book.need.n, book.need.sum, book.need.won, book.greed.n, book.greed.won, #book.recent }
    -- A winner's line with no history behind it counts by itself.
    go("CHAT_MSG_LOOT", "|HlootHistory:5|h[Loot]|h: You (Need - 64) Won: " .. axe)
    r[#r + 1] = book.need.n .. "/" .. book.need.won
    -- Someone else's winning line is not yours.
    go("CHAT_MSG_LOOT", "|HlootHistory:6|h[Loot]|h: Kesh (Need - 99) Won: " .. axe)
    r[#r + 1] = book.need.n
    -- The classic loot history: GetItem and GetPlayerInfo.
    C_LootHistory = {
      GetItem = function(i) return 7, axe, 2, true, 1 end,
      GetPlayerInfo = function(i, j) if j == 1 then return "Kesh", "ROGUE", 2, 40, true, false end return "Vitoc", "WARRIOR", 2, 33, false, true end,
      GetNumItems = function() return 1 end,
    }
    go("LOOT_HISTORY_FULL_UPDATE")
    r[#r + 1] = book.greed.n .. "/" .. book.greed.sum
    r[#r + 1] = tostring(#SnitchbotDB.rollTrace > 0)
    return table.concat(r, "~")
  `, { ui: true });
  assert.deepEqual(out.split("~"), ["1", "16", "0", "1", "1", "2", "2/1", "2", "2/110", "true"]);
});

test("the window resizes from its corner: the size is kept, held to its bounds, and a double-click resets it", () => {
  const out = run(`
    local e = SnitchbotEvents
    e.scripts.OnEvent(e, "PLAYER_LOGIN")
    SlashCmdList.SNITCHBOT("craft")
    local f = SnitchbotFrame
    local sizes = {}
    f.SetSize = function(_, w, h) sizes[#sizes + 1] = w .. "x" .. h end
    f.StartSizing = function(_, corner) SIZING = corner end
    local W, H = 520, 640
    f.GetWidth = function() return W end
    f.GetHeight = function() return H end
    f.GetPoint = function() return "TOPLEFT", UIParent, "BOTTOMLEFT", 100, 700 end
    f.grip.scripts.OnMouseDown(f.grip, "LeftButton")
    f.grip.scripts.OnMouseUp(f.grip)
    local s = SnitchbotDB.settings
    local r = { SIZING, s.size[1] .. "x" .. s.size[2], s.pos.SnitchbotFrame[1], sizes[#sizes] }
    W, H = 2000, 100
    f.grip.scripts.OnMouseUp(f.grip)
    r[#r + 1] = sizes[#sizes]
    f.grip.scripts.OnDoubleClick(f.grip)
    r[#r + 1] = tostring(s.size)
    r[#r + 1] = sizes[#sizes]
    -- The rows in a scroll area follow its width.
    local k = f.k
    local widths = {}
    k.child.SetWidth = function(_, w) widths[#widths + 1] = w end
    k.scroll.scripts.OnSizeChanged(k.scroll, 488, 300)
    r[#r + 1] = widths[1]
    return table.concat(r, "~")
  `, { ui: true });
  assert.deepEqual(out.split("~"), ["BOTTOMRIGHT", "520x640", "TOPLEFT", "520x640", "800x470", "nil", "360x470", "488"]);
});

test("the Craft tab goal: type it in the box or /sb craft 250, kept per profession, max goes back to the cap", () => {
  const out = run(`
    GetProfessions = function() return 3 end
    GetProfessionInfo = function() return "Blacksmithing", 136241, 80, 300, 0, 0, 164 end
    local e = SnitchbotEvents
    e.scripts.OnEvent(e, "PLAYER_LOGIN")
    SlashCmdList.SNITCHBOT("craft")
    local k = SnitchbotFrame.k
    local r = { k.goal.text, k.sub.text }
    k.goal:SetText("150")
    k.goal.scripts.OnEnterPressed(k.goal)
    r[#r + 1] = k.goal.text
    r[#r + 1] = k.sub.text
    r[#r + 1] = SnitchbotDB.settings.craftGoal[164]
    SlashCmdList.SNITCHBOT("craft 250")
    r[#r + 1] = k.sub.text
    SlashCmdList.SNITCHBOT("craft max")
    r[#r + 1] = tostring(SnitchbotDB.settings.craftGoal[164])
    r[#r + 1] = k.goal.text
    SlashCmdList.SNITCHBOT("craft 80")
    r[#r + 1] = k.sub.text
    return table.concat(r, "~")
  `, { ui: true });
  assert.deepEqual(out.split("~"), [
    "300", "Next: Rough Bronze Leggings x10 (80-90)  ·  312 crafts to 300",
    "150", "Next: Rough Bronze Leggings x10 (80-90)  ·  90 crafts to 150",
    "150",
    "Next: Rough Bronze Leggings x10 (80-90)  ·  249 crafts to 250",
    "nil", "300",
    "Goal reached: you're at 80. Raise the goal to go on.",
  ]);
});

test("the Craft tab: reads your skill, prices the shopping list, and lists the steps", () => {
  const out = run(`
    GetProfessions = function() return 3, 4 end
    GetProfessionInfo = function(i)
      if i == 3 then return "Blacksmithing", 136241, 80, 150, 0, 0, 164 end
      return "Mining", 136248, 115, 150, 0, 0, 186
    end
    BAGS = { [2841] = 60 }
    C_Item.GetItemCount = function(id, bank) return BAGS[id] or 0 end
    local e = SnitchbotEvents
    e.scripts.OnEvent(e, "PLAYER_LOGIN")
    SnitchbotDB.prices = { house = "EU-NORMAL-ALLIANCE", at = 1, count = 2, prices = { [2841] = 175, [3860] = 1309 } }
    SlashCmdList.SNITCHBOT("craft")
    local k = SnitchbotFrame.k
    local shop = { k.who.text, k.sub.text, k.status.text, k.ready.text, k.view.label.text }
    BAGS[2841] = 400
    e.scripts.OnEvent(e, "BAG_UPDATE_DELAYED")
    shop[#shop + 1] = k.ready.text
    k.view.scripts.OnClick()
    local steps = { k.rows[1].name.text, k.rows[1].count.text, k.ready.text, k.view.label.text }
    return table.concat(shop, "~") .. "#" .. table.concat(steps, "~")
  `, { ui: true });
  const [shop, steps] = out.split("#");
  const s = shop.split("~");
  assert.equal(s[0], "Blacksmithing 80");
  assert.equal(s[1], "Next: Rough Bronze Leggings x10 (80-90)  ·  312 crafts to 300");
  assert.match(s[2], /Train Expert: your cap is 150\./);
  assert.match(s[3], /^0 of \d+ materials ready$/);
  assert.equal(s[4], "Steps");
  assert.match(s[5], /^1 of \d+ materials ready$/);
  assert.deepEqual(steps.split("~"), ["80-90  Rough Bronze Leggings", "x10", "Skill 80 of 300", "Shopping"]);
});

test("cooking plan: Wowhead's six steps, the Horde vendor, and the book and quest ranks", () => {
  const out = run(`
    local plan = ns.CraftPlanFor(185)
    local fresh = ns.CraftPlan(plan, 1)
    local mid = ns.CraftPlan(plan, 140, nil, nil, nil, 150)
    local late = ns.CraftPlan(plan, 210, nil, nil, nil, 225)
    local snapper = plan.steps[2][7]
    return table.concat({ plan.name, fresh.crafts, #fresh.steps, tostring(fresh.rows[1].tool),
      mid.steps[1].name, mid.steps[1].crafts, mid.rank.name, mid.rank.how,
      late.rank.name, late.rank.how,
      ns.CraftVendor(snapper, "Horde").npc, ns.CraftVendor(snapper, "Alliance").npc, ns.CraftVendor(plan.steps[3][7], "Horde").npc }, "~")
  `);
  assert.deepEqual(out.split("~"), [
    "Cooking", "347", "6", "nil",
    // 140 to 175 is 35 of the catfish step's 75 points: 56 of 120 crafts.
    "Bristle Whisker Catfish", "56", "Expert",
    "Expert: buy The Expert Cookbook from Shandrina (Ashenvale) or Wulan (Desolace). Needs skill 125.",
    "Artisan", "Artisan: the quest Clamlette Surprise from Dirge Quikcleave in Gadgetzan, Tanaris. Needs level 35.",
    "Naal Mistrunner", "Tharynn Bouden", "Kilxx",
  ]);
});

test("the Craft tab dropdown: your professions first, then every other plan; pick one, even one you haven't learned", () => {
  const out = run(`
    GetProfessions = function() return 3, nil, nil, 9, 10 end
    GetProfessionInfo = function(i)
      if i == 3 then return "Blacksmithing", 136241, 80, 150, 0, 0, 164 end
      if i == 9 then return "Fishing", 136245, 90, 150, 0, 0, 356 end
      return "Cooking", 133971, 140, 150, 0, 0, 185
    end
    UnitFactionGroup = function() return "Horde" end
    local e = SnitchbotEvents
    e.scripts.OnEvent(e, "PLAYER_LOGIN")
    SlashCmdList.SNITCHBOT("craft")
    local k = SnitchbotFrame.k
    local r = { k.pick.label.text, tostring(k.menu.shown) }
    k.pick.scripts.OnClick()
    local names = {}
    for _, b in ipairs(k.menu.items) do if b.shown then names[#names + 1] = b.name.text .. "=" .. b.skill.text end end
    r[#r + 1] = table.concat(names, ",")
    -- Pick Cooking.
    k.menu.items[2].scripts.OnClick()
    r[#r + 1] = tostring(k.menu.shown)
    r[#r + 1] = k.pick.label.text
    r[#r + 1] = k.status.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    k.view.scripts.OnClick()
    r[#r + 1] = k.rows[1].name.text
    r[#r + 1] = k.rows[1].tip[3]
    SlashCmdList.SNITCHBOT("craft 160")
    r[#r + 1] = k.sub.text
    SlashCmdList.SNITCHBOT("craft black")
    r[#r + 1] = k.pick.label.text
    r[#r + 1] = k.goal.text
    SlashCmdList.SNITCHBOT("craft cook")
    r[#r + 1] = k.goal.text
    -- Tailoring isn't learned: the steps from 1, and how to get it.
    k.pick.scripts.OnClick()
    for _, b in ipairs(k.menu.items) do if b.name.text == "Tailoring" then b.scripts.OnClick() end end
    r[#r + 1] = k.pick.label.text
    r[#r + 1] = k.status.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    r[#r + 1] = k.rows[1].name.text
    r[#r + 1] = k.ready.text
    return table.concat(r, "#")
  `, { ui: true });
  assert.deepEqual(out.split("#"), [
    "Blacksmithing 80", "false",
    "Blacksmithing=80 / 150,Cooking=140 / 150,Alchemy=not learned,Enchanting=not learned,Engineering=not learned,"
      + "First Aid=not learned,Leatherworking=not learned,Tailoring=not learned",
    "false", "Cooking 140",
    "Expert: buy The Expert Cookbook from Shandrina (Ashenvale) or Wulan (Desolace). Needs skill 125. Your cap is 150.",
    "100-175  Bristle Whisker Catfish",
    "Recipe from Kilxx, The Barrens.",
    "Next: Bristle Whisker Catfish x32 (100-160)  ·  32 crafts to 160",
    "Blacksmithing 80", "300", "160",
    "Tailoring",
    "You haven't learned Tailoring: any Tailoring trainer teaches it.",
    "1-43  Bolt of Linen Cloth", "Skill 1 of 300",
  ]);
});

test("the Craft list starts at the top for another profession or view, and never stays scrolled past a shorter list", () => {
  const out = run(`
    GetProfessions = function() return 3, nil, nil, nil, 10 end
    GetProfessionInfo = function(i)
      if i == 3 then return "Blacksmithing", 136241, 80, 150, 0, 0, 164 end
      return "Cooking", 133971, 60, 75, 0, 0, 185
    end
    local e = SnitchbotEvents
    e.scripts.OnEvent(e, "PLAYER_LOGIN")
    SlashCmdList.SNITCHBOT("craft black")
    local sf = SnitchbotFrame.k.scroll
    sf.vs, sf.range = 0, 0
    sf.SetVerticalScroll = function(self, v) self.vs = v end
    sf.GetVerticalScroll = function(self) return self.vs end
    sf.GetVerticalScrollRange = function(self) return self.range end
    sf.GetHeight = function() return 300 end
    -- Scrolled far down the Blacksmithing list, then Cooking.
    sf.vs = 400
    SlashCmdList.SNITCHBOT("craft cook")
    local r = { sf.vs }
    -- The same list redrawn keeps its place; a list that got shorter is clamped to its end.
    sf.vs, sf.range = 40, 100
    e.scripts.OnEvent(e, "BAG_UPDATE_DELAYED")
    r[#r + 1] = sf.vs
    sf.range = 10
    sf.place()
    r[#r + 1] = sf.vs
    SnitchbotFrame.k.view.scripts.OnClick()
    r[#r + 1] = sf.vs
    return table.concat(r, " ")
  `, { ui: true });
  assert.equal(out, "0 40 10 0");
});

test("every profession plan runs 1 to 300 with no gaps, and each part it makes has a recipe or a step", () => {
  const out = run(`
    local r = {}
    local lines = {}
    for line in pairs(ns.CRAFT_PLANS) do lines[#lines + 1] = line end
    table.sort(lines)
    for _, line in ipairs(lines) do
      local plan = ns.CRAFT_PLANS[line]
      local at, bad = 1, {}
      for i, s in ipairs(plan.steps) do
        if s[1] ~= at or s[2] <= s[1] or s[5] < 1 then bad[#bad + 1] = i end
        for _, m in ipairs(s[6]) do if not (m[1] > 0 and m[2] > 0) then bad[#bad + 1] = i end end
        at = s[2]
      end
      local fresh = ns.CraftPlan(plan, 1)
      r[#r + 1] = string.format("%s:%d:%d:%s:%s", plan.name, at, fresh.crafts, #bad == 0 and "ok" or table.concat(bad, ","), tostring(plan.icon ~= nil))
    end
    return table.concat(r, " ")
  `);
  assert.equal(out, [
    // The crafts are the guides' own numbers added up.
    "First Aid:300:390:ok:true", "Blacksmithing:300:401:ok:true", "Leatherworking:300:409:ok:true",
    "Alchemy:300:316:ok:true", "Cooking:300:347:ok:true", "Tailoring:300:365:ok:true",
    "Engineering:300:393:ok:true", "Enchanting:300:315:ok:true",
  ].join(" "));
});

test("parts the steps make count for later steps; the rest is made, even parts inside parts", () => {
  const out = run(`
    local eng, tail = ns.CRAFT_PLANS[202], ns.CRAFT_PLANS[197]
    local function rows(p) local by = {} for _, r in ipairs(p.rows) do by[r.id] = r end return by end
    local fresh = rows(ns.CraftPlan(eng, 1))
    -- 216: past the Unstable Trigger step, so the bombs' triggers are made, each with Solid Blasting Powder.
    local late = rows(ns.CraftPlan(eng, 216))
    local cloth = rows(ns.CraftPlan(tail, 1, function(id) return id == 2997 and 10 or 0 end))
    local function n(r) return r and (r.need .. "/" .. r.missing .. (r.made and "m" or "")) or "-" end
    return table.concat({
      n(fresh[4357]), n(fresh[2835]), n(fresh[4359]), n(fresh[10560]), n(fresh[10505]), n(fresh[4377]), n(fresh[2838]),
      n(late[10560]), n(late[10505]), n(late[7912]), n(late[3860]), n(late[10561]),
      n(cloth[2996]), n(cloth[2997]), n(cloth[2592]),
    }, " ")
  `);
  assert.deepEqual(out.split(" "), [
    // Powder: 58 for the bombs, 32 from the 1-30 step, 26 more made; stone for all 58.
    "26/26m", "58/58",
    // Bolts: 29 for the bombs, 20 from 30-50, 9 more made.
    "9/9m",
    // Triggers and solid powder: the steps make enough.
    "-", "-",
    // Heavy Blasting Powder: no step makes it, so all 30 from Heavy Stone.
    "30/30m", "30/30",
    // From 216: 15 triggers made, 30 + 15 solid powder, 90 Solid Stone, 96 + 15 Mithril; casings covered.
    "15/15m", "45/45m", "90/90", "111/111", "-",
    // Linen bolts covered; woolen: 84 - 12 made by the step = 72, 10 in bags, 62 made from 186 + 36 wool.
    "-", "72/62m", "222/222",
  ]);
});

test("the Craft tab tips: special trainers for your side, step notes, and the disenchant step", () => {
  const out = run(`
    GetProfessions = function() return 3, 4 end
    GetProfessionInfo = function(i)
      if i == 3 then return "Enchanting", 136244, 1, 75, 0, 0, 333 end
      return "Alchemy", 136240, 265, 300, 0, 0, 171
    end
    UnitFactionGroup = function() return "Horde" end
    local e = SnitchbotEvents
    e.scripts.OnEvent(e, "PLAYER_LOGIN")
    SnitchbotDB.settings.craftView = "steps"
    SlashCmdList.SNITCHBOT("craft ench")
    local k = SnitchbotFrame.k
    local r = { k.who.text, k.rows[1].tip[3], k.rows[1].tip[4], k.rows[2].name.text, tostring(k.rows[2].tip[3]), tostring(k.rows[2].tip[4]) }
    SlashCmdList.SNITCHBOT("craft alch")
    r[#r + 1] = k.rows[2].name.text
    r[#r + 1] = k.rows[2].tip[3]
    r[#r + 1] = k.rows[2].tip[4]
    return table.concat(r, "#")
  `, { ui: true });
  assert.deepEqual(out.split("#"), [
    "Enchanting 1",
    "From the trainer.",
    "Keep the rod: the enchants to 155 need it. Mote of Magic is sold by enchanting supply vendors.",
    "2-20  Disenchant green items",
    "Each green or better item you disenchant is a skill point up to 20. Keep the dust and essences.", "nil",
    "270-300  Major Discolored Healing Potion",
    "Trained by Apothecary Renferrel, Silverpine Forest.",
    "Taught after a short questline.",
  ]);
});

// A fake auction house: AUCTIONS rows are { id, count, buyout }.
const FAKE_AH = `
  AUCTIONS = {}
  SENT = {}
  CAN_REPLICATE = true
  GetTime = function() return CLOCK end
  CLOCK = 100
  AuctionHouseFrame = CreateFrame("Frame", "AuctionHouseFrame")
  AuctionHouseFrame.IsShown = function() return true end
  C_AuctionHouse = {
    ReplicateItems = function() REPLICATED = true end,
    GetNumReplicateItems = function() return #AUCTIONS end,
    GetReplicateItemInfo = function(i)
      local a = AUCTIONS[i + 1]
      return "x", 1, a[2], 1, true, 1, 0, 0, 0, a[3], 0, false, nil, "Seller", nil, 0, a[1], true
    end,
    MakeItemKey = function(id) return { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end,
    SendSearchQuery = function(key) SENT[#SENT + 1] = key.itemID end,
    IsThrottledMessageSystemReady = function() return true end,
    GetNumCommoditySearchResults = function(id) local n = 0; for _, a in ipairs(AUCTIONS) do if a[1] == id then n = n + 1 end end; return n end,
    GetCommoditySearchResultInfo = function(id, i)
      local best
      for _, a in ipairs(AUCTIONS) do if a[1] == id and (not best or a[3] / a[2] < best) then best = a[3] / a[2] end end
      return { itemID = id, unitPrice = best and math.floor(best) }
    end,
  }
  local e = SnitchbotEvents
  e.scripts.OnEvent(e, "PLAYER_LOGIN")
  GetProfessions = function() return 3 end
  GetProfessionInfo = function() return "Blacksmithing", 1, 290, 300, 0, 0, 164 end
  SnitchbotDB.prices = { house = "EU-NORMAL-ALLIANCE", at = 1, count = 2, prices = { [12359] = 9999, [123] = 50 } }
  e.scripts.OnEvent(e, "AUCTION_HOUSE_SHOW")
  BUTTON = AuctionHouseFrame
  -- The scan's ticker: the last frame made with an OnUpdate (the window's comes first).
  for _, f in ipairs(FRAMES) do if f.scripts.OnUpdate and f ~= SnitchbotFrame then TICKER = f end end
  function tick(n) for _ = 1, n or 1 do CLOCK = CLOCK + 0.1; TICKER.scripts.OnUpdate(TICKER, 0.1) end end
`;

test("AH scan: one full scan keeps the lowest price per item and replaces the pasted prices", () => {
  const out = run(`
    ${FAKE_AH}
    AUCTIONS = { { 12359, 20, 40000 }, { 12359, 5, 12500 }, { 3860, 1, 1500 }, { 3860, 10, 0 } }
    SlashCmdList.SNITCHBOT("scan")
    local asked = tostring(REPLICATED)
    e = SnitchbotEvents
    e.scripts.OnEvent(e, "REPLICATE_ITEM_LIST_UPDATE")
    tick(3)
    local p = SnitchbotDB.prices
    -- A second scan within 15 minutes searches the lists instead.
    SlashCmdList.SNITCHBOT("scan")
    local second = SnitchbotDB.prices.scan
    return table.concat({ asked, p.prices[12359], p.prices[3860], tostring(p.prices[123]), p.count, p.scan, p.house, tostring(second) }, "|")
  `, { ui: true });
  assert.equal(out, "true|2000|1500|nil|2|full|In-game scan|full");
});

test("AH scan: without a full scan it searches the Craft list items one at a time and keeps other prices", () => {
  const out = run(`
    ${FAKE_AH}
    C_AuctionHouse.ReplicateItems = nil
    AUCTIONS = { { 12359, 20, 40000 }, { 7082, 1, 30000 } }
    SlashCmdList.SNITCHBOT("scan")
    -- Answer each search as the game would; one item gets no answer and times out.
    for _ = 1, 40 do
      local id = SENT[#SENT]
      if id and id ~= LAST then
        LAST = id
        if id ~= 8170 then e = SnitchbotEvents; e.scripts.OnEvent(e, "COMMODITY_SEARCH_RESULTS_UPDATED", id) end
      end
      tick(1)
      if id == 8170 then tick(40) end
    end
    local p = SnitchbotDB.prices
    return table.concat({ #SENT, p.prices[12359], p.prices[7082], p.prices[123], p.scan, tostring(p.prices[8170]), SAID[#SAID] }, "~")
  `, { ui: true });
  const [sent, thorium, air, kept, kind, rugged, said] = out.split("~");
  assert.ok(Number(sent) >= 5, `searched ${sent} items`);
  assert.equal(thorium, "2000");
  assert.equal(air, "30000");
  assert.equal(kept, "50");
  assert.equal(kind, "items");
  assert.equal(rugged, "nil");
  assert.match(said, /Prices saved for 2 items\./);
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

test("a run ends when you leave the area alive, leave the group outside, or type /sb end; a corpse run or the door keeps it", () => {
  const out = run(`
    CLOCK, INSIDE, ZONE, GHOST, GROUP = 1000, false, "Blackrock Mountain", false, true
    time = function() return CLOCK end
    IsInInstance = function() if INSIDE then return true, "party" end return false, "none" end
    GetInstanceInfo = function() return "Blackrock Depths", "party", 1, "Normal", 5, 0, false, 230 end
    GetRealZoneText = function() if INSIDE then return "Blackrock Depths" end return ZONE end
    UnitIsDeadOrGhost = function() return GHOST end
    UnitLevel = function() return 60 end
    LoggingCombat = function() end
    IsInGroup = function() return GROUP end
    IsInRaid = function() return false end
    UnitName = function(u) if u == "party1" then return "Kesh" end if u == "player" then return "Vitoc War" end return nil end
    UnitClass = function() return "Rogue", "ROGUE" end
    CHAT = {}
    SendChatMessage = function(msg, channel) CHAT[#CHAT + 1] = msg end
    local e = SnitchbotEvents
    local function go(event, ...) e.scripts.OnEvent(e, event, ...) end
    local function enter() INSIDE = true; go("PLAYER_ENTERING_WORLD") end
    local function leave(zone) INSIDE = false; ZONE = zone or ZONE; go("PLAYER_ENTERING_WORLD") end
    -- The Snitchbot line containing text, said since mark (nil if none).
    local mark = 0
    local function said(text)
      for i = mark + 1, #SAID do
        local line = SAID[i]:gsub("^|c%x+Snitchbot:|r ", "")
        if line:find(text, 1, true) then return line end
      end
      return "none"
    end
    local r = {}
    go("PLAYER_LOGIN")
    go("ZONE_CHANGED_NEW_AREA")
    enter()
    -- 1. Wipe: a ghost at the graveyard in another zone keeps the run.
    CLOCK = CLOCK + 300; GHOST = true; leave("Burning Steppes")
    r[#r + 1] = tostring(SnitchbotDB.run ~= nil)
    GHOST = false; ZONE = "Blackrock Mountain"; enter()
    -- 2. Waiting at the door: still open, and the XP tab counts down.
    mark = #SAID; CLOCK = CLOCK + 300; leave()
    r[#r + 1] = tostring(SnitchbotDB.run ~= nil)
    r[#r + 1] = said("Out of")
    CLOCK = CLOCK + 120; go("ZONE_CHANGED_NEW_AREA")
    -- 3. Hearth to Ironforge: ended at once.
    mark = #SAID; CLOCK = CLOCK + 60; ZONE = "Ironforge"; go("ZONE_CHANGED_NEW_AREA")
    r[#r + 1] = tostring(SnitchbotDB.run ~= nil)
    r[#r + 1] = said("Left")
    -- 4. Back in within 15 minutes: no second announcement, and one run in the list.
    local announced = #CHAT
    mark = #SAID; ZONE = "Blackrock Mountain"; go("ZONE_CHANGED_NEW_AREA"); CLOCK = CLOCK + 200; enter()
    r[#r + 1] = said("Back in") .. "/" .. said("Tracking")
    -- 5. Out of the dungeon and out of the group: ended.
    CLOCK = CLOCK + 100; leave(); GROUP = false; go("GROUP_ROSTER_UPDATE")
    r[#r + 1] = tostring(SnitchbotDB.run ~= nil)
    r[#r + 1] = #SnitchbotDB.runs
    r[#r + 1] = tostring(#CHAT == announced)
    -- 6. /sb end, from anywhere.
    GROUP = true; CLOCK = CLOCK + 3600; enter(); CLOCK = CLOCK + 60
    SlashCmdList.SNITCHBOT("end")
    r[#r + 1] = tostring(SnitchbotDB.run ~= nil)
    mark = #SAID; SlashCmdList.SNITCHBOT("end")
    r[#r + 1] = said("No run")
    return table.concat(r, "|")
  `, { ui: true });
  assert.equal(out, [
    "true", "true",
    "Out of Blackrock Depths. The run ends in 15 minutes, when you leave the area, or now with /sb end.",
    "false", "Left Blackrock Depths: run ended.",
    "Back in Blackrock Depths: same run./none",
    "false", "1", "true",
    "false", "No run is open.",
  ].join("|"));
});

test("ns.LeftArea: alive elsewhere than where you went in", () => {
  const out = run(`
    return table.concat({
      tostring(ns.LeftArea("Ironforge", "Blackrock Mountain", "Ironforge", true)),
      tostring(ns.LeftArea("Blackrock Mountain", "Blackrock Mountain", "Blackrock Mountain", true)),
      tostring(ns.LeftArea("Burning Steppes", "Blackrock Mountain", "Burning Steppes", false)),
      tostring(ns.LeftArea("Ironforge", nil, "Blackrock Mountain", true)),
      tostring(ns.LeftArea("Ironforge", nil, nil, true)),
      tostring(ns.LeftArea(nil, "Blackrock Mountain", nil, true)),
    }, "|")
  `);
  assert.equal(out, "true|false|false|true|false|false");
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
