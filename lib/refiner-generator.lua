-- lib/refiner-generator.lua
-- v4.1.0: Quality Refiner dynamic recipes.
--
-- Para cada item replicable (recipe dmrsa-repl-<item> generada por el árbol
-- espejo), genera 4 recipes de refinado — una por escalón de calidad:
--   normal → uncommon (1%), uncommon → rare (0.5%), rare → epic (0.25%),
--   epic → legendary (0.1%).
--
-- Cada ciclo consume 1 item del escalón actual y devuelve, con probabilidades
-- independientes:
--   - el MISMO item (reintento) con probabilidad 1 - 0.05 - p
--   - el item +1 calidad con probabilidad p
--   - nada (5%: la pieza se destruye) — cuando ninguna probability acierta
--
-- Energía por ciclo = 3x la energía de la recipe de replicación del item
-- (v4.2 B2: antes x10 — con la reescala del cost-model, x10 = 6000s en
-- endgame, inoperable; x3 mantiene el premium de calidad jugable).
--
-- Solo se generan para items REPLICABLES (filosofía fiel: el refiner solo
-- puede refinar estructuras cuya replicación dominas — armas, vehículos y
-- demás excluidos del árbol espejo no aparecen aquí).
--
-- Gate: requiere un mod de calidad activo (data.raw["quality"]["uncommon"]);
-- sin él, generate() no hace nada.
local helpers = require("lib.helpers")
local gprefix = "dmrsa-"

local RefinerGenerator = {}

-- Escalones de calidad: probabilidad de éxito DECRECIENTE por escalón
-- (el 1% del diseño original baja a la mitad en cada salto).
local QUALITY_STEPS = {
    { from = "normal",    to = "uncommon",  p = 0.01 },   -- 1%
    { from = "uncommon",  to = "rare",      p = 0.005 },  -- 0.5%
    { from = "rare",      to = "epic",      p = 0.0025 }, -- 0.25%
    { from = "epic",      to = "legendary", p = 0.001 },  -- 0.1%
}
-- Probabilidad de destrucción por ciclo (independiente del éxito).
local LOSS_PROB = 0.05
-- Multiplicador de energía frente a la recipe de replicación original.
-- v4.2 (B2): 10 → 3 (ver cabecera — la reescala de costos hace x10 inoperable).
local ENERGY_MULT = 3

-- Placeable items use entity-name locale, everything else item-name.
local function get_loc_prefix(name)
    local item_proto = data.raw.item[name]
    if item_proto and item_proto.place_result then
        return "entity-name"
    end
    return "item-name"
end

function RefinerGenerator.generate()
    if not (data.raw["quality"] and data.raw["quality"]["uncommon"]) then
        helpers.info("Refiner: quality not enabled, skipping refining recipes.")
        return 0
    end

    local count = 0
    local prefix = gprefix .. "repl-"

    for recipe_name, recipe in pairs(data.raw.recipe) do
        if string.sub(recipe_name, 1, #prefix) == prefix then
            local res = recipe.results and recipe.results[1]
            if not (res and res.type == "item" and res.name) then
                goto continue_item
            end
            if not data.raw.item[res.name] then
                goto continue_item
            end
            -- Only non-secret replicable items: mirror generator attaches
            -- every target here; skip dmrsa-* own items defensively.
            if string.sub(res.name, 1, #gprefix) == gprefix then
                goto continue_item
            end

            local base_energy = recipe.energy_required or 1
            local loc_pref = get_loc_prefix(res.name)

            for _, step in ipairs(QUALITY_STEPS) do
                local retry_p = 1 - LOSS_PROB - step.p
                if retry_p < 0 then retry_p = 0 end

                -- Factorio 2.1 REQUIRES an icon on recipes whose results carry
                -- a `quality` field (the quality-refining recipe picker can't
                -- auto-detect the icon from a quality result). Reuse the source
                -- item's icon so the entry shows the item being refined.
                local item_proto = data.raw.item[res.name]
                local r_icon, r_icon_size, r_icons
                if item_proto.icons and #item_proto.icons > 0 then
                    local layers = {}
                    for _, spec in ipairs(item_proto.icons) do
                        local cp = helpers.deep_copy(spec)
                        cp.icon_mipmaps = nil
                        table.insert(layers, cp)
                    end
                    r_icons = layers
                    r_icon_size = item_proto.icon_size or 64
                elseif item_proto.icon then
                    r_icon = item_proto.icon
                    r_icon_size = item_proto.icon_size or 64
                else
                    r_icon = "__dark-matter-replicators-reborn__/graphics/icons/tenemut.png"
                    r_icon_size = 64
                end

                local refine_recipe = {
                    type = "recipe",
                    name = gprefix .. "refine-" .. res.name .. "-" .. step.to,
                    localised_name = {
                        "recipe-name.dmrsa-refining-recipe",
                        { loc_pref .. "." .. res.name },
                        { "quality-name." .. step.to }
                    },
                    energy_required = math.max(1, base_energy * ENERGY_MULT),
                    ingredients = {
                        { type = "item", name = res.name, amount = 1, quality = step.from }
                    },
                    results = {
                        -- Factorio 2.1: retry/success probabilities are
                        -- INDEPENDENT per result (pumpjack-style). The property
                        -- is `independent_probability` (2.1 renamed the old
                        -- `probability` — loading with `probability` errors:
                        -- "'probability' property ... renamed into
                        -- 'independent_probability'").
                        { type = "item", name = res.name, amount = 1, quality = step.from, independent_probability = retry_p },
                        { type = "item", name = res.name, amount = 1, quality = step.to, independent_probability = step.p }
                    },
                    -- Hidden from the player's hand-crafting menu; the recipe
                    -- picker of the refiner (its crafting category) shows them.
                    enabled = true,
                    hidden = true,
                    subgroup = gprefix .. "refining",
                    categories = { gprefix .. "refining" },
                    order = "z[" .. res.name .. "][" .. step.to .. "]",
                    icon = r_icon,
                    icon_size = r_icon_size,
                    icons = r_icons,
                }
                -- icon and icons are mutually exclusive in a prototype; strip
                -- the simple icon when the layered icons array is present.
                if r_icons then
                    refine_recipe.icon = nil
                    refine_recipe.icon_size = r_icon_size
                end
                data:extend({ refine_recipe })
                count = count + 1
            end
        end
        ::continue_item::
    end

    helpers.info("Refiner: generated " .. count .. " refining recipes.")
    return count
end

return RefinerGenerator