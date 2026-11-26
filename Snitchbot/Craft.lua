--[[ Snitchbot: profession leveling plans, with no UI, so the tests run them.

  A plan is the steps from skill 1 to the cap: which recipe from which skill to
  which, how many crafts on average, and what those crafts use in all. From the
  character's skill now, ns.CraftPlan works out the crafts still to do and a
  shopping list: what you have (bags and bank), what's missing, and what that
  costs at the pasted auction house prices.

  Parts you make along the way (grinding stones) are made from stone: the
  shopping list asks for the stone, minus any stones you already have.
]]
local _, ns = ...
ns = ns or {}

-- Blacksmithing 1-300 for WoW Forever. The route is Wowhead's "Tried & Tested
-- in Forever" guide (version 2, updated 2026-11-04):
-- https://www.wowhead.com/forever/profession-leveling-guides/blacksmithing?guide=3
-- `crafts` is the guide's average; `mats` is what those crafts use in all.
-- `learn`: nil for the trainer, else the plans you buy (item, vendor, where).
local ROUGH_STONE, COARSE_STONE, HEAVY_STONE, SOLID_STONE, DENSE_STONE = 2835, 2836, 2838, 7912, 12365
local COPPER, BRONZE, SILVER, IRON, STEEL, MITHRIL, TRUESILVER, THORIUM, ARCANITE = 2840, 2841, 2842, 3575, 3859, 3860, 6037, 12359, 12360
local AZEROTHIUM = 249726
local R_GRIND, C_GRIND, H_GRIND, S_GRIND, D_GRIND = 3470, 3478, 3486, 7966, 12644
local MEDIUM_LEATHER, THICK_LEATHER, RUGGED_LEATHER = 2319, 4304, 8170
local MAGEWEAVE, GREEN_DYE, STRONG_FLUX = 4338, 2605, 3466
local BLACK_PEARL, SHADOWGEM, STAR_RUBY, LARGE_OPAL, ESSENCE_OF_AIR = 7971, 1210, 7910, 12799, 7082

local MAGNUS = { npc = "Magnus Frostwake", zone = "Western Plaguelands" }
local PEXMIT = { npc = "Pexmit", zone = "Mount Hyjal" }

ns.CRAFT_PLANS = {
  [164] = {
    name = "Blacksmithing",
    max = 300,
    source = "Wowhead: Tried & Tested in Forever",
    tool = 5956, -- Blacksmith Hammer, from a trade supplies vendor
    -- Parts you make: one of the key is made from these.
    makes = {
      [R_GRIND] = { { ROUGH_STONE, 2 } },
      [C_GRIND] = { { COARSE_STONE, 2 } },
      [H_GRIND] = { { HEAVY_STONE, 3 } },
      [S_GRIND] = { { SOLID_STONE, 4 } },
      [D_GRIND] = { { DENSE_STONE, 4 } },
    },
    -- Train the next rank before its cap: rank name and cap.
    ranks = { { "Journeyman", 75, 150 }, { "Expert", 150, 225 }, { "Artisan", 225, 300 } },
    steps = {
      { 1, 30, 2660, "Rough Sharpening Stone", 32, { { ROUGH_STONE, 32 } } },
      { 30, 65, 3320, "Rough Grinding Stone", 42, { { ROUGH_STONE, 84 } } },
      { 65, 75, 2661, "Copper Chain Belt", 10, { { COPPER, 60 } } },
      { 75, 80, 19666, "Silver Skeleton Key", 5, { { SILVER, 5 }, { R_GRIND, 5 } } },
      { 80, 90, 2668, "Rough Bronze Leggings", 10, { { BRONZE, 60 } } },
      { 90, 100, 2666, "Runed Copper Belt", 13, { { COPPER, 130 } } },
      { 100, 105, 2674, "Heavy Sharpening Stone", 5, { { HEAVY_STONE, 5 } } },
      { 105, 110, 2666, "Runed Copper Belt", 10, { { COPPER, 100 } } },
      { 110, 125, 2668, "Rough Bronze Leggings", 15, { { BRONZE, 90 } } },
      { 125, 129, 8768, "Iron Buckle", 6, { { IRON, 6 } } },
      { 129, 140, 9985, "Bronze Warhammer", 11, { { BRONZE, 88 }, { STRONG_FLUX, 11 }, { MEDIUM_LEATHER, 11 } } },
      { 140, 147, 2672, "Patterned Bronze Bracers", 17, { { BRONZE, 85 }, { C_GRIND, 34 } } },
      { 147, 155, 3501, "Green Iron Bracers", 8, { { IRON, 48 }, { GREEN_DYE, 8 } } },
      { 155, 165, 3506, "Green Iron Leggings", 12, { { IRON, 96 }, { H_GRIND, 12 }, { GREEN_DYE, 12 } } },
      { 165, 183, 3501, "Green Iron Bracers", 31, { { IRON, 186 }, { GREEN_DYE, 31 } } },
      { 183, 190, 9928, "Heavy Mithril Gauntlet", 7, { { MITHRIL, 42 }, { MAGEWEAVE, 28 } } },
      { 190, 200, 7223, "Golden Scale Bracers", 16, { { STEEL, 80 }, { H_GRIND, 32 } } },
      { 200, 205, 9928, "Heavy Mithril Gauntlet", 5, { { MITHRIL, 30 }, { MAGEWEAVE, 20 } } },
      { 205, 210, 9931, "Mithril Plate Pants", 5, { { MITHRIL, 60 } } },
      { 210, 215, 9928, "Heavy Mithril Gauntlet", 12, { { MITHRIL, 72 }, { MAGEWEAVE, 48 } } },
      { 215, 225, 9959, "Heavy Mithril Breastplate", 10, { { MITHRIL, 160 } } },
      { 225, 235, 16640, "Dense Weightstone", 15, { { DENSE_STONE, 15 } } },
      { 235, 240, 9961, "Mithril Coif", 12, { { MITHRIL, 120 }, { MAGEWEAVE, 72 } } },
      { 240, 246, 9968, "Heavy Mithril Boots", 17, { { MITHRIL, 238 }, { THICK_LEATHER, 68 } } },
      { 246, 250, 10001, "Big Black Mace", 12, { { MITHRIL, 192 }, { BLACK_PEARL, 12 }, { SHADOWGEM, 48 }, { S_GRIND, 12 }, { THICK_LEATHER, 24 } } },
      { 250, 257, 19669, "Arcanite Skeleton Key", 10, { { ARCANITE, 10 }, { D_GRIND, 10 } } },
      { 257, 270, 10013, "Ebon Shiv", 20, { { MITHRIL, 240 }, { TRUESILVER, 120 }, { STAR_RUBY, 40 }, { S_GRIND, 20 }, { THICK_LEATHER, 40 } },
        { item = 8030, npc = MAGNUS.npc, zone = MAGNUS.zone } },
      { 270, 275, 1252365, "Bold Dirk", 5, { { THORIUM, 150 }, { ESSENCE_OF_AIR, 20 }, { AZEROTHIUM, 50 }, { RUGGED_LEATHER, 20 } },
        { item = 251468, npc = PEXMIT.npc, zone = PEXMIT.zone } },
      { 275, 279, 16969, "Ornate Thorium Handaxe", 4, { { THORIUM, 80 }, { LARGE_OPAL, 8 }, { D_GRIND, 8 }, { RUGGED_LEATHER, 16 } },
        { item = 12819, npc = MAGNUS.npc, zone = MAGNUS.zone } },
      { 279, 300, 1252365, "Bold Dirk", 24, { { THORIUM, 720 }, { ESSENCE_OF_AIR, 96 }, { AZEROTHIUM, 240 }, { RUGGED_LEATHER, 96 } },
        { item = 251468, npc = PEXMIT.npc, zone = PEXMIT.zone } },
    },
  },
}

--- The plan for a profession skill line, or nil.
function ns.CraftPlanFor(skillLine)
  return ns.CRAFT_PLANS[tonumber(skillLine) or -1]
end

--- From `skill` to the plan's cap. Each callback may be nil:
---   have(id) -> how many you have (bags and bank)
---   price(id) -> copper each at the auction house, or nil
---   known(spell) -> true when you already know the recipe
--- Returns {
---   skill, max, done,
---   steps = { { from, to, name, spell, crafts, current, learn } }  (crafts still to do)
---   rows = { { id, need, have, missing, price, cost, made, plans, tool } }
---   cost (copper for everything missing that has a price), unpriced (rows missing with no price),
---   crafts (all crafts left), made (parts to make along the way),
---   rank = { name, at, cap } when the next rank must be trained before the cap you have
--- }
function ns.CraftPlan(plan, skill, have, price, known, cap)
  skill = math.max(1, math.floor(tonumber(skill) or 1))
  have = have or function() return 0 end
  price = price or function() return nil end
  known = known or function() return false end
  local out = { skill = skill, max = plan.max, done = skill >= plan.max, steps = {}, rows = {}, cost = 0, unpriced = 0, crafts = 0, made = 0 }
  local need, order = {}, {}
  local function want(id, n)
    if n <= 0 then return end
    if not need[id] then need[id] = 0; order[#order + 1] = id end
    need[id] = need[id] + n
  end
  local plans, planOrder = {}, {}
  for _, s in ipairs(plan.steps) do
    local from, to, spell, name, crafts, mats, learn = s[1], s[2], s[3], s[4], s[5], s[6], s[7]
    if skill < to then
      local left = crafts
      if skill > from then left = math.ceil(crafts * (to - skill) / (to - from)) end
      out.steps[#out.steps + 1] = { from = from, to = to, name = name, spell = spell, crafts = left, current = skill >= from, learn = learn }
      out.crafts = out.crafts + left
      for _, m in ipairs(mats) do want(m[1], math.ceil(m[2] / crafts * left)) end
      if learn and learn.item and not known(spell) and not plans[learn.item] then
        plans[learn.item] = learn
        planOrder[#planOrder + 1] = learn.item
      end
    end
  end
  if out.done then return out end
  -- Parts you make: the stones you have count first, the rest is made from stone.
  local parts = {}
  for _, id in ipairs(order) do
    local recipe = plan.makes and plan.makes[id]
    if recipe then
      local short = math.max(0, need[id] - (tonumber(have(id)) or 0))
      parts[id] = true
      out.made = out.made + short
      for _, m in ipairs(recipe) do want(m[1], short * m[2]) end
    end
  end
  local function row(id, n, extra)
    local h = tonumber(have(id)) or 0
    local r = { id = id, need = n, have = math.min(h, n), missing = math.max(0, n - h) }
    for k, v in pairs(extra or {}) do r[k] = v end
    if not r.made then
      local p = tonumber(price(id))
      r.price = p
      if r.missing > 0 then
        if p then r.cost = p * r.missing; out.cost = out.cost + r.cost else out.unpriced = out.unpriced + 1 end
      end
    end
    out.rows[#out.rows + 1] = r
  end
  if plan.tool then row(plan.tool, 1, { tool = true }) end
  for _, id in ipairs(planOrder) do row(id, 1, { plans = plans[id] }) end
  for _, id in ipairs(order) do
    if parts[id] then row(id, need[id], { made = true }) else row(id, need[id]) end
  end
  -- The rank to train: your cap is below the skill the next step needs.
  cap = tonumber(cap)
  if cap and cap < plan.max then
    for _, r in ipairs(plan.ranks or {}) do
      if cap <= r[2] then out.rank = { name = r[1], at = r[2], cap = r[3] }; break end
    end
  end
  return out
end
