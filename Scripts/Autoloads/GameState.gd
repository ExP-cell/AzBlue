extends Node

# ==============================================================================
# GAME STATE — PLAYER STATS & SESSION DATA
# ==============================================================================
# Sections:
#   ① PLAYER IDENTITY  — name, class, gender, difficulty, progression
#   ② PLAYER STATS     — runtime HP / energy, level, XP, inventory
#   ③ STAT ALLOCATION  — bonus points distributed on level-up
#   ④ CLASS STATS      — read-only helpers derived from CLASS_DATA + STAT_CONFIG
#   ⑤ COMBATANT OBJECT — dict passed into StatusEffects system
#   ⑥ PROGRESSION HELPERS
#   ⑦ COMBATANT SYNC
# ==============================================================================


# ── ① PLAYER IDENTITY ─────────────────────────────────────────────────────────
var player_name    : String = ""
var selected_class : String = "sword"
var gender         : String = "male"
var difficulty     : String = "normal"   # "baby" | "normal" | "hardcore"


# ── ② PLAYER STATS ────────────────────────────────────────────────────────────
var level      : int = 1
var xp         : int = 0
var xp_to_next : int = 100
var score      : int = 0
var stage      : int = 1

var player_hp     : int = 100
var max_player_hp : int = 100
var energy        : int = 100
var max_energy    : int = 100

# Starting inventory — empty (items added through gameplay)
var inventory  : Dictionary = {}
var materials  : Dictionary = {}


# ── ③ STAT ALLOCATION ─────────────────────────────────────────────────────────
# Points earned each level-up (see LEVEL_CONFIG.json → statPointsPerLevel).
# Stored separately from class base stats so they can be saved / reset cleanly.
var stat_points : int = 0

# Bonus points the player has manually allocated across all level-ups.
# Keys match the class stat keys: str, int, dex, spd, hp, faith.
var bonus_stats : Dictionary = {
	"str":   0,
	"int":   0,
	"dex":   0,
	"spd":   0,
	"hp":    0,
	"faith": 0,
}


# ── Combatant Object (see ⑤) ──────────────────────────────────────────────────
var player : Dictionary = {
	"name"      : "Player",
	"hp"        : 100,
	"max_hp"    : 100,
	"energy"    : 100,
	"max_energy": 100,
	"effects"   : [],
	"fire_dmg"  : 5,
	"bleed_dmg" : 4,
	"dodge"     : 0.05,
	"block"     : 0.10,
}


func _ready() -> void:
	_rebuild_player_combatant()


# ==============================================================================
# ④ CLASS STATS — READ-ONLY HELPERS
# ==============================================================================

## Raw class data dictionary from CLASS_DATA.json.
func get_current_class_data() -> Dictionary:
	if DataManager and DataManager.class_data and DataManager.class_data.has(selected_class):
		return DataManager.class_data[selected_class]
	return {}


## Base stat block for the selected class PLUS manually allocated bonus points.
## Shape: { "str": int, "int": int, "dex": int, "spd": int, "hp": int, ["faith": int] }
func get_class_stats() -> Dictionary:
	var data  := get_current_class_data()
	var base  : Dictionary = data.get("stats", { "str": 10, "int": 5, "dex": 5, "spd": 5, "hp": 20 })
	# Merge bonus allocations on top of base stats
	var final : Dictionary = base.duplicate()
	for key in bonus_stats:
		if final.has(key):
			final[key] += bonus_stats[key]
		else:
			final[key]  = bonus_stats[key]
	return final


## Move list for the selected class.
func get_class_moves() -> Array:
	var data := get_current_class_data()
	return data.get("moves", [])


## Max HP = class hp stat × hpPerPoint + level scaling.
func get_max_hp() -> int:
	var cfg      := _cfg()
	var hp_per_pt: float = cfg.get("hpPerPoint", 5.0)
	var stats    := get_class_stats()
	var base_hp  : int = int(stats.get("hp", 20) * hp_per_pt)
	return base_hp + (level - 1) * 10


## Max Energy = maxEnergyBase + INT × intEnergyPerPoint.
func get_max_energy() -> int:
	var cfg    := _cfg()
	var base   : float = cfg.get("maxEnergyBase",    80.0)
	var per_pt : float = cfg.get("intEnergyPerPoint", 2.0)
	var stats  := get_class_stats()
	return int(base + stats.get("int", 5) * per_pt)


## Base dodge chance from DEX stat + STAT_CONFIG formula.
func get_base_dodge() -> float:
	var cfg    := _cfg()
	var base   : float = cfg.get("baseDodge",        0.02)
	var per_pt : float = cfg.get("dexDodgePerPoint",  0.01)
	var max_dg : float = cfg.get("maxDodge",          0.60)
	var stats  := get_class_stats()
	return minf(base + stats.get("dex", 5) * per_pt, max_dg)


## Base block chance from STR stat + STAT_CONFIG formula.
func get_base_block() -> float:
	var cfg    := _cfg()
	var per_pt : float = cfg.get("strBlockPerPoint", 0.5)
	var max_blk: float = cfg.get("maxBlockPercent",  0.75)
	var stats  := get_class_stats()
	return minf(stats.get("str", 10) * per_pt * 0.01, max_blk)


## Flat per-turn energy regen during battle (from STAT_CONFIG.battleEnergyRegen).
## Edit battleEnergyRegen in STAT_CONFIG.json to tune mid-battle energy feel.
func get_battle_energy_regen() -> int:
	return int(_cfg().get("battleEnergyRegen", 10))


## Energy restored by Resting between battles (from STAT_CONFIG.restEnergyRefill).
## Edit restEnergyRefill in STAT_CONFIG.json to tune rest energy feel.
func get_rest_energy_refill() -> int:
	return int(_cfg().get("restEnergyRefill", 40))


# ==============================================================================
# ⑥ PROGRESSION HELPERS
# ==============================================================================

func add_xp(amount: int) -> void:
	xp += amount
	var level_cfg: Dictionary = DataManager.load_json_dict("res://Data/LEVEL_CONFIG.json") if DataManager else {}
	var max_level : int = level_cfg.get("maxLevel", 50) if not level_cfg.is_empty() else 50
	var pts_per_lv: int = level_cfg.get("statPointsPerLevel", 3) if not level_cfg.is_empty() else 3

	while xp >= xp_to_next and level < max_level:
		xp        -= xp_to_next
		level     += 1
		xp_to_next = int(xp_to_next * 1.55)
		stat_points += pts_per_lv
		_rebuild_player_combatant()
		print("Level Up! Level: %d | Stat points available: %d" % [level, stat_points])


## Spend a stat point on a stat key. Returns true if successful.
func allocate_stat(stat_key: String) -> bool:
	if stat_points <= 0:
		return false
	if not bonus_stats.has(stat_key):
		bonus_stats[stat_key] = 0
	bonus_stats[stat_key] += 1
	stat_points -= 1
	_rebuild_player_combatant()
	return true


func use_item(item_id: String) -> bool:
	if inventory.get(item_id, 0) > 0:
		inventory[item_id] -= 1
		return true
	return false


## Restore HP & energy to full (called between battles / after rest).
func reset_player() -> void:
	player_hp = max_player_hp
	energy    = max_energy
	_rebuild_player_combatant()


# ==============================================================================
# ⑦ COMBATANT SYNC
# ==============================================================================

## Rebuilds the `player` combatant dict from current derived stats.
## Call at battle start and after level-ups / stat allocation.
func _rebuild_player_combatant() -> void:
	max_player_hp = get_max_hp()
	player_hp     = min(player_hp, max_player_hp)
	max_energy    = get_max_energy()
	energy        = min(energy, max_energy)

	player["name"]       = player_name if player_name != "" else selected_class.capitalize()
	player["max_hp"]     = max_player_hp
	player["hp"]         = player_hp
	player["max_energy"] = max_energy
	player["energy"]     = energy
	player["dodge"]      = get_base_dodge()
	player["block"]      = get_base_block()


## Pull hp / energy back from the combatant dict after StatusEffects modifies it.
func sync_hp_from_combatant() -> void:
	player_hp          = player["hp"]
	energy             = player.get("energy", energy)
	player["max_hp"]   = max_player_hp
	player["max_energy"] = max_energy


# ── Private ────────────────────────────────────────────────────────────────────
func _cfg() -> Dictionary:
	return DataManager.stat_config if DataManager and DataManager.stat_config else {}
