-- data-final-fixes.lua
-- Runs AFTER all mods have finished their data-updates phase.
-- Orquestador: cada PASS vive en prototypes/fixes/pass-*.lua por concern.
--   PASS 0: Dynamic recipe generation (generator + refiner + planetary attaches)
--   PASS 1: Strip invalid technology prerequisites (dmrsa-*)
--   PASS 2: Re-validate cross-mod technologies depending on dmrsa techs
--   PASS 3: Handle orphaned DMR technologies (reassign unlocks to baseline)
--   PASS 4: Ensure replication-lab accepts all planetary science packs
--   PASS 5: Auto-hide empty replication category subgroups
-- (PASS 6 fue REMOVIDO en v4.0 — ver pass-generate.lua.)

require("defines")
local helpers = require("lib.helpers")

-- ── PASS 0: Dynamic recipe generation + Quality Refiner ──
-- Debe correr PRIMERO: genera las recipes (0-ingredient) y techs espejo desde
-- datos COMPLETOS (los deps opcionales ? bobplates etc. fuerzan este
-- data-final-fixes DESPUÉS de los mods overhaul).
require("prototypes.fixes.pass-generate")

-- ── PASS 1 + 2: Sanitización de prereqs ──
require("prototypes.fixes.pass-prereqs")

-- ── PASS 3: Orphans ──
require("prototypes.fixes.pass-orphans")

-- ── PASS 4: Lab inputs SA ──
require("prototypes.fixes.pass-lab-inputs")

-- ── PASS 5: Auto-hide categorías vacías ──
require("prototypes.fixes.pass-empty-categories")

helpers.log("data-final-fixes: all passes complete.")