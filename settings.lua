require("defines")

local planets = { "Nauvis" }
local default_planet = "Nauvis" -- Default is always Nauvis for seamless early game progression
if mods["space-age"] then
	table.insert(planets, "Vulcanus")
	table.insert(planets, "Fulgora")
	table.insert(planets, "Gleba")
	table.insert(planets, "Aquilo")
end

-- v3.7.0 (C1): auto-detect overhaul mods. When Bob's / Angel's / K2 are
-- active, the grouped replication techs cover hundreds more items, so the
-- default grouped-tech cost multiplier is raised to keep research meaningful.
-- Zero-config: the player can still override the setting in the options.
local OVERHAUL_MOD_NAMES = {
    "bobplates", "bobassembly", "bobtech", "bobores", "boblogistics",
    "bobmodules", "bobwarfare", "bobpower", "bobmining",
    "angelssmelting", "angelsrefining", "angelsindustries", "angelspetrochem",
    "Krastorio2", "SpaceExtension",
}
local default_grouped_mult = 10.0
for _, mod_name in ipairs(OVERHAUL_MOD_NAMES) do
    if mods[mod_name] then
        default_grouped_mult = 15.0
        break
    end
end

-- DMR Startup and Balancing Settings
data:extend({
	{
		name = "dmrsa-log-level",
		type = "string-setting",
		order = "9-1",
		setting_type = "startup",
		allowed_values = { "none", "error", "warn", "info", "debug" },
		default_value = "warn",
	},
	{
		name = "tenemut-near-spawn",
		type = "bool-setting",
		order = "1-1-0",
		setting_type = "startup",
		default_value = true,
	},
	{
		name = "tenemut-spawning-planet",
		type = "string-setting",
		order = "1-1-1",
		setting_type = "startup",
		allowed_values = planets,
		default_value = default_planet, -- Fully configurable dropdown inside Factorio's Mod Settings
	},
	{
		name = "replstats-speed-base",
		type = "double-setting",
		order = "1-1-3",
		setting_type = "startup",
		default_value = 1,
		minimum_value = 0.001
	},
	{
		name = "replstats-speed-factor",
		type = "double-setting",
		order = "1-1-4",
		setting_type = "startup",
		default_value = 2,
		minimum_value = 0.001
	},
	{
		name = "replstats-energy-base",
		type = "double-setting",
		order = "1-2-1",
		setting_type = "startup",
		default_value = 256,
		minimum_value = 0.001
	},
	{
		name = "replstats-energy-factor",
		type = "double-setting",
		order = "1-2-2",
		setting_type = "startup",
		default_value = 2.5,
		minimum_value = 0.001
	},
	{
		name = "replstats-pollution-base",
		type = "double-setting",
		order = "1-3-1",
		setting_type = "startup",
		default_value = 1,
		minimum_value = 0
	},
	{
		name = "replstats-pollution-factor",
		type = "double-setting",
		order = "1-3-2",
		setting_type = "startup",
		default_value = 1.75,
		minimum_value = 0
	},
	{
		name = "replstats-size-base",
		type = "double-setting",
		order = "1-4-1",
		setting_type = "startup",
		default_value = 2,
		minimum_value = 1
	},
	{
		name = "replstats-size-addend",
		type = "double-setting",
		order = "1-4-3",
		setting_type = "startup",
		default_value = 0
	},
	{
		name = "replstats-modules-base",
		type = "double-setting",
		order = "1-5-1",
		setting_type = "startup",
		default_value = 1,
		minimum_value = 0
	},
	{
		name = "replstats-modules-addend",
		type = "double-setting",
		order = "1-5-3",
		setting_type = "startup",
		default_value = 0.5
	},
	{
		name = "replresearch-item-multiplier",
		type = "double-setting",
		order = "3-1-1",
		setting_type = "startup",
		default_value = 25,
		minimum_value = 0.001
	},
	{
		name = "replresearch-item-time",
		type = "double-setting",
		order = "3-1-2",
		setting_type = "startup",
		default_value = 5,
		minimum_value = 0.001
	},
	{
		name = "replresearch-space-lock",
		type = "int-setting",
		order = "3-2-1",
		setting_type = "startup",
		default_value = 6,
		allowed_values = {1, 2, 3, 4, 5, 6}
	},
	{
		name = "dmrsa-research-difficulty",
		type = "string-setting",
		order = "3-2-2",
		setting_type = "startup",
		allowed_values = { "Easy (Fast)", "Medium", "High", "Very Hard" },
		default_value = "Easy (Fast)",
	},
	{
		name = "dmrsa-research-pack-order",
		type = "string-setting",
		order = "3-2-3",
		setting_type = "startup",
		allowed_values = { "DMR Item First", "Science Pack First" },
		default_value = "DMR Item First",
	},
	{
		name = "replication-penalty",
		type = "double-setting",
		order = "4-1",
		setting_type = "startup",
		default_value = 0.5,
		minimum_value = 0
	},
	{
		name = "replication-fluid-quantity",
		type = "int-setting",
		order = "4-2",
		setting_type = "startup",
		default_value = 25,
		minimum_value = 1
	},
	{
		name = "dmrsa-tech-distribution",
		type = "string-setting",
		order = "5-1",
		setting_type = "startup",
		allowed_values = { "Individual Technologies", "Base Game Technologies", "Grouped Categories" },
		default_value = "Grouped Categories",
	},
	{
		name = "dmrsa-grouped-tech-cost-multiplier",
		type = "double-setting",
		order = "5-1-a",
		setting_type = "startup",
		default_value = default_grouped_mult,  -- v3.7.0 (C1): 10.0 base, 15.0 with overhaul mods
		minimum_value = 0.1,
	},
	{
		name = "dmrsa-cost-calculation-method",
		type = "string-setting",
		order = "5-2",
		setting_type = "startup",
		allowed_values = { "Recursive Steps (Compounding)", "Raw Ingredients (Flat)" },
		default_value = "Raw Ingredients (Flat)",
	},
	{
		name = "dmrsa-use-machine-efficiency",
		type = "bool-setting",
		order = "5-3",
		setting_type = "startup",
		default_value = true,
	},
})

if mods["space-age"] then
	data:extend({
		{
			name = "tenemut-other-planets",
			type = "string-setting",
			order = "1-1-2",
			setting_type = "startup",
			allowed_values = { "None", "All Except Nauvis", "All" },
			default_value = "None"
		},
	})
end

if mods["space-exploration"] or mods["space-age"] then
	data:extend({
		{
			name = "replication-in-space",
			type = "bool-setting",
			order = "1-6-1",
			setting_type = "startup",
			default_value = false,
		}
	})
end