-- prototypes/entities/refiner.lua
-- v4.1.0: Quality Refiner — a separate machine that refines replicable items
-- one quality step higher (never skips). Faithful balance: every cycle costs
-- 10x replication energy, has a low per-step success chance (1% -> 0.5% ->
-- 0.25% -> 0.1%) and a 5% destruction risk. The machine accepts NO modules —
-- the probabilities ARE the mechanic.
--
-- Placeholder graphics: vanilla assembling-machine-1 sprites with a violet /
-- black-obsidian tint (parameters taken from the real 2.x prototype, not
-- memory: 214x226, frame_count 32, line_length 8, scale 0.58).
--
-- The whole subsystem only exists when a quality mod is active
-- (data.raw["quality"]["uncommon"]).
local helpers = require("lib.helpers")
local gprefix = "dmrsa-"

local QUALITY_ON = (data.raw["quality"] and data.raw["quality"]["uncommon"] ~= nil)
if not QUALITY_ON then
    return
end

local diff_vals = helpers.get_research_difficulty_values()
local tech_prereqs = { gprefix .. "replication-materials-5" }
if data.raw.technology["quality"] then
    table.insert(tech_prereqs, "quality")
end

data:extend({
    -- Recipe category for refining (only visible inside the refiner)
    {
        type = "recipe-category",
        name = gprefix .. "refining"
    },
    -- Visual subgroup while picking recipes in the refiner
    {
        type = "item-subgroup",
        name = gprefix .. "refining",
        group = "production",
        order = "z"
    },
    -- Item
    {
        type = "item",
        name = gprefix .. "refiner",
        icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-5.png",
        icon_size = 64,
        subgroup = gprefix .. "replicators",
        order = "c",
        place_result = gprefix .. "refiner",
        stack_size = 50
    },
    -- Entity (placeholder: assembler-1 tinted obsidian-violet)
    {
        type = "assembling-machine",
        name = gprefix .. "refiner",
        icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-5.png",
        icon_size = 64,
        flags = { "placeable-neutral", "placeable-player", "player-creation" },
        minable = { mining_time = 0.2, result = gprefix .. "refiner" },
        fast_replaceable_group = gprefix .. "replicator",
        max_health = 400,
        resistances = {
            {
                type = "fire",
                percent = 80
            }
        },
        dying_explosion = "big-explosion",
        corpse = "big-remnants",
        collision_box = { { -1.2, -1.2 }, { 1.2, 1.2 } },
        selection_box = { { -1.5, -1.5 }, { 1.5, 1.5 } },
        crafting_categories = { gprefix .. "refining" },
        crafting_speed = 1,
        -- v4.2 (B2 refinement): 6MW → 4MW — with slower replication times
        -- (speed 1.6) the refiner keeps its energy per cycle affordable
        -- ("si es más lento, más económico en términos energéticos").
        energy_usage = "4MW",
        energy_source = {
            type = "electric",
            usage_priority = "secondary-input",
            emissions_per_second = 0.05
        },
        graphics_set = {
            animation = {
                -- Placeholder: DMR's own replicator-5 sprite (robust — the
                -- vanilla assembler-1 sheet path doesn't exist once an
                -- overhaul mod (Bob's) replaces it, so we use our own proven
                -- sprite with an obsidian-violet tint as the placeholder).
                filename = "__dark-matter-replicators-reborn__/graphics/entity/replicator-5.png",
                priority = "high",
                width = 113,
                height = 91,
                frame_count = 33,
                line_length = 11,
                animation_speed = 1 / 3,
                shift = { 0.4, 0.1 },
                tint = { r = 0.35, g = 0.25, b = 0.65, a = 1 }
            }
        },
        working_sound = {
            sound = {
                {
                    filename = "__base__/sound/lab.ogg",
                    volume = 0.7
                }
            },
            idle_sound = { filename = "__base__/sound/idle1.ogg", volume = 0.6 },
            apparent_volume = 1.5
        },
        -- NO module slots: quality/probability balance is the mechanic itself.
        module_slots = 0,
        allowed_effects = { "consumption" }
    },
    -- Recipe (unlocked by the refining technology)
    {
        type = "recipe",
        name = gprefix .. "refiner",
        enabled = false,
        ingredients = {
            { type = "item", name = gprefix .. "replicator-4", amount = 1 },
            { type = "item", name = "processing-unit", amount = 15 },
            { type = "item", name = gprefix .. "matter-conduit", amount = 10 }
        },
        results = {
            { type = "item", name = gprefix .. "refiner", amount = 1 }
        }
    },
    -- Technology (only when quality exists)
    {
        type = "technology",
        name = gprefix .. "replication-refining",
        localised_name = { "technology-name.dmrsa-replication-refining" },
        localised_description = { "technology-description.dmrsa-replication-refining" },
        -- Factorio 2.1 REQUIRES icon/icons on technologies (the other DMR
        -- techs define icons via get_tech_icons; this standalone tech uses
        -- the refiner's placeholder icon).
        icon = "__dark-matter-replicators-reborn__/graphics/icons/replicator-5.png",
        icon_size = 64,
        effects = {
            { type = "unlock-recipe", recipe = gprefix .. "refiner" }
        },
        prerequisites = tech_prereqs,
        unit = {
            count = math.max(1, math.ceil(50 * (diff_vals.cost / 25))),
            ingredients = { { gprefix .. "matter-conduit", 1 } },
            time = math.max(1, math.ceil(diff_vals.time * 4))
        },
        order = "a-r-f"
    }
})