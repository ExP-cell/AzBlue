extends Node2D

# ==============================================================================
# BASE BATTLE LOOP & CONTROLLER
# ==============================================================================
# This script manages the turn-based combat flow:
#   1. Battle Lifecycle (Intro -> Player Turn -> Enemy Turn -> Victory / Defeat)
#   2. Player Actions (Fight, Items, Guard, Run)
#   3. Enemy Action Callback
#   4. Dynamic Formula Hooks (Damage, Guard reduction, XP rewards)
#
# NOTE: No hardcoded monsters are included. This base code uses a generic
# dummy combatant schema so it can run immediately, and allows any enemy data
# dictionary to be passed into `start_battle(enemy_data)` when you are ready.
# ==============================================================================

# ── Signals ───────────────────────────────────────────────────────────────────
signal battle_started(enemy_data: Dictionary)
signal player_turn_started()
signal enemy_turn_started()
signal action_resolved(actor: String, action_type: String, value: int)
signal battle_ended(result: String) # "victory", "defeat", "escaped"

# ── Battle State Machine ──────────────────────────────────────────────────────
enum BattleState {
	INTRO,
	PLAYER_TURN,
	PLAYER_ACTION,
	ENEMY_TURN,
	CHECK_STATUS,
	VICTORY,
	DEFEAT,
	ESCAPED
}

var current_state: BattleState = BattleState.INTRO
var turn_count: int = 1
var is_player_guarding: bool = false

# ── Base Enemy / Combatant Schema (NO MONSTERS ADDED) ─────────────────────────
# When you want to spawn a monster, pass a dictionary with these keys into start_battle()
const DEFAULT_TARGET: Dictionary = {
	"name": "Target Dummy",
	"hp": 50,
	"max_hp": 50,
	"atk": 8,
	"def": 2,
	"exp_reward": 50,
	"sprite": "" # Path to monster sprite when added
}

var current_enemy: Dictionary = {}

# ── Ragnarok Online Sprite Sheet Settings ─────────────────────────────────────
const FRAME_W        := 65
const FRAME_H        := 81
const FRAMES_PER_ROW := 8
const PLAYER_DIR_ROW := 3   # NW direction (faces upper-left)
const ENEMY_DIR_ROW  := 7   # SE direction (faces lower-right)
const IDLE_FRAME     := 0

const ENEMY_POS      := Vector2(850, 200)
const ENEMY_SCALE    := Vector2(4.0, 4.0)
const PLAYER_POS     := Vector2(280, 440)
const PLAYER_SCALE   := Vector2(4.0, 4.0)

# ── Node References ───────────────────────────────────────────────────────────
@onready var player_sprite   : Sprite2D    = $PlayerSprite
@onready var enemy_sprite    : Sprite2D    = $EnemySprite

@onready var enemy_name_lbl  : Label       = $EnemyInfoBox/VBox/EnemyName
@onready var enemy_hp_bar    : ProgressBar = $EnemyInfoBox/VBox/EnemyHP

@onready var player_name_lbl : Label       = $PlayerInfoBox/VBox/PlayerName
@onready var player_hp_bar   : ProgressBar = $PlayerInfoBox/VBox/PlayerHP
@onready var player_exp_bar  : ProgressBar = $PlayerInfoBox/VBox/PlayerEXP

@onready var dialog_label    : Label       = $DialogBox/DialogText

@onready var fight_btn       : Button      = $ActionMenu/Grid/FightBtn
@onready var items_btn       : Button      = $ActionMenu/Grid/ItemsBtn
@onready var guard_btn       : Button      = $ActionMenu/Grid/GuardBtn
@onready var run_btn         : Button      = $ActionMenu/Grid/RunBtn


# ==============================================================================
# INITIALIZATION & BATTLE START
# ==============================================================================
func _ready() -> void:
	_connect_buttons()
	setup_player_sprite()
	setup_ui()
	# Start combat with the generic test target schema
	start_battle(DEFAULT_TARGET)


func _connect_buttons() -> void:
	if fight_btn and not fight_btn.pressed.is_connected(_on_fight_pressed):
		fight_btn.pressed.connect(_on_fight_pressed)
	if items_btn and not items_btn.pressed.is_connected(_on_items_pressed):
		items_btn.pressed.connect(_on_items_pressed)
	if guard_btn and not guard_btn.pressed.is_connected(_on_guard_pressed):
		guard_btn.pressed.connect(_on_guard_pressed)
	if run_btn and not run_btn.pressed.is_connected(_on_run_pressed):
		run_btn.pressed.connect(_on_run_pressed)


## Initiates a battle encounter. Pass custom enemy stats when ready.
func start_battle(enemy_data: Dictionary = {}) -> void:
	if enemy_data.is_empty():
		current_enemy = DEFAULT_TARGET.duplicate(true)
	else:
		current_enemy = enemy_data.duplicate(true)

	# Ensure fallback fields are always populated
	if not current_enemy.has("name"): current_enemy["name"] = "Target"
	if not current_enemy.has("hp"): current_enemy["hp"] = 50
	if not current_enemy.has("max_hp"): current_enemy["max_hp"] = current_enemy["hp"]
	if not current_enemy.has("atk"): current_enemy["atk"] = 8
	if not current_enemy.has("def"): current_enemy["def"] = 0
	if not current_enemy.has("exp_reward"): current_enemy["exp_reward"] = 40

	turn_count = 1
	is_player_guarding = false
	current_state = BattleState.INTRO

	set_actions_enabled(false)
	load_enemy_sprite(current_enemy)
	update_ui()

	show_dialog("Battle started against %s!" % current_enemy["name"])
	emit_signal("battle_started", current_enemy)

	# Short intro delay before handing control to the player
	await get_tree().create_timer(1.2).timeout
	start_player_turn()


# ==============================================================================
# BATTLE STATE MACHINE & TURN FLOW
# ==============================================================================
## Starts the player's turn and enables the command menu.
func start_player_turn() -> void:
	if current_state == BattleState.VICTORY or current_state == BattleState.DEFEAT or current_state == BattleState.ESCAPED:
		return

	current_state = BattleState.PLAYER_TURN
	is_player_guarding = false # Guard stance resets at the start of player turn
	set_actions_enabled(true)
	show_dialog("Turn %d: What will you do?" % turn_count)
	emit_signal("player_turn_started")


## Starts the enemy's turn and processes enemy action.
func start_enemy_turn() -> void:
	if current_state == BattleState.VICTORY or current_state == BattleState.DEFEAT or current_state == BattleState.ESCAPED:
		return

	current_state = BattleState.ENEMY_TURN
	set_actions_enabled(false)
	emit_signal("enemy_turn_started")

	show_dialog("%s is preparing to attack..." % current_enemy["name"])
	await get_tree().create_timer(1.0).timeout

	execute_enemy_turn()


## Concludes the current round and transitions to the next turn.
func end_round() -> void:
	if current_state == BattleState.VICTORY or current_state == BattleState.DEFEAT or current_state == BattleState.ESCAPED:
		return

	turn_count += 1
	start_player_turn()


# ==============================================================================
# ACTION BUTTON HANDLERS
# ==============================================================================
func _on_fight_pressed() -> void:
	if current_state != BattleState.PLAYER_TURN:
		return
	set_actions_enabled(false)
	current_state = BattleState.PLAYER_ACTION
	execute_player_attack()


func _on_guard_pressed() -> void:
	if current_state != BattleState.PLAYER_TURN:
		return
	set_actions_enabled(false)
	current_state = BattleState.PLAYER_ACTION
	execute_player_guard()


func _on_items_pressed() -> void:
	if current_state != BattleState.PLAYER_TURN:
		return
	set_actions_enabled(false)
	current_state = BattleState.PLAYER_ACTION
	execute_player_item()


func _on_run_pressed() -> void:
	if current_state != BattleState.PLAYER_TURN:
		return
	set_actions_enabled(false)
	current_state = BattleState.PLAYER_ACTION
	execute_player_run()


# ==============================================================================
# ACTION EXECUTION HOOKS (EDIT THESE FOR CUSTOM MECHANICS / C-CHALLENGES)
# ==============================================================================
## Executes player attack. Hook in coding questions or skill choices here.
func execute_player_attack() -> void:
	var damage: int = calculate_player_damage()
	current_enemy["hp"] = max(0, current_enemy["hp"] - damage)
	update_ui()
	_flash_sprite(enemy_sprite, Color(1.0, 0.3, 0.3, 0.8))

	show_dialog("You attacked! Dealt %d damage to %s." % [damage, current_enemy["name"]])
	emit_signal("action_resolved", "player", "attack", damage)

	await get_tree().create_timer(1.2).timeout

	if current_enemy["hp"] <= 0:
		handle_victory()
	else:
		start_enemy_turn()


## Executes guarding stance, reducing damage on next incoming hit.
func execute_player_guard() -> void:
	is_player_guarding = true
	show_dialog("You braced for impact! Guard is active.")
	emit_signal("action_resolved", "player", "guard", 0)

	await get_tree().create_timer(1.0).timeout
	start_enemy_turn()


## Executes item usage (e.g., Potion healing from inventory).
func execute_player_item() -> void:
	var potions_available: int = GameState.inventory.get("potion", 0)
	if potions_available <= 0:
		show_dialog("No potions left in inventory!")
		set_actions_enabled(true)
		current_state = BattleState.PLAYER_TURN
		return

	# Use potion
	GameState.inventory["potion"] -= 1
	var heal_amount := 35
	GameState.player_hp = min(GameState.max_player_hp, GameState.player_hp + heal_amount)
	update_ui()
	_flash_sprite(player_sprite, Color(0.3, 1.0, 0.3, 0.8))

	show_dialog("Used Potion! Restored %d HP. (%d remaining)" % [heal_amount, GameState.inventory["potion"]])
	emit_signal("action_resolved", "player", "item", heal_amount)

	await get_tree().create_timer(1.2).timeout
	start_enemy_turn()


## Executes run / escape attempt.
func execute_player_run() -> void:
	show_dialog("Attempting to escape...")
	await get_tree().create_timer(0.8).timeout

	# 80% base escape probability
	var escape_roll := randf()
	if escape_roll < 0.8:
		current_state = BattleState.ESCAPED
		show_dialog("Got away safely!")
		emit_signal("battle_ended", "escaped")
		await get_tree().create_timer(1.2).timeout
		get_tree().change_scene_to_file("res://Scenes/Main.tscn")
	else:
		show_dialog("Could not escape!")
		await get_tree().create_timer(1.0).timeout
		start_enemy_turn()


## Executes enemy action.
func execute_enemy_turn() -> void:
	var incoming_damage: int = calculate_enemy_damage()

	if is_player_guarding:
		var reduced := int(incoming_damage * 0.5)
		incoming_damage = max(1, reduced)
		show_dialog("Your guard softened the impact!")
		await get_tree().create_timer(0.8).timeout

	GameState.player_hp = max(0, GameState.player_hp - incoming_damage)
	update_ui()
	_flash_sprite(player_sprite, Color(1.0, 0.3, 0.3, 0.8))

	show_dialog("%s strikes for %d damage!" % [current_enemy["name"], incoming_damage])
	emit_signal("action_resolved", "enemy", "attack", incoming_damage)

	await get_tree().create_timer(1.2).timeout

	if GameState.player_hp <= 0:
		handle_defeat()
	else:
		end_round()


# ==============================================================================
# RESOLUTION (VICTORY / DEFEAT)
# ==============================================================================
func handle_victory() -> void:
	current_state = BattleState.VICTORY
	var exp_gained: int = current_enemy.get("exp_reward", 40)
	show_dialog("Defeated %s! Victory!" % current_enemy["name"])
	emit_signal("battle_ended", "victory")

	await get_tree().create_timer(1.0).timeout
	GameState.add_xp(exp_gained)
	update_ui()
	show_dialog("Gained +%d EXP!" % exp_gained)

	await get_tree().create_timer(1.5).timeout
	# Transition back to Main scene
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")


func handle_defeat() -> void:
	current_state = BattleState.DEFEAT
	show_dialog("You have fallen in battle...")
	emit_signal("battle_ended", "defeat")

	await get_tree().create_timer(2.0).timeout
	# Reset HP and return to Main
	GameState.player_hp = GameState.max_player_hp
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")


# ==============================================================================
# FORMULAS & COMBAT CALCULATIONS (EDIT THESE FOR STAT SCALING / RULES)
# ==============================================================================
## Calculates player attack power based on class stats.
func calculate_player_damage() -> int:
	var stats: Dictionary = GameState.get_class_stats()
	var base_power := 15
	if GameState.selected_class == "sword":
		base_power += int(stats.get("str", 10) * 1.2)
	elif GameState.selected_class == "mage":
		base_power += int(stats.get("int", 10) * 1.4)
	elif GameState.selected_class == "assassin" or GameState.selected_class == "thief":
		base_power += int(stats.get("dex", 10) * 1.3)
	else:
		base_power += 10

	var variance := randi_range(-3, 4)
	var def_val: int = current_enemy.get("def", 0)
	var final_damage: int = max(1, base_power + variance - def_val)
	return final_damage


## Calculates enemy attack power.
func calculate_enemy_damage() -> int:
	var base_atk: int = current_enemy.get("atk", 10)
	var variance := randi_range(-2, 3)
	return max(1, base_atk + variance)


# ==============================================================================
# UI & VISUAL HELPERS
# ==============================================================================
func setup_ui() -> void:
	player_name_lbl.text     = GameState.selected_class.capitalize()
	player_hp_bar.max_value  = GameState.max_player_hp
	player_hp_bar.value      = GameState.player_hp
	player_exp_bar.max_value = GameState.xp_to_next
	player_exp_bar.value     = GameState.xp


func update_ui() -> void:
	player_hp_bar.max_value  = GameState.max_player_hp
	player_hp_bar.value      = GameState.player_hp
	player_exp_bar.max_value = GameState.xp_to_next
	player_exp_bar.value     = GameState.xp

	if not current_enemy.is_empty():
		enemy_name_lbl.text    = current_enemy.get("name", "Target")
		enemy_hp_bar.max_value = current_enemy.get("max_hp", 50)
		enemy_hp_bar.value     = current_enemy.get("hp", 0)


func show_dialog(text: String) -> void:
	if dialog_label:
		dialog_label.text = text


func set_actions_enabled(enabled: bool) -> void:
	if fight_btn: fight_btn.disabled = not enabled
	if items_btn: items_btn.disabled = not enabled
	if guard_btn: guard_btn.disabled = not enabled
	if run_btn:   run_btn.disabled   = not enabled


func _flash_sprite(sprite: Sprite2D, flash_color: Color) -> void:
	if not sprite: return
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", flash_color, 0.1)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)


# ==============================================================================
# SPRITE LOADING
# ==============================================================================
func setup_player_sprite() -> void:
	var cls    : String = GameState.selected_class
	if cls == "": cls = "sword"
	var gender : String = GameState.gender
	if gender == "": gender = "male"
	var folder : String = "res://Assets/Player/Body/" + gender.capitalize() + "/"

	var class_map := { "mage": "Mage", "sword": "Swordsman", "thief": "Thief", "assassin": "Thief" }
	var keyword   : String = class_map.get(cls, "Swordsman")

	var dir := DirAccess.open(folder)
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".png") and keyword in fname:
				var tex : Texture2D = load(folder + fname)
				_apply_directional_frame(player_sprite, tex, PLAYER_DIR_ROW)
				player_sprite.position = PLAYER_POS
				player_sprite.scale    = PLAYER_SCALE
				break
			fname = dir.get_next()


func load_enemy_sprite(enemy_data: Dictionary) -> void:
	var sprite_path: String = enemy_data.get("sprite", "")
	if sprite_path == "" or not ResourceLoader.exists(sprite_path):
		enemy_sprite.texture = null
		return

	var tex: Texture2D = load(sprite_path)
	if tex.get_width() > FRAME_W * 2:
		_apply_directional_frame(enemy_sprite, tex, ENEMY_DIR_ROW)
	else:
		enemy_sprite.texture        = tex
		enemy_sprite.region_enabled = false

	enemy_sprite.position = ENEMY_POS
	enemy_sprite.scale    = ENEMY_SCALE


func _apply_directional_frame(sprite: Sprite2D, tex: Texture2D, dir_row: int) -> void:
	if not sprite or not tex: return
	sprite.texture        = tex
	sprite.region_enabled = true
	sprite.region_rect    = Rect2(
		IDLE_FRAME * FRAME_W,
		dir_row    * FRAME_H,
		FRAME_W,
		FRAME_H
	)
