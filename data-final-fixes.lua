-- data-final-fixes.lua
-- Runs AFTER all mods have finished their data-updates phase.
--
-- PASS 0: Dynamic recipe generation (moved here from data-updates in v3.7.0 A6).
-- PASS 1: Strip invalid technology prerequisites from all DMR technologies that
-- may have been removed by other mods in their own data-final-fixes phase.
--
-- PASS 2: Re-validate every technology in the game that lists a dmrsa technology
-- as its prerequisite -- prevents cascading failures.
--
-- PASS 3: Handle orphaned DMR technologies (empty prereqs) by reassigning their
-- unlocks to the baseline replication-{tier} tech.

require("defines")
local helpers = require("lib.helpers")

-- ── PASS 0: Dynamic recipe generation (v3.7.0 A6) ──
-- Moved from data-updates.lua. The generator MUST run here, AFTER overhaul
-- mods (Bob's, Angel's, K2) have defined their recipes AND their unlock-recipe
-- tech effects in their own data-updates/data-final-fixes. Running it in
-- data-updates meant:
--   1. recipe_tech_map was incomplete → 118 items (with Bob's) lost their
--      original-tech prereq (silently replicable from tier 1).
--   2. recipe_map resolved partial recipes → 367 items were under-tiered
--      (dump-verified: bob-destroyer-robot assigned 1, real 5; solar-panel
--      assigned 1, real 4; ...).
-- Optional dependencies in info.json (? bobplates, ? bobwarfare, ...) force
-- THIS data-final-fixes to run after the overhaul mods' own.
-- v4.0: choose the generator by tech-distribution setting.
--   "Mirror" (default) → MirrorGenerator (árbol espejo: 1 tech por tech original,
--     materials techs, tier = science level de la tech original)
--   "Individual" (legacy) → DynamicGenerator (1 tech por item, como v3.7.x)
-- The grouped-categories mode was REMOVED in v4.0.
local tech_dist = helpers.get_startup_setting("dmrsa-tech-distribution", "Mirror")
local planetary_unlocks
if tech_dist == "Individual" then
    local DynamicGenerator = require("prototypes.recipes.dynamic-generator")
    local baseline_unlocks = DynamicGenerator.generate()
    -- Attach baseline unlocks to their corresponding technology nodes
    for tier = 1, 5 do
        local tech_name = gprefix .. "replication-" .. tier
        local tech = data.raw.technology[tech_name]
        local unlocks = baseline_unlocks[tier]

        if tech and (not (tier == 3 and mods["space-age"])) and unlocks and #unlocks > 0 then
            tech.effects = tech.effects or {}
            for _, recipe_name in ipairs(unlocks) do
                table.insert(tech.effects, { type = "unlock-recipe", recipe = recipe_name })
            end
        elseif tier == 3 and mods["space-age"] and unlocks and #unlocks > 0 then
            -- Attach baseline Tier 3 unlocks to the three planetary technologies
            local planetary_techs = {
                gprefix .. "replication-vulcanus-tech",
                gprefix .. "replication-fulgora-tech",
                gprefix .. "replication-gleba-tech"
            }
            for _, p_tech_name in ipairs(planetary_techs) do
                local p_tech = data.raw.technology[p_tech_name]
                if p_tech then
                    p_tech.effects = p_tech.effects or {}
                    for _, recipe_name in ipairs(unlocks) do
                        table.insert(p_tech.effects, { type = "unlock-recipe", recipe = recipe_name })
                    end
                end
            end
        end
    end
else
    -- v4.0 MIRROR mode: MirrorGenerator handles recipes, mirror techs, AND the
    -- materials-tech baseline attachment internally. Returns planetary unlocks.
    local MirrorGenerator = require("lib.mirror-generator")
    planetary_unlocks = MirrorGenerator.generate()
end

-- Attach planetary unlocks to their corresponding planetary technology nodes
if mods["space-age"] and planetary_unlocks then
    for planet, unlocks in pairs(planetary_unlocks) do
        local tech_name = gprefix .. "replication-" .. planet .. "-tech"
        local tech = data.raw.technology[tech_name]
        if tech and unlocks and #unlocks > 0 then
            tech.effects = tech.effects or {}
            for _, recipe_name in ipairs(unlocks) do
                table.insert(tech.effects, { type = "unlock-recipe", recipe = recipe_name })
            end
        end
    end
end

local removed_count = 0
local fixed_count = 0

-- CRITICAL: In Lua patterns, '-' is a lazy quantifier (0 or more of preceding).
-- We MUST escape it in gprefix before using it in string.find/string.match.
-- Otherwise 'dmrsa-' would be interpreted as 'dmrs' + 'a' + lazy-quantifier.
local prefix_raw = gprefix                       -- "dmrsa-"
local prefix_pat = prefix_raw:gsub("%-", "%%-")   -- "dmrsa%-"

-- ── PASS 1: Strip missing prereqs from all dmrsa-* technologies ──
for tech_name, tech in pairs(data.raw.technology) do
    if string.find(tech_name, "^" .. prefix_pat) and tech.prerequisites then
        local valid = {}
        local seen = {}
        for _, prereq in ipairs(tech.prerequisites) do
            if data.raw.technology[prereq] and not seen[prereq] then
                seen[prereq] = true
                table.insert(valid, prereq)
            else
                helpers.log("data-final-fixes: Removed missing prerequisite '" .. prereq .. "' from '" .. tech_name .. "'")
                removed_count = removed_count + 1
            end
        end
        tech.prerequisites = valid
        fixed_count = fixed_count + 1
    end
end

-- ── PASS 2: Re-validate every technology that depends on dmrsa technologies ──
for tech_name, tech in pairs(data.raw.technology) do
    if tech.prerequisites then
        local changed = false
        local valid = {}
        local seen = {}
        for _, prereq in ipairs(tech.prerequisites) do
            if data.raw.technology[prereq] and not seen[prereq] then
                seen[prereq] = true
                table.insert(valid, prereq)
            elseif not data.raw.technology[prereq] then
                helpers.log("data-final-fixes: [cross-mod] Removed missing prereq '" .. prereq .. "' from '" .. tech_name .. "'")
                removed_count = removed_count + 1
                changed = true
            end
        end
        if changed then
            tech.prerequisites = valid
        end
    end
end

-- ── PASS 3: Handle orphaned DMR technologies (empty prereqs) ──
-- Find dmrsa-* technologies that have zero prerequisites left after stripping.
-- Reassign their recipe unlocks to the baseline replication-{tier} tech,
-- then make the orphan hidden and harmless.
local orphan_techs = {}
for tech_name, tech in pairs(data.raw.technology) do
    if string.find(tech_name, "^" .. prefix_pat) and tech.prerequisites and #tech.prerequisites == 0 then
        if tech_name ~= prefix_raw .. "replication-1" then
            table.insert(orphan_techs, tech_name)
        end
    end
end

for _, orphan_name in ipairs(orphan_techs) do
    local tech = data.raw.technology[orphan_name]
    if tech and tech.effects then
        -- Extract the replication tier from the orphan tech name
        -- Pattern targets: dmrsa-replication-N or dmrsa-grouped-repl-N-*
        local tier_match = string.match(orphan_name, prefix_pat .. "replication%-([1-5])")
            or string.match(orphan_name, prefix_pat .. "grouped%-repl%-([1-5])")
        -- Pattern for planetary grouped techs: dmrsa-grouped-repl-{planet}-{category}-tech
        -- These don't carry a tier digit, so extract the planet name instead.
        local planet_match = string.match(orphan_name, prefix_pat .. "grouped%-repl%-(%a+)%-(%a+)%-tech")

        local target_tech_name
        if tier_match then
            -- Tier 3 in SA still has the placeholder `dmrsa-replication-3` tech
            -- (hidden, empty effects) defined in technologies.lua, so it is a
            -- safe reassignment target. Previously this branch discarded unlocks
            -- silently; the placeholder is the lesser evil since the tech is
            -- hidden and its effects are inert until we add to them.
            if mods["space-age"] and tier_match == "3" then
                target_tech_name = prefix_raw .. "replication-3"
            else
                target_tech_name = prefix_raw .. "replication-" .. tier_match
            end
        elseif planet_match then
            target_tech_name = prefix_raw .. "replication-" .. planet_match .. "-tech"
        end

        -- Defensive: if neither pattern matched, we have an orphan tech whose
        -- name does not fit any known shape. Log it so we can extend the
        -- patterns instead of silently losing its unlocks.
        if not target_tech_name then
            helpers.warn("data-final-fixes: Orphaned tech '" .. orphan_name .. "' did not match tier or planet pattern; unlocks will be dropped")
        end

        -- Reassign unlocks to the target baseline tech
        if target_tech_name and data.raw.technology[target_tech_name] then
            local target = data.raw.technology[target_tech_name]
            target.effects = target.effects or {}
            for _, effect in ipairs(tech.effects) do
                local already = false
                for _, existing in ipairs(target.effects) do
                    if existing.recipe == effect.recipe then
                        already = true
                        break
                    end
                end
                if not already then
                    table.insert(target.effects, effect)
                end
            end
            helpers.log("data-final-fixes: Reassigned unlocks from orphaned tech '" .. orphan_name .. "' to '" .. target_tech_name .. "'")
        end

        -- Make the orphan tech hidden and cost-free
        tech.hidden = true
        tech.enabled = false
        tech.prerequisites = {}
        tech.unit = {
            count = 1,
            ingredients = { { prefix_raw .. "tenemut", 1 } },
            time = 1
        }
        helpers.log("data-final-fixes: Disabled orphaned technology '" .. orphan_name .. "'")
    end
end

helpers.log("data-final-fixes: Sanitized " .. fixed_count .. " DMR technologies, removed " .. removed_count .. " missing prerequisites.")

-- ── PASS 4: Ensure replication-lab accepts all planetary science packs ──
-- Space Age science packs are conditionally required by grouped technologies
-- (e.g. dmrsa-grouped-repl-vulcanus-*-tech needs metallurgic-science-pack).
-- The lab's base inputs are defined in prototypes/entities/replicators.lua;
-- this pass adds the planetary packs in data-final-fixes as a belt-and-suspenders
-- safety net to prevent "no lab will accept all science packs" errors.
if mods["space-age"] then
    local lab = data.raw.lab[prefix_raw .. "replication-lab"]
    if lab and lab.inputs then
        local sa_packs = {
            "metallurgic-science-pack",
            "electromagnetic-science-pack",
            "agricultural-science-pack",
            "cryogenic-science-pack",
            "space-science-pack",
            "promethium-science-pack"
        }
        for _, pack in ipairs(sa_packs) do
            local found = false
            for _, input in ipairs(lab.inputs) do
                if input == pack then found = true; break end
            end
            if not found then
                table.insert(lab.inputs, pack)
                helpers.log("data-final-fixes: Added '" .. pack .. "' to replication-lab inputs")
            end
        end
        -- Defensive validation (v3.6.0): after the add-loop, every pack we
        -- intend the lab to accept must actually be present. If the lab or its
        -- inputs table was nil, or a pack insertion failed silently, warn so
        -- the player knows the lab may not accept all science packs.
        for _, pack in ipairs(sa_packs) do
            local present = false
            if lab.inputs then
                for _, input in ipairs(lab.inputs) do
                    if input == pack then present = true; break end
                end
            end
            if not present then
                helpers.warn("data-final-fixes: replication-lab does NOT accept '" .. pack .. "' — grouped techs requiring it may be unresearcheable!")
            end
        end
    else
        helpers.warn("data-final-fixes: replication-lab not found or has no inputs — cannot validate SA science pack acceptance!")
    end
end

-- ── PASS 5: Auto-hide empty replication category subgroups (v3.6.3) ──
-- If a replication category (ore, element, chemical, military, ...) ended up
-- with ZERO generated recipes (e.g. all its items were step-filtered, or the
-- player's mod list has nothing in that category), remove its item-subgroup
-- so the replicator crafting menu doesn't show an empty tab. The tier
-- fallback subgroups (replication-tier-1..5) are never removed because they
-- always have recipes.
local empty_category_count = 0
local category_subgroups = {
    "ore", "element", "shape", "alloy", "chemical", "organic",
    "module", "module-advanced", "science", "military", "military-advanced",
    "life", "exotic", "magic", "alien", "general"
}
local function count_recipe_subgroup(subgroup_name)
    local count = 0
    local recipes = data.raw.recipe
    if recipes then
        for _, recipe in pairs(recipes) do
            if recipe.subgroup == subgroup_name then
                count = count + 1
            end
        end
    end
    return count
end
for _, cat in ipairs(category_subgroups) do
    local sg_name = gprefix .. "replication-" .. cat
    if count_recipe_subgroup(sg_name) == 0 then
        -- Remove the empty subgroup so it doesn't render as an empty tab
        data.raw["item-subgroup"][sg_name] = nil
        empty_category_count = empty_category_count + 1
    end
end
if empty_category_count > 0 then
    helpers.info("data-final-fixes: hid " .. empty_category_count .. " empty replication category subgroup(s).")
end

-- ── PASS 6: REMOVED in v4.0 ──
-- The v3.7.0 A4 re-attach pass rebuilt recipe_tech_map from final data and
-- re-added missing original-tech prereqs. In v4.0 MIRROR mode this is no
-- longer needed: MirrorGenerator.generate() runs in data-final-fixes (after
-- all mods' data-updates/data-final-fixes thanks to the ? bob* optional deps),
-- builds its reverse map from the COMPLETE technology data, and each mirror
-- tech's prereq IS the original tech itself (when dmrsa-require-original-tech
-- is ON). The old failure mode (generation before other mods define their
-- unlock effects) cannot happen because we now generate from final data.
-- In legacy Individual mode, DynamicGenerator attaches original-tech prereqs
-- inline exactly as v3.7.x did.
