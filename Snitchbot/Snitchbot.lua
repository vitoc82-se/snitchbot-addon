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

local ROWS_SHOWN = 14
local ROW_HEIGHT = 22
local GREEN, RED, GREY, GOLD = "|cff5fd068", "|cffff6b5b", "|cff9d9d9d", "|cffffd100"

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

local function itemIcon(id)
  return (C_Item and C_Item.GetItemIconByID and safe(C_Item.GetItemIconByID, id)) or safe(GetItemIcon, id)
    or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- The list for this character, else the last one pasted.
local function currentList()
  local d = db()
  return d.lists[me()] or (d.last and d.lists[d.last]) or nil
end

-- ---- Frames

local frame, rows, scroll, paste

local function backdrop(f)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
  end
end

local function button(parent, text, width)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width or 140, 24)
  b:SetText(text)
  return b
end

local refresh

local function makeRow(parent, i)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(330, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(18, 18)
  row.icon:SetPoint("LEFT", 2, 0)
  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.name:SetWidth(215)
  row.name:SetJustifyH("LEFT")
  row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.count:SetPoint("RIGHT", -4, 0)
  row.count:SetJustifyH("RIGHT")
  row:SetScript("OnEnter", function(self)
    if not self.itemId or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    safe(GameTooltip.SetItemByID, GameTooltip, self.itemId)
    if self.bank and self.bank > 0 then GameTooltip:AddLine(string.format("%d in your bank", self.bank), 1, 1, 1) end
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  -- Shift-click puts the item's link in chat, as everywhere in the game.
  row:SetScript("OnClick", function(self)
    if not self.itemId then return end
    local link = select(2, safe(GetItemInfo, self.itemId))
    if link and IsModifiedClick and safe(IsModifiedClick, "CHATLINK") and ChatEdit_InsertLink then safe(ChatEdit_InsertLink, link) end
  end)
  return row
end

local function makePaste()
  paste = CreateFrame("Frame", "SnitchbotPasteFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  paste:SetSize(460, 220)
  paste:SetPoint("CENTER", 0, 60)
  paste:SetFrameStrata("DIALOG")
  backdrop(paste)
  paste.title = paste:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  paste.title:SetPoint("TOP", 0, -18)
  paste.hint = paste:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  paste.hint:SetPoint("TOP", 0, -42)
  paste.hint:SetWidth(400)
  local box = CreateFrame("ScrollFrame", "SnitchbotPasteScroll", paste, "UIPanelScrollFrameTemplate")
  box:SetPoint("TOPLEFT", 22, -66)
  box:SetPoint("BOTTOMRIGHT", -40, 50)
  paste.edit = CreateFrame("EditBox", nil, box)
  paste.edit:SetMultiLine(true)
  paste.edit:SetAutoFocus(false)
  paste.edit:SetMaxLetters(0)
  paste.edit:SetFontObject(ChatFontNormal or GameFontHighlight)
  paste.edit:SetWidth(380)
  paste.edit:SetScript("OnEscapePressed", function() paste:Hide() end)
  box:SetScrollChild(paste.edit)
  paste.ok = button(paste, "Import", 110)
  paste.ok:SetPoint("BOTTOMRIGHT", -20, 16)
  local cancel = button(paste, "Close", 90)
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
  if UISpecialFrames then table.insert(UISpecialFrames, "SnitchbotPasteFrame") end
end

-- Paste mode: an empty box and Import. Copy mode: read-only text to copy.
local function openPaste()
  if not paste then makePaste() end
  paste.title:SetText("Paste your raid list")
  paste.hint:SetText("On auction.snitchbot.app → Raid list, press Copy for the addon. Then click below and press Ctrl+V (Cmd+V on Mac).")
  paste.ok:Show()
  paste.edit:SetScript("OnTextChanged", nil)
  paste.edit:SetText("")
  paste:Show()
  paste.edit:SetFocus()
end

local function showCopy(title, text)
  if not paste then makePaste() end
  paste.title:SetText(title)
  paste.hint:SetText("Press Ctrl+C (Cmd+C on Mac) to copy it, then paste it to Snitchbot.")
  paste.ok:Hide()
  paste.edit:SetText(text)
  paste.edit:SetScript("OnTextChanged", function(self, userInput)
    if userInput then self:SetText(text); self:HighlightText() end
  end)
  paste:Show()
  paste.edit:SetFocus()
  paste.edit:HighlightText()
end

local function makeFrame()
  frame = CreateFrame("Frame", "SnitchbotFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(400, 150 + ROWS_SHOWN * ROW_HEIGHT)
  frame:SetPoint("CENTER", 260, 0)
  frame:SetFrameStrata("HIGH")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  backdrop(frame)

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.title:SetPoint("TOP", 0, -18)
  frame.title:SetText("Snitchbot raid list")
  frame.sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.sub:SetPoint("TOP", 0, -40)
  frame.sub:SetWidth(350)
  frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.status:SetPoint("TOPLEFT", 26, -62)
  frame.status:SetWidth(350)
  frame.status:SetJustifyH("LEFT")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  scroll = CreateFrame("ScrollFrame", "SnitchbotListScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 24, -84)
  scroll:SetPoint("BOTTOMRIGHT", -42, 52)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(330, ROW_HEIGHT)
  scroll:SetScrollChild(child)
  frame.child = child
  rows = {}

  local pasteButton = button(frame, "Paste a new list", 150)
  pasteButton:SetPoint("BOTTOMLEFT", 20, 16)
  pasteButton:SetScript("OnClick", openPaste)
  frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.empty:SetPoint("TOPLEFT", 26, -90)
  frame.empty:SetWidth(340)
  frame.empty:SetJustifyH("LEFT")
  frame.empty:SetText("No raid list yet.\n\nOn auction.snitchbot.app, open Raid list, press Copy for the addon, then press Paste a new list here.")

  frame:SetScript("OnShow", function() refresh() end)
  if UISpecialFrames then table.insert(UISpecialFrames, "SnitchbotFrame") end
  frame:Hide()
end

refresh = function()
  if not frame or not frame:IsShown() then return end
  local list = currentList()
  for _, r in ipairs(rows) do r:Hide() end
  if not list then
    frame.sub:SetText("")
    frame.status:SetText("")
    frame.empty:Show()
    return
  end
  frame.empty:Hide()
  local mine = list.character == "" or list.character == me()
  frame.sub:SetText(string.format("%s · %s%s", list.character ~= "" and list.character or me(), ns.RaidLabel(list),
    list.guild ~= "" and (" · " .. list.guild) or ""))
  local progress, short = ns.Progress(list, count)
  if not mine then
    frame.status:SetText(GREY .. "This list is for " .. list.character .. ". Counts are this character's bags.|r")
  elseif short == 0 then
    frame.status:SetText(GREEN .. "You have everything for one raid night.|r")
  else
    frame.status:SetText(string.format("%s%d of %d items short.|r", RED, short, #progress))
  end
  frame.child:SetHeight(math.max(ROW_HEIGHT, #progress * ROW_HEIGHT))
  for i, p in ipairs(progress) do
    rows[i] = rows[i] or makeRow(frame.child, i)
    local r = rows[i]
    r.itemId, r.bank = p.id, p.total - p.bags
    r.icon:SetTexture(itemIcon(p.id))
    r.name:SetText(itemName(p.id) or (GREY .. "Item " .. p.id .. "|r"))
    local colour = p.missing > 0 and RED or GREEN
    local bank = p.total > p.bags and (GREY .. string.format(" (%d bank)", p.total - p.bags) .. "|r") or ""
    r.count:SetText(string.format("%s%d/%d|r%s", colour, math.min(p.total, p.need), p.need, bank))
    r:Show()
  end
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
