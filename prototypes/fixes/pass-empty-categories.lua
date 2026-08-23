-- prototypes/fixes/pass-empty-categories.lua
-- PASS 5: Auto-hide empty replication category subgroups (v3.6.3).
-- If a replication category (ore, element, chemical, military, ...) ended up
-- with ZERO generated recipes (e.g. all its items were step-filtered, or the
-- player's mod list has nothing in that category), remove its item-subgroup
-- so the replicator crafting menu doesn't show an empty tab. The tier
-- fallback subgroups (replication-tier-1..5) are never removed because they
-- always have recipes.
require("defines")
local helpers = require("lib.helpers")

local gprefix_raw = gprefix

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
    local sg_name = gprefix_raw .. "replication-" .. cat
    if count_recipe_subgroup(sg_name) == 0 then
        -- Remove the empty subgroup so it doesn't render as an empty tab
        data.raw["item-subgroup"][sg_name] = nil
        empty_category_count = empty_category_count + 1
    end
end
if empty_category_count > 0 then
    helpers.info("data-final-fixes: hid " .. empty_category_count .. " empty replication category subgroup(s).")
end