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
-- `learn`: nil for the trainer, else the plans you buy (item, vendor, where),
-- with the Horde vendor in `horde` when the two sides buy from different ones;
-- `trainer = true` (no item) for a recipe a special trainer teaches.
-- `out`: the part a step makes that later steps use; `note`: a tip for the step.
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
    icon = "Interface\\Icons\\Trade_BlackSmithing",
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
      { 30, 65, 3320, "Rough Grinding Stone", 42, { { ROUGH_STONE, 84 } }, out = R_GRIND },
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

  -- Cooking 1-300 for WoW Forever, from Wowhead's "Tried & Tested in Forever"
  -- guide (version 2, updated 2026-11-03):
  -- https://www.wowhead.com/forever/profession-leveling-guides/cooking
  -- A recipe sold on both sides has its Horde vendor in `horde`.
  [185] = {
    name = "Cooking",
    max = 300,
    source = "Wowhead: Tried & Tested in Forever",
    icon = "Interface\\Icons\\INV_Misc_Food_15",
    learnWord = "Recipe",
    ranks = {
      { "Journeyman", 75, 150 },
      { "Expert", 150, 225, how = "Expert: buy The Expert Cookbook from Shandrina (Ashenvale) or Wulan (Desolace). Needs skill 125." },
      { "Artisan", 225, 300, how = "Artisan: the quest Clamlette Surprise from Dirge Quikcleave in Gadgetzan, Tanaris. Needs level 35." },
    },
    steps = {
      { 1, 50, 7751, "Brilliant Smallfish", 49, { { 6291, 49 } } },
      { 50, 100, 7753, "Longjaw Mud Snapper", 51, { { 6289, 51 } },
        { item = 6328, npc = "Tharynn Bouden", zone = "Elwynn Forest", horde = { npc = "Naal Mistrunner", zone = "Thunder Bluff" } } },
      { 100, 175, 7755, "Bristle Whisker Catfish", 120, { { 6308, 120 } },
        { item = 6330, npc = "Kilxx", zone = "The Barrens" } },
      { 175, 225, 20916, "Mithril Headed Trout", 51, { { 8365, 51 } },
        { item = 17062, npc = "Kelsey Yance", zone = "Stranglethorn Vale" } },
      { 225, 275, 18238, "Spotted Yellowtail", 51, { { 4603, 51 } },
        { item = 13939, npc = "Gikkix", zone = "Tanaris" } },
      { 275, 300, 18246, "Mightfish Steak", 25, { { 13893, 25 }, { 2692, 25 }, { 3713, 25 } },
        { item = 13948, npc = "Vivianna", zone = "Feralas", horde = { npc = "Sheendra Tallgrass", zone = "Feralas" } } },
    },
  },

  -- The plans below are Wowhead's "Tried & Tested in Forever" guides too
  -- (https://www.wowhead.com/forever/profession-leveling-guides/<name>),
  -- as of 2026-11-28.
  [129] = {
    name = "First Aid",
    max = 300,
    icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    learnWord = "Manual",
    ranks = {
      { "Journeyman", 75, 150 },
      { "Expert", 150, 225, how = "Expert: buy Expert First Aid - Under Wraps from Deneb Walker (Arathi Highlands) or Balai Lok'Wein (Dustwallow Marsh). Needs skill 125." },
      { "Artisan", 225, 300, how = "Artisan: the quest Triage from Doctor Gustaf VanHowzen (Theramore) or Doctor Gregory Victor (Hammerfall). Needs level 35." },
    },
    steps = {
      { 1, 40, 3275, "Linen Bandage", 41, { { 2589, 41 } } },
      { 40, 80, 3276, "Heavy Linen Bandage", 55, { { 2589, 110 } } },
      { 80, 115, 3277, "Wool Bandage", 48, { { 2592, 48 } } },
      { 115, 150, 3278, "Heavy Wool Bandage", 48, { { 2592, 96 } } },
      { 150, 180, 7928, "Silk Bandage", 41, { { 4306, 41 } } },
      { 180, 210, 7929, "Heavy Silk Bandage", 41, { { 4306, 82 } },
        { item = 16112, npc = "Deneb Walker", zone = "Arathi Highlands", horde = { npc = "Balai Lok'Wein", zone = "Dustwallow Marsh" } } },
      { 210, 240, 10840, "Mageweave Bandage", 41, { { 4338, 41 } },
        { item = 16113, npc = "Deneb Walker", zone = "Arathi Highlands", horde = { npc = "Balai Lok'Wein", zone = "Dustwallow Marsh" } } },
      { 240, 260, 10841, "Heavy Mageweave Bandage", 24, { { 4338, 48 } },
        { trainer = true, npc = "Doctor Gustaf VanHowzen", zone = "Dustwallow Marsh", horde = { npc = "Doctor Gregory Victor", zone = "Arathi Highlands" } }, note = "As in Classic: not yet checked in Forever." },
      { 260, 290, 18629, "Runecloth Bandage", 40, { { 14047, 40 } },
        { trainer = true, npc = "Doctor Gustaf VanHowzen", zone = "Dustwallow Marsh", horde = { npc = "Doctor Gregory Victor", zone = "Arathi Highlands" } }, note = "As in Classic: not yet checked in Forever." },
      { 290, 300, 18630, "Heavy Runecloth Bandage", 11, { { 14047, 22 } },
        { trainer = true, npc = "Doctor Gustaf VanHowzen", zone = "Dustwallow Marsh", horde = { npc = "Doctor Gregory Victor", zone = "Arathi Highlands" } }, note = "As in Classic: not yet checked in Forever." },
    },
  },

  [171] = {
    name = "Alchemy",
    max = 300,
    icon = "Interface\\Icons\\Trade_Alchemy",
    learnWord = "Recipe",
    ranks = { { "Journeyman", 75, 150 }, { "Expert", 150, 225 }, { "Artisan", 225, 300 } },
    steps = {
      { 1, 12, 1245250, "Elixir of Minor Force", 11, { { 765, 11 }, { 3371, 11 } } },
      { 12, 55, 7183, "Elixir of Minor Defense", 43, { { 765, 43 }, { 2447, 43 }, { 3371, 43 } } },
      { 55, 65, 2331, "Minor Mana Potion", 10, { { 785, 10 }, { 2447, 10 }, { 3371, 10 } } },
      { 65, 90, 2334, "Elixir of Minor Fortitude", 26, { { 2449, 52 }, { 2447, 26 }, { 3371, 26 } } },
      { 90, 120, 3171, "Elixir of Wisdom", 30, { { 785, 30 }, { 2450, 60 }, { 3371, 30 } } },
      { 120, 160, 3173, "Lesser Mana Potion", 43, { { 785, 43 }, { 3820, 43 }, { 3371, 43 } } },
      { 160, 195, 3452, "Mana Potion", 38, { { 3820, 38 }, { 3356, 38 }, { 3372, 38 } } },
      { 195, 205, 11449, "Elixir of Agility", 10, { { 3820, 10 }, { 3821, 10 }, { 3372, 10 } } },
      { 205, 225, 11448, "Greater Mana Potion", 20, { { 3358, 20 }, { 3821, 20 }, { 3372, 20 } } },
      { 225, 226, 11459, "Philosopher's Stone", 1, { { 3575, 4 }, { 9262, 1 }, { 8831, 4 }, { 4625, 4 } },
        { item = 9303, npc = "Alchemist Pestlezugg", zone = "Tanaris" }, note = "Keep it: transmutes need it." },
      { 226, 240, 11448, "Greater Mana Potion", 20, { { 3358, 20 }, { 3821, 20 }, { 3372, 20 } } },
      { 240, 260, 11460, "Draught of Detect Undead", 23, { { 8836, 23 }, { 8925, 23 } } },
      { 260, 270, 17553, "Superior Mana Potion", 10, { { 8838, 20 }, { 8839, 20 }, { 8925, 10 } },
        { item = 13477, npc = "Ulthir", zone = "Darnassus", horde = { npc = "Algernon", zone = "Undercity" } } },
      { 270, 300, 1231583, "Major Discolored Healing Potion", 31, { { 8925, 31 }, { 13466, 31 }, { 730, 31 } },
        { trainer = true, npc = "the Odd Child", zone = "Westfall", horde = { npc = "Apothecary Renferrel", zone = "Silverpine Forest" } },
        note = "Taught after a short questline." },
    },
  },

  [333] = {
    name = "Enchanting",
    max = 300,
    icon = "Interface\\Icons\\Trade_Engraving",
    learnWord = "Formula",
    ranks = { { "Journeyman", 75, 150 }, { "Expert", 150, 225 }, { "Artisan", 225, 300 } },
    steps = {
      { 1, 2, 7421, "Runed Copper Rod", 1, { { 6217, 1 }, { 247786, 1 } },
        note = "Keep the rod: the enchants to 155 need it. Mote of Magic is sold by enchanting supply vendors." },
      { 2, 20, nil, "Disenchant green items", 18, {},
        note = "Each green or better item you disenchant is a skill point up to 20. Keep the dust and essences." },
      { 20, 79, 14293, "Lesser Magic Wand", 59, { { 4470, 59 }, { 10938, 59 } } },
      { 79, 90, 7426, "Enchant Chest - Minor Absorption", 11, { { 10938, 11 } } },
      { 90, 100, 7457, "Enchant Bracer - Minor Stamina", 10, { { 10940, 20 } } },
      { 100, 101, 7795, "Runed Silver Rod", 1, { { 6338, 1 }, { 10940, 3 }, { 10938, 4 }, { 1210, 1 } },
        note = "Keep the rod: the enchants to 155 need it." },
      { 101, 110, 14807, "Greater Magic Wand", 9, { { 4470, 9 }, { 10938, 18 } } },
      { 110, 135, 13419, "Enchant Cloak - Minor Agility", 25, { { 10998, 25 } },
        { item = 11039, npc = "Dalria", zone = "Ashenvale", horde = { npc = "Kulwia", zone = "Stonetalon Mountains" } } },
      { 135, 155, 13501, "Enchant Bracer - Lesser Stamina", 20, { { 11083, 20 } } },
      { 155, 156, 13628, "Runed Golden Rod", 1, { { 11128, 1 }, { 5500, 1 }, { 11082, 1 }, { 11083, 1 } },
        note = "Keep the rod: the enchants to 200 need it." },
      { 156, 185, 13536, "Enchant Bracer - Lesser Strength", 36, { { 11083, 36 } },
        { item = 11101, npc = "Dalria", zone = "Ashenvale", horde = { npc = "Kulwia", zone = "Stonetalon Mountains" } } },
      { 185, 200, 13661, "Enchant Bracer - Strength", 15, { { 11137, 15 } } },
      { 200, 201, 13702, "Runed Truesilver Rod", 1, { { 11144, 1 }, { 7971, 1 }, { 11135, 1 }, { 11137, 1 } },
        note = "Keep the rod: the enchants to 290 need it." },
      { 201, 220, 13661, "Enchant Bracer - Strength", 26, { { 11137, 26 } } },
      { 220, 225, 13746, "Enchant Cloak - Greater Defense", 5, { { 11137, 5 } } },
      { 225, 230, 13815, "Enchant Gloves - Agility", 5, { { 11137, 5 } } },
      { 230, 235, 13836, "Enchant Boots - Stamina", 5, { { 11137, 10 } } },
      { 235, 250, 13858, "Enchant Chest - Superior Stamina", 16, { { 11137, 48 } } },
      { 250, 265, 25127, "Lesser Mana Oil", 15, { { 11176, 15 }, { 8831, 15 }, { 8925, 15 } },
        { item = 20754, npc = "Lokhtos Darkbargainer", zone = "Blackrock Depths" } },
      { 265, 294, 20017, "Enchant Shield - Greater Stamina", 30, { { 11176, 180 } },
        { item = 16217, npc = "Mythrin'dir", zone = "Darnassus", horde = { npc = "Daniel Bartlett", zone = "Undercity" } } },
      { 294, 295, 20051, "Runed Arcanite Rod", 1, { { 16206, 1 }, { 13926, 1 }, { 16204, 10 }, { 16203, 4 }, { 14343, 4 }, { 14344, 2 } },
        { item = 16243, npc = "Lorelae Wintersong", zone = "Moonglade" }, note = "Keep the rod: the last enchants need it." },
      { 295, 300, 20015, "Enchant Cloak - Superior Defense", 5, { { 16204, 40 } },
        { item = 16224, npc = "Lorelae Wintersong", zone = "Moonglade" } },
    },
  },

  [202] = {
    name = "Engineering",
    max = 300,
    icon = "Interface\\Icons\\Trade_Engineering",
    learnWord = "Schematic",
    ranks = { { "Journeyman", 75, 150 }, { "Expert", 150, 225 }, { "Artisan", 225, 300 } },
    -- Parts the later steps use, made from these when the steps don't make enough.
    makes = {
      [4357] = { { 2835, 1 } },                         -- Rough Blasting Powder
      [4359] = { { 2840, 1 } },                         -- Handful of Copper Bolts
      [4364] = { { 2836, 1 } },                         -- Coarse Blasting Powder
      [4371] = { { 2841, 2 }, { 2880, 1 } },            -- Bronze Tube
      [4375] = { { 2841, 2 }, { 2592, 1 } },            -- Whirring Bronze Gizmo
      [4382] = { { 2841, 2 }, { 2319, 1 }, { 2592, 1 } }, -- Bronze Framework
      [4377] = { { 2838, 1 } },                         -- Heavy Blasting Powder
      [10505] = { { 7912, 2 } },                        -- Solid Blasting Powder
      [10560] = { { 3860, 1 }, { 4338, 1 }, { 10505, 1 } }, -- Unstable Trigger
      [10561] = { { 3860, 3 } },                        -- Mithril Casing
    },
    steps = {
      { 1, 30, 3918, "Rough Blasting Powder", 32, { { 2835, 32 } }, out = 4357, note = "Keep them: the bombs at 51 use them." },
      { 30, 50, 3922, "Handful of Copper Bolts", 20, { { 2840, 20 } }, out = 4359, note = "Keep them: the bombs at 51 use them." },
      { 50, 51, 7430, "Arclight Spanner", 1, { { 2840, 6 } }, note = "Keep it: most later recipes need it as a tool." },
      { 51, 75, 3923, "Rough Copper Bomb", 29, { { 2840, 29 }, { 4359, 29 }, { 4357, 58 }, { 2589, 29 } } },
      { 75, 90, 3929, "Coarse Blasting Powder", 16, { { 2836, 16 } }, out = 4364 },
      { 90, 100, 3931, "Coarse Dynamite", 15, { { 4364, 45 }, { 2589, 15 } } },
      { 100, 105, 3973, "Silver Contact", 5, { { 2842, 5 } } },
      { 105, 125, 3938, "Bronze Tube", 25, { { 2841, 50 }, { 2880, 25 } }, out = 4371 },
      { 125, 135, 3978, "Standard Scope", 10, { { 4371, 10 }, { 1206, 10 } } },
      { 135, 150, 3942, "Whirring Bronze Gizmo", 23, { { 2841, 46 }, { 2592, 23 } }, out = 4375 },
      { 150, 160, 3953, "Bronze Framework", 12, { { 2841, 24 }, { 2319, 12 }, { 2592, 12 } }, out = 4382 },
      { 160, 175, 3955, "Explosive Sheep", 15, { { 4382, 15 }, { 4375, 15 }, { 4377, 30 }, { 2592, 30 } } },
      { 175, 194, 12585, "Solid Blasting Powder", 51, { { 7912, 102 } }, out = 10505 },
      { 194, 195, 12590, "Gyromatic Micro-Adjustor", 1, { { 3859, 4 } }, note = "Keep it: goggles and scopes need it as a tool." },
      { 195, 200, 12589, "Mithril Tube", 5, { { 3860, 15 } } },
      { 200, 215, 12591, "Unstable Trigger", 18, { { 3860, 18 }, { 4338, 18 }, { 10505, 18 } }, out = 10560 },
      { 215, 238, 12599, "Mithril Casing", 33, { { 3860, 99 } }, out = 10561 },
      { 238, 250, 12619, "Hi-Explosive Bomb", 15, { { 10561, 30 }, { 10560, 15 }, { 10505, 30 } } },
      { 250, 260, 19788, "Dense Blasting Powder", 27, { { 12365, 54 } } },
      { 260, 285, 19791, "Thorium Widget", 25, { { 12359, 75 }, { 14047, 25 } },
        { item = 16042, npc = "Gearcutter Cogspinner", zone = "Ironforge", horde = { npc = "Sovik", zone = "Orgrimmar" } } },
      { 285, 300, 19795, "Thorium Tube", 15, { { 12359, 90 } },
        { item = 16047, npc = "Xizzer Fizzbolt", zone = "Winterspring" } },
    },
  },

  [165] = {
    name = "Leatherworking",
    max = 300,
    icon = "Interface\\Icons\\Trade_LeatherWorking",
    learnWord = "Pattern",
    ranks = { { "Journeyman", 75, 150 }, { "Expert", 150, 225 }, { "Artisan", 225, 300 } },
    makes = {
      [4233] = { { 4232, 1 }, { 4289, 1 } }, -- Cured Medium Hide: Medium Hide and Salt
      [4236] = { { 4235, 1 }, { 4289, 3 } }, -- Cured Heavy Hide: Heavy Hide and 3 Salt
      [4246] = { { 2318, 6 }, { 2320, 2 } }, -- Fine Leather Belt
    },
    steps = {
      { 1, 30, 2881, "Light Leather", 32, { { 2934, 96 } }, out = 2318 },
      { 30, 45, 2152, "Light Armor Kit", 20, { { 2318, 20 } } },
      { 45, 55, 3816, "Cured Light Hide", 10, { { 783, 10 }, { 4289, 10 } } },
      { 55, 85, 3756, "Embossed Leather Gloves", 35, { { 2318, 105 }, { 2320, 70 } } },
      { 85, 100, 3763, "Fine Leather Belt", 20, { { 2318, 120 }, { 2320, 40 } }, out = 4246, note = "Keep them: the Dark Leather Belts at 118 use them." },
      { 100, 115, 7135, "Dark Leather Pants", 15, { { 2319, 180 }, { 4340, 15 }, { 2321, 15 } } },
      { 115, 118, 2167, "Gray Leather Boots", 7, { { 2319, 28 }, { 2321, 14 }, { 4340, 7 } } },
      { 118, 125, 3766, "Dark Leather Belt", 7, { { 4246, 7 }, { 4233, 7 }, { 2321, 14 }, { 4340, 7 } } },
      { 125, 135, 3818, "Cured Heavy Hide", 10, { { 4235, 10 }, { 4289, 30 } }, out = 4236 },
      { 135, 143, 3766, "Dark Leather Belt", 18, { { 4246, 18 }, { 4233, 18 }, { 2321, 36 }, { 4340, 18 } } },
      { 143, 145, 3818, "Cured Heavy Hide", 12, { { 4235, 12 }, { 4289, 36 } }, out = 4236 },
      { 145, 155, 3770, "Toughened Leather Gloves", 25, { { 2319, 100 }, { 4233, 50 }, { 3389, 50 }, { 3182, 50 }, { 2321, 50 } } },
      { 155, 160, 7151, "Barbaric Shoulders", 5, { { 4234, 40 }, { 4236, 5 }, { 2321, 10 } } },
      { 160, 180, 3778, "Gem-studded Leather Belt", 20, { { 4236, 80 }, { 5500, 40 }, { 1529, 40 }, { 3864, 20 }, { 2321, 20 } },
        { item = 14635, npc = "Rikqiz", zone = "Stranglethorn Vale" } },
      { 180, 185, 7151, "Barbaric Shoulders", 12, { { 4234, 96 }, { 4236, 12 }, { 2321, 24 } } },
      { 185, 190, 3778, "Gem-studded Leather Belt", 7, { { 4236, 28 }, { 5500, 14 }, { 1529, 14 }, { 3864, 7 }, { 2321, 7 } },
        { item = 14635, npc = "Rikqiz", zone = "Stranglethorn Vale" } },
      { 190, 200, 7156, "Guardian Gloves", 20, { { 4234, 80 }, { 4236, 20 }, { 4291, 20 } } },
      { 200, 210, 10487, "Thick Armor Kit", 20, { { 4304, 100 }, { 4291, 20 } } },
      { 210, 225, 10548, "Nightscape Pants", 15, { { 4304, 210 }, { 4291, 60 } } },
      { 225, 230, 19058, "Rugged Armor Kit", 5, { { 8170, 25 } } },
      { 230, 240, 10548, "Nightscape Pants", 20, { { 4304, 280 }, { 4291, 80 } } },
      { 240, 255, 19049, "Wicked Leather Gauntlets", 15, { { 8170, 120 }, { 2325, 15 }, { 14341, 15 } },
        { item = 15725, npc = "Leonard Porter", zone = "Western Plaguelands", horde = { npc = "Werg Thickblade", zone = "Tirisfal Glades" } } },
      { 255, 260, 19048, "Heavy Scorpid Bracers", 6, { { 8170, 24 }, { 15408, 24 }, { 14341, 6 } },
        { item = 15724, npc = "Zannok Hidepiercer", zone = "Silithus" } },
      { 260, 270, 19049, "Wicked Leather Gauntlets", 20, { { 8170, 160 }, { 2325, 20 }, { 14341, 20 } },
        { item = 15725, npc = "Leonard Porter", zone = "Western Plaguelands", horde = { npc = "Werg Thickblade", zone = "Tirisfal Glades" } } },
      { 270, 300, 19088, "Heavy Scorpid Helm", 33, { { 8170, 264 }, { 15408, 396 }, { 15407, 33 }, { 14341, 33 } },
        { item = 15762, npc = "Zannok Hidepiercer", zone = "Silithus" } },
    },
  },

  [197] = {
    name = "Tailoring",
    max = 300,
    icon = "Interface\\Icons\\Trade_Tailoring",
    learnWord = "Pattern",
    ranks = { { "Journeyman", 75, 150 }, { "Expert", 150, 225 }, { "Artisan", 225, 300 } },
    -- Bolts: the steps that make them don't make enough for the rest.
    makes = {
      [2996] = { { 2589, 2 } },  -- Bolt of Linen Cloth
      [2997] = { { 2592, 3 } },  -- Bolt of Woolen Cloth
      [4305] = { { 4306, 4 } },  -- Bolt of Silk Cloth
      [4339] = { { 4338, 5 } },  -- Bolt of Mageweave
      [14048] = { { 14047, 5 } }, -- Bolt of Runecloth
    },
    steps = {
      { 1, 43, 2963, "Bolt of Linen Cloth", 54, { { 2589, 108 } }, out = 2996 },
      { 43, 45, 2385, "Brown Linen Vest", 2, { { 2996, 2 }, { 2320, 2 } } },
      { 45, 70, 8776, "Linen Belt", 33, { { 2996, 33 }, { 2320, 33 } } },
      { 70, 75, 2397, "Reinforced Linen Cape", 7, { { 2996, 14 }, { 2320, 21 } } },
      { 75, 81, 2964, "Bolt of Woolen Cloth", 12, { { 2592, 36 } }, out = 2997 },
      { 81, 100, 2402, "Woolen Cape", 27, { { 2997, 27 }, { 2321, 27 } } },
      { 100, 110, 3839, "Bolt of Silk Cloth", 10, { { 4306, 40 } }, out = 4305 },
      { 110, 125, 3848, "Double-stitched Woolen Shoulders", 19, { { 2997, 57 }, { 2321, 38 } } },
      { 125, 132, 8760, "Azure Silk Hood", 7, { { 4305, 14 }, { 6260, 14 }, { 2321, 7 } } },
      { 132, 139, 6690, "Lesser Wizard's Robe", 8, { { 4305, 16 }, { 2321, 16 }, { 3182, 16 } } },
      { 139, 140, 3871, "Formal White Shirt", 1, { { 4305, 3 }, { 2324, 2 }, { 2321, 1 } } },
      { 140, 149, 3865, "Bolt of Mageweave", 11, { { 4338, 55 } }, out = 4339 },
      { 149, 160, 8764, "Earthen Vest", 11, { { 4305, 33 }, { 7067, 11 }, { 2321, 22 } } },
      { 160, 170, 8770, "Robe of Power", 10, { { 4339, 20 }, { 7067, 20 }, { 7070, 20 }, { 7068, 20 }, { 7069, 20 }, { 4291, 20 } } },
      { 170, 180, 12048, "Black Mageweave Vest", 10, { { 4339, 20 }, { 4291, 30 } } },
      { 180, 190, 12061, "Orange Mageweave Shirt", 11, { { 4339, 11 }, { 6261, 11 }, { 8343, 11 } } },
      { 190, 205, 12053, "Black Mageweave Gloves", 17, { { 4339, 34 }, { 8343, 34 } } },
      { 205, 214, 18401, "Bolt of Runecloth", 11, { { 14047, 55 } }, out = 14048 },
      { 214, 234, 18402, "Runecloth Belt", 21, { { 14048, 63 }, { 14341, 21 } } },
      { 234, 250, 18409, "Runecloth Cloak", 18, { { 14048, 72 }, { 14227, 18 }, { 14341, 18 } },
        { item = 14472, npc = "Darnall", zone = "Moonglade" } },
      { 250, 260, 18423, "Runecloth Boots", 12, { { 14048, 48 }, { 14227, 24 }, { 8170, 48 }, { 14341, 12 } },
        { item = 14488, npc = "Darnall", zone = "Moonglade" } },
      { 260, 280, 1257487, "Runecloth Cuffs", 25, { { 14048, 125 }, { 14227, 25 }, { 14341, 25 } },
        { item = 254124, npc = "Pexmit", zone = "Mount Hyjal" } },
      { 280, 285, 23662, "Wisdom of the Timbermaw", 8, { { 14048, 64 }, { 7076, 24 }, { 12803, 24 }, { 14227, 16 } },
        { item = 19215, npc = "Meilosh", zone = "Felwood" } },
      { 285, 292, 1297120, "Venomspew Gloves", 7, { { 14048, 28 }, { 14343, 7 }, { 7082, 21 }, { 14341, 42 } },
        { item = 275580, npc = "Mishta", zone = "Silithus" } },
      { 292, 299, 1297121, "Venomspew Cord", 9, { { 14048, 54 }, { 14343, 9 }, { 7082, 27 }, { 14341, 54 } },
        { item = 275581, npc = "Mishta", zone = "Silithus" } },
      { 299, 300, 1297122, "Venomspew Footpads", 4, { { 14048, 20 }, { 14343, 4 }, { 7082, 12 }, { 14341, 24 } },
        { item = 275582, npc = "Mishta", zone = "Silithus" } },
    },
  },
}

--- Who sells a recipe or plans to your faction: { npc, zone }.
function ns.CraftVendor(learn, faction)
  if faction == "Horde" and learn.horde then return learn.horde end
  return learn
end

--- The plan for a profession skill line, or nil.
function ns.CraftPlanFor(skillLine)
  return ns.CRAFT_PLANS[tonumber(skillLine) or -1]
end

--- The skill to level to: `goal` kept between 1 and the plan's cap (the cap when nil).
function ns.CraftGoal(plan, goal)
  goal = math.floor(tonumber(goal) or plan.max)
  return math.max(1, math.min(plan.max, goal))
end

--- From `skill` to `goal` (the plan's cap when nil). Each callback may be nil:
---   have(id) -> how many you have (bags and bank)
---   price(id) -> copper each at the auction house, or nil
---   known(spell) -> true when you already know the recipe
--- Returns {
---   skill, max (the goal), done,
---   steps = { { from, to, name, spell, crafts, current, learn } }  (crafts still to do)
---   rows = { { id, need, have, missing, price, cost, made, plans, tool } }
---   cost (copper for everything missing that has a price), unpriced (rows missing with no price),
---   crafts (all crafts left), made (parts to make along the way),
---   rank = { name, at, cap, how } when the next rank must be trained before the cap you have
--- }
function ns.CraftPlan(plan, skill, have, price, known, cap, goal)
  skill = math.max(1, math.floor(tonumber(skill) or 1))
  goal = ns.CraftGoal(plan, goal)
  have = have or function() return 0 end
  price = price or function() return nil end
  known = known or function() return false end
  local function owned(id) return tonumber(have(id)) or 0 end
  local out = { skill = skill, max = goal, done = skill >= goal, steps = {}, rows = {}, cost = 0, unpriced = 0, crafts = 0, made = 0 }
  local direct, order, seen = {}, {}, {}
  local function note(id) if not seen[id] then seen[id] = true; order[#order + 1] = id end end
  local function want(id, n)
    if n <= 0 then return end
    note(id)
    direct[id] = (direct[id] or 0) + n
  end
  -- What the steps make along the way (bolts, powder, cured hides) for later steps.
  local stepMade = {}
  local plans, planOrder = {}, {}
  for _, s in ipairs(plan.steps) do
    local from, to, spell, name, crafts, mats, learn = s[1], s[2], s[3], s[4], s[5], s[6], s[7]
    -- Only the part of the step between your skill and the goal.
    local lo, hi = math.max(skill, from), math.min(to, goal)
    if lo < hi then
      local left = crafts
      if lo > from or hi < to then left = math.ceil(crafts * (hi - lo) / (to - from)) end
      out.steps[#out.steps + 1] = { from = from, to = hi, name = name, spell = spell, crafts = left, current = skill >= from, learn = learn, note = s.note }
      out.crafts = out.crafts + left
      for _, m in ipairs(mats) do want(m[1], math.ceil(m[2] / crafts * left)) end
      if s.out then stepMade[s.out] = (stepMade[s.out] or 0) + left end
      if learn and learn.item and spell and not known(spell) and not plans[learn.item] then
        plans[learn.item] = learn
        planOrder[#planOrder + 1] = learn.item
      end
    end
  end
  if out.done then return out end
  -- Parts you make: what you have and what the steps make count first, the rest
  -- is made from its materials. Parts can need parts, so go round until it settles.
  local makes = plan.makes or {}
  local total, extra = direct, {}
  for _ = 1, 8 do
    local nextTotal = {}
    for id, n in pairs(direct) do nextTotal[id] = n end
    extra = {}
    for _, id in ipairs(order) do
      local recipe = makes[id]
      if recipe and total[id] then
        local short = math.max(0, total[id] - owned(id) - (stepMade[id] or 0))
        extra[id] = short
        for _, m in ipairs(recipe) do
          if short > 0 then note(m[1]); nextTotal[m[1]] = (nextTotal[m[1]] or 0) + short * m[2] end
        end
      end
    end
    local same = true
    for _, id in ipairs(order) do if (nextTotal[id] or 0) ~= (total[id] or 0) then same = false end end
    total = nextTotal
    if same then break end
  end
  local function row(id, n, extraFields)
    local h = owned(id)
    local r = { id = id, need = n, have = math.min(h, n), missing = math.max(0, n - h) }
    for k, v in pairs(extraFields or {}) do r[k] = v end
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
    -- What the steps make themselves isn't on the list.
    local n = (total[id] or 0) - (stepMade[id] or 0)
    if n > 0 then
      if makes[id] then
        out.made = out.made + (extra[id] or 0)
        row(id, n, { made = true })
      else
        row(id, n)
      end
    end
  end
  -- The rank to train: your cap is below the skill the next step needs.
  cap = tonumber(cap)
  if cap and cap < goal then
    for _, r in ipairs(plan.ranks or {}) do
      if cap <= r[2] then out.rank = { name = r[1], at = r[2], cap = r[3], how = r.how }; break end
    end
  end
  return out
end
