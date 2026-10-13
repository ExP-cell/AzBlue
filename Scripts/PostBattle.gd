extends Control

# ==============================================================================
# POST-BATTLE SCREEN
# ==============================================================================
# 3-panel layout:
#   LEFT   — Inventory / Crafting (placeholder)
#   CENTER — Player Moves list  +  Stat Allocation (+1 buttons for each stat)
#   RIGHT  — Equipment slots    +  Full stat sheet  +  "Invest Points (N)" button
#
# Flow:
#   Battle.gd  →  PostBattle.tscn  →  (player allocates stats)  →  Main.tscn
# ==============================================================================

# ── Stat display key → friendly name mapping ──────────────────────────────────
const STAT_DISPLAY: Dictionary = {
	"str":   "STR",
	"int":   "INT",
	"dex":   "DEX",
	"spd":   "SPD",
	"hp":    "HP",
	"faith": "FTH",
}

# ── Node refs — Center panel ──────────────────────────────────────────────────
@onready var xp_label        : Label  = $HBox/CenterPanel/VBox/XPLabel
@onready var level_label     : Label  = $HBox/CenterPanel/VBox/LevelLabel
@onready var moves_container : VBoxContainer = $HBox/CenterPanel/VBox/MovesBox
@onready var stats_alloc_box : VBoxContainer = $HBox/CenterPanel/VBox/StatAllocBox
@onready var invest_btn      : Button = $HBox/CenterPanel/VBox/InvestBtn

# ── Node refs — Right panel ───────────────────────────────────────────────────
@onready var stat_sheet_label: Label  = $HBox/RightPanel/VBox/StatSheet

# ── Node refs — Continue button ───────────────────────────────────────────────
@onready var continue_btn    : Button = $HBox/CenterPanel/VBox/ContinueBtn


func _ready() -> void:
	_refresh_all()
	if continue_btn:
		continue_btn.pressed.connect(_on_continue_pressed)


# ==============================================================================
# REFRESH HELPERS
# ==============================================================================
func _refresh_all() -> void:
	_update_xp_display()
	_build_moves_list()
	_build_stat_alloc()
	_update_stat_sheet()
	_update_invest_button()


func _update_xp_display() -> void:
	if xp_label:
		xp_label.text = "XP: %d / %d  (Level %d)" % [
			GameState.xp, GameState.xp_to_next, GameState.level
		]
	if level_label:
		if GameState.stat_points > 0:
			level_label.text = "★ LEVEL UP! Points remaining: %d" % GameState.stat_points
		else:
			level_label.text = ""


func _build_moves_list() -> void:
	if not moves_container:
		return
	for child in moves_container.get_children():
		child.queue_free()

	var header := Label.new()
	header.text = "── Abilities ──"
	header.add_theme_font_size_override("font_size", 16)
	moves_container.add_child(header)

	var moves: Array = GameState.get_class_moves()
	if moves.is_empty():
		var lbl := Label.new()
		lbl.text = "(No moves)"
		moves_container.add_child(lbl)
		return

	for move in moves:
		var m: Dictionary = move as Dictionary
		var row := HBoxContainer.new()

		var icon_lbl := Label.new()
		icon_lbl.text = m.get("icon", "•") + "  "
		icon_lbl.custom_minimum_size = Vector2(24, 0)
		row.add_child(icon_lbl)

		var name_lbl := Label.new()
		name_lbl.text = m.get("name", "?")
		name_lbl.custom_minimum_size = Vector2(120, 0)
		row.add_child(name_lbl)

		var cost_lbl := Label.new()
		cost_lbl.text = "[%d E]" % m.get("energyCost", 0)
		cost_lbl.custom_minimum_size = Vector2(48, 0)
		cost_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
		row.add_child(cost_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = m.get("desc", "")
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(desc_lbl)

		moves_container.add_child(row)


func _build_stat_alloc() -> void:
	if not stats_alloc_box:
		return
	for child in stats_alloc_box.get_children():
		child.queue_free()

	var header := Label.new()
	header.text = "── Stat Allocation ──"
	header.add_theme_font_size_override("font_size", 16)
	stats_alloc_box.add_child(header)

	var stats := GameState.get_class_stats()
	for key in STAT_DISPLAY:
		var row := HBoxContainer.new()

		var name_lbl := Label.new()
		name_lbl.text = STAT_DISPLAY[key]
		name_lbl.custom_minimum_size = Vector2(48, 0)
		row.add_child(name_lbl)

		var val_lbl := Label.new()
		val_lbl.text = str(stats.get(key, 0))
		val_lbl.custom_minimum_size = Vector2(40, 0)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val_lbl)

		var plus_btn := Button.new()
		plus_btn.text = " + "
		plus_btn.custom_minimum_size = Vector2(36, 0)
		plus_btn.disabled = (GameState.stat_points <= 0)
		# Capture key by value via a closure
		plus_btn.pressed.connect(_on_stat_plus.bind(key))
		row.add_child(plus_btn)

		var bonus_lbl := Label.new()
		bonus_lbl.text = "(+%d)" % GameState.bonus_stats.get(key, 0)
		bonus_lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
		row.add_child(bonus_lbl)

		stats_alloc_box.add_child(row)


func _update_stat_sheet() -> void:
	if not stat_sheet_label:
		return
	var stats := GameState.get_class_stats()
	var lines: Array[String] = []
	lines.append("── Stats ──")
	for key in STAT_DISPLAY:
		lines.append("%s  %d" % [STAT_DISPLAY[key], stats.get(key, 0)])
	lines.append("")
	lines.append("HP   %d / %d" % [GameState.player_hp, GameState.max_player_hp])
	lines.append("EN   %d / %d" % [GameState.energy,    GameState.max_energy])
	lines.append("LVL  %d" % GameState.level)
	stat_sheet_label.text = "\n".join(lines)


func _update_invest_button() -> void:
	if invest_btn:
		invest_btn.text = "Invest Points (%d)" % GameState.stat_points
		invest_btn.disabled = (GameState.stat_points <= 0)


# ==============================================================================
# BUTTON CALLBACKS
# ==============================================================================
func _on_stat_plus(key: String) -> void:
	if GameState.allocate_stat(key):
		_refresh_all()
		SaveManager.save()


func _on_continue_pressed() -> void:
	SaveManager.save()
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")
