extends Node

# ==============================================================================
# SAVE MANAGER — Single auto-slot JSON save to user://
# ==============================================================================
# Saves and loads all persistent GameState fields.
# Called automatically between battles (after handle_victory routes to Main).
#
# Save file location: user://save.json
#   → On Windows: %APPDATA%\Godot\app_userdata\AzBlue\save.json
#   → Find it in Godot editor: Project → Open User Data Folder
# ==============================================================================

const SAVE_PATH := "user://save.json"


# ── Public API ─────────────────────────────────────────────────────────────────

## Returns true if a save file exists.
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Saves all relevant GameState fields to user://save.json.
func save() -> void:
	var data := {
		# Identity
		"player_name":    GameState.player_name,
		"selected_class": GameState.selected_class,
		"gender":         GameState.gender,
		"difficulty":     GameState.difficulty,
		# Progression
		"level":          GameState.level,
		"xp":             GameState.xp,
		"xp_to_next":     GameState.xp_to_next,
		"score":          GameState.score,
		"stage":          GameState.stage,
		# Stats
		"player_hp":      GameState.player_hp,
		"max_player_hp":  GameState.max_player_hp,
		"energy":         GameState.energy,
		"max_energy":     GameState.max_energy,
		# Stat allocation
		"stat_points":    GameState.stat_points,
		"bonus_stats":    GameState.bonus_stats.duplicate(),
		# Inventory
		"inventory":      GameState.inventory.duplicate(),
		"materials":      GameState.materials.duplicate(),
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		print("[SaveManager] Game saved.")
	else:
		push_error("[SaveManager] Could not open save file for writing: " + SAVE_PATH)


## Loads the save file into GameState. Returns true on success, false if no save.
func load_save() -> bool:
	if not has_save():
		push_warning("[SaveManager] No save file found at: " + SAVE_PATH)
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		push_error("[SaveManager] Could not open save file for reading: " + SAVE_PATH)
		return false

	var json  := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()

	if error != OK:
		push_error("[SaveManager] JSON parse error in save file: " + json.get_error_message())
		return false

	if not (json.data is Dictionary):
		push_error("[SaveManager] Save file has unexpected format.")
		return false
	var data: Dictionary = json.data as Dictionary

	# ── Restore into GameState ───────────────────────────────────────────
	GameState.player_name    = data.get("player_name",    "")
	GameState.selected_class = data.get("selected_class", "sword")
	GameState.gender         = data.get("gender",         "male")
	GameState.difficulty     = data.get("difficulty",     "normal")

	GameState.level          = data.get("level",          1)
	GameState.xp             = data.get("xp",             0)
	GameState.xp_to_next     = data.get("xp_to_next",     100)
	GameState.score          = data.get("score",          0)
	GameState.stage          = data.get("stage",          1)

	GameState.player_hp      = data.get("player_hp",      100)
	GameState.max_player_hp  = data.get("max_player_hp",  100)
	GameState.energy         = data.get("energy",         100)
	GameState.max_energy     = data.get("max_energy",     100)

	GameState.stat_points    = data.get("stat_points",    0)
	GameState.bonus_stats    = data.get("bonus_stats",    { "str": 0, "int": 0, "dex": 0, "spd": 0, "hp": 0, "faith": 0 })
	GameState.inventory      = data.get("inventory",      {})
	GameState.materials      = data.get("materials",      {})

	GameState._rebuild_player_combatant()
	print("[SaveManager] Game loaded. Level %d | Class: %s" % [GameState.level, GameState.selected_class])
	return true


## Deletes the save file (called on Hardcore permadeath).
func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		print("[SaveManager] Save file deleted.")
