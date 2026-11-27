--[[ Snitchbot: personal bests, level log, where XP and gold come from, loot
  value, the group's raid buffs and the export code for snitchbot.app. No UI
  here, so tests/code.test.mjs runs it against a fake game.

  Price code, made by auction.snitchbot.app ("Copy prices for the addon"):
    SNITCHBOT:PRICES:1;<house>;<unix time>;<item id>.<copper>,...;END
  with ids and prices in base 36 to keep it short. The website's writer is
  addonPriceCode() in snitchbot-forever/src/lib/ah/addon-prices.ts.

  Character code, read by myself.snitchbot.app:
    SNITCHBOT:CHAR:1;<region>;<name>;<class>;<level>;<unix time>;<levels>;<runs>;<gold>;<xp>;<rep>;END
  levels  <level>.<seconds played>.<unix time reached>,...
  runs    <dungeon>.<started>.<seconds>.<kills>.<xp>.<copper>.<deaths>.<boss kills>.<boss pulls>.<items>.<loot value>,...
  gold    <source>.<copper>,...      (copper can be negative)
  xp      <source>.<xp>,...
  rep     <faction>.<points>,...
  Text is %-encoded except letters, digits and spaces, as ns.Encode does.
  The website's reader is parseAddonCode() in snitchbot-forever/src/lib/addon-import.ts.
]]
local _, ns = ...
ns = ns or {}

ns.PRICES_PREFIX = "SNITCHBOT:PRICES:1"
ns.CHAR_PREFIX = "SNITCHBOT:CHAR:1"

local function add(t, key, n)
  if key == nil or not n or n == 0 then return end
  t[key] = (t[key] or 0) + n
end
ns.Add = add

-- ---- Prices

--- The price code -> { house, at, prices = { [itemId] = copper }, count }, or nil and why.
function ns.ParsePrices(text)
  text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text:sub(1, #ns.PRICES_PREFIX) ~= ns.PRICES_PREFIX then return nil, "That isn't a Snitchbot price code." end
  local parts = {}
  for part in (text .. ";"):gmatch("(.-);") do parts[#parts + 1] = part end
  if parts[#parts] ~= "END" then return nil, "The price code is cut off. Copy it again." end
  local prices, count = {}, 0
  for id, price in (parts[4] or ""):gmatch("(%w+)%.(%w+)") do
    local i, p = tonumber(id, 36), tonumber(price, 36)
    if i and p then prices[i] = p; count = count + 1 end
  end
  if count == 0 then return nil, "The price code has no prices in it." end
  return { house = ns.Decode(parts[2]), at = tonumber(parts[3]) or 0, prices = prices, count = count }
end

-- ---- Prices from an auction house scan in the game

--- What one of a stack costs at its buyout, in copper; nil with no buyout.
function ns.UnitPrice(count, buyout)
  buyout = tonumber(buyout)
  if not buyout or buyout <= 0 then return nil end
  return math.floor(buyout / math.max(1, tonumber(count) or 1))
end

--- Keeps the lowest price seen per item in `t`.
function ns.KeepLowest(t, id, price)
  id, price = tonumber(id), tonumber(price)
  if id and price and price > 0 and (not t[id] or price < t[id]) then t[id] = price end
end

--- The price record after a scan. A full scan replaces every price; a search
--- of some items updates those and keeps the rest.
--- -> { house, at, prices, count, scan = "full" | "items" }
function ns.MergePrices(old, found, full, at, house)
  local prices = {}
  if not full and type(old) == "table" and type(old.prices) == "table" then
    for id, p in pairs(old.prices) do prices[id] = p end
  end
  for id, p in pairs(found) do prices[id] = p end
  local count = 0
  for _ in pairs(prices) do count = count + 1 end
  return { house = house or (type(old) == "table" and old.house) or "In-game scan", at = at, prices = prices, count = count, scan = full and "full" or "items" }
end

-- ---- Runs: personal bests, comparisons, who you run with, what bosses drop

local function dungeon(run) return (tostring(run.key or run.name or ""):match("^[^:]*")) end
ns.Dungeon = dungeon

local function seconds(run) return (run.ended or run.started) - run.started end

--- Best runs per dungeon: the fastest full clear (most bosses killed in any run
--- of it, at least one) and the best XP per hour (runs of 10 minutes or more).
function ns.Bests(list)
  local out, order = {}, {}
  for _, run in ipairs(list) do
    if run.ended then
      local key = dungeon(run)
      local b = out[key]
      if not b then
        b = { name = run.name, runs = 0, bosses = 0 }
        out[key] = b
        order[#order + 1] = key
      end
      b.runs = b.runs + 1
      local kills = ns.BossCount(run)
      local s = seconds(run)
      if kills > b.bosses then b.bosses, b.fastest = kills, nil end
      if kills > 0 and kills == b.bosses and (not b.fastest or s < seconds(b.fastest)) then b.fastest = run end
      local rate = s >= 600 and ns.Rate(run.xp or 0, s)
      if rate and (not b.rate or rate > b.rate) then b.rate, b.rateRun = rate, run end
    end
  end
  return out, order
end

--- How a run that just ended compares with the earlier runs of the same dungeon,
--- as one sentence, or nil when there's nothing to compare with.
function ns.RunVerdict(run, earlier)
  local key, same = dungeon(run), {}
  for _, r in ipairs(earlier) do
    if r ~= run and r.ended and dungeon(r) == key then same[#same + 1] = r end
  end
  if #same == 0 then return nil end
  local kills = ns.BossCount(run)
  local s = seconds(run)
  local best = ns.Bests(same)[key]
  if kills > 0 and best and kills >= best.bosses and best.fastest and s < seconds(best.fastest) then
    return string.format("New best for %s: %s (was %s).", run.name, ns.Duration(s), ns.Duration(seconds(best.fastest)))
  end
  local rate = s >= 600 and ns.Rate(run.xp or 0, s)
  if rate and best and best.rate and rate > best.rate then
    return string.format("Best XP per hour in %s yet: %s (was %s).", run.name, ns.Num(rate), ns.Num(best.rate))
  end
  local last = same[1]
  local lastKills = ns.BossCount(last)
  if kills > 0 and kills == lastKills then
    local diff = s - seconds(last)
    if math.abs(diff) >= 60 then
      return string.format("%s %s than last time.", ns.Duration(math.abs(diff)), diff < 0 and "faster" or "slower")
    end
  end
  return nil
end

--- Who you've run with: { name, class, runs, last } sorted by runs, then most recent.
function ns.GroupHistory(list)
  local by, out = {}, {}
  for _, run in ipairs(list) do
    for name, class in pairs(run.group or {}) do
      local g = by[name]
      if not g then
        g = { name = name, class = class, runs = 0, last = 0 }
        by[name] = g
        out[#out + 1] = g
      end
      g.runs = g.runs + 1
      if (run.started or 0) > g.last then g.last = run.started or 0 end
    end
  end
  table.sort(out, function(a, b)
    if a.runs ~= b.runs then return a.runs > b.runs end
    if a.last ~= b.last then return a.last > b.last end
    return a.name < b.name
  end)
  return out
end

--- What each boss dropped across runs: { boss, kills, items = { { id, name, q, n } } }, most kills first.
function ns.BossLoot(list)
  local by, out = {}, {}
  local function boss(name)
    local b = by[name]
    if not b then
      b = { boss = name, kills = 0, items = {}, seen = {} }
      by[name] = b
      out[#out + 1] = b
    end
    return b
  end
  for _, run in ipairs(list) do
    for _, b in ipairs(run.bosses or {}) do
      if b.kill and b.name then boss(b.name).kills = boss(b.name).kills + 1 end
    end
    for _, l in ipairs(run.loot or {}) do
      if l.boss then
        local b = boss(l.boss)
        local item = b.seen[l.id]
        if not item then
          item = { id = l.id, name = l.name, q = l.q, n = 0 }
          b.seen[l.id] = item
          b.items[#b.items + 1] = item
        end
        item.n = item.n + (l.n or 1)
      end
    end
  end
  for _, b in ipairs(out) do
    b.seen = nil
    table.sort(b.items, function(x, y)
      if (x.q or 0) ~= (y.q or 0) then return (x.q or 0) > (y.q or 0) end
      return x.n > y.n
    end)
  end
  table.sort(out, function(a, b) return a.kills > b.kills end)
  return out
end

-- ---- XP

--- The bonus XP on a kill line: "(+45 exp Rested bonus)", "(+12 group bonus)".
function ns.XPBonus(msg)
  local total = 0
  for n in tostring(msg or ""):gmatch("%+(%d+)") do total = total + tonumber(n) end
  return total
end

--- "Discovered Westfall: 120 experience gained" -> 120, from the game's own string.
function ns.ExploreXP(msg, format)
  local f = type(format) == "string" and format ~= "" and format or "Discovered %s: %d experience gained"
  local name, xp = tostring(msg or ""):match(ns.KillPattern(f))
  if name then return tonumber(xp) end
  return nil
end

--- XP from each source, with "other" for what the chat lines didn't explain.
function ns.XPSources(total, by)
  by = by or {}
  local known = (by.kills or 0) + (by.quests or 0) + (by.explore or 0)
  local list = {
    { key = "kills", label = "Kills", xp = by.kills or 0 },
    { key = "quests", label = "Quests", xp = by.quests or 0 },
    { key = "explore", label = "Exploring", xp = by.explore or 0 },
    { key = "other", label = "Other", xp = math.max(0, (total or 0) - known) },
  }
  local out = {}
  for _, s in ipairs(list) do if s.xp > 0 then out[#out + 1] = s end end
  return out
end

-- ---- Reputation

--- "Reputation with Stormwind increased by 25." -> "Stormwind", 25 (negative when it went down).
function ns.ParseRep(msg, up, down)
  msg = tostring(msg or "")
  local function try(format, sign)
    if type(format) ~= "string" or format == "" then return nil end
    local a, b = msg:match(ns.KillPattern(format))
    if a and tonumber(b) then return a, sign * tonumber(b) end
    return nil
  end
  local name, n = try(up, 1)
  if name then return name, n end
  name, n = try(down, -1)
  if name then return name, n end
  name, n = try("Reputation with %s increased by %d.", 1)
  if name then return name, n end
  return try("Reputation with %s decreased by %d.", -1)
end

-- ---- Gold

ns.GOLD_SOURCES = {
  { key = "loot", label = "Looted" },
  { key = "quests", label = "Quests" },
  { key = "vendor", label = "Vendors" },
  { key = "auction", label = "Auction house and mail" },
  { key = "trade", label = "Trades" },
  { key = "repairs", label = "Repairs" },
  { key = "training", label = "Training" },
  { key = "flights", label = "Flights" },
  { key = "other", label = "Other" },
}

--- Which source a change in gold belongs to, from what's open (`ctx`) and what
--- just happened: ctx.questAt / ctx.repairAt are times, ctx.open the open window.
function ns.GoldSource(ctx, delta, now)
  ctx = ctx or {}
  if ctx.repairAt and now - ctx.repairAt <= 2 and delta < 0 then return "repairs" end
  if ctx.questAt and now - ctx.questAt <= 2 and delta > 0 then return "quests" end
  -- Flights and some purchases land just after the window closes.
  local open = ctx.open or (ctx.recentAt and now - ctx.recentAt <= 2 and ctx.recent) or nil
  if open == "merchant" then return "vendor" end
  if open == "mail" or open == "auction" then return "auction" end
  if open == "trade" then return "trade" end
  if open == "trainer" then return "training" end
  if open == "taxi" then return "flights" end
  if delta > 0 then return "loot" end
  return "other"
end

-- ---- Levels

--- How long levels take and when you'll reach `target`, from the level log
--- { [level] = { played, started, ended, partial } }. `perDay` is seconds
--- played per day lately (nil if unknown). Later levels take longer, so each is
--- scaled by its level over the average level of the ones measured.
function ns.LevelPlan(levels, current, target, perDay)
  local sum, n, lvSum = 0, 0, 0
  for level, l in pairs(levels or {}) do
    if l.ended and not l.partial and (l.played or 0) > 0 and level < current then
      sum, n, lvSum = sum + l.played, n + 1, lvSum + level
    end
  end
  if n == 0 or not target or target <= current then return nil end
  local avg, avgLevel = sum / n, lvSum / n
  local needed = 0
  for level = current, target - 1 do needed = needed + avg * level / avgLevel end
  local cur = levels and levels[current]
  if cur and cur.played then needed = math.max(0, needed - cur.played) end
  return { average = avg, measured = n, played = needed, days = perDay and perDay > 0 and needed / perDay or nil }
end

--- Seconds played per day lately, from `days` = { [day number] = seconds played }
--- (day number = unix time / 86400). Counts the last `window` days, from the
--- first one with play in it; nil when there's none.
function ns.PlayedPerDay(days, now, window)
  window = window or 7
  local today = math.floor(now / 86400)
  local played, first = 0, nil
  for day, secs in pairs(days or {}) do
    if day > today - window and day <= today and secs > 0 then
      played = played + secs
      if not first or day < first then first = day end
    end
  end
  if not first then return nil end
  return played / (today - first + 1)
end

-- ---- Raid buffs

local FLASKS = { [17626] = true, [17627] = true, [17628] = true, [17629] = true }
local ELIXIRS = {
  [17538] = true, [11405] = true, [11334] = true, [17537] = true, [17539] = true, [11474] = true, [26276] = true,
  [21920] = true, [11348] = true, [3593] = true, [24361] = true, [24363] = true, [17535] = true, [11396] = true,
  [11390] = true, [3223] = true, [11328] = true, [16323] = true, [16329] = true,
}
local WORLD = {
  [22888] = true, [16609] = true, [15366] = true, [24425] = true, [22817] = true, [22818] = true, [22820] = true,
  [23735] = true, [23736] = true, [23737] = true, [23738] = true, [23766] = true, [23767] = true, [23768] = true, [23769] = true,
}

--- One person's buffs -> { flask, elixirs, food, world }. `auras` is a list of
--- { spellId, name }. Known spell ids first, then the names as a fallback.
function ns.BuffCheck(auras)
  local out = { flask = false, elixirs = 0, food = false, world = 0 }
  for _, a in ipairs(auras or {}) do
    local id, name = a.spellId, tostring(a.name or "")
    if FLASKS[id] or name:find("^Flask of") then out.flask = true
    elseif ELIXIRS[id] or name:find("Elixir") or name == "Mageblood" then out.elixirs = out.elixirs + 1
    elseif WORLD[id] then out.world = out.world + 1
    elseif name == "Well Fed" then out.food = true end
  end
  return out
end

--- The group's buffs as chat lines: who has no flask, no elixir, no food, and world buffs.
function ns.BuffReport(people)
  local noFlask, noElixir, noFood, world, away = {}, {}, {}, 0, {}
  for _, p in ipairs(people) do
    if p.away then away[#away + 1] = p.name
    else
      if not p.buffs.flask then noFlask[#noFlask + 1] = p.name end
      if not p.buffs.flask and p.buffs.elixirs == 0 then noElixir[#noElixir + 1] = p.name end
      if not p.buffs.food then noFood[#noFood + 1] = p.name end
      if p.buffs.world > 0 then world = world + 1 end
    end
  end
  local function line(label, names)
    table.sort(names)
    return #names == 0 and (label .. ": everyone") or string.format("%s (%d): %s", label, #names, table.concat(names, ", "))
  end
  local checked = #people - #away
  local out = {
    string.format("Buff check, %d %s:", checked, checked == 1 and "person" or "people"),
    line("No flask", noFlask),
    line("No flask or elixir", noElixir),
    line("Not well fed", noFood),
    string.format("World buffs: %d of %d have one or more", world, checked),
  }
  if #away > 0 then
    table.sort(away)
    out[#out + 1] = "Too far away to check: " .. table.concat(away, ", ")
  end
  return out
end

-- ---- Gear

--- The lowest durability of the worn items as a share (0-1), and how many are broken; nil when unknown.
function ns.Durability(slots)
  local low, broken = nil, 0
  for _, s in ipairs(slots) do
    if s.max and s.max > 0 then
      local share = (s.cur or 0) / s.max
      if not low or share < low then low = share end
      if (s.cur or 0) == 0 then broken = broken + 1 end
    end
  end
  return low, broken
end

-- ---- The code for myself.snitchbot.app

local function b36(n)
  n = math.floor(math.abs(n))
  local digits, s = "0123456789abcdefghijklmnopqrstuvwxyz", ""
  repeat
    local d = n % 36
    s = digits:sub(d + 1, d + 1) .. s
    n = math.floor(n / 36)
  until n == 0
  return s
end
ns.B36 = b36

--- What the addon knows about this character, as one line for myself.snitchbot.app.
--- `c` = { region, name, class, level, now, levels, runs, gold, xp, rep }.
function ns.CharCode(c)
  local E = ns.Encode
  local levels = {}
  local keys = {}
  for level in pairs(c.levels or {}) do keys[#keys + 1] = level end
  table.sort(keys)
  for _, level in ipairs(keys) do
    local l = c.levels[level]
    levels[#levels + 1] = string.format("%d.%d.%d", level, math.floor(l.played or 0), math.floor(l.started or 0))
  end
  local runs = {}
  for i, run in ipairs(c.runs or {}) do
    if i > 50 then break end
    local kills, pulls = ns.BossCount(run)
    runs[#runs + 1] = table.concat({ E(run.name or "Dungeon"), math.floor(run.started or 0), math.floor(seconds(run)), run.kills or 0,
      math.floor(run.xp or 0), math.floor(run.money or 0), run.deaths or 0, kills, pulls, #(run.loot or {}), math.floor(run.value or 0) }, ".")
  end
  local function pairsOf(t)
    local out, ks = {}, {}
    for k in pairs(t or {}) do ks[#ks + 1] = k end
    table.sort(ks)
    for _, k in ipairs(ks) do
      if t[k] ~= 0 then out[#out + 1] = E(k) .. "." .. math.floor(t[k]) end
    end
    return table.concat(out, ",")
  end
  return table.concat({ ns.CHAR_PREFIX, c.region or "eu", E(c.name), E(c.class or ""), c.level or 0, math.floor(c.now or 0),
    table.concat(levels, ","), table.concat(runs, ","), pairsOf(c.gold), pairsOf(c.xp), pairsOf(c.rep), "END" }, ";")
end

-- ---- Need and Greed rolls: what you rolled, and whether you won.

-- A Lua pattern for one of the game's roll strings. Forever's strings start
-- with a loot history link that has a number of its own
-- ("|HlootHistory:%d|h[Loot]|h: Need Roll - %d for %s by %s"): what's inside a
-- link's |H...|h is matched but not kept, so the captures are the roll, the
-- item and the name. Their order doesn't matter: ns.ParseRoll tells them
-- apart by what they hold. "%2$s" style codes work too.
local function rollPattern(f)
  local out, i, inLink = {}, 1, false
  while i <= #f do
    local c2 = f:sub(i, i + 1)
    if c2 == "|H" then inLink = true; out[#out + 1] = "|H"; i = i + 2
    elseif c2 == "|h" then inLink = false; out[#out + 1] = "|h"; i = i + 2
    elseif c2 == "%%" then out[#out + 1] = "%%"; i = i + 2
    else
      local spec, len = f:match("^%%%d*%$?([sd])()", i)
      if spec then
        local any = spec == "d" and "%d+" or ".-"
        out[#out + 1] = inLink and any or ("(" .. any .. ")")
        i = len
      else
        local ch = f:sub(i, i)
        out[#out + 1] = ch:match("[%(%)%.%+%-%*%?%[%]%^%$%%]") and ("%" .. ch) or ch
        i = i + 1
      end
    end
  end
  -- Not anchored at the start, in case a client puts something in front.
  return table.concat(out) .. "$"
end

--- Patterns for "Need Roll - 87 for [item] by Name" and its Greed and
--- Disenchant forms, from the game's own strings when it has them.
function ns.RollPatterns(g)
  g = g or {}
  local list = {}
  local function add(kind, key, fallback)
    local f = type(g[key]) == "string" and g[key] ~= "" and g[key] or fallback
    list[#list + 1] = { kind = kind, pattern = rollPattern(f) }
  end
  add("need", "LOOT_ROLL_ROLLED_NEED_ROLE_BONUS", "Need Roll - %d for %s by %s + Role Bonus")
  add("need", "LOOT_ROLL_ROLLED_NEED", "Need Roll - %d for %s by %s")
  add("greed", "LOOT_ROLL_ROLLED_GREED", "Greed Roll - %d for %s by %s")
  add("de", "LOOT_ROLL_ROLLED_DE", "Disenchant Roll - %d for %s by %s")
  -- With the loot lines kept short (the game's default) only the winner's
  -- line comes, with the roll in it: "[Loot]: You (Need - 87) Won: [item]".
  local function mine(kind, key, fallback)
    local f = type(g[key]) == "string" and g[key] ~= "" and g[key] or fallback
    list[#list + 1] = { kind = kind, pattern = rollPattern(f), self = true, won = true }
  end
  mine("need", "LOOT_ROLL_YOU_WON_NO_SPAM_NEED", "|HlootHistory:%d|h[Loot]|h: You (Need - %d) Won: %s")
  mine("greed", "LOOT_ROLL_YOU_WON_NO_SPAM_GREED", "|HlootHistory:%d|h[Loot]|h: You (Greed - %d) Won: %s")
  mine("de", "LOOT_ROLL_YOU_WON_NO_SPAM_DE", "|HlootHistory:%d|h[Loot]|h: You (Disenchant - %d) Won: %s")
  add("won", "LOOT_ROLL_YOU_WON", "You won: %s")
  return list
end

--- A loot chat line -> { kind, roll, who, id, name, self, won } for a roll (self and won
--- for your own winning line), { kind = "won", id, name } for an item you won, or nil.
function ns.ParseRoll(msg, patterns)
  msg = tostring(msg or "")
  for _, p in ipairs(patterns) do
    local c = { msg:match(p.pattern) }
    if c[1] then
      -- The item is the capture with an item link, the roll the number, the name the rest.
      local link, roll, who
      for _, v in ipairs(c) do
        if v:find("|Hitem:", 1, true) then link = link or v
        elseif not roll and v:match("^%d+$") then roll = tonumber(v)
        elseif v ~= "" then who = who or v end
      end
      local id, name = ns.ParseLoot(link)
      if id and p.kind == "won" then return { kind = "won", id = id, name = name } end
      if id and roll and roll >= 1 and roll <= 100 then
        return { kind = p.kind, roll = roll, who = who, id = id, name = name, self = p.self, won = p.won }
      end
    end
  end
  return nil
end

--- Adds one of your rolls to `book` = { need = { n, sum, won, hi, lo }, greed, de, recent }.
function ns.AddRoll(book, kind, roll, id, name, at)
  book[kind] = type(book[kind]) == "table" and book[kind] or { n = 0, sum = 0, won = 0 }
  local s = book[kind]
  s.n, s.sum = s.n + 1, s.sum + roll
  s.hi = math.max(s.hi or roll, roll)
  s.lo = math.min(s.lo or roll, roll)
  book.recent = type(book.recent) == "table" and book.recent or {}
  table.insert(book.recent, 1, { kind = kind, roll = roll, id = id, name = name, at = at })
  while #book.recent > 20 do table.remove(book.recent) end
end

--- You won `id`: your last roll on it in the last 10 minutes counts as a win.
function ns.WonRoll(book, id, at)
  for _, r in ipairs(type(book.recent) == "table" and book.recent or {}) do
    if r.id == id and not r.won and (at or 0) - (r.at or 0) <= 600 then
      r.won = true
      local s = book[r.kind]
      if s then s.won = (s.won or 0) + 1 end
      return r.kind
    end
  end
  return nil
end

--- One of your rolls, from whichever source saw it: the chat line, the
--- winner's line or the loot history. The same roll seen twice (same item,
--- kind and number within 10 minutes) counts once; a win marks it.
function ns.NoteRoll(book, kind, roll, id, name, at, won)
  for _, r in ipairs(type(book.recent) == "table" and book.recent or {}) do
    if r.id == id and r.kind == kind and r.roll == roll and math.abs((at or 0) - (r.at or 0)) <= 600 then
      if won and not r.won then
        r.won = true
        if book[kind] then book[kind].won = (book[kind].won or 0) + 1 end
      end
      return false
    end
  end
  ns.AddRoll(book, kind, roll, id, name, at)
  if won then
    book.recent[1].won = true
    book[kind].won = (book[kind].won or 0) + 1
  end
  return true
end

--- The kind of roll the loot history gives: the modern state
--- (Enum.EncounterLootDropRollState: 0, 1 need, 3 greed) or the classic type (1 need, 2 greed, 3 disenchant).
function ns.HistoryKind(state, classic)
  state = tonumber(state)
  if classic then return ({ "need", "greed", "de" })[state or 0] end
  if state == 0 or state == 1 then return "need" end
  if state == 3 then return "greed" end
  return nil
end

--- The average roll of a kind, or nil with none.
function ns.RollAverage(s)
  if type(s) ~= "table" or (s.n or 0) == 0 then return nil end
  return s.sum / s.n
end

return ns
