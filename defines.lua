modname = "dmrsa"
gprefix = modname .. "-"

-- Version detection for dual compatibility (Factorio 2.0 + 2.1)
-- 2.1 renamed recipe.category (string) → recipe.categories (array)
-- We detect the format from base game recipes at data stage.
-- In data.lua / data-updates.lua / data-final-fixes.lua the `data` global
-- is available, so this helper should only be called after data is populated.
function dmrsa_is_v21()
    if not data or not data.raw or not data.raw.recipe then
        return false
    end
    -- Check a known base recipe: 2.1 uses categories array, 2.0 uses category string
    local iron_plate = data.raw.recipe["iron-plate"]
    if iron_plate then
        return iron_plate.categories ~= nil
    end
    -- Fallback: check any recipe
    for _, recipe in pairs(data.raw.recipe) do
        if recipe.categories then
            return true
        end
    end
    return false
end
