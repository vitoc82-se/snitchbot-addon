--[[ Snitchbot: the parts with no UI, so the same file runs in the tests
  (tests/code.test.mjs) against a fake game.

  Shopping code, made by auction.snitchbot.app's Raid list tab:
    SNITCHBOT:SHOP:1;<guild>;<character>;<raid size>;<raid name>;<item>,<item>,...;END
  and each item is  <item id>.<how many>[.<buff spell id>]  (more parts may
  follow in later versions and are ignored). Text fields are %-encoded except
  letters, digits and spaces. The website's writer is shoppingCode() in
  snitchbot-forever/src/lib/shopping.ts: change both together.
]]
local _, ns = ...
ns = ns or {}

ns.SHOP_PREFIX = "SNITCHBOT:SHOP:1"
ns.PROBE_PREFIX = "SNITCHBOT:PROBE:1"

-- Calls fn when it exists and doesn't error; nil otherwise. WoW Forever's API
-- isn't documented, so every game call goes through this.
local function safe(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g, h, i, j, k = pcall(fn, ...)
  if ok then return a, b, c, d, e, f, g, h, i, j, k end
  return nil
end
ns.safe = safe

function ns.Encode(s)
  return (tostring(s or ""):gsub("[^%w ]", function(c) return string.format("%%%02X", c:byte()) end))
end

function ns.Decode(s)
  return (tostring(s or ""):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- "Vitoc War-CAMWOW EU5 Realm 7 PVE" -> "Vitoc War". Names have no "-".
function ns.ShortName(name)
  return (tostring(name or ""):match("^[^-]+") or "")
end

local function split(s, sep)
  local out = {}
  for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
  return out
end

--- A pasted shopping code -> { guild, character, size, raid, items = { { id, need, spell } } }, or nil and why.
function ns.ParseShop(text)
  -- Names keep their spaces, so only line breaks and the ends are trimmed.
  local code = tostring(text or ""):gsub("[\r\n]", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if code:sub(1, #ns.SHOP_PREFIX) ~= ns.SHOP_PREFIX then
    if code:match("^SNITCHBOT:SHOP:") then return nil, "This code is for a newer Snitchbot addon. Update the addon." end
    return nil, "That's not a Snitchbot shopping code. Copy it from Raid list on auction.snitchbot.app."
  end
  local parts = split(code, ";")
  if parts[#parts] ~= "END" then return nil, "The code is cut off. Copy all of it." end
  if #parts < 7 then return nil, "The code is incomplete." end
  local list = {
    guild = ns.Decode(parts[2]),
    character = ns.Decode(parts[3]),
    size = tonumber(parts[4]) or 0,
    raid = ns.Decode(parts[5]),
    items = {},
  }
  local seen = {}
  for _, item in ipairs(split(parts[6], ",")) do
    local f = split(item, ".")
    local id, need = tonumber(f[1]), tonumber(f[2])
    if id and need and id > 0 and need > 0 and not seen[id] then
      seen[id] = true
      list.items[#list.items + 1] = { id = id, need = need, spell = tonumber(f[3]) }
    end
  end
  if #list.items == 0 then return nil, "The code has no items." end
  return list
end

--- How many of each item you have. `count(id, withBank)` is the game's item count.
--- Returns rows { id, need, bags, total, missing } in list order, and how many items are short.
function ns.Progress(list, count)
  local rows, short = {}, 0
  for _, it in ipairs(list.items) do
    local bags = tonumber(count(it.id, false)) or 0
    local total = math.max(bags, tonumber(count(it.id, true)) or 0)
    local missing = math.max(0, it.need - total)
    if missing > 0 then short = short + 1 end
    rows[#rows + 1] = { id = it.id, need = it.need, bags = bags, total = total, missing = missing, spell = it.spell }
  end
  return rows, short
end

--- "Barrow Deeps (10)" or "Onyxia's Lair (40)".
function ns.RaidLabel(list)
  if list.raid and list.raid ~= "" then return string.format("%s (%d)", list.raid, list.size) end
  return string.format("%d-man", list.size)
end

--- The probe: which game functions and events this client has, as one line to copy.
--- `get(path)` returns the value at a dotted global path; `canRegister(event)` says if the event exists.
function ns.ProbeCode(get, canRegister, build)
  local fields = { ns.PROBE_PREFIX }
  local function add(k, v) fields[#fields + 1] = k .. "=" .. tostring(v) end
  add("version", build.version or "?")
  add("build", build.build or "?")
  add("interface", build.interface or "?")
  add("project", build.project or "?")
  for _, path in ipairs(ns.PROBE_FUNCTIONS) do
    add(path, type(get(path)) == "function" and 1 or (get(path) ~= nil and "t" or 0))
  end
  for _, event in ipairs(ns.PROBE_EVENTS) do add(event, canRegister(event) and 1 or 0) end
  fields[#fields + 1] = "END"
  return table.concat(fields, ";")
end

-- What the next versions need, checked once in game so we stop guessing.
ns.PROBE_FUNCTIONS = {
  -- Bags and bank (shopping list)
  "C_Item.GetItemCount", "GetItemCount", "C_Container.GetContainerItemInfo", "GetContainerItemInfo",
  "C_Item.GetItemInfo", "GetItemInfo", "C_Item.GetItemIconByID", "GetItemIcon", "C_Item.RequestLoadItemDataByID",
  -- Auction house search
  "C_AuctionHouse", "C_AuctionHouse.SendBrowseQuery", "C_AuctionHouse.SendSearchQuery", "QueryAuctionItems",
  -- Raid check: buffs on raiders
  "C_UnitAuras.GetAuraDataByIndex", "C_UnitAuras.GetBuffDataByIndex", "UnitAura", "UnitBuff", "AuraUtil.ForEachAura",
  "GetNumGroupMembers", "GetRaidRosterInfo", "IsInRaid",
  -- Raid log
  "CombatLogGetCurrentEventInfo", "C_ChatInfo.SendAddonMessage", "GetInstanceInfo",
  -- Guild roster extras
  "GetGuildRosterInfo", "GetGuildRosterLastOnline", "CanViewOfficerNote", "C_GuildInfo.CanViewOfficerNote",
  "GuildControlGetRankName", "C_GuildInfo.GuildRoster",
  -- Guild bank
  "GetNumGuildBankTabs", "GetGuildBankTabInfo", "GetGuildBankItemInfo", "GetGuildBankItemLink",
  "GetGuildBankMoney", "QueryGuildBankLog", "GetNumGuildBankTransactions",
  -- Profession cooldowns
  "C_TradeSkillUI", "GetTradeSkillInfo", "GetTradeSkillCooldown", "C_Spell.GetSpellCooldown", "GetSpellCooldown",
}
ns.PROBE_EVENTS = {
  "ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL", "ENCOUNTER_LOOT_RECEIVED", "CHAT_MSG_LOOT",
  "COMBAT_LOG_EVENT_UNFILTERED", "GUILDBANKFRAME_OPENED", "GUILDBANKBAGSLOTS_CHANGED",
  "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "AUCTION_HOUSE_SHOW", "BANKFRAME_OPENED", "TRADE_SKILL_SHOW",
}

return ns
