-- prototypes/fixes/pass-lab-inputs.lua
-- PASS 4: Ensure replication-lab accepts all planetary science packs.
-- Space Age science packs are conditionally required by grouped technologies
-- (e.g. dmrsa-grouped-repl-vulcanus-*-tech needs metallurgic-science-pack).
-- The lab's base inputs are defined in prototypes/entities/replicators.lua;
-- this pass adds the planetary packs in data-final-fixes as a belt-and-suspenders
-- safety net to prevent "no lab will accept all science packs" errors.
require("defines")
local helpers = require("lib.helpers")

local prefix_raw = gprefix

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