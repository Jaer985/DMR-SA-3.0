-- prototypes/fixes/pass-orphans.lua
-- PASS 3: Handle orphaned DMR technologies (empty prereqs).
-- Find dmrsa-* technologies that have zero prerequisites left after stripping.
-- Reassign their recipe unlocks to the baseline replication-{tier} tech,
-- then make the orphan hidden and harmless.
require("defines")
local helpers = require("lib.helpers")

local prefix_raw = gprefix
local prefix_pat = prefix_raw:gsub("%-", "%%-")

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