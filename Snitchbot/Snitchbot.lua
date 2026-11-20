--[[ Snitchbot: your guild's raid shopping list in game.
  One window with tabs: Raid list, XP, Runs, Stats, Settings. Open it with the
  minimap button (or /sb). It stays open over reloads until you close it.

  Written defensively: WoW Forever's addon API isn't documented, so every game
  call is feature-checked or pcall-guarded (ns.safe). The worst case is a
  message in chat, never a Lua error.
]]
local ADDON, ns = ...
local safe = ns.safe


local function say(msg)
  local f = DEFAULT_CHAT_FRAME
  if f and f.AddMessage then f:AddMessage("|cffe0b04aSnitchbot:|r " .. msg) else print("Snitchbot: " .. msg) end
end

local function db()
  SnitchbotDB = type(SnitchbotDB) == "table" and SnitchbotDB or {}
  SnitchbotDB.lists = type(SnitchbotDB.lists) == "table" and SnitchbotDB.lists or {}
  return SnitchbotDB
end

local function me()
  return ns.ShortName(safe(UnitName, "player") or "")
end

-- The game's item count, bags only or bags and bank.
local function count(id, withBank)
  if C_Item and C_Item.GetItemCount then return safe(C_Item.GetItemCount, id, withBank) or 0 end
  return safe(GetItemCount, id, withBank) or 0
end

local function itemName(id)
  local name = (C_Item and C_Item.GetItemInfo and safe(C_Item.GetItemInfo, id)) or safe(GetItemInfo, id)
  if not name and C_Item and C_Item.RequestLoadItemDataByID then safe(C_Item.RequestLoadItemDataByID, id) end
  return name
end

-- Forever has only the C_Item versions (probe, 2026-11-15); the globals are a fallback.
local function itemLink(id)
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  return select(2, safe(getInfo, id))
end

local function itemIcon(id)
  return (C_Item and C_Item.GetItemIconByID and safe(C_Item.GetItemIconByID, id)) or safe(GetItemIcon, id)
    or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- The list for this character, else the last one pasted.
local function currentList()
  local d = db()
  return d.lists[me()] or (d.last and d.lists[d.last]) or nil
end

-- ---- Look: snitchbot.app's own. Charcoal, one gold accent, Geist, pill tabs, stat cards.

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local FONT = {
  regular = MEDIA .. "Fonts\\Geist-Regular.ttf",
  medium = MEDIA .. "Fonts\\Geist-Medium.ttf",
  semibold = MEDIA .. "Fonts\\Geist-SemiBold.ttf",
}

local C = {
  ground = { 0.078, 0.09, 0.118, 0.97 }, -- #14171e
  header = { 0.051, 0.059, 0.078, 1 }, -- #0d0f14, the site's background
  footer = { 0.051, 0.059, 0.078, 1 },
  well = { 0.051, 0.059, 0.078, 1 },
  card = { 0.11, 0.129, 0.169, 1 }, -- #1c212b
  shadow = { 0, 0, 0, 0.5 },
  text = { 0.902, 0.91, 0.933, 1 }, -- #e6e8ee
  dim = { 0.722, 0.741, 0.792, 1 },
  muted = { 0.545, 0.576, 0.655, 1 }, -- #8b93a7
  accent = { 0.878, 0.69, 0.29, 1 }, -- #e0b04a
  accentLit = { 0.922, 0.757, 0.388, 1 },
  onAccent = { 0.102, 0.078, 0.024, 1 }, -- #1a1406
  success = { 0.361, 0.761, 0.431, 1 },
  danger = { 0.925, 0.353, 0.373, 1 },
  item = { 0.78, 0.68, 1, 1 },
  border = { 0.165, 0.192, 0.251, 1 }, -- #2a3140
  line = { 0.137, 0.161, 0.216, 1 },
  hover = { 1, 1, 1, 0.05 },
  track = { 0.165, 0.192, 0.251, 1 },
}

local function show(f, on)
  if on then f:Show() else f:Hide() end
end

local function hex(c)
  return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

local ROWS_SHOWN = 10
local ROW_HEIGHT = 28
local WIDTH = 360
local PAD = 16
local TRACK = WIDTH - 2 * PAD - 44 -- the footer bar, leaving room for the percent

-- ---- Building blocks

local function fill(f, color, layer, sublevel)
  local t = f:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
  t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
  return t
end

-- A 1-pixel border inside f.
local function hairline(f, color)
  local function side(a, b, w, h)
    local t = fill(f, color, "BORDER")
    t:SetPoint(a)
    t:SetPoint(b)
    if w then t:SetWidth(w) else t:SetHeight(h) end
  end
  side("TOPLEFT", "TOPRIGHT", nil, 1)
  side("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
  side("TOPLEFT", "BOTTOMLEFT", 1)
  side("TOPRIGHT", "BOTTOMRIGHT", 1)
end

local function divider(f, y)
  local t = fill(f, C.line, "ARTWORK")
  t:SetHeight(1)
  t:SetPoint("TOPLEFT", PAD, y)
  t:SetPoint("TOPRIGHT", -PAD, y)
  return t
end

-- Geist when the game takes it, else the game's own font.
local function setFont(fs, size, weight)
  if not safe(fs.SetFont, fs, FONT[weight or "regular"], size, "") then
    safe(fs.SetFontObject, fs, size >= 14 and GameFontNormalLarge or GameFontHighlight)
  end
end

local function text(parent, size, weight, color, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY", "GameFontHighlight")
  setFont(fs, size, weight)
  fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  fs:SetJustifyH("LEFT")
  safe(fs.SetWordWrap, fs, false)
  return fs
end

-- Flat buttons: gold for the main action, a card with an outline for the rest.
local function button(parent, label, primary, width)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width or 120, 26)
  local rest = primary and C.accent or C.card
  local lit = primary and C.accentLit or C.border
  b.bg = fill(b, rest)
  b.bg:SetAllPoints()
  if not primary then hairline(b, C.border) end
  b.label = text(b, 12, "semibold", primary and C.onAccent or C.text)
  b.label:SetPoint("CENTER")
  b.label:SetJustifyH("CENTER")
  b.label:SetText(label)
  b:SetScript("OnEnter", function() b.bg:SetColorTexture(lit[1], lit[2], lit[3], lit[4]) end)
  b:SetScript("OnLeave", function() b.bg:SetColorTexture(rest[1], rest[2], rest[3], rest[4]) end)
  return b
end

-- A glyph in the header (× or +): muted, white on hover.
local function headerButton(parent, glyph, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(26, 26)
  b.label = text(b, size or 16, "regular", C.muted)
  b.label:SetPoint("CENTER", 0, 1)
  b.label:SetJustifyH("CENTER")
  b.label:SetText(glyph)
  b:SetScript("OnEnter", function() b.label:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
  b:SetScript("OnLeave", function() b.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end)
  return b
end

-- A short gold bar, the mark in front of the window's title.
local function mark(parent)
  local t = fill(parent, C.accent, "ARTWORK")
  t:SetSize(3, 14)
  return t
end

-- The window: ground, hairline, soft shadow, and a header you drag it by.
-- Where you last dragged the window, or the default spot.
local function place(f, name, point, x, y)
  local s = db().settings
  local p = type(s) == "table" and type(s.pos) == "table" and s.pos[name]
  f:ClearAllPoints()
  if type(p) == "table" and type(p[1]) == "string" then
    f:SetPoint(p[1], UIParent, p[2] or p[1], tonumber(p[3]) or 0, tonumber(p[4]) or 0)
  else
    f:SetPoint(point, UIParent, point, x, y)
  end
end

local function window(name, width, height, strata, keepOnEscape)
  local f = CreateFrame("Frame", name, UIParent)
  f:SetSize(width, height)
  f:SetFrameStrata(strata or "HIGH")
  f:SetMovable(true)
  f:EnableMouse(true)
  safe(f.SetClampedToScreen, f, true)
  local shadow = fill(f, C.shadow, "BACKGROUND", -8)
  shadow:SetPoint("TOPLEFT", -4, 4)
  shadow:SetPoint("BOTTOMRIGHT", 4, -6)
  fill(f, C.ground, "BACKGROUND", -7):SetAllPoints()
  hairline(f, C.border)

  local header = CreateFrame("Frame", nil, f)
  header:SetPoint("TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", -1, -1)
  header:SetHeight(32)
  fill(header, C.header):SetAllPoints()
  local under = fill(header, C.line, "ARTWORK")
  under:SetHeight(1)
  under:SetPoint("BOTTOMLEFT")
  under:SetPoint("BOTTOMRIGHT")
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() f:StartMoving() end)
  header:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    -- Remembered here: the game's own layout cache skips windows made after login, like these.
    safe(f.SetUserPlaced, f, false)
    local point, _, relPoint, x, y = f:GetPoint()
    if point and x and y then
      local d = db()
      d.settings = type(d.settings) == "table" and d.settings or {}
      d.settings.pos = type(d.settings.pos) == "table" and d.settings.pos or {}
      d.settings.pos[name] = { point, relPoint or point, math.floor(x + 0.5), math.floor(y + 0.5) }
    end
  end)
  f.header = header
  mark(header):SetPoint("LEFT", PAD, 0)
  f.title = text(header, 13, "semibold", C.text)
  f.title:SetPoint("LEFT", PAD + 11, 0)
  f.close = headerButton(header, "×", 18)
  f.close:SetPoint("RIGHT", -6, 0)
  f.close:SetScript("OnClick", function() f:Hide() end)
  f.header = header
  if UISpecialFrames and not keepOnEscape then table.insert(UISpecialFrames, name) end
  return f
end

-- A scroll area with a slim thumb; the mouse wheel scrolls it.
local function scrollArea(parent, step)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(1, 1)
  sf:SetScrollChild(child)
  local thumb = fill(sf, C.border, "OVERLAY")
  thumb:SetWidth(3)
  thumb:Hide()
  local function place()
    local range = tonumber(safe(sf.GetVerticalScrollRange, sf)) or 0
    local height = tonumber(safe(sf.GetHeight, sf)) or 0
    if range <= 0 or height <= 0 then return thumb:Hide() end
    local size = math.max(24, height * height / (height + range))
    local at = (tonumber(safe(sf.GetVerticalScroll, sf)) or 0) / range * (height - size)
    thumb:SetHeight(size)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 6, -at)
    thumb:Show()
  end
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta)
    local range = tonumber(safe(self.GetVerticalScrollRange, self)) or 0
    local now = tonumber(safe(self.GetVerticalScroll, self)) or 0
    self:SetVerticalScroll(math.max(0, math.min(range, now - delta * step)))
    place()
  end)
  sf:SetScript("OnScrollRangeChanged", place)
  sf.place = place
  return sf, child
end

-- ---- Frames

local frame, rows, paste
local refresh, update, selectTab

local function makeRow(parent, i)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
  row:SetPoint("RIGHT", parent, "RIGHT")
  row.hover = fill(row, C.hover)
  row.hover:SetAllPoints()
  row.hover:Hide()
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(20, 20)
  row.icon:SetPoint("LEFT", 2, 0)
  safe(row.icon.SetTexCoord, row.icon, 0.08, 0.92, 0.08, 0.92)

  -- The box on the right: empty while short, gold with a tick when you have enough.
  row.box = CreateFrame("Frame", nil, row)
  row.box:SetSize(14, 14)
  row.box:SetPoint("RIGHT", -4, 0)
  row.boxFill = fill(row.box, C.accent, "ARTWORK")
  row.boxFill:SetAllPoints()
  hairline(row.box, { C.muted[1], C.muted[2], C.muted[3], 0.7 })
  row.tick = row.box:CreateTexture(nil, "OVERLAY")
  row.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  row.tick:SetSize(20, 20)
  row.tick:SetPoint("CENTER", 1, 0)
  safe(row.tick.SetDesaturated, row.tick, true)
  row.tick:SetVertexColor(C.onAccent[1], C.onAccent[2], C.onAccent[3])

  row.count = text(row, 12, "medium", C.dim)
  row.count:SetPoint("RIGHT", row.box, "LEFT", -10, 0)
  row.count:SetJustifyH("RIGHT")
  row.name = text(row, 13, "regular", C.item)
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
  row.name:SetPoint("RIGHT", row.count, "LEFT", -8, 0)

  row:SetScript("OnEnter", function(self)
    self.hover:Show()
    if not self.itemId or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    safe(GameTooltip.SetItemByID, GameTooltip, self.itemId)
    if self.bank and self.bank > 0 then GameTooltip:AddLine(string.format("%d in your bank", self.bank), 1, 1, 1) end
    GameTooltip:AddLine("Shift-click to link it in chat", C.muted[1], C.muted[2], C.muted[3])
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function(self)
    self.hover:Hide()
    if GameTooltip then GameTooltip:Hide() end
  end)
  -- Shift-click puts the item's link in chat, as everywhere in the game.
  row:SetScript("OnClick", function(self)
    if not self.itemId then return end
    local link = itemLink(self.itemId)
    if link and IsModifiedClick and safe(IsModifiedClick, "CHATLINK") and ChatEdit_InsertLink then safe(ChatEdit_InsertLink, link) end
  end)
  return row
end

local function makePaste()
  paste = window("SnitchbotPasteFrame", 460, 250, "DIALOG")
  place(paste, "SnitchbotPasteFrame", "CENTER", 0, 60)
  paste.hint = text(paste, 12, "regular", C.dim)
  paste.hint:SetPoint("TOPLEFT", PAD, -46)
  paste.hint:SetPoint("TOPRIGHT", -PAD, -46)
  safe(paste.hint.SetWordWrap, paste.hint, true)
  paste.hint:SetJustifyV("TOP")

  -- The well the code goes in.
  local well = CreateFrame("Frame", nil, paste)
  well:SetPoint("TOPLEFT", PAD, -86)
  well:SetPoint("BOTTOMRIGHT", -PAD, 56)
  fill(well, C.well):SetAllPoints()
  hairline(well, C.border)
  local sf = scrollArea(well, 14)
  sf:SetPoint("TOPLEFT", 10, -8)
  sf:SetPoint("BOTTOMRIGHT", -14, 8)
  paste.edit = CreateFrame("EditBox", nil, sf)
  paste.edit:SetMultiLine(true)
  paste.edit:SetAutoFocus(false)
  paste.edit:SetMaxLetters(0)
  paste.edit:SetFontObject(ChatFontNormal or GameFontHighlight)
  safe(paste.edit.SetFont, paste.edit, FONT.regular, 12, "")
  paste.edit:SetTextColor(C.text[1], C.text[2], C.text[3])
  paste.edit:SetWidth(400)
  sf:SetScrollChild(paste.edit)
  paste.edit:SetScript("OnSizeChanged", function() sf.place() end)
  paste.edit:SetScript("OnEscapePressed", function() paste:Hide() end)
  -- Clicking anywhere in the well puts the cursor in the box.
  well:EnableMouse(true)
  well:SetScript("OnMouseDown", function() paste.edit:SetFocus() end)

  paste.ok = button(paste, "Import", true, 110)
  paste.ok:SetPoint("BOTTOMRIGHT", -PAD, 16)
  local cancel = button(paste, "Close", false, 90)
  cancel:SetPoint("RIGHT", paste.ok, "LEFT", -8, 0)
  cancel:SetScript("OnClick", function() paste:Hide() end)
  paste.ok:SetScript("OnClick", function()
    local code = paste.edit:GetText() or ""
    if code:find(ns.PRICES_PREFIX, 1, true) then
      local prices, why = ns.ParsePrices(code)
      if not prices then return say(why) end
      db().prices = prices
      paste:Hide()
      say(string.format("Prices saved: %s items from %s. Your loot is now valued at these prices.", ns.Num(prices.count), prices.house))
      update()
      return
    end
    local list, why = ns.ParseShop(code)
    if not list then return say(why) end
    local d = db()
    local who = list.character ~= "" and list.character or me()
    d.lists[who], d.last = list, who
    paste:Hide()
    say(string.format("Raid list for %s saved: %d items for %s.", who, #list.items, ns.RaidLabel(list)))
    if frame then frame:Show(); selectTab("raid") end
  end)
  paste:Hide()
end

-- Paste mode: an empty box and Import. Copy mode: read-only text to copy.
local function openPaste(kind)
  if not paste then makePaste() end
  if kind == "prices" then
    paste.title:SetText("Paste auction house prices")
    paste.hint:SetText("On auction.snitchbot.app, pick your auction house and press Copy prices for the addon. Then click the box below and press Ctrl+V (Cmd+V on a Mac).")
  else
    paste.title:SetText("Paste your raid list")
    paste.hint:SetText("On auction.snitchbot.app, open Raid list and press Copy for the addon. Then click the box below and press Ctrl+V (Cmd+V on a Mac).")
  end
  paste.ok:Show()
  paste.edit:SetScript("OnTextChanged", nil)
  paste.edit:SetText("")
  paste:Show()
  paste.edit:SetFocus()
end

local function showCopy(title, value, hint)
  if not paste then makePaste() end
  paste.title:SetText(title)
  paste.hint:SetText(hint or "Press Ctrl+C (Cmd+C on a Mac) to copy it, then paste it to Snitchbot.")
  paste.ok:Hide()
  paste.edit:SetText(value)
  paste.edit:SetScript("OnTextChanged", function(self, userInput)
    if userInput then self:SetText(value); self:HighlightText() end
  end)
  paste:Show()
  paste.edit:SetFocus()
  paste.edit:HighlightText()
end

-- ---- State: settings, XP, session, dungeon runs

local KILL = ns.KillPattern(COMBATLOG_XPGAIN_FIRSTPERSON)
local xpNow
local now = function() return safe(time) or 0 end

local DEFAULTS = { combatLog = true, openInDungeon = true, minimap = true, announce = true, tab = "raid" }
local ANNOUNCE = "I'm using the snitchbot.app addon to track this run."
local money = function() return tonumber(safe(GetMoney)) or 0 end

local function settings()
  local d = db()
  d.settings = type(d.settings) == "table" and d.settings or {}
  for k, v in pairs(DEFAULTS) do
    if d.settings[k] == nil then d.settings[k] = v end
  end
  return d.settings
end

local function reading()
  return {
    level = tonumber(safe(UnitLevel, "player")) or 0,
    xp = tonumber(safe(UnitXP, "player")) or 0,
    max = tonumber(safe(UnitXPMax, "player")) or 0,
  }
end

-- The session carries on over a /reload or a quick relog (checked at login), else starts again.
local function session(atLogin)
  local d = db()
  local key = me()
  if type(d.session) ~= "table" or (atLogin and not ns.CanResume(d.session, now(), key, 600)) then
    d.session = { key = key, started = now(), xp = 0, kills = 0, moneyStart = money() }
  end
  d.session.moneyStart = d.session.moneyStart or money()
  d.session.lastSeen = now()
  return d.session
end

local function resetSession()
  db().session = nil
  session()
  say("Session reset.")
end

-- Kept for good, per character: the level log, time played per day, and where
-- XP, gold and reputation came from.
local function char()
  local d = db()
  d.chars = type(d.chars) == "table" and d.chars or {}
  local key = me()
  local c = d.chars[key]
  if type(c) ~= "table" then c = {}; d.chars[key] = c end
  for _, k in ipairs({ "levels", "days", "gold", "xpBy", "rep" }) do c[k] = type(c[k]) == "table" and c[k] or {} end
  return c
end

-- Adds n under `field`.`key` for the session, the run you're in and the character.
local function tally(field, key, n)
  if not key or not n or n == 0 then return end
  local s = session()
  s[field] = type(s[field]) == "table" and s[field] or {}
  ns.Add(s[field], key, n)
  local run = db().run
  if run then
    run[field] = type(run[field]) == "table" and run[field] or {}
    ns.Add(run[field], key, n)
  end
  ns.Add(char()[field], key, n)
end

-- Time played: counted while you're logged in, into the level you're at and the day.
local lastTick
local function tick()
  local t = now()
  if lastTick and t > lastTick then
    local dt = math.min(t - lastTick, 120)
    local c, level = char(), reading().level
    if level > 0 then
      c.levels[level] = c.levels[level] or { started = t, played = 0, partial = true }
      c.levels[level].played = (c.levels[level].played or 0) + dt
    end
    local day = math.floor(t / 86400)
    c.days[day] = (c.days[day] or 0) + dt
    for old in pairs(c.days) do if old < day - 30 then c.days[old] = nil end end
  end
  lastTick = t
end

local function onLevelUp(newLevel)
  tick()
  local c, t = char(), now()
  local level = tonumber(newLevel) or reading().level
  if c.levels[level - 1] then c.levels[level - 1].ended = t end
  c.levels[level] = { started = t, played = 0 }
end

-- The dungeon or raid you're in: its name and a key that tells dungeons apart. Just the
-- dungeon: WoW Forever reports difficulty 0 or 1 for the same run (seen 2026-11-16).
local function instance()
  local inside, kind = safe(IsInInstance)
  if not inside or (kind ~= "party" and kind ~= "raid") then return nil end
  local name, _, _, difficultyName, _, _, _, id = safe(GetInstanceInfo)
  return { name = name or "Dungeon", key = tostring(id or name), kind = kind, difficulty = difficultyName ~= "" and difficultyName or nil }
end

-- Runs saved by 0.1.5 keyed "36:0".
local function runKey(run) return (tostring(run.key or ""):match("^[^:]*")) end

local function runs()
  local d = db()
  d.runs = type(d.runs) == "table" and d.runs or {}
  return d.runs
end

-- ---- The combat log: on in dungeons, so we can learn what WoW Forever writes.

-- WoW Forever always answers "off" when asked (seen 2026-11-20), even while the log
-- is being written. So Snitchbot goes by what it did itself: on once per run, off after.
local function combatLogging() return db().startedLog or (safe(LoggingCombat) and true or false) end

local function startCombatLog()
  if not settings().combatLog then return end
  if type(LoggingCombat) ~= "function" then return say("This client can't start the combat log from an addon. Type /combatlog instead.") end
  if combatLogging() then return end
  -- Advanced logging adds positions and health: what Warcraft Logs reads.
  if C_CVar and C_CVar.SetCVar then safe(C_CVar.SetCVar, "advancedCombatLogging", "1") else safe(SetCVar, "advancedCombatLogging", "1") end
  safe(LoggingCombat, true)
  db().startedLog = true
  say("Combat log on for this dungeon. It's saved in the game's Logs folder.")
end

local function stopCombatLog()
  local d = db()
  if not d.startedLog then return end
  d.startedLog = nil
  safe(LoggingCombat, false)
  say("Combat log off.")
end

local function setCombatLog(on)
  settings().combatLog = on
  if on and db().run then startCombatLog() elseif not on then stopCombatLog() end
end

-- ---- Runs

-- How long you can be out of the dungeon (a wipe, a corpse run, a step outside)
-- and still be on the same run when you come back in.
local AWAY = 15 * 60

-- The run ends when you were last inside it.
local function endRun(closed)
  local d = db()
  local run = d.run
  if not run then return end
  d.run = nil
  run.ended = run.leftAt or run.lastSeen or now()
  run.lastSeen, run.leftAt, run.diedAt, run.outAt, run.backAt, run.groupOut = nil, nil, nil, nil, nil, nil
  if closed then run.closed = true end
  local list = runs()
  table.insert(list, 1, run)
  ns.MergeRuns(list, AWAY)
  while #list > 100 do table.remove(list) end
  say(ns.RunSummary(list[1], now()))
  local verdict = ns.RunVerdict(list[1], list)
  if verdict then say(verdict) end
  stopCombatLog()
end

-- "End run" on the XP tab: done now, and no new run until you leave and come back.
local function endRunNow()
  local d = db()
  if not d.run then return end
  local inside = instance()
  if inside then d.skipKey = inside.key end
  d.run.leftAt = d.run.leftAt or now()
  endRun(true)
end

-- Worn gear's durability, when a run starts.
local function checkGear()
  local slots = {}
  for slot = 1, 18 do
    local cur, max = safe(GetInventoryItemDurability, slot)
    if max then slots[#slots + 1] = { cur = cur, max = max } end
  end
  local low, broken = ns.Durability(slots)
  if broken > 0 then
    say(string.format("%d %s broken. Repair before you pull.", broken, broken == 1 and "item is" or "items are"))
  elseif low and low < 0.3 then
    say(string.format("Your gear is at %d%% durability. Repair before you pull.", math.floor(low * 100 + 0.5)))
  end
end

-- Who's in the group, with their class: attendance, later.
local function noteGroup(run)
  if not run then return end
  run.group = run.group or {}
  local raid = safe(IsInRaid)
  local n = raid and (tonumber(safe(GetNumGroupMembers)) or 0) or 4
  for i = 1, n do
    local unit = raid and ("raid" .. i) or ("party" .. i)
    local name = safe(UnitName, unit)
    if name and name ~= "" and name ~= UNKNOWNOBJECT and name ~= me() then
      local class = safe(UnitClass, unit)
      run.group[ns.ShortName(name)] = class or "?"
    end
  end
end

-- One line in group chat when a run starts. Solo, nothing is said.
local function announce()
  if not settings().announce or not SendChatMessage then return end
  local channel
  -- Dungeon finder groups talk in instance chat; skip that check if the client has no such group kind.
  if LE_PARTY_CATEGORY_INSTANCE and safe(IsInGroup, LE_PARTY_CATEGORY_INSTANCE) then channel = "INSTANCE_CHAT"
  elseif safe(IsInRaid) then channel = "RAID"
  elseif safe(IsInGroup) then channel = "PARTY" end
  if channel then safe(SendChatMessage, ANNOUNCE, channel) end
end

local function checkInstance(atLogin)
  local d = db()
  local inside = instance()
  local run = d.run
  if run and inside and runKey(run) ~= inside.key then
    endRun() -- a different dungeon
  elseif run and not inside then
    -- Out of the dungeon: a wipe, a corpse run, waiting at the door, or done.
    -- Back in within 15 minutes is the same run; after that it's over.
    if not run.leftAt then -- the group as you left: a new one you join outside isn't this run's
      run.groupOut = {}
      for name, class in pairs(run.group or {}) do run.groupOut[name] = class end
    end
    run.leftAt = run.leftAt or (atLogin and run.lastSeen) or now()
    if now() - run.leftAt > AWAY then endRun() end
  elseif run and atLogin and not ns.CanResume(run, now(), nil, AWAY) then
    endRun() -- logged out inside and came back much later
  end
  if not inside then d.skipKey = nil; return end
  if not d.run and d.skipKey == inside.key then return end -- you ended this one with End run
  if not d.run then
    d.run = {
      key = inside.key, name = inside.name, kind = inside.kind, difficulty = inside.difficulty,
      character = me(), level = reading().level, started = now(), kills = 0, xp = 0, deaths = 0, mobs = {},
      bosses = {}, loot = {}, group = {}, moneyStart = money(), money = 0,
    }
    noteGroup(d.run)
    say(string.format("Tracking %s: kills, XP, bosses, loot and gold.", inside.name))
    checkGear()
    -- A moment later, so the chat channels are ready after the loading screen.
    if C_Timer and C_Timer.After then C_Timer.After(3, announce) else announce() end
    if settings().openInDungeon and frame then
      frame:Show()
      selectTab("xp")
    end
  end
  if d.run.leftAt then d.run.outAt, d.run.backAt = d.run.leftAt, now() end -- back in: same run, unless it's another copy
  d.run.lastSeen = now()
  d.run.leftAt = nil
  d.run.key = inside.key
  d.run.difficulty = d.run.difficulty or inside.difficulty
  startCombatLog()
end

local function onXP()
  local gained
  gained, xpNow = ns.XPGain(xpNow, reading())
  if gained <= 0 then return end
  session().xp = session().xp + gained
  local run = db().run
  if run then run.xp = run.xp + gained; run.lastSeen = now() end
  update()
end

local function countKill(name)
  local s = session()
  s.kills = s.kills + 1
  local run = db().run
  if run then
    run.kills = run.kills + 1
    run.mobs = run.mobs or {}
    run.mobs[name] = (run.mobs[name] or 0) + 1
    run.lastSeen = now()
  end
  update()
end

local function onKill(msg)
  local name, xp = ns.ParseKill(msg, KILL)
  if not name then return end
  tally("xpBy", "kills", (xp or 0) + ns.XPBonus(msg))
  countKill(name)
end

-- At max level there are no XP lines, so a kill is an enemy you see die: your
-- target or a nameplate. Each one counts once; one someone else tagged doesn't.
local seenDead, seenCount = {}, 0
local function onUnitDeath(unit)
  if type(unit) ~= "string" then return end
  local cap = tonumber(safe(GetMaxPlayerLevel)) or tonumber(MAX_PLAYER_LEVEL) or 60
  if (tonumber(safe(UnitLevel, "player")) or 0) < cap or not safe(UnitIsDead, unit) then return end
  if safe(UnitIsPlayer, unit) or safe(UnitIsTapDenied, unit) then return end
  local reaction = tonumber(safe(UnitReaction, unit, "player"))
  if reaction and reaction > 4 then return end -- friendly
  local guid = safe(UnitGUID, unit)
  if not ns.InstanceCopy(guid) or seenDead[guid] then return end
  if seenCount >= 2000 then seenDead, seenCount = {}, 0 end
  seenDead[guid], seenCount = true, seenCount + 1
  countKill(safe(UnitName, unit) or "?")
end

-- Which copy of the dungeon you're in, from the creatures around you. Back inside
-- within 15 minutes is the same run, unless it's another copy: someone reset it,
-- or you joined a new group. Then the old run ends when you left it.
local function noteCopy(unit)
  local run = db().run
  if not run or run.leftAt then return end
  local map, copy = ns.InstanceCopy(safe(UnitGUID, unit))
  if not copy or map ~= runKey(run) then return end
  if not run.copy then run.copy = copy; return end
  if run.copy == copy then return end
  local back = run.backAt
  run.leftAt = run.outAt or now()
  run.group = run.groupOut or run.group
  endRun(true)
  checkInstance(false)
  local new = db().run
  if new then
    new.copy = copy
    new.started = back or new.started
  end
  update()
end

local function onEncounter(event, id, name, _, _, success)
  local run = db().run
  if not run then return end
  run.bosses = run.bosses or {}
  if event == "ENCOUNTER_START" then
    run.pull = { id = id, name = name, started = now() }
  else
    local pull = run.pull and run.pull.id == id and run.pull or { id = id, name = name, started = now() }
    run.pull = nil
    local kill = success == 1 or success == true
    run.bosses[#run.bosses + 1] = { id = id, name = name or pull.name, seconds = now() - pull.started, kill = kill }
    if kill then run.lastKill = { name = name or pull.name, at = now() } end
  end
  run.lastSeen = now()
  update()
end

local LOOT = ns.LootPatterns(_G)

-- "Nonut Novemba" or "Nonut-Novemba" -> "Nonut", when Nonut is in the run.
local function looter(run, who)
  who = tostring(who or "")
  local names = { me() }
  for name in pairs(run.group or {}) do names[#names + 1] = name end
  for _, name in ipairs(names) do
    local rest = who:sub(#name + 1, #name + 1)
    if who:sub(1, #name) == name and (rest == "" or rest == " " or rest == "-") then return name end
  end
  local short = ns.ShortName(who)
  return short ~= "" and short or nil
end

-- What an item is worth: the pasted auction house price, else what a vendor pays.
local function itemValue(id)
  local p = db().prices
  if type(p) == "table" and type(p.prices) == "table" and p.prices[id] then return p.prices[id] end
  local sell = select(11, safe(C_Item and C_Item.GetItemInfo or GetItemInfo, id))
  return tonumber(sell)
end

local function onLoot(msg, who)
  local run = db().run
  local l = ns.ParseLootLine(msg, LOOT)
  if not l then return end
  if l.self then
    local value = itemValue(l.id)
    if value and value > 0 then
      value = value * (l.count or 1)
      local s = session()
      s.value = (s.value or 0) + value
      if run then run.value = (run.value or 0) + value end
    end
  end
  if not run or (l.quality and l.quality < 2) then return end
  local quality = l.quality
  if not quality then
    quality = select(3, safe(C_Item and C_Item.GetItemInfo or GetItemInfo, l.id))
    if quality and quality < 2 then return end
  end
  run.loot = run.loot or {}
  if #run.loot < 60 then
    local name = l.self and me() or looter(run, (who and who ~= "") and who or l.who)
    local boss = run.lastKill and now() - (run.lastKill.at or 0) <= 300 and run.lastKill.name or nil
    run.loot[#run.loot + 1] = { id = l.id, name = l.name, q = quality or 2, n = l.count, who = name or me(), boss = boss }
  end
  update()
end

-- 0.1.5 saved every Need, Greed and roll line as an item called "Loot".
local function cleanLoot()
  for _, run in ipairs(runs()) do
    if type(run.loot) == "table" then
      local kept = {}
      for _, l in ipairs(run.loot) do if l.name ~= "Loot" then kept[#kept + 1] = l end end
      run.loot = kept
    end
  end
end

-- What's open when gold changes says where it came from.
local goldCtx, lastMoney = {}, nil
local function onMoney()
  local run, m = db().run, money()
  if run and run.moneyStart then run.money = m - run.moneyStart end
  if lastMoney and m ~= lastMoney then tally("gold", ns.GoldSource(goldCtx, m - lastMoney, now()), m - lastMoney) end
  lastMoney = m
end

local function setOpen(kind, open)
  if open then
    goldCtx.open = kind
  elseif goldCtx.open == kind then
    goldCtx.open, goldCtx.recent, goldCtx.recentAt = nil, kind, now()
  end
end

local OPENS = { MERCHANT_SHOW = "merchant", MAIL_SHOW = "mail", AUCTION_HOUSE_SHOW = "auction", TRAINER_SHOW = "trainer",
  TAXIMAP_OPENED = "taxi", TRADE_SHOW = "trade" }
local CLOSES = { MERCHANT_CLOSED = "merchant", MAIL_CLOSED = "mail", AUCTION_HOUSE_CLOSED = "auction", TRAINER_CLOSED = "trainer",
  TAXIMAP_CLOSED = "taxi", TRADE_CLOSED = "trade" }
-- The modern client says which window through one event.
local INTERACTION = { Merchant = "merchant", MailInfo = "mail", Auctioneer = "auction", Trainer = "trainer", TaxiNode = "taxi", TradePartner = "trade" }
local function interaction(kind)
  local types = Enum and Enum.PlayerInteractionType
  if type(types) ~= "table" then return nil end
  for name, value in pairs(types) do
    if value == kind then return INTERACTION[name] end
  end
  return nil
end

-- ---- Raid buffs: who has a flask, elixirs, food and world buffs

local function auraList(unit)
  local list = {}
  for i = 1, 40 do
    local a
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      a = safe(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
    else
      local name, _, _, _, _, _, _, _, _, id = safe(UnitBuff, unit, i)
      a = name and { name = name, spellId = id } or nil
    end
    if type(a) ~= "table" then break end
    list[#list + 1] = { name = a.name, spellId = a.spellId }
  end
  return list
end

local function buffCheck()
  local people = {}
  local function check(unit)
    local name = safe(UnitName, unit)
    if not name or name == "" then return end
    local away = safe(UnitIsConnected, unit) == false or safe(UnitIsVisible, unit) == false
    people[#people + 1] = { name = ns.ShortName(name), away = away, buffs = ns.BuffCheck(auraList(unit)) }
  end
  if safe(IsInRaid) then
    for i = 1, tonumber(safe(GetNumGroupMembers)) or 0 do check("raid" .. i) end
  else
    check("player")
    for i = 1, 4 do check("party" .. i) end
  end
  for _, line in ipairs(ns.BuffReport(people)) do say(line) end
end

-- ---- The code for myself.snitchbot.app

local REGIONS = { [1] = "us", [3] = "eu" }
local function exportCode()
  tick()
  local name, realm = safe(UnitFullName, "player")
  if not name then name, realm = safe(UnitName, "player") end
  -- WoW Forever names are two words ("Lill Slampan"); the game hands them over as name and realm.
  local full = (realm and realm ~= "") and (name .. " " .. realm) or (name or "")
  local _, class = safe(UnitClass, "player")
  local c = char()
  local code = ns.CharCode({ region = REGIONS[tonumber(safe(GetCurrentRegion)) or 0] or "eu", name = full, class = class,
    level = reading().level, now = now(), levels = c.levels, runs = runs(), gold = c.gold, xp = c.xpBy, rep = c.rep })
  showCopy("Copy for snitchbot.app", code,
    "Press Ctrl+C (Cmd+C on a Mac) to copy it. Then open myself.snitchbot.app, sign in and paste it there: your runs, levels and gold show on your character's page, for you only.")
end

-- ---- Probe

local function probe()
  local function get(path)
    local v = _G
    for key in path:gmatch("[^.]+") do
      if type(v) ~= "table" then return nil end
      v = v[key]
    end
    return v
  end
  local tester = CreateFrame("Frame")
  local function canRegister(event)
    local ok = pcall(tester.RegisterEvent, tester, event)
    pcall(tester.UnregisterEvent, tester, event)
    return ok
  end
  local version, build, _, interface = safe(GetBuildInfo)
  local code = ns.ProbeCode(get, canRegister, { version = version, build = build, interface = interface, project = WOW_PROJECT_ID })
  db().probe = code
  showCopy("Snitchbot probe", code)
end

-- ---- The window: one window, five tabs, everything a click away.

local TABS = {
  { key = "raid", label = "Raid list" },
  { key = "xp", label = "XP" },
  { key = "runs", label = "Runs" },
  { key = "stats", label = "Stats" },
  { key = "settings", label = "Settings" },
}
local TOP = 66 -- header and tab bar
local HEIGHT = 470
local panes, tabButtons = {}, {}

local function smallButton(parent, label, width)
  local b = button(parent, label, false, width or 90)
  b:SetHeight(22)
  setFont(b.label, 11, "medium")
  return b
end

-- A tick box and a label; the whole line is the button.
local toggles = {}
local function toggle(parent, y, label, hint, get, set)
  local b = CreateFrame("Button", nil, parent)
  b:SetPoint("TOPLEFT", PAD - 4, y)
  b:SetPoint("RIGHT", -(PAD - 4), 0)
  b:SetHeight(hint and 40 or 28)
  b.hover = fill(b, C.hover)
  b.hover:SetAllPoints()
  b.hover:Hide()
  local box = CreateFrame("Frame", nil, b)
  box:SetSize(14, 14)
  box:SetPoint("TOPLEFT", 4, hint and -6 or -7)
  b.fill = fill(box, C.accent, "ARTWORK")
  b.fill:SetAllPoints()
  hairline(box, { C.muted[1], C.muted[2], C.muted[3], 0.7 })
  b.tick = box:CreateTexture(nil, "OVERLAY")
  b.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  b.tick:SetSize(20, 20)
  b.tick:SetPoint("CENTER", 1, 0)
  safe(b.tick.SetDesaturated, b.tick, true)
  b.tick:SetVertexColor(C.onAccent[1], C.onAccent[2], C.onAccent[3])
  b.label = text(b, 13, "regular", C.text)
  b.label:SetPoint("TOPLEFT", 28, hint and -5 or -7)
  b.label:SetText(label)
  if hint then
    b.hint = text(b, 11, "regular", C.muted)
    b.hint:SetPoint("TOPLEFT", 28, -22)
    b.hint:SetPoint("RIGHT", -4, 0)
    b.hint:SetText(hint)
  end
  b.sync = function() local on = get() and true or false; show(b.fill, on); show(b.tick, on) end
  b:SetScript("OnClick", function() set(not get()); b.sync(); update() end)
  b:SetScript("OnEnter", function() b.hover:Show() end)
  b:SetScript("OnLeave", function() b.hover:Hide() end)
  toggles[#toggles + 1] = b
  return b
end

local function makeRaidPane(p)
  local listTop, footerHeight = 82, 44
  frame.who = text(p, 16, "semibold", C.text)
  frame.who:SetPoint("TOPLEFT", PAD, -14)
  frame.who:SetPoint("RIGHT", -PAD - 190, 0)
  frame.sub = text(p, 12, "regular", C.muted)
  frame.sub:SetPoint("TOPLEFT", PAD, -36)
  frame.sub:SetPoint("RIGHT", -PAD, 0)
  frame.status = text(p, 12, "medium", C.dim)
  frame.status:SetPoint("TOPLEFT", PAD, -54)
  frame.status:SetPoint("RIGHT", -PAD, 0)
  frame.newList = smallButton(p, "New list", 84)
  frame.newList:SetPoint("TOPRIGHT", -PAD, -12)
  frame.newList:SetScript("OnClick", function() openPaste() end)
  -- Always there, list or not: before a raid, who's missing flasks and food.
  frame.checkBuffs = smallButton(p, "Check buffs", 92)
  frame.checkBuffs:SetPoint("RIGHT", frame.newList, "LEFT", -6, 0)
  frame.checkBuffs:SetScript("OnClick", buffCheck)
  frame.rule = divider(p, -(listTop - 6))

  local sf, child = scrollArea(p, ROW_HEIGHT * 2)
  sf:SetPoint("TOPLEFT", PAD - 4, -listTop)
  sf:SetPoint("BOTTOMRIGHT", -(PAD - 4), footerHeight + 4)
  child:SetSize(WIDTH - 2 * (PAD - 4), ROW_HEIGHT)
  frame.scroll, frame.child = sf, child
  rows = {}

  -- Footer: how much of the list is in your bags, as a bar.
  local footer = CreateFrame("Frame", nil, p)
  footer:SetPoint("BOTTOMLEFT")
  footer:SetPoint("BOTTOMRIGHT")
  footer:SetHeight(footerHeight)
  fill(footer, C.footer):SetAllPoints()
  local top = fill(footer, C.line, "ARTWORK")
  top:SetHeight(1)
  top:SetPoint("TOPLEFT")
  top:SetPoint("TOPRIGHT")
  frame.ready = text(footer, 12, "regular", C.dim)
  frame.ready:SetPoint("TOPLEFT", PAD - 1, -9)
  frame.pct = text(footer, 12, "medium", C.dim)
  frame.pct:SetPoint("BOTTOMRIGHT", -PAD + 1, 8)
  frame.pct:SetJustifyH("RIGHT")
  frame.track = fill(footer, C.track, "ARTWORK")
  frame.track:SetHeight(3)
  frame.track:SetPoint("BOTTOMLEFT", PAD - 1, 12)
  frame.track:SetWidth(TRACK)
  frame.bar = fill(footer, C.accent, "OVERLAY")
  frame.bar:SetHeight(3)
  frame.bar:SetPoint("LEFT", frame.track, "LEFT")
  frame.footer = footer

  -- No list yet.
  frame.empty = text(p, 13, "regular", C.dim)
  frame.empty:SetPoint("TOPLEFT", PAD, -50)
  frame.empty:SetPoint("RIGHT", -PAD, 0)
  safe(frame.empty.SetWordWrap, frame.empty, true)
  frame.empty:SetText("No raid list yet.\n\nOn auction.snitchbot.app, open Raid list and press Copy for the addon. Then paste it here.")
  frame.emptyButton = button(p, "Paste a list", true, 130)
  frame.emptyButton:SetPoint("TOPLEFT", frame.empty, "BOTTOMLEFT", 0, -18)
  frame.emptyButton:SetScript("OnClick", function() openPaste() end)
end

local XPW = WIDTH - 2 * PAD

-- A stat card: a small label over a big number. Returns the number and the label.
local CARD_GAP, CARD_H = 8, 42
local CARD_W = (XPW - CARD_GAP) / 2
local function card(parent, col, row, y, label)
  local c = CreateFrame("Frame", nil, parent)
  c:SetSize(CARD_W, CARD_H)
  c:SetPoint("TOPLEFT", PAD + col * (CARD_W + CARD_GAP), y - row * (CARD_H + 6))
  fill(c, C.card):SetAllPoints()
  local l = text(c, 11, "regular", C.muted)
  l:SetPoint("TOPLEFT", 10, -6)
  l:SetText(label)
  local v = text(c, 15, "semibold", C.text)
  v:SetPoint("TOPLEFT", 10, -21)
  v:SetPoint("RIGHT", -8, 0)
  return v, l
end

local function makeXPPane(p)
  local x = {}
  frame.x = x
  x.level = text(p, 16, "semibold", C.text)
  x.level:SetPoint("TOPLEFT", PAD, -14)
  x.pct = text(p, 12, "medium", C.dim)
  x.pct:SetPoint("TOPRIGHT", -PAD, -17)
  x.pct:SetJustifyH("RIGHT")
  local track = fill(p, C.track, "ARTWORK")
  track:SetHeight(5)
  track:SetPoint("TOPLEFT", PAD, -40)
  track:SetWidth(XPW)
  x.rested = fill(p, { 0.47, 0.6, 1, 0.45 }, "ARTWORK", 1)
  x.rested:SetHeight(5)
  x.rested:SetPoint("LEFT", track, "LEFT")
  x.bar = fill(p, C.accent, "OVERLAY")
  x.bar:SetHeight(5)
  x.bar:SetPoint("LEFT", track, "LEFT")
  x.xp = text(p, 11, "regular", C.muted)
  x.xp:SetPoint("TOPLEFT", PAD, -52)
  x.xp:SetPoint("RIGHT", -PAD, 0)

  x.rate = card(p, 0, 0, -76, "XP per hour")
  x.ttl = card(p, 1, 0, -76, "To next level")
  x.gold, x.goldLabel = card(p, 0, 1, -76, "Gold")
  x.value = card(p, 1, 1, -76, "Your loot is worth")
  x.kills = card(p, 0, 2, -76, "Kills")
  x.time = card(p, 1, 2, -76, "Session")
  x.value:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
  local reset = smallButton(p, "Reset session", 104)
  reset:SetPoint("TOPRIGHT", -PAD, -224)
  reset:SetScript("OnClick", function() resetSession(); update() end)
  divider(p, -254)

  x.runLabel = text(p, 11, "semibold", C.muted)
  x.runLabel:SetPoint("TOPLEFT", PAD, -268)
  x.runName = text(p, 14, "semibold", C.text)
  x.runName:SetPoint("TOPLEFT", PAD, -286)
  x.runName:SetPoint("RIGHT", -PAD, 0)
  x.runLine = text(p, 12, "regular", C.dim)
  x.runLine:SetPoint("TOPLEFT", PAD, -306)
  x.runLine:SetPoint("RIGHT", -PAD, 0)
  local all = smallButton(p, "All runs", 84)
  all:SetPoint("TOPLEFT", PAD, -332)
  all:SetScript("OnClick", function() selectTab("runs") end)
  x.endRun = smallButton(p, "End run", 84)
  x.endRun:SetPoint("LEFT", all, "RIGHT", 6, 0)
  x.endRun:SetScript("OnClick", function() endRunNow(); update() end)

  -- Footer: is the combat log on? Click to switch it for dungeons.
  local log = CreateFrame("Button", nil, p)
  log:SetPoint("BOTTOMLEFT")
  log:SetPoint("BOTTOMRIGHT")
  log:SetHeight(30)
  fill(log, C.footer):SetAllPoints()
  local top = fill(log, C.line, "ARTWORK")
  top:SetHeight(1)
  top:SetPoint("TOPLEFT")
  top:SetPoint("TOPRIGHT")
  x.dot = fill(log, C.muted, "ARTWORK")
  x.dot:SetSize(6, 6)
  x.dot:SetPoint("LEFT", PAD, 0)
  x.log = text(log, 11, "regular", C.dim)
  x.log:SetPoint("LEFT", PAD + 12, 0)
  x.logAction = text(log, 11, "medium", C.accent)
  x.logAction:SetPoint("RIGHT", -PAD, 0)
  x.logAction:SetJustifyH("RIGHT")
  log:SetScript("OnClick", function() setCombatLog(not settings().combatLog); update() end)
end

local RUN_HEIGHT = 62
local QUALITY_HEX = { [2] = "|cff1eff00", [3] = "|cff0070dd", [4] = "|cffa335ee", [5] = "|cffff8000" }

-- Everything about a run, on hover: bosses, loot, group.
local function runTooltip(row)
  local run = row.run
  if not run or not GameTooltip then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetText(run.name or "Dungeon")
  if run.difficulty then GameTooltip:AddLine(run.difficulty, C.muted[1], C.muted[2], C.muted[3]) end
  if run.bosses and #run.bosses > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Bosses", C.accent[1], C.accent[2], C.accent[3])
    for _, b in ipairs(run.bosses) do
      local c = b.kill and C.success or C.danger
      GameTooltip:AddDoubleLine((b.name or "Boss") .. (b.kill and "" or " (wipe)"), ns.Duration(b.seconds or 0), c[1], c[2], c[3], C.dim[1], C.dim[2], C.dim[3])
    end
  end
  if run.loot and #run.loot > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Loot", C.accent[1], C.accent[2], C.accent[3])
    local lines, seen = {}, {}
    for _, l in ipairs(run.loot) do
      local k = tostring(l.id) .. ":" .. tostring(l.who)
      if seen[k] then seen[k].n = seen[k].n + (l.n or 1)
      else seen[k] = { name = l.name, q = l.q, who = l.who, n = l.n or 1 }; lines[#lines + 1] = seen[k] end
    end
    for i, l in ipairs(lines) do
      if i > 15 then
        GameTooltip:AddLine(string.format("and %d more", #lines - 15), C.muted[1], C.muted[2], C.muted[3])
        break
      end
      GameTooltip:AddDoubleLine((QUALITY_HEX[l.q] or "") .. l.name .. "|r" .. (l.n > 1 and (" x" .. l.n) or ""), l.who or "", 1, 1, 1, C.dim[1], C.dim[2], C.dim[3])
    end
  end
  if (run.value or 0) > 0 or run.rep then
    GameTooltip:AddLine(" ")
    if (run.value or 0) > 0 then GameTooltip:AddDoubleLine("Your loot is worth", ns.Money(run.value), C.dim[1], C.dim[2], C.dim[3], 1, 1, 1) end
    for faction, n in pairs(run.rep or {}) do
      GameTooltip:AddDoubleLine(faction, (n > 0 and "+" or "") .. ns.Num(n) .. " rep", C.dim[1], C.dim[2], C.dim[3], 1, 1, 1)
    end
  end
  local names = {}
  for name, class in pairs(run.group or {}) do names[#names + 1] = name .. " (" .. class .. ")" end
  if #names > 0 then
    table.sort(names)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Group", C.accent[1], C.accent[2], C.accent[3])
    GameTooltip:AddLine(table.concat(names, ", "), C.dim[1], C.dim[2], C.dim[3], true)
  end
  GameTooltip:Show()
end

-- "2 of 3 bosses · 4 items · 4 in group"
local function runDetails(run)
  local parts = {}
  local kills, pulls = ns.BossCount(run)
  if pulls > 0 then parts[#parts + 1] = kills .. (kills == 1 and " boss" or " bosses") .. ((pulls > kills) and (", " .. (pulls - kills) .. " wipes") or "") end
  if run.loot and #run.loot > 0 then parts[#parts + 1] = #run.loot .. (#run.loot == 1 and " item" or " items") end
  local n = 0
  for _ in pairs(run.group or {}) do n = n + 1 end
  if n > 0 then parts[#parts + 1] = "with " .. n .. (n == 1 and " other" or " others") end
  return #parts > 0 and table.concat(parts, "  ·  ") or "No bosses or loot yet"
end

local function makeRunRow(parent, i)
  local r = CreateFrame("Button", nil, parent)
  r.hover = fill(r, C.hover)
  r.hover:SetAllPoints()
  r.hover:Hide()
  r:SetScript("OnEnter", function(self) self.hover:Show(); runTooltip(self) end)
  r:SetScript("OnLeave", function(self) self.hover:Hide(); if GameTooltip then GameTooltip:Hide() end end)
  r:SetHeight(RUN_HEIGHT)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * RUN_HEIGHT)
  r:SetPoint("RIGHT", parent, "RIGHT")
  r.mark = fill(r, C.accent, "ARTWORK")
  r.mark:SetWidth(2)
  r.mark:SetPoint("TOPLEFT", 0, -6)
  r.mark:SetPoint("BOTTOMLEFT", 0, 6)
  r.name = text(r, 13, "semibold", C.text)
  r.name:SetPoint("TOPLEFT", 10, -7)
  r.name:SetPoint("RIGHT", -96, 0)
  r.when = text(r, 11, "regular", C.muted)
  r.when:SetPoint("TOPRIGHT", -4, -8)
  r.when:SetJustifyH("RIGHT")
  r.line = text(r, 12, "regular", C.dim)
  r.line:SetPoint("TOPLEFT", 10, -25)
  r.line:SetPoint("RIGHT", -4, 0)
  r.details = text(r, 11, "regular", C.muted)
  r.details:SetPoint("TOPLEFT", 10, -42)
  r.details:SetPoint("RIGHT", -4, 0)
  local rule = fill(r, C.line, "ARTWORK")
  rule:SetHeight(1)
  rule:SetPoint("BOTTOMLEFT")
  rule:SetPoint("BOTTOMRIGHT")
  return r
end

local function makeRunsPane(p)
  local r = {}
  frame.r = r
  r.title = text(p, 16, "semibold", C.text)
  r.title:SetPoint("TOPLEFT", PAD, -14)
  r.sub = text(p, 12, "regular", C.muted)
  r.sub:SetPoint("TOPLEFT", PAD, -36)
  r.sub:SetPoint("RIGHT", -PAD, 0)
  divider(p, -60)
  local sf, child = scrollArea(p, RUN_HEIGHT * 2)
  sf:SetPoint("TOPLEFT", PAD - 4, -64)
  sf:SetPoint("BOTTOMRIGHT", -(PAD - 4), 8)
  child:SetSize(WIDTH - 2 * (PAD - 4), RUN_HEIGHT)
  r.scroll, r.child, r.rows = sf, child, {}
  r.empty = text(p, 13, "regular", C.dim)
  r.empty:SetPoint("TOPLEFT", PAD, -76)
  r.empty:SetPoint("RIGHT", -PAD, 0)
  safe(r.empty.SetWordWrap, r.empty, true)
  r.empty:SetText("No runs yet.\n\nEnter a dungeon and Snitchbot starts tracking by itself: time, kills, XP, bosses, loot, gold and deaths. Hover a run to see it all.")
end

-- The Stats tab: a scrolling list of lines, headings and label / value pairs.
local LINE = 20

local function makeStatsPane(p)
  local st = {}
  frame.st = st
  st.title = text(p, 16, "semibold", C.text)
  st.title:SetPoint("TOPLEFT", PAD, -14)
  st.title:SetText("Stats")
  st.sub = text(p, 12, "regular", C.muted)
  st.sub:SetPoint("TOPLEFT", PAD, -36)
  st.sub:SetPoint("RIGHT", -PAD - 150, 0)
  st.copy = smallButton(p, "Copy for snitchbot.app", 146)
  st.copy:SetPoint("TOPRIGHT", -PAD, -12)
  st.copy:SetScript("OnClick", exportCode)
  divider(p, -60)
  local sf, child = scrollArea(p, LINE * 4)
  sf:SetPoint("TOPLEFT", PAD - 4, -64)
  sf:SetPoint("BOTTOMRIGHT", -(PAD - 4), 8)
  child:SetSize(WIDTH - 2 * (PAD - 4), LINE)
  st.scroll, st.child, st.rows = sf, child, {}
end

local function statRow(parent, i)
  local r = CreateFrame("Frame", nil, parent)
  r:SetHeight(LINE)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * LINE)
  r:SetPoint("RIGHT", parent, "RIGHT")
  r.right = text(r, 12, "medium", C.text)
  r.right:SetPoint("RIGHT", -4, 0)
  r.right:SetJustifyH("RIGHT")
  r.left = text(r, 12, "regular", C.dim)
  r.left:SetPoint("LEFT", 4, 0)
  r.left:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
  r.left:SetJustifyH("LEFT")
  return r
end

local function makeSettingsPane(p)
  local title = text(p, 16, "semibold", C.text)
  title:SetPoint("TOPLEFT", PAD, -14)
  title:SetText("Settings")
  local s = settings
  toggle(p, -42, "Combat log in dungeons", "Starts the game's combat log when you enter a dungeon, stops it when you leave.",
    function() return s().combatLog end, setCombatLog)
  toggle(p, -86, "Open in dungeons", "Opens this window on the XP tab when a run starts.",
    function() return s().openInDungeon end, function(on) s().openInDungeon = on end)
  toggle(p, -130, "Tell my group", "Says \"" .. ANNOUNCE .. "\" in group chat when a run starts.",
    function() return s().announce end, function(on) s().announce = on end)
  toggle(p, -174, "Minimap button", "Click it to open or close Snitchbot. Drag it to move it.",
    function() return s().minimap end, function(on) s().minimap = on; if frame.minimap then show(frame.minimap, on) end end)
  divider(p, -224)

  local pasteB = button(p, "Paste a raid list", true, 150)
  pasteB:SetPoint("TOPLEFT", PAD, -240)
  pasteB:SetScript("OnClick", function() openPaste() end)
  local pricesB = button(p, "Paste AH prices", false, 140)
  pricesB:SetPoint("LEFT", pasteB, "RIGHT", 10, 0)
  pricesB:SetScript("OnClick", function() openPaste("prices") end)
  frame.prices = text(p, 11, "regular", C.muted)
  frame.prices:SetPoint("TOPLEFT", PAD, -276)
  frame.prices:SetPoint("RIGHT", -PAD, 0)
  safe(frame.prices.SetWordWrap, frame.prices, true)
  local probeB = button(p, "Probe the game", false, 140)
  probeB:SetPoint("TOPLEFT", PAD, -312)
  probeB:SetScript("OnClick", probe)
  local probeHint = text(p, 11, "regular", C.muted)
  probeHint:SetPoint("TOPLEFT", PAD, -346)
  probeHint:SetPoint("RIGHT", -PAD, 0)
  safe(probeHint.SetWordWrap, probeHint, true)
  probeHint:SetText("Probe makes a line that says which game functions this client has. Send it to Snitchbot when asked.")

  local about = text(p, 11, "regular", C.muted)
  about:SetPoint("BOTTOMLEFT", PAD, 14)
  local version = (C_AddOns and C_AddOns.GetAddOnMetadata and safe(C_AddOns.GetAddOnMetadata, ADDON, "Version"))
    or safe(GetAddOnMetadata, ADDON, "Version") or ""
  about:SetText("Snitchbot " .. version .. "  ·  snitchbot.app")
end

local function makeTabs()
  local bar = CreateFrame("Frame", nil, frame)
  bar:SetPoint("TOPLEFT", 1, -33)
  bar:SetPoint("TOPRIGHT", -1, -33)
  bar:SetHeight(TOP - 33)
  local under = fill(bar, C.line, "ARTWORK")
  under:SetHeight(1)
  under:SetPoint("BOTTOMLEFT")
  under:SetPoint("BOTTOMRIGHT")
  local x = PAD - 4
  for _, t in ipairs(TABS) do
    local b = CreateFrame("Button", nil, bar)
    b.label = text(b, 12, "semibold", C.muted)
    b.label:SetPoint("CENTER", 0, 0)
    b.label:SetJustifyH("CENTER")
    b.label:SetText(t.label)
    local w = math.max(40, (tonumber(safe(b.label.GetStringWidth, b.label)) or 40) + 22)
    b:SetSize(w, TOP - 34)
    b:SetPoint("BOTTOMLEFT", x, 0)
    x = x + w + 4
    b.pill = fill(b, C.accent, "BACKGROUND", 1)
    b.pill:SetPoint("TOPLEFT", 0, -6)
    b.pill:SetPoint("BOTTOMRIGHT", 0, 6)
    b.hover = fill(b, C.card, "BACKGROUND")
    b.hover:SetAllPoints(b.pill)
    b.hover:Hide()
    b:SetScript("OnClick", function() selectTab(t.key) end)
    b:SetScript("OnEnter", function() if settings().tab ~= t.key then b.hover:Show(); b.label:SetTextColor(C.text[1], C.text[2], C.text[3]) end end)
    b:SetScript("OnLeave", function() b.hover:Hide(); if settings().tab ~= t.key then b.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end end)
    tabButtons[t.key] = b
  end
end

-- The minimap button: click opens or closes the window, drag moves it round the map.
local function makeMinimapButton()
  if not Minimap then return end
  local b = CreateFrame("Button", "SnitchbotMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  safe(b.SetFrameLevel, b, 8)
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("CENTER")
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_02")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER")
  safe(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  safe(b.SetHighlightTexture, b, "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local function place()
    local a = math.rad(settings().minimapAngle or 200)
    local r = ((tonumber(safe(Minimap.GetWidth, Minimap)) or 140) / 2) + 6
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
  end
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      local atan2 = math.atan2 or math.atan
      settings().minimapAngle = math.deg(atan2(py / scale - my, px / scale - mx))
      place()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnClick", function() SnitchbotToggle() end)
  b:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Snitchbot")
    GameTooltip:AddLine("Click to open or close.", 1, 1, 1)
    GameTooltip:AddLine("Drag to move.", C.muted[1], C.muted[2], C.muted[3])
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  place()
  show(b, settings().minimap)
  frame.minimap = b
end

local function makeFrame()
  frame = window("SnitchbotFrame", WIDTH, HEIGHT, "MEDIUM", true)
  place(frame, "SnitchbotFrame", "CENTER", 300, 40)
  frame.title:SetText("Snitchbot")
  -- × only hides it; it stays shut until you open it again.
  frame.close:SetScript("OnClick", function() frame:Hide(); settings().open = false end)
  makeTabs()
  for _, t in ipairs(TABS) do
    local p = CreateFrame("Frame", nil, frame)
    p:SetPoint("TOPLEFT", 1, -TOP)
    p:SetPoint("BOTTOMRIGHT", -1, 1)
    p:Hide()
    panes[t.key] = p
  end
  makeRaidPane(panes.raid)
  makeXPPane(panes.xp)
  makeRunsPane(panes.runs)
  makeStatsPane(panes.stats)
  makeSettingsPane(panes.settings)
  makeMinimapButton()

  local elapsed = 0
  frame:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + (dt or 0)
    if elapsed >= 1 then elapsed = 0; if settings().tab ~= "raid" then update() end end
  end)
  frame:SetScript("OnShow", function() settings().open = true; selectTab(settings().tab) end)
  frame:Hide()
end

function SnitchbotToggle()
  if not frame then return end
  if frame:IsShown() then frame:Hide(); settings().open = false else frame:Show() end
end

selectTab = function(key)
  if not panes[key] then key = "raid" end
  settings().tab = key
  for k, p in pairs(panes) do show(p, k == key) end
  for k, b in pairs(tabButtons) do
    local c = k == key and C.onAccent or C.muted
    b.label:SetTextColor(c[1], c[2], c[3])
    show(b.pill, k == key)
    b.hover:Hide()
  end
  update()
end

-- ---- Filling in the tabs

local function setBar(done, total)
  local share = total > 0 and done / total or 0
  frame.bar:SetWidth(math.max(0.01, TRACK * share))
  show(frame.bar, share > 0)
  frame.pct:SetText(string.format("%d%%", math.floor(share * 100 + 0.5)))
end

refresh = function()
  if not frame or not frame:IsShown() or settings().tab ~= "raid" then return end
  local list = currentList()
  for _, r in ipairs(rows) do r:Hide() end
  local has = list ~= nil
  for _, part in ipairs({ frame.who, frame.sub, frame.status, frame.rule, frame.scroll, frame.footer, frame.newList }) do show(part, has) end
  show(frame.empty, not has)
  show(frame.emptyButton, not has)
  if not list then return end

  local who = list.character ~= "" and list.character or me()
  local mine = list.character == "" or list.character == me()
  frame.who:SetText(who)
  frame.sub:SetText(ns.RaidLabel(list) .. (list.guild ~= "" and ("  ·  " .. list.guild) or ""))
  local progress, short = ns.Progress(list, count)
  if not mine then
    frame.status:SetText(hex(C.muted) .. "This list is for " .. list.character .. ". The counts are this character's bags.|r")
  elseif short == 0 then
    frame.status:SetText(hex(C.success) .. "You have everything for one raid night.|r")
  else
    frame.status:SetText(string.format("%s%d of %d items short.|r", hex(C.danger), short, #progress))
  end

  frame.child:SetHeight(math.max(ROW_HEIGHT, #progress * ROW_HEIGHT))
  for i, p in ipairs(progress) do
    rows[i] = rows[i] or makeRow(frame.child, i)
    local r = rows[i]
    r.itemId, r.bank = p.id, p.total - p.bags
    r.icon:SetTexture(itemIcon(p.id))
    local name = itemName(p.id)
    r.name:SetText(name or ("Item " .. p.id))
    local nc = name and C.item or C.muted
    r.name:SetTextColor(nc[1], nc[2], nc[3])
    local done = p.missing == 0
    local have = math.min(p.total, p.need)
    local bank = p.total > p.bags and string.format("%s  +%d bank|r", hex(C.muted), p.total - p.bags) or ""
    r.count:SetText(string.format("%s%d / %d|r%s", hex(done and C.dim or C.danger), have, p.need, bank))
    show(r.boxFill, done)
    show(r.tick, done)
    r:Show()
  end
  local ready = #progress - short
  frame.ready:SetText(string.format("%d of %d ready for raid night", ready, #progress))
  setBar(ready, #progress)
  if frame.scroll.place then frame.scroll.place() end
end

local function runLine(run, t)
  return (ns.RunSummary(run, t):gsub("^.-: ", ""):gsub("%.$", ""))
end

local function fillXP()
  local x, s, r, t = frame.x, session(), reading(), now()
  local maxLevel = r.max <= 0
  x.level:SetText("Level " .. r.level)
  local share = maxLevel and 1 or math.min(1, r.xp / r.max)
  x.pct:SetText(maxLevel and "" or string.format("%.1f%%", share * 100))
  x.bar:SetWidth(math.max(0.01, XPW * share))
  local rested = tonumber(safe(GetXPExhaustion)) or 0
  show(x.rested, rested > 0 and not maxLevel)
  x.rested:SetWidth(math.max(0.01, XPW * math.min(1, (r.xp + rested) / math.max(1, r.max))))
  x.xp:SetText(maxLevel and "Max level" or string.format("%s / %s XP%s", ns.Num(r.xp), ns.Num(r.max),
    rested > 0 and ("  ·  " .. ns.Num(rested) .. " rested") or ""))

  local seconds = t - s.started
  local rate = ns.Rate(s.xp, seconds)
  x.rate:SetText(rate and ns.Num(rate) or "–")
  local left = ns.TimeToLevel(r.max - r.xp, rate)
  x.ttl:SetText(maxLevel and "–" or (left and ns.Duration(left) or "–"))
  x.kills:SetText(ns.Num(s.kills))
  x.time:SetText(ns.Duration(seconds))
  local earned = money() - (s.moneyStart or money())
  local goldRate = seconds >= 60 and earned ~= 0 and (earned * 3600 / seconds) or nil
  x.gold:SetText((earned > 0 and "+" or "") .. ns.Money(earned))
  x.goldLabel:SetText(goldRate and ("Gold  ·  " .. ns.Money(goldRate) .. "/h") or "Gold")
  x.value:SetText((s.value or 0) > 0 and ns.Money(s.value) or "–")

  local d = db()
  local run = d.run or runs()[1]
  show(x.endRun, d.run ~= nil)
  x.runLabel:SetText(d.run and (d.run.leftAt and "THIS RUN · OUTSIDE" or "THIS RUN") or run and "LAST RUN" or "DUNGEON RUNS")
  if run then
    x.runName:SetText(run.name)
    x.runLine:SetText(runLine(run, t))
  else
    x.runName:SetText("Not in a dungeon")
    x.runLine:SetText("A run starts by itself when you enter one.")
  end

  local on, want = combatLogging(), settings().combatLog
  local dot = on and C.success or C.muted
  x.dot:SetColorTexture(dot[1], dot[2], dot[3], 1)
  x.log:SetText(on and "Combat log is on" or (want and "Combat log starts in dungeons" or "Combat log is off in dungeons"))
  x.logAction:SetText(want and "Turn off" or "Turn on")
end

local function fillRuns()
  local r, d, t = frame.r, db(), now()
  local list = {}
  if d.run then list[1] = d.run end
  for _, run in ipairs(runs()) do list[#list + 1] = run end
  r.title:SetText("Dungeon runs")
  local total, xp, secs = 0, 0, 0
  for _, run in ipairs(runs()) do
    total = total + 1
    xp = xp + (run.xp or 0)
    secs = secs + ((run.ended or t) - run.started)
  end
  local rate = ns.Rate(xp, secs)
  r.sub:SetText(total == 0 and "None finished yet" or string.format("%d finished  ·  %s in dungeons%s", total, ns.Duration(secs),
    rate and ("  ·  " .. ns.Num(rate) .. " XP/h") or ""))
  show(r.empty, #list == 0)
  show(r.scroll, #list > 0)
  for _, row in ipairs(r.rows) do row:Hide() end
  r.child:SetHeight(math.max(RUN_HEIGHT, #list * RUN_HEIGHT))
  for i, run in ipairs(list) do
    r.rows[i] = r.rows[i] or makeRunRow(r.child, i)
    local row = r.rows[i]
    local live = run == d.run
    row.name:SetText(run.name or "Dungeon")
    row.when:SetText(live and (hex(C.accent) .. "NOW|r") or (safe(date, "%b %d, %H:%M", run.started) or ""))
    row.line:SetText(runLine(run, t))
    row.details:SetText(runDetails(run))
    row.run = run
    show(row.mark, live)
    row:Show()
  end
  if r.scroll.place then r.scroll.place() end
end

-- How old something is: "3h old", "2 days old".
local function age(t)
  local secs = math.max(0, now() - (t or 0))
  if secs < 3600 then return math.floor(secs / 60) .. " min old" end
  if secs < 86400 then return math.floor(secs / 3600) .. "h old" end
  return math.floor(secs / 86400) .. " days old"
end

local function fillStats()
  local st, s, c, t, r = frame.st, session(), char(), now(), reading()
  local lines = {}
  local function head(label) lines[#lines + 1] = { head = label } end
  local function row(left, right, color, rightColor) lines[#lines + 1] = { left = left, right = right, color = color, rightColor = rightColor } end
  local function note(left) lines[#lines + 1] = { left = left, note = true } end
  local done = runs()

  -- Leveling
  head("LEVELING")
  local cur = c.levels[r.level]
  row("Level " .. r.level, cur and (ns.Duration(cur.played or 0) .. " played at this level") or "–")
  local target = math.min(60, (math.floor(r.level / 10) + 1) * 10)
  local plan = r.max > 0 and ns.LevelPlan(c.levels, r.level, target, ns.PlayedPerDay(c.days, t)) or nil
  if plan then
    row("Average level", ns.Duration(plan.average) .. " played (" .. plan.measured .. (plan.measured == 1 and " level)" or " levels)"))
    local when = plan.days and ("  ·  around " .. (safe(date, "%a %d %b", t + plan.days * 86400) or "")) or ""
    row("Level " .. target, "about " .. ns.Duration(plan.played) .. " played" .. when)
  else
    note("Level once with Snitchbot on to see how long levels take.")
  end
  local recent = {}
  for level, l in pairs(c.levels) do if l.ended and not l.partial then recent[#recent + 1] = level end end
  table.sort(recent, function(a, b) return a > b end)
  for i, level in ipairs(recent) do
    if i > 5 then break end
    row("Level " .. level, ns.Duration(c.levels[level].played or 0) .. "  ·  " .. (safe(date, "%b %d", c.levels[level].ended) or ""), C.muted)
  end

  -- XP and gold this session
  local sources = ns.XPSources(s.xp, s.xpBy)
  if #sources > 0 then
    head("XP THIS SESSION")
    for _, src in ipairs(sources) do
      row(src.label, string.format("%s  ·  %d%%", ns.Num(src.xp), math.floor(src.xp * 100 / math.max(1, s.xp) + 0.5)))
    end
  end
  head("GOLD THIS SESSION")
  local any = false
  for _, src in ipairs(ns.GOLD_SOURCES) do
    local n = (s.gold or {})[src.key]
    if n and n ~= 0 then
      any = true
      row(src.label, (n > 0 and "+" or "") .. ns.Money(n), nil, n > 0 and C.success or C.danger)
    end
  end
  if not any then note("Nothing yet.") end
  row("Your loot is worth", (s.value or 0) > 0 and ns.Money(s.value) or "–")
  local prices = db().prices
  if type(prices) == "table" and prices.house then
    note("Auction prices from " .. prices.house .. ", " .. age(prices.at) .. ". Vendor price for the rest.")
  else
    note("Vendor prices. Paste auction prices in Settings for a truer value.")
  end

  -- Reputation this session
  local reps = {}
  for faction, n in pairs(s.rep or {}) do reps[#reps + 1] = { faction = faction, n = n } end
  if #reps > 0 then
    table.sort(reps, function(a, b) return a.n > b.n end)
    head("REPUTATION THIS SESSION")
    for _, x in ipairs(reps) do row(x.faction, (x.n > 0 and "+" or "") .. ns.Num(x.n)) end
  end

  -- Personal bests
  local bests, order = ns.Bests(done)
  if #order > 0 then
    head("PERSONAL BESTS")
    for _, key in ipairs(order) do
      local b = bests[key]
      local parts = {}
      if b.fastest then parts[#parts + 1] = ns.Duration(b.fastest.ended - b.fastest.started) end
      if b.rate then parts[#parts + 1] = ns.Num(b.rate) .. " XP/h" end
      row(b.name or "Dungeon", #parts > 0 and table.concat(parts, "  ·  ") or "–")
      note(string.format("%d %s%s", b.runs, b.runs == 1 and "run" or "runs", b.bosses > 0 and ("  ·  fastest with all " .. b.bosses .. " bosses") or ""))
    end
  end

  -- Who you run with
  local people = ns.GroupHistory(done)
  if #people > 0 then
    head("RAN WITH")
    for i, g in ipairs(people) do
      if i > 10 then break end
      row(g.name .. " (" .. g.class .. ")", g.runs .. (g.runs == 1 and " run" or " runs"))
    end
  end

  -- What bosses dropped
  local loot = ns.BossLoot(done)
  local shown = 0
  for _, b in ipairs(loot) do
    if #b.items > 0 and shown < 8 then
      if shown == 0 then head("BOSS LOOT") end
      shown = shown + 1
      row(b.boss, b.kills .. (b.kills == 1 and " kill" or " kills"), C.text)
      for i, item in ipairs(b.items) do
        if i > 3 then break end
        row("   " .. (QUALITY_HEX[item.q] or "") .. item.name .. "|r", item.n > 1 and ("x" .. item.n) or "")
      end
    end
  end

  st.sub:SetText(string.format("%s  ·  %d runs", me(), #done))
  for _, x in ipairs(st.rows) do x:Hide() end
  st.child:SetHeight(math.max(LINE, #lines * LINE))
  for i, line in ipairs(lines) do
    st.rows[i] = st.rows[i] or statRow(st.child, i)
    local x = st.rows[i]
    if line.head then
      setFont(x.left, 11, "semibold")
      x.left:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
      x.left:SetText(line.head)
      x.right:SetText("")
    else
      setFont(x.left, line.note and 11 or 12, "regular")
      local lc = line.color or (line.note and C.muted or C.dim)
      x.left:SetTextColor(lc[1], lc[2], lc[3])
      x.left:SetText(line.left)
      local rc = line.rightColor or C.text
      x.right:SetTextColor(rc[1], rc[2], rc[3])
      x.right:SetText(line.right or "")
    end
    x:Show()
  end
  if st.scroll.place then st.scroll.place() end
end

local function fillSettings()
  for _, b in ipairs(toggles) do b.sync() end
  local p = db().prices
  if frame.prices then
    frame.prices:SetText(type(p) == "table" and p.house
      and string.format("Prices: %s, %s items, %s.", p.house, ns.Num(p.count or 0), age(p.at))
      or "No auction prices yet: loot is valued at what a vendor pays.")
  end
end

update = function()
  if not frame or not frame:IsShown() then return end
  local tab = settings().tab
  if tab == "raid" then refresh()
  elseif tab == "xp" then fillXP()
  elseif tab == "runs" then fillRuns()
  elseif tab == "stats" then fillStats()
  elseif tab == "settings" then fillSettings() end
end

-- ---- Events and slash commands

local events = CreateFrame("Frame", "SnitchbotEvents")
local pending = false
local function soon()
  -- Bag events come in bursts: redraw once, a moment later.
  if pending then return end
  pending = true
  if C_Timer and C_Timer.After then C_Timer.After(0.3, function() pending = false; refresh() end) else pending = false; refresh() end
end

events:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    makeFrame()
    xpNow = reading()
    session(true)
    lastMoney = money()
    lastTick = now()
    local level = reading().level
    if level > 0 and not char().levels[level] then char().levels[level] = { started = now(), played = 0, partial = true } end
    if hooksecurefunc and RepairAllItems then pcall(hooksecurefunc, "RepairAllItems", function() goldCtx.repairAt = now() end) end
    cleanLoot()
    ns.MergeRuns(runs(), AWAY)
    if C_Timer and C_Timer.NewTicker then
      -- Keeps the run's "last seen" fresh while you stand still.
      safe(C_Timer.NewTicker, 30, function()
        -- Also ends a corpse run that went on too long, and starts the combat log if it didn't take.
        checkInstance(false)
        session()
        tick()
        update()
      end)
    end
    if settings().open then frame:Show() end
    local list = db().lists[me()]
    if list then
      local _, short = ns.Progress(list, count)
      if short > 0 and not settings().open then
        say(string.format("%d raid items short for %s. Click the Snitchbot minimap button to see them.", short, ns.RaidLabel(list)))
      end
    end
  elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE" then
    local isLogin, isReload = ...
    if event == "PLAYER_ENTERING_WORLD" and isLogin then db().startedLog = nil end -- logging out turns the log off
    checkInstance(event == "PLAYER_ENTERING_WORLD" and (isLogin or isReload))
    update()
  elseif event == "PLAYER_XP_UPDATE" then
    onXP()
  elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
    onKill((...))
  elseif event == "PLAYER_DEAD" then
    local run = db().run
    if run then run.deaths = (run.deaths or 0) + 1 end
  elseif event == "ENCOUNTER_START" or event == "ENCOUNTER_END" then
    if event == "ENCOUNTER_START" then noteCopy("boss1") end
    onEncounter(event, ...)
  elseif event == "UNIT_HEALTH" or event == "NAME_PLATE_UNIT_REMOVED" then
    onUnitDeath((...))
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    noteCopy((...))
  elseif event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" then
    noteCopy(event == "PLAYER_TARGET_CHANGED" and "target" or "mouseover")
  elseif event == "CHAT_MSG_LOOT" then
    local msg, who, _, _, who2 = ...
    onLoot(msg, (who and who ~= "") and who or who2)
  elseif event == "CHAT_MSG_SYSTEM" then
    local run, msg = db().run, tostring((...) or "")
    local reset = ns.KillPattern(INSTANCE_RESET_SUCCESS or "%s has been reset.")
    local name = msg:match(reset)
    local same = name and run and (name == run.name or name:find(run.name, 1, true) or run.name:find(name, 1, true))
    if run and run.leftAt and same then endRun(true) end
    tally("xpBy", "explore", ns.ExploreXP(msg, ERR_ZONE_EXPLORED_XP))
  elseif event == "PLAYER_MONEY" then
    onMoney()
  elseif event == "GROUP_ROSTER_UPDATE" then
    noteGroup(db().run)
  elseif event == "PLAYER_LEVEL_UP" then
    onLevelUp((...))
  elseif event == "QUEST_TURNED_IN" then
    local _, xp = ...
    goldCtx.questAt = now()
    tally("xpBy", "quests", tonumber(xp))
  elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
    local faction, n = ns.ParseRep((...), FACTION_STANDING_INCREASED, FACTION_STANDING_DECREASED)
    tally("rep", faction, n)
  elseif OPENS[event] then
    setOpen(OPENS[event], true)
  elseif CLOSES[event] then
    setOpen(CLOSES[event], false)
  elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
    local kind = interaction((...))
    if kind then setOpen(kind, event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW") end
  elseif event == "PLAYER_LOGOUT" then
    tick()
  else
    soon()
  end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED", "GET_ITEM_INFO_RECEIVED",
  "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_UNGHOST", "PLAYER_ALIVE", "PLAYER_XP_UPDATE",
  "CHAT_MSG_COMBAT_XP_GAIN", "PLAYER_DEAD", "ENCOUNTER_START", "ENCOUNTER_END", "CHAT_MSG_LOOT", "PLAYER_MONEY",
  "GROUP_ROSTER_UPDATE", "CHAT_MSG_SYSTEM", "PLAYER_LEVEL_UP", "QUEST_TURNED_IN", "CHAT_MSG_COMBAT_FACTION_CHANGE",
  "MERCHANT_SHOW", "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
  "TRAINER_SHOW", "TRAINER_CLOSED", "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "TRADE_SHOW", "TRADE_CLOSED",
  "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "PLAYER_LOGOUT",
  "UNIT_HEALTH", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT" }) do
  pcall(events.RegisterEvent, events, e)
end

-- /sb still opens and closes the window; the rest are shortcuts to tabs.
SLASH_SNITCHBOT1 = "/sb"
SLASH_SNITCHBOT2 = "/snitchbot"
SlashCmdList.SNITCHBOT = function(msg)
  local cmd = tostring(msg or ""):lower():match("^%s*(%S*)")
  if not frame then makeFrame() end
  if cmd == "paste" or cmd == "import" then
    openPaste()
  elseif cmd == "probe" then
    probe()
  elseif cmd == "prices" then
    openPaste("prices")
  elseif cmd == "check" or cmd == "buffs" then
    buffCheck()
  elseif cmd == "export" then
    exportCode()
  elseif cmd == "xp" or cmd == "runs" or cmd == "stats" or cmd == "settings" or cmd == "raid" then
    frame:Show()
    selectTab(cmd)
  else
    SnitchbotToggle()
  end
end
