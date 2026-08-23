-- Define mod namespace
require("defines")

-- Safe require wrapper with traceback on error
local function safe_require(module_path)
    local ok, result = pcall(require, module_path)
    if not ok then
        log("[DarkMatterReplicators] ERROR loading " .. module_path .. ": " .. tostring(result) .. "\n" .. debug.traceback())
    end
    return result
end

-- Load modular prototypes
safe_require("prototypes.items.dark-matter")
safe_require("prototypes.entities.replicators")
safe_require("prototypes.entities.refiner")
safe_require("prototypes.recipes.base-recipes")
safe_require("prototypes.technologies.technologies")

-- Load Space Age specialized planetary prototypes
if mods["space-age"] then
    safe_require("prototypes.entities.planetary-replicators")
    safe_require("prototypes.technologies.planetary-tech")
end

-- Load baseline tenemut resource definition (maps resources on planets)
safe_require("prototypes.raw-resources")