--[[ Snitchbot: your guild's raid shopping list in game.
  One window with tabs: Raid list, XP, Runs, Settings. Open it with the
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

-- ---- Look: a night-blue flat window, hairlines, one gold accent, Inter.

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local FONT = {
  regular = MEDIA .. "Fonts\\Inter-Regular.ttf",
  medium = MEDIA .. "Fonts\\Inter-Medium.ttf",
  semibold = MEDIA .. "Fonts\\Inter-SemiBold.ttf",
}

local C = {
  ground = { 0.095, 0.115, 0.178, 0.97 },
  header = { 0.072, 0.088, 0.14, 1 },
  footer = { 0.08, 0.097, 0.151, 1 },
  well = { 0.055, 0.068, 0.11, 1 },
  shadow = { 0, 0, 0.02, 0.45 },
  text = { 0.967, 0.974, 0.991, 1 },
  dim = { 0.765, 0.793, 0.868, 1 },
  muted = { 0.606, 0.637, 0.726, 1 },
  accent = { 0.9, 0.73, 0.4, 1 },
  onAccent = { 0.04, 0.05, 0.08, 1 },
  success = { 0.42, 0.85, 0.6, 1 },
  danger = { 0.96, 0.45, 0.45, 1 },
  item = { 0.78, 0.68, 1, 1 },
  border = { 1, 1, 1, 0.14 },
  line = { 1, 1, 1, 0.1 },
  hover = { 1, 1, 1, 0.07 },
  track = { 1, 1, 1, 0.1 },
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

-- Inter when the game takes it, else the game's own font.
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

-- Flat buttons: gold for the main action, an outline for the rest.
local function button(parent, label, primary, width)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width or 120, 26)
  local rest = primary and C.accent or { 1, 1, 1, 0.04 }
  local lit = primary and { 0.96, 0.8, 0.48, 1 } or { 1, 1, 1, 0.1 }
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

-- A small gold diamond, the mark in front of the window's title.
local function mark(parent)
  local t = fill(parent, C.accent, "ARTWORK")
  t:SetSize(7, 7)
  safe(t.SetRotation, t, math.rad(45))
  return t
end

-- The window: ground, hairline, soft shadow, and a header you drag it by.
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
  header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
  mark(header):SetPoint("LEFT", PAD - 1, 0)
  f.title = text(header, 13, "semibold", C.text)
  f.title:SetPoint("LEFT", PAD + 14, 0)
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
  local thumb = fill(sf, { 1, 1, 1, 0.22 }, "OVERLAY")
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
  paste:SetPoint("CENTER", 0, 60)
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
    local list, why = ns.ParseShop(paste.edit:GetText())
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
local function openPaste()
  if not paste then makePaste() end
  paste.title:SetText("Paste your raid list")
  paste.hint:SetText("On auction.snitchbot.app, open Raid list and press Copy for the addon. Then click the box below and press Ctrl+V (Cmd+V on a Mac).")
  paste.ok:Show()
  paste.edit:SetScript("OnTextChanged", nil)
  paste.edit:SetText("")
  paste:Show()
  paste.edit:SetFocus()
end

local function showCopy(title, value)
  if not paste then makePaste() end
  paste.title:SetText(title)
  paste.hint:SetText("Press Ctrl+C (Cmd+C on a Mac) to copy it, then paste it to Snitchbot.")
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

local function combatLogging() return safe(LoggingCombat) and true or false end

local function startCombatLog()
  if not settings().combatLog then return end
  if type(LoggingCombat) ~= "function" then return say("This client can't start the combat log from an addon. Type /combatlog instead.") end
  if combatLogging() then return end
  -- Advanced logging adds positions and health: what Warcraft Logs reads.
  if C_CVar and C_CVar.SetCVar then safe(C_CVar.SetCVar, "advancedCombatLogging", "1") else safe(SetCVar, "advancedCombatLogging", "1") end
  safe(LoggingCombat, true)
  db().startedLog = true
  local run = db().run
  if combatLogging() then
    say("Combat log on for this dungeon. It's saved in the game's Logs folder.")
  elseif run and not run.logFailed then
    run.logFailed = true -- said once; the 30-second check keeps trying
    say("Couldn't start the combat log yet. Snitchbot keeps trying, or type /combatlog.")
  end
end

local function stopCombatLog()
  local d = db()
  if not d.startedLog then return end
  d.startedLog = nil
  if combatLogging() then safe(LoggingCombat, false); say("Combat log off.") end
end

local function setCombatLog(on)
  settings().combatLog = on
  if on and db().run then startCombatLog() elseif not on then stopCombatLog() end
end

-- ---- Runs

-- A run you left ends now; one left alone (logged out, gave up) ended when last seen.
local function endRun(stale)
  local d = db()
  local run = d.run
  if not run then return end
  d.run = nil
  run.ended = stale and run.lastSeen or now()
  run.lastSeen = nil
  local list = runs()
  table.insert(list, 1, run)
  while #list > 100 do table.remove(list) end
  say(ns.RunSummary(run, now()))
  stopCombatLog()
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

-- How long you can be outside after a death (released, revived at the door) before the run ends.
local CORPSE_RUN = 15 * 60

local function checkInstance(atLogin)
  local d = db()
  local inside = instance()
  -- After a logout of more than 15 minutes, the run is over.
  if atLogin and d.run and not ns.CanResume(d.run, now(), nil, 900) then endRun(true) end
  local run = d.run
  if run and inside and runKey(run) ~= inside.key then
    endRun() -- a different dungeon
  elseif run and not inside then
    -- Leaving alive ends the run. After a death you release, run back, and may be
    -- revived at the door outside: that's still the run, for a while.
    local ghost = safe(UnitIsDeadOrGhost, "player")
    if not ghost then
      if not run.diedAt then endRun()
      elseif now() - run.diedAt >= CORPSE_RUN then endRun(true) end -- ends when last seen inside
    end
  end
  if not inside then return end
  if not d.run then
    d.run = {
      key = inside.key, name = inside.name, kind = inside.kind, difficulty = inside.difficulty,
      character = me(), level = reading().level, started = now(), kills = 0, xp = 0, deaths = 0, mobs = {},
      bosses = {}, loot = {}, group = {}, moneyStart = money(), money = 0,
    }
    noteGroup(d.run)
    say(string.format("Tracking %s: kills, XP, bosses, loot and gold.", inside.name))
    -- A moment later, so the chat channels are ready after the loading screen.
    if C_Timer and C_Timer.After then C_Timer.After(3, announce) else announce() end
    if settings().openInDungeon and frame then
      frame:Show()
      selectTab("xp")
    end
  end
  d.run.lastSeen = now()
  if not safe(UnitIsDeadOrGhost, "player") then d.run.diedAt = nil end
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

local function onKill(msg)
  local name = ns.ParseKill(msg, KILL)
  if not name then return end
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

local function onEncounter(event, id, name, _, _, success)
  local run = db().run
  if not run then return end
  run.bosses = run.bosses or {}
  if event == "ENCOUNTER_START" then
    run.pull = { id = id, name = name, started = now() }
  else
    local pull = run.pull and run.pull.id == id and run.pull or { id = id, name = name, started = now() }
    run.pull = nil
    run.bosses[#run.bosses + 1] = { id = id, name = name or pull.name, seconds = now() - pull.started, kill = success == 1 or success == true }
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

local function onLoot(msg, who)
  local run = db().run
  if not run then return end
  local l = ns.ParseLootLine(msg, LOOT)
  if not l or (l.quality and l.quality < 2) then return end
  local quality = l.quality
  if not quality then
    quality = select(3, safe(C_Item and C_Item.GetItemInfo or GetItemInfo, l.id))
    if quality and quality < 2 then return end
  end
  run.loot = run.loot or {}
  if #run.loot < 60 then
    local name = l.self and me() or looter(run, (who and who ~= "") and who or l.who)
    run.loot[#run.loot + 1] = { id = l.id, name = l.name, q = quality or 2, n = l.count, who = name or me() }
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

local function onMoney()
  local run, m = db().run, money()
  if run and run.moneyStart then run.money = m - run.moneyStart end
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

-- ---- The window: one window, four tabs, everything a click away.

local TABS = {
  { key = "raid", label = "Raid list" },
  { key = "xp", label = "XP" },
  { key = "runs", label = "Runs" },
  { key = "settings", label = "Settings" },
}
local TOP = 66 -- header and tab bar
local HEIGHT = 470
local panes, tabButtons = {}, {}

-- A label on the left and a value on the right, at y in pane.
local function stat(parent, y, label)
  local l = text(parent, 12, "regular", C.muted)
  l:SetPoint("TOPLEFT", PAD, y)
  l:SetText(label)
  local v = text(parent, 12, "medium", C.text)
  v:SetPoint("TOPRIGHT", -PAD, y)
  v:SetJustifyH("RIGHT")
  return v
end

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
  frame.who:SetPoint("RIGHT", -PAD - 96, 0)
  frame.sub = text(p, 12, "regular", C.muted)
  frame.sub:SetPoint("TOPLEFT", PAD, -36)
  frame.sub:SetPoint("RIGHT", -PAD, 0)
  frame.status = text(p, 12, "medium", C.dim)
  frame.status:SetPoint("TOPLEFT", PAD, -54)
  frame.status:SetPoint("RIGHT", -PAD, 0)
  frame.newList = smallButton(p, "New list", 84)
  frame.newList:SetPoint("TOPRIGHT", -PAD, -12)
  frame.newList:SetScript("OnClick", openPaste)
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
  frame.empty:SetPoint("TOPLEFT", PAD, -20)
  frame.empty:SetPoint("RIGHT", -PAD, 0)
  safe(frame.empty.SetWordWrap, frame.empty, true)
  frame.empty:SetText("No raid list yet.\n\nOn auction.snitchbot.app, open Raid list and press Copy for the addon. Then paste it here.")
  frame.emptyButton = button(p, "Paste a list", true, 130)
  frame.emptyButton:SetPoint("TOPLEFT", frame.empty, "BOTTOMLEFT", 0, -18)
  frame.emptyButton:SetScript("OnClick", openPaste)
end

local XPW = WIDTH - 2 * PAD

local function makeXPPane(p)
  local x = {}
  frame.x = x
  x.level = text(p, 16, "semibold", C.text)
  x.level:SetPoint("TOPLEFT", PAD, -14)
  x.pct = text(p, 12, "medium", C.dim)
  x.pct:SetPoint("TOPRIGHT", -PAD, -17)
  x.pct:SetJustifyH("RIGHT")
  local track = fill(p, C.track, "ARTWORK")
  track:SetHeight(4)
  track:SetPoint("TOPLEFT", PAD, -40)
  track:SetWidth(XPW)
  x.rested = fill(p, { 0.47, 0.6, 1, 0.45 }, "ARTWORK", 1)
  x.rested:SetHeight(4)
  x.rested:SetPoint("LEFT", track, "LEFT")
  x.bar = fill(p, C.accent, "OVERLAY")
  x.bar:SetHeight(4)
  x.bar:SetPoint("LEFT", track, "LEFT")
  x.xp = text(p, 11, "regular", C.muted)
  x.xp:SetPoint("TOPLEFT", PAD, -52)
  x.xp:SetPoint("RIGHT", -PAD, 0)

  divider(p, -74)
  x.rate = stat(p, -88, "XP per hour")
  x.ttl = stat(p, -110, "To next level")
  x.kills = stat(p, -132, "Kills")
  x.gold = stat(p, -154, "Gold")
  x.time = stat(p, -176, "Session")
  local reset = smallButton(p, "Reset session", 104)
  reset:SetPoint("TOPRIGHT", -PAD, -200)
  reset:SetScript("OnClick", function() resetSession(); update() end)
  divider(p, -232)

  x.runLabel = text(p, 11, "semibold", C.muted)
  x.runLabel:SetPoint("TOPLEFT", PAD, -246)
  x.runName = text(p, 14, "semibold", C.text)
  x.runName:SetPoint("TOPLEFT", PAD, -264)
  x.runName:SetPoint("RIGHT", -PAD, 0)
  x.runLine = text(p, 12, "regular", C.dim)
  x.runLine:SetPoint("TOPLEFT", PAD, -284)
  x.runLine:SetPoint("RIGHT", -PAD, 0)
  local all = smallButton(p, "All runs", 84)
  all:SetPoint("TOPLEFT", PAD, -310)
  all:SetScript("OnClick", function() selectTab("runs") end)

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
  pasteB:SetScript("OnClick", openPaste)
  local probeB = button(p, "Probe the game", false, 140)
  probeB:SetPoint("LEFT", pasteB, "RIGHT", 10, 0)
  probeB:SetScript("OnClick", probe)
  local probeHint = text(p, 11, "regular", C.muted)
  probeHint:SetPoint("TOPLEFT", PAD, -276)
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
  local x = PAD - 6
  for _, t in ipairs(TABS) do
    local b = CreateFrame("Button", nil, bar)
    b.label = text(b, 12, "medium", C.muted)
    b.label:SetPoint("CENTER", 0, 1)
    b.label:SetJustifyH("CENTER")
    b.label:SetText(t.label)
    local w = math.max(48, (tonumber(safe(b.label.GetStringWidth, b.label)) or 40) + 20)
    b:SetSize(w, TOP - 34)
    b:SetPoint("BOTTOMLEFT", x, 0)
    x = x + w + 2
    b.line = fill(b, C.accent, "OVERLAY")
    b.line:SetHeight(2)
    b.line:SetPoint("BOTTOMLEFT", 6, 0)
    b.line:SetPoint("BOTTOMRIGHT", -6, 0)
    b:SetScript("OnClick", function() selectTab(t.key) end)
    b:SetScript("OnEnter", function() if settings().tab ~= t.key then b.label:SetTextColor(C.text[1], C.text[2], C.text[3]) end end)
    b:SetScript("OnLeave", function() if settings().tab ~= t.key then b.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end end)
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
  frame:SetPoint("CENTER", 300, 40)
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
    local c = k == key and C.text or C.muted
    b.label:SetTextColor(c[1], c[2], c[3])
    show(b.line, k == key)
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
  x.gold:SetText((earned > 0 and "+" or "") .. ns.Money(earned) .. (goldRate and ("  ·  " .. ns.Money(goldRate) .. "/h") or ""))

  local d = db()
  local run = d.run or runs()[1]
  x.runLabel:SetText(d.run and "THIS RUN" or run and "LAST RUN" or "DUNGEON RUNS")
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

update = function()
  if not frame or not frame:IsShown() then return end
  local tab = settings().tab
  if tab == "raid" then refresh()
  elseif tab == "xp" then fillXP()
  elseif tab == "runs" then fillRuns()
  elseif tab == "settings" then for _, b in ipairs(toggles) do b.sync() end end
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
    cleanLoot()
    if C_Timer and C_Timer.NewTicker then
      -- Keeps the run's "last seen" fresh while you stand still.
      safe(C_Timer.NewTicker, 30, function()
        -- Also ends a corpse run that went on too long, and starts the combat log if it didn't take.
        checkInstance(false)
        session()
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
    checkInstance(event == "PLAYER_ENTERING_WORLD" and (isLogin or isReload))
    update()
  elseif event == "PLAYER_XP_UPDATE" then
    onXP()
  elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
    onKill((...))
  elseif event == "PLAYER_DEAD" then
    local run = db().run
    if run then run.deaths = (run.deaths or 0) + 1; run.diedAt = now() end
  elseif event == "ENCOUNTER_START" or event == "ENCOUNTER_END" then
    onEncounter(event, ...)
  elseif event == "CHAT_MSG_LOOT" then
    local msg, who, _, _, who2 = ...
    onLoot(msg, (who and who ~= "") and who or who2)
  elseif event == "PLAYER_MONEY" then
    onMoney()
  elseif event == "GROUP_ROSTER_UPDATE" then
    noteGroup(db().run)
  else
    soon()
  end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED", "GET_ITEM_INFO_RECEIVED",
  "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_UNGHOST", "PLAYER_ALIVE", "PLAYER_XP_UPDATE",
  "CHAT_MSG_COMBAT_XP_GAIN", "PLAYER_DEAD", "ENCOUNTER_START", "ENCOUNTER_END", "CHAT_MSG_LOOT", "PLAYER_MONEY",
  "GROUP_ROSTER_UPDATE" }) do
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
  elseif cmd == "xp" or cmd == "runs" or cmd == "settings" or cmd == "raid" then
    frame:Show()
    selectTab(cmd)
  else
    SnitchbotToggle()
  end
end
