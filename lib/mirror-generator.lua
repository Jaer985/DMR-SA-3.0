-- lib/mirror-generator.lua
-- v4.0 (Factorio 2.1): Árbol espejo de replicación.
--
-- Cada tech ORIGINAL del juego genera UNA tech de replicación
-- ("Replication: <tech original>") que desbloquea la replicación de TODOS los
-- items que esa tech desbloquea. El grouped-por-categoría desaparece; las
-- categorías (shape/alloy/chemical/...) quedan SOLO como subgroups visuales.
--
-- Cadena de progresión (filosofía: no replicas sin conocer los materiales):
--   replication-N (máquina)
--     → replication-materials-N (materiales base del tier, 5 techs nuevas)
--       → Replication: <tech original> (techs espejo, una por tech del juego)
--
-- Dump-verificado (3.7.1, Bob's+SA): 945 items → 144 excluidos → 801
-- replicables → ~417 techs espejo + 5 materials + 4 planetary = ~426 techs.

local helpers = require("lib.helpers")
local CostSolver = require("lib.cost-solver")
local TargetMapper = require("lib.target-mapper")
local repltypes = require("lib.repltypes")
local gprefix = "dmrsa-"

local MirrorGenerator = {}

-- ══════════════════════════════════════════════════════════════════
-- Science pack → progression level (1-5)
-- ══════════════════════════════════════════════════════════════════

local PACK_LEVELS = {
    ["automation-science-pack"] = 1,
    ["logistic-science-pack"] = 1,
    ["military-science-pack"] = 2,
    ["chemical-science-pack"] = 3,
    ["production-science-pack"] = 3,
    ["utility-science-pack"] = 3,
    ["metallurgic-science-pack"] = 4,
    ["electromagnetic-science-pack"] = 4,
    ["agricultural-science-pack"] = 4,
    ["space-science-pack"] = 5,
    ["cryogenic-science-pack"] = 5,
    ["promethium-science-pack"] = 5,
}

-- Mod science packs → level (endgame equivalences). Extend here as new
-- overhaul mods appear; unknown packs fall back to the item-tier heuristic.
local MOD_PACK_LEVELS = {
    ["bob-science-pack-gold"] = 5,
    ["bob-alien-science-pack"] = 5,
    ["bob-alien-science-pack-blue"] = 5,
    ["bob-alien-science-pack-green"] = 5,
    ["bob-alien-science-pack-orange"] = 5,
    ["bob-alien-science-pack-purple"] = 5,
    ["bob-alien-science-pack-red"] = 5,
    ["bob-alien-science-pack-yellow"] = 5,
}

-- ══════════════════════════════════════════════════════════════════
-- v4.2 ADAPTABILITY: dynamic progression levels for UNKNOWN mod packs.
-- Design decision (user, 2026-08-23): the mod must adapt to ANY modlist,
-- not just ours. PACK_LEVELS/MOD_PACK_LEVELS only cover vanilla/SA/Bob's;
-- everything else is inferred from how the loaded modlist itself uses the
-- pack:
--   level(P) = max TABLE-BASED science level among the visible non-DMR
--              technologies that consume P as a research ingredient.
-- Kitchen-sink techs (>8 distinct ingredients, e.g. promethium-style
-- "consume everything" techs) are EXCLUDED from anchoring so endgame
-- mega-techs don't drag early packs to level 5. One pass, no recursion,
-- derived ONLY from table-known levels — no cycles possible.
-- (Declared BEFORE pack_level so the upvalues resolve correctly.)
-- ══════════════════════════════════════════════════════════════════
local inferred_pack_levels = {}
local inferred_built = false
local function ensure_inferred_pack_levels()
    if inferred_built then return end
    inferred_built = true
    for tech_name, tech in pairs(data.raw.technology) do
        if not string.find(tech_name, "dmrsa%-") and not tech.hidden and tech.unit then
            local packs_used, n_packs = {}, 0
            local known_max = nil
            for _, ing in ipairs(tech.unit.ingredients or {}) do
                local p = ing
                if type(ing) == "table" then p = ing[1] or ing.name end
                if type(p) == "string" then
                    n_packs = n_packs + 1
                    packs_used[p] = true
                    local lvl = PACK_LEVELS[p] or MOD_PACK_LEVELS[p]
                    if lvl and (not known_max or lvl > known_max) then known_max = lvl end
                end
            end
            -- anchor only from reasonably-shaped techs
            if known_max and n_packs <= 8 then
                for p in pairs(packs_used) do
                    local cur = inferred_pack_levels[p]
                    if not cur or known_max > cur then inferred_pack_levels[p] = known_max end
                end
            end
        end
    end
end

-- Testable accessor (dmr-tests): inferred level for an unknown pack, or nil.
function MirrorGenerator.get_inferred_pack_level(pack_name)
    ensure_inferred_pack_levels()
    return inferred_pack_levels[pack_name]
end

local function pack_level(pack_name)
    if not pack_name or type(pack_name) ~= "string" then return nil end
    if PACK_LEVELS[pack_name] then return PACK_LEVELS[pack_name] end
    if MOD_PACK_LEVELS[pack_name] then return MOD_PACK_LEVELS[pack_name] end
    -- Name heuristics for known Space Age families
    if string.find(pack_name, "promethium") or string.find(pack_name, "cryogenic")
       or string.find(pack_name, "%-space%-") then
        return 5
    end
    if string.find(pack_name, "metallurgic") or string.find(pack_name, "electromagnetic")
       or string.find(pack_name, "agricultural") then
        return 4
    end
    -- v4.2 (adaptability): ANY modlist — unknown packs are anchored dynamically
    -- (see ensure_inferred_pack_levels above)
    ensure_inferred_pack_levels()
    return inferred_pack_levels[pack_name]
end

-- Science level (1-5) of a technology, from the max level of its unit packs.
-- Returns nil when the tech has no detectable standard/mod packs.
function MirrorGenerator.get_tech_science_level(tech_name)
    local tech = data.raw.technology[tech_name]
    if not tech or not tech.unit then return nil end
    local max_level = nil
    for _, ing in ipairs(tech.unit.ingredients or {}) do
        local pack = ing
        if type(ing) == "table" then
            pack = ing[1] or ing.name
        end
        local lvl = pack_level(pack)
        if lvl and (not max_level or lvl > max_level) then
            max_level = lvl
        end
    end
    return max_level
end

-- v4.0: REAL depth of a technology in the research tree (1 = no prereqs).
-- When dmrsa-require-original-tech is ON, the mirror tech takes the original
-- tech as a DIRECT prerequisite, so the mirror's tier must be >= the original's
-- tree depth — otherwise Factorio rejects it with
-- "Non-contiguous levels: N, followed by M" (e.g. angel's chlorine-processing
-- sits at depth 4 while its science-pack level maps to 2). Memoized + cycle-safe.
local depth_cache = {}
local depth_in_progress = {}
function MirrorGenerator.get_tech_tree_depth(tech_name)
    if depth_cache[tech_name] then return depth_cache[tech_name] end
    if depth_in_progress[tech_name] then return 1 end  -- cycle guard
    local tech = data.raw.technology[tech_name]
    if not tech or not tech.prerequisites or #tech.prerequisites == 0 then
        depth_cache[tech_name] = 1
        return 1
    end
    depth_in_progress[tech_name] = true
    local max_depth = 0
    for _, prereq in ipairs(tech.prerequisites) do
        local d = MirrorGenerator.get_tech_tree_depth(prereq)
        if d > max_depth then max_depth = d end
    end
    depth_in_progress[tech_name] = nil
    depth_cache[tech_name] = max_depth + 1
    return depth_cache[tech_name]
end

-- ══════════════════════════════════════════════════════════════════
-- Item classification helpers (moved from dynamic-generator)
-- ══════════════════════════════════════════════════════════════════

-- v4.2: mod prefix = everything before the first hyphen ("" for base items).
-- Used to guard process-output tech inheritance (an angels-* item only
-- inherits techs from angels-* producing recipes, never from foreign mods).
local function mod_prefix(name)
    local dash = string.find(name, "-", 1, true)
    if dash then return string.sub(name, 1, dash - 1) end
    return ""
end

-- v4.2: minable resources never inherit a producing recipe's tech — they are
-- mined, not crafted; their tier comes from the cost-solver/base-resource map.
local function is_minable_resource(name)
    local res = data.raw.resource and data.raw.resource[name]
    return res ~= nil
end

-- Determine item category for VISUAL subgroup only (no tier gating in v4.0).
local function get_item_category(name, target)
    local subgroup = target.subgroup or ""
    local type_name = target.type or ""
    local item_proto = data.raw[target.type] and data.raw[target.type][name]

    if mods["space-age"] and item_proto then
        local is_organic = false
        if item_proto.spoil_ticks or item_proto.spoil_to or item_proto.spoil_result then
            is_organic = true
        end
        if is_organic or string.find(name, "yumako") or string.find(name, "jellynut")
           or name == "spoiled-organic-substrate" or name == "nutrients" then
            return "organic"
        end
    end

    if type_name == "resource" or subgroup == "ore" or subgroup == "raw-resource"
       or string.find(name, "ore$") or string.find(name, "%-ore") or string.find(name, "ore%-") then
        return "ore"
    end
    if string.find(name, "science%-pack") then return "science" end
    if type_name == "fluid" then return "chemical" end
    if string.find(name, "module") or subgroup == "module" then
        if string.find(name, "module%-3") then return "module-advanced" end
        return "module"
    end
    local is_military = false
    if type_name == "gun" or type_name == "ammo" or type_name == "armor" or type_name == "capsule" then
        is_military = true
    end
    if string.find(name, "weapon") or string.find(name, "bullet") or string.find(name, "magazine")
       or string.find(name, "rocket") or string.find(name, "grenade") or string.find(name, "shotgun")
       or string.find(name, "rifle") or string.find(name, "cannon") or string.find(name, "missile")
       or string.find(name, "mine%-") or string.find(name, "%-mine") or string.find(name, "capsule")
       or subgroup == "gun" or subgroup == "ammo" then
        is_military = true
    end
    if is_military then
        if string.find(name, "uranium") or string.find(name, "artillery")
           or string.find(name, "explosive%-rocket") or string.find(name, "cluster")
           or string.find(name, "spidertron") or string.find(name, "nuke")
           or string.find(name, "nuclear") or string.find(name, "explosive%-cannon")
           or string.find(name, "sniper") or string.find(name, "laser%-rifle")
           or string.find(name, "gatling") or string.find(name, "plasma")
           or string.find(name, "turret%-[3-9]") or string.find(name, "armor%-mk[3-9]")
           or string.find(name, "mech%-") or string.find(name, "tank%-[2-9]") then
            return "military-advanced"
        end
        return "military"
    end
    if string.find(name, "plate") or string.find(name, "alloy") or string.find(name, "foil")
       or string.find(name, "sheet") or subgroup == "plate" or subgroup == "alloy" then
        return "alloy"
    end
    if string.find(name, "gear") or string.find(name, "pipe") or string.find(name, "stick")
       or string.find(name, "cable") or string.find(name, "wire") or string.find(name, "brick")
       or string.find(name, "frame") or string.find(name, "bearing") or string.find(name, "spring")
       or string.find(name, "ring") or string.find(name, "rod") or string.find(name, "tube")
       or string.find(name, "barrel") or string.find(name, "coil") or string.find(name, "%-ball")
       or string.find(name, "ball%-") or subgroup == "component" or subgroup == "part"
       or subgroup == "intermediate" then
        return "shape"
    end
    if item_proto then
        local name_lower = string.lower(name)
        for _, elem in ipairs(repltypes.element_names) do
            if string.find(name_lower, elem) then return "element" end
        end
    end
    if string.find(name, "exotic") or string.find(name, "artifact") or subgroup == "artifact" then
        return "exotic"
    end
    if string.find(name, "magic") or string.find(name, "mana") or string.find(name, "arcane") then
        return "magic"
    end
    if string.find(name, "alien") or subgroup == "alien" then return "alien" end
    if string.find(name, "spawner") or string.find(name, "worm")
       or (type_name == "capsule" and string.find(name, "spawn")) or subgroup == "living" then
        return "life"
    end
    return "general"
end

-- Correct locale prefix for a target (placeable items use entity-name).
local function get_loc_prefix(name, target)
    if target.type == "fluid" then return "fluid-name" end
    if target.type == "item" or target.type == "ammo" or target.type == "armor"
       or target.type == "gun" or target.type == "capsule" or target.type == "tool"
       or target.type == "module" or target.type == "item-with-entity-data"
       or target.type == "item-with-tags" or target.type == "spidertron-remote"
       or target.type == "space-platform-starter" then
        local item_proto = data.raw[target.type] and data.raw[target.type][name]
        if item_proto and item_proto.place_result then
            return "entity-name"
        end
        return "item-name"
    end
    return "entity-name"
end

-- v3.5.24: composite tech icon — bordered 128x128 with the item icon centered.
local function get_tech_icons(name, target, tier)
    local border = "tech-device" .. tier
    if tier < 2 then border = "tech-device2" end
    local subgroup = target.subgroup or ""
    local type_name = target.type or ""
    if type_name == "fluid" then
        border = "tech-chemical"
    elseif string.find(name, "ore") or string.find(subgroup, "ore") or subgroup == "raw-resource" then
        border = "tech-ore"
    elseif string.find(name, "science%-pack") then
        border = "tech-science"
    elseif string.find(name, "module") or subgroup == "module" then
        border = "tech-module"
    elseif string.find(name, "plate") or string.find(name, "alloy") then
        border = "tech-alloy"
    end
    local border_path = "__dark-matter-replicators-reborn__/graphics/icons/borders/" .. border .. ".png"
    local icons = {}
    table.insert(icons, { icon = border_path, icon_size = 128, scale = 1 })
    if target.icons and #target.icons > 0 then
        for _, icon_spec in ipairs(target.icons) do
            local spec = helpers.deep_copy(icon_spec)
            spec.icon_mipmaps = nil
            local isize = spec.icon_size or target.icon_size or 64
            if type(isize) ~= "number" or isize <= 0 then isize = 64 end
            local current_scale = spec.scale or 1
            spec.scale = current_scale * (64 / isize)
            if spec.shift then
                spec.shift = { spec.shift[1] * (64 / isize), spec.shift[2] * (64 / isize) }
            end
            table.insert(icons, spec)
        end
    else
        local icon_path = target.icon or "__dark-matter-replicators-reborn__/graphics/icons/tenemut.png"
        local isize = target.icon_size or 64
        if type(isize) ~= "number" or isize <= 0 then isize = 64 end
        table.insert(icons, { icon = icon_path, icon_size = isize, scale = 64 / isize })
    end
    return icons
end

-- ══════════════════════════════════════════════════════════════════
-- Main generation
-- ══════════════════════════════════════════════════════════════════

-- v3.6.0: research pack order helper (cosmetic).
local function add_research_pack(research_packs, pack, is_dmr_item)
    local order = helpers.get_startup_setting("dmrsa-research-pack-order", "DMR Item First")
    if order == "Science Pack First" and is_dmr_item then
        table.insert(research_packs, 1, pack)
    else
        table.insert(research_packs, pack)
    end
end

local function tier_material_pack(tier)
    if tier <= 1 then return gprefix .. "tenemut" end
    if tier == 2 then return gprefix .. "dark-matter-scoop" end
    if tier == 3 then return gprefix .. "dark-matter-transducer" end
    return gprefix .. "matter-conduit"
end

function MirrorGenerator.generate()
    helpers.info("Starting MIRROR (v4.0) dynamic generation...")

    -- 1. Init solver state
    CostSolver.initialize_base_resources()
    CostSolver.build_recipe_map()
    CostSolver.build_tech_map()

    -- 2. Targets (already filtered by v4.0 exclusions in target-mapper)
    local targets = TargetMapper.get_potential_replication_targets()
    local fluid_qty = helpers.get_startup_setting("replication-fluid-quantity", 25)
    local require_orig = helpers.get_startup_setting("dmrsa-require-original-tech", true)

    -- v4.2 (B2, user-approved 2026-08-22): cost-model constants.
    --   CT_MULT   = time multiplier over the assembler reference, across the
    --               board (no mass-use split).
    --   BAND_LO/HI = per-tier time bands (nominal seconds; real time divides
    --               by the replicator's crafting_speed). FIXED — the machine
    --               multiplier pushes the raw cost, the bands stay fixed.
    --   MACHINE_MULT = per-tier multiplier for machine-layer items (entities
    --               with crafting / infra types): 1.5x t1 → 3.5x t5.
    local CT_MULT = { [1] = 3, [2] = 4, [3] = 5, [4] = 6, [5] = 7 }
    -- v4.2 (B2 refinement): bands ×1.33 — with speed_factor 1.6 the real
    -- times across tiers land ~2-3x slower than the first B2 pass (which
    -- felt too fast: 1.6-12s everywhere). New nominal bands:
    -- 2.7-16 / 5.3-32 / 10.6-64 / 20-120 / 33.3-200s → real ~2.7-30.5s.
    local BAND_LO = { [1] = 2.7, [2] = 5.3, [3] = 10.6, [4] = 20, [5] = 33.3 }
    local BAND_HI = { [1] = 16, [2] = 32, [3] = 64, [4] = 120, [5] = 200 }
    local MACHINE_MULT = { [1] = 1.5, [2] = 2, [3] = 2.5, [4] = 3, [5] = 3.5 }

    -- v4.2 (B2): machine-layer detection — entities whose prototype type is
    -- infrastructure (solar panels, steam engines, labs, turrets...) or ANY
    -- entity with crafting capabilities catches every mod machine built on
    -- standard prototype types automatically (Bob's/Angel's/SE/factorissimo
    -- factories included via their entity types).
    local MACHINE_TYPES = {
        ["assembling-machine"] = true, ["furnace"] = true, ["mining-drill"] = true,
        ["lab"] = true, ["centrifuge"] = true, ["rocket-silo"] = true,
        ["reactor"] = true, ["heat-exchanger"] = true, ["boiler"] = true,
        ["generator"] = true, ["steam-engine"] = true, ["steam-turbine"] = true,
        ["offshore-pump"] = true, ["roboport"] = true, ["beacon"] = true,
        ["radar"] = true, ["turret"] = true, ["artillery-turret"] = true,
        ["solar-panel"] = true, ["accumulator"] = true, ["storage-tank"] = true,
        ["pump"] = true, ["electric-energy-interface"] = true,
        ["burner-generator"] = true,
    }
    local machine_entities = {}
    for kind, tbl in pairs(data.raw) do
        if type(tbl) == "table" then
            for e_name, e in pairs(tbl) do
                if type(e) == "table" and (MACHINE_TYPES[kind] or e.crafting_categories or e.crafting_speed) then
                    machine_entities[e_name] = true
                end
            end
        end
    end
    local function is_machine_item(name, target)
        local proto = data.raw[target.type] and data.raw[target.type][name]
        if proto and proto.place_result and machine_entities[proto.place_result] then return true end
        if MACHINE_TYPES[target.type] then return true end
        return machine_entities[name] or false
    end

    -- item -> entry: { recipe_name, tier, target, planet_suffix, item_category }
    local items = {}
    local planetary_unlocks = { vulcanus = {}, fulgora = {}, gleba = {}, aquilo = {} }

    -- 3. Generate replication recipes for every target
    local recipe_count = 0
    for name, target in pairs(targets) do
        local solved = CostSolver.solve_cost(name)
        if not solved then
            helpers.debug("Mirror: no cost solution for '" .. name .. "', skipping")
            goto continue_item
        end

        local dark_matter_cost = solved.dark_matter
        local time_cost = solved.time
        local tier = solved.tier or 1
        -- v4.2 refino (original-mod study): los replicadores DMR son
        -- replicables — cada uno cae en su PROPIO tier (replicator-1 → t1...
        -- replicator-5 → t5), como el original (device3-5 upgrade=true).
        local REPLICATOR_TIER = {
            ["dmrsa-replicator-1"] = 1, ["dmrsa-replicator-2"] = 2,
            ["dmrsa-replicator-3"] = 3, ["dmrsa-replicator-4"] = 4,
            ["dmrsa-replicator-5"] = 5,
        }
        if REPLICATOR_TIER[name] then tier = REPLICATOR_TIER[name] end
        -- v4.0: dmrsa-tenemut is only replicable at tier 5 ("Mastery of Dark
        -- Matter") — the raw material stays a mining resource through tiers
        -- 1-4, and becomes replicable only with the tier-5 machine.
        if name == gprefix .. "tenemut" then
            tier = 5
        end
        -- v4.2 fix (gate-test dump 2026-08-23): science packs FORCED to their
        -- progression tier (same rule as Individual mode) — the cost-solver
        -- follows their ingredient chains (chemical needs advanced circuits...)
        -- and silently inflates them to tier 4-5.
        local sci_forced = PACK_LEVELS[name] or MOD_PACK_LEVELS[name]
        if sci_forced then tier = sci_forced end
        if tier > 5 then tier = 5 end
        if tier < 1 then tier = 1 end

        -- Planet routing (unchanged from v3.7.x): organic/planetary items go to
        -- their planet replicator; they never become mirror/baseline targets.
        local item_proto = data.raw[target.type] and data.raw[target.type][name]
        local is_organic = false
        if mods["space-age"] and item_proto then
            if item_proto.spoil_ticks or item_proto.spoil_to or item_proto.spoil_result then
                is_organic = true
            end
        end

        local planet_suffix = nil
        if mods["space-age"] then
            if is_organic or string.find(name, "yumako") or string.find(name, "jellynut")
               or name == "spoiled-organic-substrate" or name == "agricultural-science-pack"
               or name == "nutrients" then
                planet_suffix = "gleba"
            elseif string.find(name, "tungsten") or name == "calcite"
                   or name == "metallurgic-science-pack" or string.find(name, "molten%-")
                   or name == "foundry" or name == "lava" then
                planet_suffix = "vulcanus"
            elseif name == "superconducting-cable" or name == "electromagnetic-science-pack"
                   or (string.find(name, "scrap") and not string.find(name, "spaceship")) then
                planet_suffix = "fulgora"
            elseif name == "ice" or string.find(name, "lithium")
                   or string.find(name, "fluoroketone") or name == "fluorine"
                   or name == "cryogenic-science-pack" then
                planet_suffix = "aquilo"
            end
        end

        -- Category: VISUAL ONLY in v4.0 (no tier gating)
        local item_category = get_item_category(name, target)
        local recipe_name = gprefix .. "repl-" .. name
        local loc_prefix = get_loc_prefix(name, target)

        local recipe_subgroup
        if planet_suffix then
            recipe_subgroup = gprefix .. "replication-resources"
        elseif item_category and repltypes[item_category] then
            recipe_subgroup = gprefix .. "replication-" .. item_category
        else
            recipe_subgroup = gprefix .. "replication-tier-" .. tier
        end

        local result_amount = 1
        if target.type == "fluid" then
            result_amount = fluid_qty
        end

        -- v4.2 (B2, user-approved 2026-08-22): NEW COST MODEL.
        --   base    = min(vanilla_energy, solver_tax) — never pricier than
        --             crafting it nor than its own recipe chain (the solver's
        --             machine-efficiency flavour survives where the chain is
        --             cheaper than vanilla — smelting stays cheap).
        --   time    = clamp(base × CT(tier) × machine, lo, hi)
        --   FLUID LOT CLAMP: ×fluid_qty happens BEFORE the band clamp, so a
        --             0.03s water unit floors to ~2s PER LOT, not 50s/lot.
        --   machines (entities with crafting / infra types) pay ×2 (flat in
        --             the core; per-tier machine multiplier lands at the
        --             close of the B2 package).
        local base_e = solved.dark_matter or 1
        local orig_recipe = data.raw.recipe[name]
        if orig_recipe then
            local ve = orig_recipe.energy_required
            if not ve and orig_recipe.normal then ve = orig_recipe.normal.energy_required end
            if ve and ve > 0 then base_e = math.min(base_e, ve) end
        end
        -- v4.2 (B2, punto 4 del usuario): MACHINE multiplier PER TIER — the
        -- layer grows with the tier (1.5x t1 → 3.5x t5). The bands stay FIXED
        -- (2-12 / 4-24 / 8-48 / 15-90 / 25-150): the multiplier pushes the raw
        -- cost up, the fixed hi caps the worst case (a tier-5 machine never
        -- exceeds 150s nominal = ~9s real at speed 16x).
        local mm = 1
        if is_machine_item(name, target) then mm = MACHINE_MULT[tier] end
        local raw_cost = base_e * CT_MULT[tier] * mm
        if target.type == "fluid" then raw_cost = raw_cost * fluid_qty end
        -- v4.2 (mejora 6, user): la DIFICULTAD también escala los tiempos de
        -- replicación — replic_mult (Easy 1.0 / Medium 1.5 / High 2.0 /
        -- Very Hard 3.0) multiplica raw Y bandas (todo sube, no solo el raw).
        -- El cap por dificultad (get_replication_time_cap) sigue como red.
        local replic_mult = helpers.get_research_difficulty_values().replic_mult or 1
        raw_cost = raw_cost * replic_mult
        dark_matter_cost = math.max(BAND_LO[tier] * replic_mult, math.min(BAND_HI[tier] * replic_mult, raw_cost))
        dark_matter_cost = math.max(1, math.ceil(dark_matter_cost))
        local time_cap = helpers.get_replication_time_cap()
        if dark_matter_cost > time_cap then dark_matter_cost = time_cap end
        time_cost = math.max(0.1, tonumber(string.format("%.2f", time_cost)))

        local repl_recipe = {
            type = "recipe",
            name = recipe_name,
            localised_name = {
                "recipe-name.dmrsa-replication-recipe",
                { loc_prefix .. "." .. name }
            },
            energy_required = dark_matter_cost,
            ingredients = {},
            results = {
                { type = target.type == "fluid" and "fluid" or "item", name = name, amount = result_amount }
            },
            enabled = false,
            hidden = false,
            subgroup = recipe_subgroup,
            order = "z[" .. name .. "]"
        }
        -- Factorio 2.1: categories array (no dual-compat in v4.0)
        if planet_suffix then
            repl_recipe.categories = { gprefix .. "replication-" .. planet_suffix }
        else
            repl_recipe.categories = { gprefix .. "replication-" .. tier }
        end

        -- v4.1.0 (Quality Refiner): by default the replicator is faithful — it
        -- replicates matter AS IT KNOWS IT (normal quality). Quality output on
        -- the replicator itself is opt-in via dmrsa-replicator-quality
        -- (permissive mode); the dedicated Quality Refiner is the DMR path to
        -- quality. Fluids have no quality, so the field never applies to them.
        local q_allow = helpers.get_startup_setting("dmrsa-replicator-quality", "Normal only")
        if q_allow ~= "Allow quality" and target.type ~= "fluid" then
            repl_recipe.quality = "normal"
        end

        if name == "promethium-science-pack" then
            repl_recipe.surface_conditions = { { property = "gravity", max = 0 } }
        end

        local category_key = planet_suffix and (gprefix .. "replication-" .. planet_suffix) or (gprefix .. "replication-" .. tier)
        if not data.raw["recipe-category"][category_key] then
            helpers.warn("Mirror: skipping '" .. name .. "': crafting category '" .. category_key .. "' not found.")
            goto continue_item
        end

        data:extend({ repl_recipe })
        recipe_count = recipe_count + 1

        -- Register for mirror/baseline/planetary
        if planet_suffix then
            table.insert(planetary_unlocks[planet_suffix], recipe_name)
        else
            items[name] = {
                recipe_name = recipe_name,
                tier = tier,
                target = target,
                item_category = item_category,
            }
        end

        ::continue_item::
    end
    helpers.info("Mirror: generated " .. recipe_count .. " replication recipes.")

    -- 4. Build reverse map: original tech -> [replicable items]
    -- Walk every technology's unlock-recipe effects. An item is keyed by its
    -- original recipe name (== item name for item/fluid results).
    local tech_items = {}  -- tech_name -> { [item] = entry }
    for tech_name, tech in pairs(data.raw.technology) do
        if not tech.hidden then
            for _, eff in ipairs(tech.effects or {}) do
                if eff.type == "unlock-recipe" and eff.recipe then
                    local entry = items[eff.recipe]
                    if entry then
                        tech_items[tech_name] = tech_items[tech_name] or {}
                        tech_items[tech_name][eff.recipe] = entry
                    end
                end
            end
        end
    end

    -- 4b. v4.2: process-output tech mapping — items that are OUTPUTS of a
    -- same-mod processing recipe inherit that recipe's unlocking tech.
    -- Root cause fix (dump 4.1.0, Angel's full + planetaris): overhaul mods
    -- do NOT unlock a recipe named after every output (angels-gas-hydrogen is
    -- a co-output of angels-water-separation, unlocked by
    -- angels-basic-chemistry). The old 1:1 item↔recipe-name assumption made
    -- all such outputs fall to the baseline (materials-N), flooding
    -- replication-materials-1 with 108 items (dump-verified).
    -- Guards: (a) producing recipe must share the item's mod prefix —
    -- cross-mod byproducts can't attach foreign techs; (b) minable resources
    -- never inherit (they are mined, not crafted); (c) recycling/barreling
    -- recipes excluded (same class as build_recipe_map).
    local recipe_unlocks = {}   -- recipe name -> visible tech names
    for tech_name, tech in pairs(data.raw.technology) do
        if (not tech.hidden) and (not string.find(tech_name, "dmrsa%-")) then
            for _, eff in ipairs(tech.effects or {}) do
                if eff.type == "unlock-recipe" and eff.recipe then
                    recipe_unlocks[eff.recipe] = recipe_unlocks[eff.recipe] or {}
                    table.insert(recipe_unlocks[eff.recipe], tech_name)
                end
            end
        end
    end

    local item_process_techs = {}  -- item -> visible tech names
    for recipe_name, recipe in pairs(data.raw.recipe) do
        if string.find(recipe_name, "dmrsa%-") then goto continue_recipe end
        if recipe_name == "recycling" or string.find(recipe_name, "%-recycling$") then
            goto continue_recipe
        end
        if string.find(recipe_name, "empty%-") or string.find(recipe_name, "%-unbarrel") then
            goto continue_recipe
        end

        local results = recipe.results
        if recipe.normal and recipe.normal.results then
            results = recipe.normal.results
        end
        if not results then goto continue_recipe end

        local unlocks = recipe_unlocks[recipe_name]
        if not unlocks or #unlocks == 0 then goto continue_recipe end

        for _, res in ipairs(results) do
            local res_name = res.name or res[1]
            if res_name and items[res_name] and not is_minable_resource(res_name) then
                if mod_prefix(res_name) == mod_prefix(recipe_name) then
                    local tlist = item_process_techs[res_name]
                    if not tlist then
                        tlist = {}
                        item_process_techs[res_name] = tlist
                    end
                    for _, tn in ipairs(unlocks) do
                        local already = false
                        for _, e in ipairs(tlist) do if e == tn then already = true break end end
                        if not already then table.insert(tlist, tn) end
                    end
                end
            end
        end
        ::continue_recipe::
    end

    -- 5. Assign every item to its BEST original tech (highest science level)
    -- Items with no original tech fall to the baseline (materials techs).
    --
    -- v4.0: techs ending in "-N" (e.g. angels-chlorine-processing-1..4) are
    -- treated by Factorio as LEVELS of a single base technology. Generating
    -- one mirror per level makes Factorio group them as one composite tech
    -- whose levels must be CONTIGUOUS — if a middle level (say -3) unlocks no
    -- replicable items, its mirror is skipped and the chain breaks with
    -- "Non-contiguous levels: 2, followed by 4". Fix: normalize every
    -- "-<digits>" suffix to its base name, so the whole chain maps to ONE
    -- mirror tech (prereq = deepest existing level).
    local function normalize_tech_base(name)
        return string.gsub(name, "%-%d+$", "")
    end

    -- v4.2 (dump audit 2026-08-22): manual tech routing for items whose
    -- unlock graph is warped by mod re-gates in this modlist:
    --   * TECH_REDIRECT[item] = original tech whose MIRROR gates this item
    --     (an item may be homonym-unlocked by a wrong tech after Angel's/
    --     planetaris re-gate them; forcing the mirror keeps progression sane).
    --   * BASELINE_FORCE[item] = skip mirror entirely; the item falls to the
    --     materials baseline at its cost-solver tier.
    -- Dump evidence:
    --   carbon      → homonym unlock re-gated under tungsten-carbide (vulcanus);
    --                 carbon is a space/asteroid/planetaris material.
    --   spaceship-scrap → was caught by the fulgora "scrap" matcher; space item.
    --   burner-pumpjack → only unlockable via cryovolcanic-power (aquilo L5) in
    --                 this modlist; an early oil pumpjack gated to the endgame.
    local TECH_REDIRECT = {
        ["carbon"] = "space-platform",
        ["spaceship-scrap"] = "space-platform",
    }
    local BASELINE_FORCE = {
        ["burner-pumpjack"] = true,
    }

    -- v4.2 (B1, opción C del usuario): split LEVELED tech chains into one
    -- mirror PER LEVEL instead of collapsing them to the base. Dump-verified:
    -- every level of these chains has ≥1 replicable item (no hollow levels),
    -- so the mirror chain stays contiguous (base=1, -N=N ... automation (1),
    -- automation-2 (2), ...). 7 chains total (bob-oil-processing does not
    -- exist in this modlist; angels-oil-processing/bob-electronics have no
    -- levels — nothing to split there).
    local SPREAD_TECHS = {
        automation = true,
        logistics = true,
        ["logistic-system"] = true,
        ["bob-robo-modular"] = true,
        ["angels-metallurgy"] = true,
        ["angels-advanced-chemistry"] = true,
        ["angels-nitrogen-processing"] = true,
    }

    local item_tech = {}       -- item -> best original tech name (normalized)
    local baseline_by_tier = { [1] = {}, [2] = {}, [3] = {}, [4] = {}, [5] = {} }
    local mirror_groups = {}   -- tech_base -> { [item] = entry }
    local mirror_deepest = {}  -- tech_base -> deepest original tech name (prereq)

    for item, entry in pairs(items) do
        local techs_for_item = {}
        -- v4.2: dump-audit overrides (see TECH_REDIRECT / BASELINE_FORCE above)
        if BASELINE_FORCE[item] then
            -- forced baseline: leave techs_for_item empty
        elseif TECH_REDIRECT[item] then
            table.insert(techs_for_item, TECH_REDIRECT[item])
        else
            for tech_name in pairs(tech_items) do
                if tech_items[tech_name][item] then
                    table.insert(techs_for_item, tech_name)
                end
            end
            -- v4.2: process-output fallback — items without a recipe named after
            -- them (overhaul-mod gas/liquid/ore outputs) inherit the tech of their
            -- same-mod producing recipe (e.g. angels-gas-hydrogen →
            -- angels-basic-chemistry). This keeps them behind THEIR tech instead
            -- of flooding the baseline materials.
            if #techs_for_item == 0 then
                for _, tn in ipairs(item_process_techs[item] or {}) do
                    table.insert(techs_for_item, tn)
                end
            end
        end
        if #techs_for_item == 0 then
            local t = math.max(1, math.min(5, entry.tier))
            table.insert(baseline_by_tier[t], entry.recipe_name)
        else
            -- Best = highest science level; among equal, prefer the DEEPEST
            -- chain level (so the prereq gate is the last one researched).
            local best, best_lvl, best_ord = nil, -1, -1
            for _, tname in ipairs(techs_for_item) do
                local lvl = MirrorGenerator.get_tech_science_level(tname) or 0
                local _, _, num = string.find(tname, "%-(" .. "%d+" .. ")$")
                local ord = num and tonumber(num) or 0
                if lvl > best_lvl or (lvl == best_lvl and ord > best_ord) then
                    best, best_lvl, best_ord = tname, lvl, ord
                end
            end
            if not best then best = techs_for_item[1] end
            local base = normalize_tech_base(best)
            -- v4.2 (B1): spread chains keep their LEVELED mirror (automation-2
            -- gets its own mirror instead of joining "automation").
            if SPREAD_TECHS[base] then base = best end
            item_tech[item] = base
            mirror_groups[base] = mirror_groups[base] or {}
            mirror_groups[base][item] = entry
            -- Track the deepest level as the original-tech prereq
            local cur = mirror_deepest[base]
            if not cur then
                mirror_deepest[base] = best
            else
                local _, _, cur_num = string.find(cur, "%-(" .. "%d+" .. ")$")
                local _, _, new_num = string.find(best, "%-(" .. "%d+" .. ")$")
                local cn = cur_num and tonumber(cur_num) or 0
                local nn = new_num and tonumber(new_num) or 0
                if nn > cn then mirror_deepest[base] = best end
            end
        end
    end

    -- 6. Generate one mirror tech per original tech (threshold=1)
    local tech_count = 0
    local diff_vals = helpers.get_research_difficulty_values()

    for tech_name, group in pairs(mirror_groups) do
        local item_count = 0
        for _ in pairs(group) do item_count = item_count + 1 end
        if item_count == 0 then goto continue_tech end

        -- v4.0: for "-N" chains (angels-chlorine-processing-1..4) the group key
        -- is the NORMALIZED base name; the real prototype that exists in
        -- data.raw is the deepest level (mirror_deepest). Use it for science
        -- level, tree depth, and the original-tech prerequisite.
        local orig_tech = mirror_deepest[tech_name] or tech_name

        -- v4.2 fix (gate-test dump 2026-08-23): science-pack mirrors are
        -- FORCED to their progression tier (auto/logistic=1, military=2,
        -- chemical/production/utility=3, planetary=4, space/cryo/prom=5).
        -- Exact-table lookup only — no name heuristics on arbitrary items.
        local forced_science_tier
        for item in pairs(group) do
            local lvl = PACK_LEVELS[item] or MOD_PACK_LEVELS[item]
            if lvl and (not forced_science_tier or lvl > forced_science_tier) then
                forced_science_tier = lvl
            end
        end
        -- v4.2 fix (gate-test dump 2026-08-23): science packs FORCED to their
        -- progression tier (auto/logistic=1, military=2, chem/prod/util=3,
        -- planetary=4, space/cryo/prom=5) — the SCL of the tech that unlocks a
        -- pack is NOT the pack's own progression tier (chemical-pack tech
        -- researches with tier-1 packs but the PACK is tier-3 progression).
        if forced_science_tier then
            tier = forced_science_tier
        elseif SPREAD_TECHS[normalize_tech_base(tech_name)] then
            -- v4.2 (B1): leveled mirror — tier is governed by the ITEMS' cost
            -- tiers (the replication-N machine gate), NOT the original tech's
            -- science level. Otherwise assembly-machine-6 would unlock behind
            -- replication-1 (free endgame machine).
            local max_t = 1
            for _, entry in pairs(group) do
                if entry.tier and entry.tier > max_t then max_t = entry.tier end
            end
            tier = max_t
        else
            tier = MirrorGenerator.get_tech_science_level(orig_tech)
            if not tier then
                -- fallback: max item tier in the group
                local max_t = 1
                for _, entry in pairs(group) do
                    if entry.tier and entry.tier > max_t then max_t = entry.tier end
                end
                tier = max_t
            end
        end
        -- v4.0: when dmrsa-require-original-tech is ON, the original tech is a
        -- DIRECT prerequisite of this mirror tech. The mirror's tier must be
        -- at least the original tech's REAL depth in the research tree, or
        -- Factorio rejects the tech with "Non-contiguous levels: N, followed
        -- by M" (science-pack level can be shallower than tree depth — e.g.
        -- angel's chlorine-processing maps to tier 2 by packs but sits at
        -- depth 4). Clamp to the tree depth when the original is required.
        -- v4.2 fix (gate-test dump 2026-08-23): tree-depth clamp REMOVED.
        -- It was added in the 4.0 gate test as a belt-and-suspenders against
        -- "Non-contiguous levels", but with real modlists it inflates nearly
        -- every mirror to tier 5 (dump: chemical-science-pack sits at depth
        -- 22, promethium at depth 80 → 458/474 mirrors ended in replication-5,
        -- incl. logistic/chemical/production/utility). The REAL contiguity
        -- hazard was leveled `-N` chains, which normalize_tech_base() already
        -- handles by grouping them into ONE mirror. If Factorio ever rejects
        -- a specific mirror for contiguity, fix THAT chain — not the whole
        -- tree via depth.
        tier = math.max(1, math.min(5, tier))

        local mirror_name = gprefix .. "mirror-" .. tech_name
        local tech_effects = {}
        local rep_item, rep_target = nil, nil
        for item, entry in pairs(group) do
            table.insert(tech_effects, { type = "unlock-recipe", recipe = entry.recipe_name })
            if not rep_item then rep_item, rep_target = item, entry.target end
        end

        -- Prereqs: machine + materials + original tech (if setting ON)
        local prerequisites = {}
        local function add_prereq(tbl, p)
            for _, v in ipairs(tbl) do if v == p then return end end
            table.insert(tbl, p)
        end
        add_prereq(prerequisites, gprefix .. "replication-" .. tier)
        add_prereq(prerequisites, gprefix .. "replication-materials-" .. tier)
        if require_orig then
            if data.raw.technology[orig_tech] then
                add_prereq(prerequisites, orig_tech)
            end
        end

        -- Research packs: DMR material of the tier (+ planetary pack for aquilo T5)
        local research_packs = {}
        add_research_pack(research_packs, { tier_material_pack(tier), 1 }, true)
        if tier == 5 and string.find(orig_tech, "cryogenic") then
            add_research_pack(research_packs, { "cryogenic-science-pack", 1 }, false)
        end

        local repetitions = 10 * tier
        -- v4.2 refino (original-mod study): SIN ×item_count — el original
        -- cobra research por TECH (tier×25), no por item del grupo. Nuestros
        -- grupos grandes (materials-1 25 items) pagaban 10×tier×25 = 250 reps;
        -- ahora 10×tier fijo (la dificultad sigue en diff_vals.cost/25).
        local reps_count = math.max(1, math.ceil(repetitions * (diff_vals.cost / 25)))
        local tech_time = math.max(1, math.ceil(diff_vals.time * 5))

        local tech_proto = {
            type = "technology",
            name = mirror_name,
            localised_name = {
                "technology-name.dmrsa-mirror-tech",
                { "technology-name." .. orig_tech }
            },
            localised_description = {
                "technology-description.dmrsa-mirror-tech",
                { "technology-name." .. orig_tech }
            },
            effects = tech_effects,
            prerequisites = prerequisites,
            unit = {
                count = reps_count,
                ingredients = research_packs,
                time = tech_time
            },
            order = "a-r-m-" .. tier .. "[" .. tech_name .. "]"
        }

        -- Icon from the representative item
        if rep_item and rep_target then
            tech_proto.icons = get_tech_icons(rep_item, rep_target, tier)
            tech_proto.icon_size = 128
        end

        -- Fail-safe validation
        local tech_valid = true
        for _, pack in ipairs(research_packs) do
            if not helpers.item_exists(pack[1]) then
                helpers.warn("Mirror: skipping tech '" .. mirror_name .. "': pack '" .. pack[1] .. "' not found.")
                tech_valid = false
                break
            end
        end
        if tech_valid then
            for _, prereq in ipairs(prerequisites) do
                if not data.raw.technology[prereq] then
                    helpers.warn("Mirror: skipping tech '" .. mirror_name .. "': prereq '" .. prereq .. "' not found.")
                    tech_valid = false
                    break
                end
            end
        end

        if tech_valid then
            local ok, err = pcall(data.extend, data, { tech_proto })
            if ok then
                tech_count = tech_count + 1
            else
                helpers.error("Mirror: could not create tech '" .. mirror_name .. "': " .. tostring(err))
                -- fallback: baseline unlock
                for item, entry in pairs(group) do
                    local t = math.max(1, math.min(5, tier))
                    table.insert(baseline_by_tier[t], entry.recipe_name)
                end
            end
        else
            -- fallback: baseline unlock
            for item, entry in pairs(group) do
                local t = math.max(1, math.min(5, tier))
                table.insert(baseline_by_tier[t], entry.recipe_name)
            end
        end

        ::continue_tech::
    end

    helpers.info("Mirror: generated " .. tech_count .. " mirror technologies.")

    -- 7. Attach baseline recipes to the materials techs (one per tier)
    -- The materials techs are defined in technologies.lua with empty effects;
    -- here we fill them with the baseline unlocks.
    local baseline_count = 0
    for tier = 1, 5 do
        local tech = data.raw.technology[gprefix .. "replication-materials-" .. tier]
        local unlocks = baseline_by_tier[tier]
        if tech and unlocks and #unlocks > 0 then
            tech.effects = tech.effects or {}
            for _, recipe_name in ipairs(unlocks) do
                local already = false
                for _, eff in ipairs(tech.effects) do
                    if eff.recipe == recipe_name then already = true; break end
                end
                if not already then
                    table.insert(tech.effects, { type = "unlock-recipe", recipe = recipe_name })
                    baseline_count = baseline_count + 1
                end
            end
        elseif not tech then
            helpers.warn("Mirror: materials tech '" .. gprefix .. "replication-materials-" .. tier .. "' not found!")
        end
    end
    helpers.info("Mirror: attached " .. baseline_count .. " baseline recipes to materials techs.")

    return planetary_unlocks
end

return MirrorGenerator
