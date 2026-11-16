--[[ Snitchbot: your guild's raid shopping list in game.
  /sb           show or hide the list
  /sb paste     paste a code from auction.snitchbot.app (Raid list → Copy for the addon)
  /sb probe     a line to send to Snitchbot: which game functions this client has

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
local function window(name, width, height, strata)
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
  if UISpecialFrames then table.insert(UISpecialFrames, name) end
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
local refresh

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
    if frame then frame:Show() end
    refresh()
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

local function makeFrame()
  local listTop, footerHeight = 112, 44
  frame = window("SnitchbotFrame", WIDTH, listTop + ROWS_SHOWN * ROW_HEIGHT + 8 + footerHeight)
  frame:SetPoint("CENTER", 300, 40)
  frame.title:SetText("Raid list")

  -- "+" next to × pastes a new list, like a new tab.
  local add = headerButton(frame.header, "+", 18)
  add:SetPoint("RIGHT", frame.close, "LEFT", 0, 0)
  add:SetScript("OnClick", openPaste)
  add:SetScript("OnEnter", function(self)
    self.label:SetTextColor(C.text[1], C.text[2], C.text[3])
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Paste a new list")
    GameTooltip:Show()
  end)
  add:SetScript("OnLeave", function(self)
    self.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    if GameTooltip then GameTooltip:Hide() end
  end)

  -- Who and what it's for, then where you stand.
  frame.who = text(frame, 16, "semibold", C.text)
  frame.who:SetPoint("TOPLEFT", PAD, -46)
  frame.who:SetPoint("RIGHT", -PAD, 0)
  frame.sub = text(frame, 12, "regular", C.muted)
  frame.sub:SetPoint("TOPLEFT", PAD, -68)
  frame.sub:SetPoint("RIGHT", -PAD, 0)
  frame.status = text(frame, 12, "medium", C.dim)
  frame.status:SetPoint("TOPLEFT", PAD, -86)
  frame.status:SetPoint("RIGHT", -PAD, 0)
  frame.rule = divider(frame, -(listTop - 6))

  local sf, child = scrollArea(frame, ROW_HEIGHT * 2)
  sf:SetPoint("TOPLEFT", PAD - 4, -listTop)
  sf:SetPoint("BOTTOMRIGHT", -(PAD - 4), footerHeight + 4)
  child:SetSize(WIDTH - 2 * (PAD - 4), ROW_HEIGHT)
  frame.scroll, frame.child = sf, child
  rows = {}

  -- Footer: how much of the list is in your bags, as a bar.
  local footer = CreateFrame("Frame", nil, frame)
  footer:SetPoint("BOTTOMLEFT", 1, 1)
  footer:SetPoint("BOTTOMRIGHT", -1, 1)
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
  frame.empty = text(frame, 13, "regular", C.dim)
  frame.empty:SetPoint("TOPLEFT", PAD, -56)
  frame.empty:SetPoint("RIGHT", -PAD, 0)
  safe(frame.empty.SetWordWrap, frame.empty, true)
  frame.empty:SetText("No raid list yet.\n\nOn auction.snitchbot.app, open Raid list and press Copy for the addon. Then paste it here.")
  frame.emptyButton = button(frame, "Paste a list", true, 130)
  frame.emptyButton:SetPoint("TOPLEFT", frame.empty, "BOTTOMLEFT", 0, -18)
  frame.emptyButton:SetScript("OnClick", openPaste)

  frame:SetScript("OnShow", function() refresh() end)
  frame:Hide()
end

local function setBar(done, total)
  local share = total > 0 and done / total or 0
  frame.bar:SetWidth(math.max(0.01, TRACK * share))
  show(frame.bar, share > 0)
  frame.pct:SetText(string.format("%d%%", math.floor(share * 100 + 0.5)))
end

refresh = function()
  if not frame or not frame:IsShown() then return end
  local list = currentList()
  for _, r in ipairs(rows) do r:Hide() end
  local has = list ~= nil
  for _, part in ipairs({ frame.who, frame.sub, frame.status, frame.rule, frame.scroll, frame.footer }) do show(part, has) end
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

-- ---- Events and slash commands

local events = CreateFrame("Frame", "SnitchbotEvents")
local pending = false
local function soon()
  -- Bag events come in bursts: redraw once, a moment later.
  if pending then return end
  pending = true
  if C_Timer and C_Timer.After then C_Timer.After(0.3, function() pending = false; refresh() end) else pending = false; refresh() end
end

events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    makeFrame()
    local list = db().lists[me()]
    if list then
      local _, short = ns.Progress(list, count)
      if short > 0 then say(string.format("%d raid items short for %s. Type /sb to see them.", short, ns.RaidLabel(list))) end
    end
  else
    soon()
  end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED", "GET_ITEM_INFO_RECEIVED" }) do
  pcall(events.RegisterEvent, events, e)
end

SLASH_SNITCHBOT1 = "/sb"
SLASH_SNITCHBOT2 = "/snitchbot"
SlashCmdList.SNITCHBOT = function(msg)
  local cmd = tostring(msg or ""):lower():match("^%s*(%S*)")
  if not frame then makeFrame() end
  if cmd == "paste" or cmd == "import" then
    openPaste()
  elseif cmd == "probe" then
    probe()
  elseif cmd == "help" then
    say("/sb shows your raid list · /sb paste adds a new one · /sb probe makes a line to send to Snitchbot")
  elseif frame:IsShown() then
    frame:Hide()
  else
    frame:Show()
  end
end
