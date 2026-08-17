local helpers = require("lib.helpers")
local gprefix = "dmrsa-"

-- Setup science pack ingredients helper
local function make_research_unit(count, packs, time)
    local ingredients = {}
    for _, pack in ipairs(packs) do
        if helpers.item_exists(pack) then
            table.insert(ingredients, { pack, 1 })
        end
    end
    -- Fallback: if all specified packs are missing, use tenemut as a fallback to avoid startup errors
    if #ingredients == 0 then
        if helpers.item_exists(gprefix .. "tenemut") then
            table.insert(ingredients, { gprefix .. "tenemut", 1 })
        end
    end
    -- Apply research difficulty multipliers (Medium/High) to ALL static techs
    local diff_mult = helpers.get_research_difficulty_multipliers()
    return {
        count = math.max(1, math.ceil(count * diff_mult.reps_mult)),
        ingredients = ingredients,
        time = math.max(1, math.ceil((time or 30) * diff_mult.time_mult))
    }
end

-- 1. Baseline Science Packs List
local t1_packs = { "automation-science-pack", "logistic-science-pack" }
-- Tier 2: automation + logistic ONLY (no chemical). Progression: chemical is
-- tier 3. t2_packs previously included chemical-science-pack, which made
-- replication-2 (transducer, replicator-2) require chemical before it should.
local t2_packs = { "automation-science-pack", "logistic-science-pack" }

-- Tier 3: chemical is the endpoint of tier 3 (before planets). With SA,
-- production/utility don't exist; the tier 3 tech uses chemical only.
local t3_packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack" }

-- Tier 4: planetary packs (SA) — the planets ARE tier 4.
local t4_packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack" }
if mods["space-age"] then
    table.insert(t4_packs, "metallurgic-science-pack")
    table.insert(t4_packs, "electromagnetic-science-pack")
    table.insert(t4_packs, "agricultural-science-pack")
else
    table.insert(t4_packs, "production-science-pack")
end

-- Tier 5: space, cryogenic (SA) or utility/space (non-SA)
local t5_packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack" }
if mods["space-age"] then
    table.insert(t5_packs, "space-science-pack")
    table.insert(t5_packs, "cryogenic-science-pack")
else
    table.insert(t5_packs, "utility-science-pack")
    table.insert(t5_packs, "space-science-pack")
end

-- Inject space-science-pack into research requirements for space-locked tiers
local function add_science_pack_if_missing(pack_list, pack_name)
    for _, name in ipairs(pack_list) do
        if name == pack_name then return end
    end
    table.insert(pack_list, pack_name)
end

local space_lock = helpers.get_startup_setting("replresearch-space-lock", 6)
if space_lock <= 1 then add_science_pack_if_missing(t1_packs, "space-science-pack") end
if space_lock <= 2 then add_science_pack_if_missing(t2_packs, "space-science-pack") end
if space_lock <= 3 then add_science_pack_if_missing(t3_packs, "space-science-pack") end
if space_lock <= 4 then add_science_pack_if_missing(t4_packs, "space-science-pack") end
if space_lock <= 5 then add_science_pack_if_missing(t5_packs, "space-science-pack") end

local tech_list = {
    -- Technology Tier 1
    {
        type = "technology",
        name = gprefix .. "replication-1",
        icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-1.png",
        icon_size = 64,
        effects = {
            { type = "unlock-recipe", recipe = gprefix .. "dark-matter-scoop" },
            { type = "unlock-recipe", recipe = gprefix .. "replication-lab" },
            { type = "unlock-recipe", recipe = gprefix .. "replicator-1" }
        },
        prerequisites = { "electronics" },
        unit = make_research_unit(50, t1_packs, 30),
        order = "a-r-1"
    },

    -- Technology Tier 2
    {
        type = "technology",
        name = gprefix .. "replication-2",
        icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-2.png",
        icon_size = 64,
        effects = {
            { type = "unlock-recipe", recipe = gprefix .. "dark-matter-transducer" },
            { type = "unlock-recipe", recipe = gprefix .. "replicator-2" }
        },
        prerequisites = { gprefix .. "replication-1", "advanced-circuits" }, -- FIXED FOR FACTORIO 2.0 (formerly advanced-electronics)
        unit = make_research_unit(100, t2_packs, 30),
        order = "a-r-2"
    }
}

if not mods["space-age"] then
    table.insert(tech_list, {
        type = "technology",
        name = gprefix .. "replication-3",
        icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-3.png",
        icon_size = 64,
        effects = {
            { type = "unlock-recipe", recipe = gprefix .. "replicator-3" }
        },
        prerequisites = { gprefix .. "replication-2" },
        unit = make_research_unit(150, t3_packs, 30),
        order = "a-r-3"
    })
else
    -- With Space Age, replication-3 is VISIBLE and unlocks the Chemical
    -- Replicator (tier 3), which comes BEFORE the planets (tier 4). It also
    -- serves as the sink for orphaned tier-3 unlocks (data-final-fixes PASS 3).
    table.insert(tech_list, {
        type = "technology",
        name = gprefix .. "replication-3",
        icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-3.png",
        icon_size = 64,
        effects = {
            { type = "unlock-recipe", recipe = gprefix .. "replicator-3" }
        },
        prerequisites = { gprefix .. "replication-2" },
        unit = make_research_unit(150, t3_packs, 30),
        order = "a-r-3"
    })
end

local rep_4_prereqs
if mods["space-age"] then
    rep_4_prereqs = {
        gprefix .. "replication-3",
        gprefix .. "replication-vulcanus-tech",
        gprefix .. "replication-fulgora-tech",
        gprefix .. "replication-gleba-tech",
        "processing-unit"
    }
else
    rep_4_prereqs = { gprefix .. "replication-3", "processing-unit" }
end

table.insert(tech_list, {
    type = "technology",
    name = gprefix .. "replication-4",
    icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-4.png",
    icon_size = 64,
    effects = {
        { type = "unlock-recipe", recipe = gprefix .. "matter-conduit" },
        { type = "unlock-recipe", recipe = gprefix .. "replicator-4" }
    },
    prerequisites = rep_4_prereqs,
    unit = make_research_unit(250, t4_packs, 30),
    order = "a-r-4"
})

table.insert(tech_list, {
    type = "technology",
    name = gprefix .. "replication-5",
    icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-5.png",
    icon_size = 64,
    effects = {
        { type = "unlock-recipe", recipe = gprefix .. "replicator-5" }
    },
    prerequisites = mods["space-age"] and { gprefix .. "replication-4", "cryogenic-science-pack" } or { gprefix .. "replication-4" },
    unit = make_research_unit(500, t5_packs, 45),
    order = "a-r-5"
})

-- v4.0: Materials techs (one per tier) — the bridge between the machine and
-- the mirror techs. Each unlocks the BASE MATERIALS of its tier (ores, fluids,
-- plates, vanilla basics that have no original unlock tech) and is a prereq of
-- every mirror tech of that tier. Philosophy: you cannot replicate items until
-- you know their base materials. Research pack = the tier's DMR intermediate.
-- Effects are filled dynamically by MirrorGenerator.generate() (data-final-fixes
-- PASS 0) with the baseline recipes.
local materials_defs = {
    { tier = 1, pack = gprefix .. "tenemut", count = 30 },
    { tier = 2, pack = gprefix .. "dark-matter-scoop", count = 40 },
    { tier = 3, pack = gprefix .. "dark-matter-transducer", count = 50 },
    { tier = 4, pack = gprefix .. "matter-conduit", count = 60 },
    { tier = 5, pack = gprefix .. "matter-conduit", count = 70 },
}
for _, def in ipairs(materials_defs) do
    table.insert(tech_list, {
        type = "technology",
        name = gprefix .. "replication-materials-" .. def.tier,
        icon = "__dark-matter-replicators-reborn__/graphics/icons/matter-conduit.png",
        icon_size = 64,
        effects = {},  -- filled in data-final-fixes with baseline recipes
        prerequisites = { gprefix .. "replication-" .. def.tier },
        unit = make_research_unit(def.count, { def.pack }, 30),
        order = "a-r-m-" .. def.tier
    })
end

data:extend(tech_list)
