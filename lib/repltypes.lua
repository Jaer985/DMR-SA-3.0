-- Replication type definitions
-- Each type has: name, tier (fixed), and order (for sorting).
-- Tier is the FIXED replication tier for items of this category.
-- Items classified here will NEVER be lower than this tier.
-- The cost-solver can still push tier HIGHER for complex items.
--
-- Categories with tier=nil use dynamic tier from cost-solver.
-- The category display name is sourced from the locale file
-- [replcategory-name] section keyed by the category name, NOT from a hardcoded
-- `localized` field here. This avoids locale drift between code and translation files.

local repltypes = {
    ore = {
        name = "ore",
        tier = 1,
        order = "aa",
    },
    element = {
        name = "element",
        tier = 2,
        order = "ba",
    },
    shape = {
        name = "shape",
        tier = 2,
        order = "bb",
    },
    alloy = {
        name = "alloy",
        tier = 3,
        order = "bc",
    },
    chemical = {
        name = "chemical",
        tier = 3,
        order = "bd",
    },
    organic = {
        name = "organic",
        tier = 3,
        order = "ce",
    },
    military = {
        name = "military",
        tier = 3,
        order = "cf",
    },
    military_advanced = {
        name = "military-advanced",
        tier = 5,
        order = "cg",
    },
    module = {
        name = "module",
        tier = 3,
        order = "ea",
    },
    module_advanced = {
        name = "module-advanced",
        tier = 4,
        order = "eb",
    },
    life = {
        name = "life",
        tier = 5,
        order = "eb",
    },
    exotic = {
        name = "exotic",
        tier = 5,
        order = "ec",
    },
    magic = {
        name = "magic",
        tier = 5,
        order = "ed",
    },
    alien = {
        name = "alien",
        tier = 5,
        order = "ee",
    },
    science = {
        name = "science",
        tier = nil,  -- dynamic: based on science pack level
        order = "ef",
    },
    -- Fallback for anything not classified above
    general = {
        name = "general",
        tier = nil,  -- dynamic: computed by cost-solver
        order = "eg",
    },
}

-- Known element names for auto-detection (lowercase)
-- Used by get_item_category to detect pure elements
repltypes.element_names = {
    "hydrogen", "helium", "lithium", "beryllium", "boron",
    "carbon", "nitrogen", "oxygen", "fluorine", "neon",
    "sodium", "magnesium", "alumin", "aluminium", "aluminum",
    "silicon", "phosphorus", "sulfur", "sulphur", "chlorine",
    "titanium", "chromium", "manganese", "iron", "cobalt",
    "nickel", "copper", "zinc", "gallium", "germanium",
    "arsenic", "selenium", "bromine", "krypton",
    "silver", "cadmium", "indium", "tin", "antimony",
    "tellurium", "iodine", "xenon",
    "barium", "lanthanum", "cerium",
    "neodymium", "promethium", "samarium", "europium",
    "gadolinium", "terbium", "dysprosium", "holmium", "erbium",
    "thulium", "ytterbium", "lutetium",
    "tantalum", "tungsten", "wolfram", "rhenium", "osmium",
    "iridium", "platinum", "gold", "mercury", "thallium",
    "lead", "bismuth", "polonium", "astatine", "radon",
    "francium", "radium", "actinium", "thorium",
    "protactinium", "uranium", "neptunium", "plutonium",
    "americium", "curium",
}

return repltypes
