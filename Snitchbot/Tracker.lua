--[[ Snitchbot: XP and dungeon run maths, with no UI, so tests/code.test.mjs
  runs it against a fake game.

  WoW Forever has no combat log for addons (probe 2026-11-15), so kills come
  from the "X dies, you gain N experience." chat line. Kills that give no XP
  (grey mobs, or at max level) aren't counted.
]]
local _, ns = ...
ns = ns or {}

--- XP gained between two readings { level, xp, max }, across one level-up,
--- and the reading to compare the next one with. When you ding, the game can
--- report the new XP before the new level: XP that drops at the same level is
--- a level-up too, and the next reading is then expected one level up.
function ns.XPGain(prev, cur)
  if not prev or not cur then return 0, cur end
  local rest = math.max(0, (prev.max or 0) - (prev.xp or 0))
  if cur.level > prev.level then return rest + (cur.xp or 0), cur end
  if cur.level < prev.level then return 0, cur end
  if (cur.xp or 0) < (prev.xp or 0) then
    return rest + (cur.xp or 0), { level = cur.level + 1, xp = cur.xp, max = cur.max }
  end
  return (cur.xp or 0) - (prev.xp or 0), cur
end

--- A Lua pattern for the game's "%s dies, you gain %d experience." line.
function ns.KillPattern(format)
  local f = type(format) == "string" and format ~= "" and format or "%s dies, you gain %d experience."
  local p = f:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%s", "(.-)"):gsub("%%d", "(%%d+)")
  return "^" .. p
end

--- The mob's name and the XP when `msg` is a kill line, else nil.
function ns.ParseKill(msg, pattern)
  local name, xp = tostring(msg or ""):match(pattern)
  if name and name ~= "" and tonumber(xp) then return name, tonumber(xp) end
  return nil
end

--- XP per hour, or nil until there's a minute of play and some XP.
function ns.Rate(xp, seconds)
  if not xp or xp <= 0 or not seconds or seconds < 60 then return nil end
  return xp * 3600 / seconds
end

--- Seconds to the next level at `perHour`, or nil.
function ns.TimeToLevel(remaining, perHour)
  if not perHour or perHour <= 0 or not remaining or remaining <= 0 then return nil end
  return remaining / perHour * 3600
end

--- "6h 52m", "41m", "35s".
function ns.Duration(seconds)
  seconds = math.max(0, math.floor(seconds or 0))
  local h, m = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
  if h > 0 then return string.format("%dh %02dm", h, m) end
  if m > 0 then return string.format("%dm", m) end
  return string.format("%ds", seconds)
end

--- 12340 -> "12,340".
function ns.Num(n)
  local s = tostring(math.floor((n or 0) + 0.5))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""):gsub("^%-,", "-"))
end

--- A run or session saved before a /reload carries on if it's recent and, for a run, the same instance.
function ns.CanResume(saved, now, key, maxGap)
  if type(saved) ~= "table" or not saved.lastSeen then return false end
  if key ~= nil and saved.key ~= key then return false end
  return now - saved.lastSeen <= (maxGap or 600)
end

--- Copper -> "12g 40s", "40s 5c", "-3g 10s".
function ns.Money(copper)
  copper = math.floor(copper or 0)
  local sign = copper < 0 and "-" or ""
  copper = math.abs(copper)
  local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
  if g > 0 then return string.format("%s%sg %ds", sign, ns.Num(g), s) end
  if s > 0 then return string.format("%s%ds %dc", sign, s, c) end
  return string.format("%s%dc", sign, c)
end

-- Item link colours to item quality: green 2, blue 3, purple 4, orange 5.
local QUALITY = { ["1eff00"] = 2, ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5, ["9d9d9d"] = 0, ["ffffff"] = 1 }

--- A loot chat line -> item id, name, quality (nil if unknown), count. Nil when there's no item link.
function ns.ParseLoot(msg)
  msg = tostring(msg or "")
  local id = tonumber(msg:match("|Hitem:(%d+)"))
  if not id then return nil end
  local name = msg:match("|h%[(.-)%]|h") or ("Item " .. id)
  local colour = msg:match("|c%x%x(%x%x%x%x%x%x)|Hitem:")
  local quality = colour and QUALITY[colour:lower()]
  local count = tonumber(msg:match("|h|rx(%d+)") or msg:match("%]|h|r%s*x(%d+)")) or 1
  return id, name, quality, count
end

--- Boss kills in a run, and pulls.
function ns.BossCount(run)
  local kills, pulls = 0, 0
  for _, b in ipairs(run.bosses or {}) do
    pulls = pulls + 1
    if b.kill then kills = kills + 1 end
  end
  return kills, pulls
end

--- One line for chat when a run ends.
function ns.RunSummary(run, now)
  local seconds = (run.ended or now) - run.started
  local parts = { ns.Duration(seconds), ns.Num(run.kills) .. " kills" }
  local bosses = ns.BossCount(run)
  if bosses > 0 then parts[#parts + 1] = bosses .. (bosses == 1 and " boss" or " bosses") end
  if (run.xp or 0) > 0 then
    parts[#parts + 1] = ns.Num(run.xp) .. " XP"
    local rate = ns.Rate(run.xp, seconds)
    if rate then parts[#parts + 1] = ns.Num(rate) .. " XP/h" end
  end
  if (run.money or 0) ~= 0 then parts[#parts + 1] = (run.money > 0 and "+" or "") .. ns.Money(run.money) end
  if (run.deaths or 0) > 0 then parts[#parts + 1] = run.deaths .. (run.deaths == 1 and " death" or " deaths") end
  return string.format("%s: %s.", run.name or "Dungeon", table.concat(parts, ", "))
end

return ns
