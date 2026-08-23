-- prototypes/fixes/pass-prereqs.lua
-- PASS 1: Strip invalid technology prerequisites from all DMR technologies
-- that may have been removed by other mods in their own data-final-fixes.
-- PASS 2: Re-validate every technology in the game that lists a dmrsa
-- technology as its prerequisite — prevents cascading failures.
require("defines")
local helpers = require("lib.helpers")

-- CRITICAL: In Lua patterns, '-' is a lazy quantifier (0 or more of preceding).
-- We MUST escape it in gprefix before using it in string.find/string.match.
-- Otherwise 'dmrsa-' would be interpreted as 'dmrs' + 'a' + lazy-quantifier.
local prefix_raw = gprefix                       -- "dmrsa-"
local prefix_pat = prefix_raw:gsub("%-", "%%-")   -- "dmrsa%-"

local removed_count = 0
local fixed_count = 0

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

helpers.log("data-final-fixes: Sanitized " .. fixed_count .. " DMR technologies, removed " .. removed_count .. " missing prerequisites.")