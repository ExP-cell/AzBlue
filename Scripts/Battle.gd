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

# The move the player will execute this turn (set by move-selection UI or auto-picked).
# Shape matches CLASS_DATA.json move entries:
#   { id, name, icon, desc, scaling, power, energyCost, type, effect }
# "effect" is either null or: { id, stacks, duration, chance, [target] }
# "target" defaults to "enemy"; use "self" for self-applied buffs/heals.
var current_move: Dictionary = {}

# Tracks which move index the enemy will use next (cycles through their moves array).
var enemy_move_index: int = 0

# ── Base Enemy / Combatant Schema ─────────────────────────────────────────────
# Pass a populated dictionary from enemy JSON into start_battle().
# "effects"    – managed by StatusEffects.gd; always reset to [] at battle start.
# "fire_dmg"   – base fire damage for Burn DOT tick.
# "bleed_dmg"  – base bleed damage for Bleed DOT tick.
# "dodge"      – base dodge chance (0.0–1.0); modified by Crippled / Shaken.
# "block"      – base block chance (0.0–1.0); modified by Shaken.
# "energy"     – current energy pool (enemy spends this on moves).
# "max_energy" – maximum enemy energy.
# "moves"      – array of move dicts (same schema as player moves).
const DEFAULT_TARGET: Dictionary = {
	"name":       "Target Dummy",
	"hp":         50,
	"max_hp":     50,
	"atk":        8,
	"def":        2,
	"exp_reward": 50,
	"sprite":     "",
	"fire_dmg":   5,
	"bleed_dmg":  4,
	"dodge":      0.0,
	"block":      0.0,
	"energy":     60,
	"max_energy": 60,
	"effects":    [],
	"moves": [
		{ "id": "punch", "name": "Punch", "icon": "*", "desc": "Basic attack.",
		  "scaling": null, "power": 1.0, "energyCost": 0, "type": "attack", "effect": null }
	],
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


## Initiates a battle encounter. Pass an enemy data dict (from JSON) or leave empty for dummy.
func start_battle(enemy_data: Dictionary = {}) -> void:
	if enemy_data.is_empty():
		current_enemy = DEFAULT_TARGET.duplicate(true)
	else:
		current_enemy = enemy_data.duplicate(true)

	# ── Normalize enemy JSON fields to internal battle schema ──────────────
	# HP / max_hp: enemy JSON stores hp inside stats{}
	if not current_enemy.has("hp"):
		var s: Dictionary = current_enemy.get("stats", {})
		current_enemy["hp"]  = s.get("hp", 50)
	if not current_enemy.has("max_hp"):
		current_enemy["max_hp"] = current_enemy["hp"]

	# ATK: may be inside stats{}
	if not current_enemy.has("atk"):
		var s: Dictionary = current_enemy.get("stats", {})
		current_enemy["atk"] = s.get("atk", 8)

	# SPD: may be inside stats{}
	if not current_enemy.has("spd"):
		var s: Dictionary = current_enemy.get("stats", {})
		current_enemy["spd"] = s.get("spd", 5)

	# XP reward: enemy JSON uses exp_give
	if not current_enemy.has("exp_reward"):
		current_enemy["exp_reward"] = current_enemy.get("exp_give", 40)

	# Safe defaults for all schema fields
	if not current_enemy.has("name"):       current_enemy["name"]       = "Enemy"
	if not current_enemy.has("def"):        current_enemy["def"]        = 0
	if not current_enemy.has("dodge"):      current_enemy["dodge"]      = 0.0
	if not current_enemy.has("block"):      current_enemy["block"]      = 0.0
	if not current_enemy.has("fire_dmg"):   current_enemy["fire_dmg"]   = 4
	if not current_enemy.has("bleed_dmg"):  current_enemy["bleed_dmg"]  = 4
	if not current_enemy.has("max_energy"): current_enemy["max_energy"] = 60
	if not current_enemy.has("energy"):     current_enemy["energy"]     = current_enemy["max_energy"]
	if not current_enemy.has("moves"):      current_enemy["moves"]      = []
	if not current_enemy.has("sprite"):     current_enemy["sprite"]     = ""

	turn_count       = 1
	is_player_guarding = false
	current_state    = BattleState.INTRO
	enemy_move_index = 0

	# ── Sync & clear the player combatant object ───────────────────────────
	GameState._rebuild_player_combatant()
	StatusEffects.clear_all(GameState.player)
	current_enemy["effects"] = []

	set_actions_enabled(false)
	load_enemy_sprite(current_enemy)
	update_ui()

	show_dialog("Battle started against %s!" % current_enemy["name"])
	emit_signal("battle_started", current_enemy)

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
	is_player_guarding = false

	# ── Energy regen (flat per turn from STAT_CONFIG.battleEnergyRegen) ───
	var regen: int = GameState.get_battle_energy_regen()
	GameState.energy = min(GameState.max_energy, GameState.energy + regen)
	GameState.player["energy"] = GameState.energy

	# ── Tick DOTs & heals on the PLAYER ───────────────────────────────────
	var dot_msgs: Array = StatusEffects.tick_dot(GameState.player)
	for msg in dot_msgs:
		show_dialog(msg)
		await get_tree().create_timer(0.6).timeout
	GameState.sync_hp_from_combatant()
	update_ui()

	if GameState.player_hp <= 0:
		handle_defeat()
		return

	# ── Stunned / Sleep: skip player turn ─────────────────────────────────
	if StatusEffects.should_skip_turn(GameState.player):
		var skip_effect: String = "Stunned" if StatusEffects.has_effect(GameState.player, StatusEffects.STATUS_STUNNED) else "Asleep"
		show_dialog("You are %s and cannot act!" % skip_effect)
		# Decay effects at end of this skipped turn
		var expired: Array = StatusEffects.decay(GameState.player)
		for e in expired:
			show_dialog("%s faded." % e)
			await get_tree().create_timer(0.4).timeout
		await get_tree().create_timer(0.8).timeout
		start_enemy_turn()
		return

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

	# ── Tick DOTs & heals on the ENEMY ────────────────────────────────────
	var dot_msgs: Array = StatusEffects.tick_dot(current_enemy)
	for msg in dot_msgs:
		show_dialog(msg)
		await get_tree().create_timer(0.6).timeout
	update_ui()

	if current_enemy["hp"] <= 0:
		handle_victory()
		return

	# ── Stunned / Sleep: skip enemy turn ──────────────────────────────────
	if StatusEffects.should_skip_turn(current_enemy):
		var skip_effect: String = "Stunned" if StatusEffects.has_effect(current_enemy, StatusEffects.STATUS_STUNNED) else "Asleep"
		show_dialog("%s is %s and cannot act!" % [current_enemy["name"], skip_effect])
		var expired: Array = StatusEffects.decay(current_enemy)
		for e in expired:
			show_dialog("%s's %s faded." % [current_enemy["name"], e])
			await get_tree().create_timer(0.4).timeout
		await get_tree().create_timer(0.8).timeout
		end_round()
		return

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

	# Auto-select the first non-guard move when no move was pre-selected by UI
	if current_move.is_empty():
		current_move = _get_default_move()

	match current_move.get("type", "attack"):
		"attack":
			execute_player_attack()
		"heal":
			execute_player_heal()
		"buff":
			execute_player_self_buff()
		_:
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
	# Baby difficulty: no items restriction not active (items disabled only in Hardcore if added)
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
# ACTION EXECUTION HOOKS
# ==============================================================================
## Executes player attack — applies energy cost, dodge/block rolls, status multipliers.
func execute_player_attack() -> void:
	# ── Energy deduction ───────────────────────────────────────────────────
	var move_cost: int = current_move.get("energyCost", 0) if not current_move.is_empty() else 0
	if GameState.energy < move_cost:
		show_dialog("Not enough energy! (%d/%d needed)" % [GameState.energy, move_cost])
		await get_tree().create_timer(0.8).timeout
		set_actions_enabled(true)
		current_state = BattleState.PLAYER_TURN
		return
	GameState.energy -= move_cost
	GameState.player["energy"] = GameState.energy

	var raw_damage: int = calculate_player_damage()

	# Apply outgoing/incoming status multipliers
	var out_mult: float = StatusEffects.outgoing_multiplier(GameState.player)
	var in_mult : float = StatusEffects.incoming_multiplier(current_enemy)
	var damage  : int   = maxi(1, int(raw_damage * out_mult * in_mult))

	# Break Sleep on enemy
	if StatusEffects.notify_attacked(current_enemy):
		show_dialog("%s woke up from the hit!" % current_enemy["name"])
		await get_tree().create_timer(0.5).timeout

	# ── Dodge roll (enemy) ─────────────────────────────────────────────────
	var eff_dodge: float = StatusEffects.effective_dodge(current_enemy, current_enemy.get("dodge", 0.0))
	if randf() < eff_dodge:
		_flash_sprite(enemy_sprite, Color(0.8, 0.8, 1.0, 0.8))
		show_dialog("%s dodged the attack!" % current_enemy["name"])
		emit_signal("action_resolved", "player", "attack", 0)
		_finish_player_action()
		return

	# ── Block roll (enemy) ─────────────────────────────────────────────────
	var eff_block: float = StatusEffects.effective_block(current_enemy, current_enemy.get("block", 0.0))
	if randf() < eff_block:
		damage = max(1, int(damage * (1.0 - eff_block)))
		show_dialog("%s blocked! Reduced to %d damage." % [current_enemy["name"], damage])
		await get_tree().create_timer(0.5).timeout

	current_enemy["hp"] = max(0, current_enemy["hp"] - damage)
	update_ui()
	_flash_sprite(enemy_sprite, Color(1.0, 0.3, 0.3, 0.8))

	var move_name: String = current_move.get("name", "Attack") if not current_move.is_empty() else "Attack"
	show_dialog("%s! Dealt %d damage to %s." % [move_name, damage, current_enemy["name"]])
	emit_signal("action_resolved", "player", "attack", damage)

	_apply_move_effect(current_move, current_enemy, GameState.player)
	_finish_player_action()


## Executes guarding stance.
func execute_player_guard() -> void:
	is_player_guarding = true
	show_dialog("You braced for impact! Guard is active.")
	emit_signal("action_resolved", "player", "guard", 0)
	await get_tree().create_timer(1.0).timeout
	start_enemy_turn()


## Executes item usage — reads effect from ITEM_DATA.json generically.
func execute_player_item() -> void:
	# Find first item in inventory with qty > 0
	var used_id: String = ""
	for item_id in GameState.inventory:
		if GameState.inventory[item_id] > 0:
			used_id = item_id
			break

	if used_id.is_empty():
		show_dialog("No items in inventory!")
		set_actions_enabled(true)
		current_state = BattleState.PLAYER_TURN
		return

	var item_cfg: Dictionary = {}
	if DataManager and DataManager.item_data and DataManager.item_data.has(used_id):
		item_cfg = DataManager.item_data[used_id]

	GameState.inventory[used_id] -= 1
	var eff: Dictionary = item_cfg.get("effect", {})
	var eff_type: String = eff.get("type", "heal")
	var eff_amt : int    = eff.get("amount", 35)
	var item_name: String = item_cfg.get("name", used_id.capitalize())

	match eff_type:
		"heal":
			GameState.player["hp"] = min(GameState.player["max_hp"], GameState.player["hp"] + eff_amt)
			GameState.sync_hp_from_combatant()
			update_ui()
			_flash_sprite(player_sprite, Color(0.3, 1.0, 0.3, 0.8))
			show_dialog("Used %s! Restored %d HP." % [item_name, eff_amt])
			emit_signal("action_resolved", "player", "item", eff_amt)
		"energy":
			GameState.energy = min(GameState.max_energy, GameState.energy + eff_amt)
			GameState.player["energy"] = GameState.energy
			update_ui()
			show_dialog("Used %s! Restored %d Energy." % [item_name, eff_amt])
			emit_signal("action_resolved", "player", "item", eff_amt)
		"damage":
			current_enemy["hp"] = max(0, current_enemy["hp"] - eff_amt)
			update_ui()
			_flash_sprite(enemy_sprite, Color(1.0, 0.3, 0.3, 0.8))
			show_dialog("Used %s! Dealt %d damage!" % [item_name, eff_amt])
			emit_signal("action_resolved", "player", "item", eff_amt)

	await get_tree().create_timer(1.2).timeout
	if current_enemy["hp"] <= 0:
		handle_victory()
	else:
		start_enemy_turn()


## Executes run / escape attempt.
func execute_player_run() -> void:
	show_dialog("Attempting to escape...")
	await get_tree().create_timer(0.8).timeout
	var escape_roll: float = randf()
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


## Executes enemy action — cycles through moves, checks energy, rolls player dodge/block.
func execute_enemy_turn() -> void:
	# ── Enemy energy regen ────────────────────────────────────────────────
	var e_regen: int = GameState.get_battle_energy_regen()
	current_enemy["energy"] = min(current_enemy.get("max_energy", 60),
								  current_enemy.get("energy", 0) + e_regen)

	# ── Pick next affordable move (fixed cycle) ───────────────────────────
	var moves: Array = current_enemy.get("moves", [])
	var chosen_move: Dictionary = {}
	var attempts: int = 0
	while attempts < moves.size():
		var candidate: Dictionary = moves[enemy_move_index % moves.size()] as Dictionary
		var cost: int = candidate.get("energyCost", 0)
		if current_enemy.get("energy", 0) >= cost:
			chosen_move = candidate
			current_enemy["energy"] -= cost
			enemy_move_index = (enemy_move_index + 1) % max(1, moves.size())
			break
		enemy_move_index = (enemy_move_index + 1) % max(1, moves.size())
		attempts += 1

	# If no move was affordable, do a free basic attack using flat atk stat
	if chosen_move.is_empty():
		chosen_move = {
			"name": "Attack", "scaling": null, "power": 1.0,
			"energyCost": 0, "type": "attack", "effect": null
		}

	var move_type: String = chosen_move.get("type", "attack")

	# ── Self-buff move (e.g. Pupa's Harden → Regen) ──────────────────────
	if move_type == "buff":
		_apply_move_effect(chosen_move, GameState.player, current_enemy)
		show_dialog("%s used %s!" % [current_enemy["name"], chosen_move.get("name", "Skill")])
		await get_tree().create_timer(1.0).timeout
		_finish_enemy_action()
		return

	# ── Attack move ────────────────────────────────────────────────────────
	var raw_damage: int = calculate_enemy_damage(chosen_move)

	# Status multipliers
	var out_mult: float = StatusEffects.outgoing_multiplier(current_enemy)
	var in_mult : float = StatusEffects.incoming_multiplier(GameState.player)
	var incoming_damage: int = maxi(1, int(raw_damage * out_mult * in_mult))

	# ── Difficulty modifier ────────────────────────────────────────────────
	# Baby: player takes 50% less damage from enemies
	if GameState.difficulty == "baby":
		incoming_damage = maxi(1, int(incoming_damage * 0.5))

	# Break Sleep on the player
	if StatusEffects.notify_attacked(GameState.player):
		show_dialog("You woke up from the hit!")
		await get_tree().create_timer(0.5).timeout

	# ── Player Dodge roll ──────────────────────────────────────────────────
	var p_dodge: float = StatusEffects.effective_dodge(GameState.player, GameState.player.get("dodge", 0.0))
	if randf() < p_dodge:
		_flash_sprite(player_sprite, Color(0.8, 0.8, 1.0, 0.8))
		show_dialog("You dodged %s's attack!" % current_enemy["name"])
		emit_signal("action_resolved", "enemy", "attack", 0)
		_finish_enemy_action()
		return

	# ── Player Block roll ──────────────────────────────────────────────────
	if is_player_guarding:
		incoming_damage = maxi(1, int(incoming_damage * 0.5))
		show_dialog("Your guard softened the impact!")
		await get_tree().create_timer(0.8).timeout
	else:
		var p_block: float = StatusEffects.effective_block(GameState.player, GameState.player.get("block", 0.0))
		if randf() < p_block:
			incoming_damage = maxi(1, int(incoming_damage * (1.0 - p_block)))
			show_dialog("You blocked! Reduced to %d damage." % incoming_damage)
			await get_tree().create_timer(0.5).timeout

	GameState.player["hp"] = max(0, GameState.player["hp"] - incoming_damage)
	GameState.sync_hp_from_combatant()
	update_ui()
	_flash_sprite(player_sprite, Color(1.0, 0.3, 0.3, 0.8))

	show_dialog("%s used %s for %d damage!" % [current_enemy["name"], chosen_move.get("name", "Attack"), incoming_damage])
	emit_signal("action_resolved", "enemy", "attack", incoming_damage)

	# Apply move effect to player if move has one
	_apply_move_effect(chosen_move, GameState.player, current_enemy)

	_finish_enemy_action()


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
	GameState.stage += 1
	update_ui()
	show_dialog("Gained +%d EXP!" % exp_gained)

	# Auto-save after every victory
	SaveManager.save()

	await get_tree().create_timer(1.5).timeout
	get_tree().change_scene_to_file("res://Scenes/PostBattle.tscn")


func handle_defeat() -> void:
	current_state = BattleState.DEFEAT
	show_dialog("You have fallen in battle...")
	emit_signal("battle_ended", "defeat")

	await get_tree().create_timer(2.0).timeout

	if GameState.difficulty == "hardcore":
		# Permadeath — full reset back to character creation
		show_dialog("Permadeath! Your journey ends here...")
		await get_tree().create_timer(1.5).timeout
		_wipe_save()
		get_tree().change_scene_to_file("res://Scenes/CharacterSelect.tscn")
	else:
		GameState.player_hp = GameState.max_player_hp
		get_tree().change_scene_to_file("res://Scenes/Main.tscn")


## Wipes all GameState progress (called on Hardcore permadeath).
func _wipe_save() -> void:
	GameState.player_name    = ""
	GameState.selected_class = "sword"
	GameState.gender         = "male"
	GameState.difficulty     = "normal"
	GameState.level          = 1
	GameState.xp             = 0
	GameState.xp_to_next     = 100
	GameState.score          = 0
	GameState.stage          = 1
	GameState.stat_points    = 0
	GameState.bonus_stats    = { "str": 0, "int": 0, "dex": 0, "spd": 0, "hp": 0, "faith": 0 }
	GameState.inventory      = {}
	GameState.materials      = {}
	GameState._rebuild_player_combatant()
	SaveManager.delete_save()


# ==============================================================================
# FORMULAS & COMBAT CALCULATIONS (EDIT THESE FOR STAT SCALING / RULES)
# ==============================================================================
## Calculates player attack power driven by the current move's scaling + power fields.
## Falls back gracefully if current_move is empty (auto-derives from class).
func calculate_player_damage() -> int:
	var stats: Dictionary = GameState.get_class_stats()
	var cfg  : Dictionary = DataManager.stat_config if DataManager and DataManager.stat_config else {}

	var scaling   : String = current_move.get("scaling", "") if not current_move.is_empty() else ""
	var power_mult: float  = current_move.get("power", 1.0)  if not current_move.is_empty() else 1.0

	var stat_val  : float = 0.0
	var dmg_per_pt: float = 1.0

	match scaling:
		"str":
			stat_val   = stats.get("str", 10)
			dmg_per_pt = cfg.get("strDmgPerPoint", 0.8)
		"int":
			stat_val   = stats.get("int", 5)
			dmg_per_pt = cfg.get("intDmgPerPoint", 0.9)
		"dex":
			stat_val   = stats.get("dex", 5)
			dmg_per_pt = cfg.get("dexDmgPerPoint", 0.7)
		"faith":
			stat_val   = stats.get("faith", 0)
			dmg_per_pt = cfg.get("faithDmgPerPoint", 0.9)
		_:
			# No scaling specified — use the highest offensive stat as fallback
			stat_val   = max(stats.get("str", 10), max(stats.get("int", 5), stats.get("dex", 5)))
			dmg_per_pt = 0.8

	var base_power: int = 15 + int(stat_val * dmg_per_pt * power_mult)
	var variance  : int = randi_range(-3, 4)
	var def_val   : int = current_enemy.get("def", 0)
	return maxi(1, base_power + variance - def_val)


## Calculates heal amount from the current move's scaling stat.
func calculate_player_heal() -> int:
	var stats: Dictionary = GameState.get_class_stats()
	var cfg  : Dictionary = DataManager.stat_config if DataManager and DataManager.stat_config else {}

	var scaling    : String = current_move.get("scaling", "faith") if not current_move.is_empty() else "faith"
	var power_mult : float  = current_move.get("power", 1.0)       if not current_move.is_empty() else 1.0
	var heal_per_pt: float  = cfg.get("faithHealPerPoint", 1.2)

	var stat_val: float = stats.get(scaling, stats.get("int", 5))
	return maxi(1, int(stat_val * heal_per_pt * power_mult * 5))


## Calculates enemy attack power using the chosen move's power multiplier.
func calculate_enemy_damage(chosen_move: Dictionary = {}) -> int:
	var base_atk  : int   = current_enemy.get("atk", 10)
	var power_mult: float = chosen_move.get("power", 1.0) if not chosen_move.is_empty() else 1.0
	var variance  : int   = randi_range(-2, 3)
	return maxi(1, int((base_atk + variance) * power_mult))


# ==============================================================================
# TURN FINISH HELPERS
# ==============================================================================
## Shared teardown after any player action — decays effects, resets move, transitions.
func _finish_player_action() -> void:
	var expired: Array = StatusEffects.decay(GameState.player)
	for e in expired:
		show_dialog("%s faded." % e)
		await get_tree().create_timer(0.4).timeout

	current_move = {}
	await get_tree().create_timer(1.2).timeout

	if current_enemy["hp"] <= 0:
		handle_victory()
	else:
		start_enemy_turn()


## Shared teardown after any enemy action — decays effects, transitions.
func _finish_enemy_action() -> void:
	var expired: Array = StatusEffects.decay(current_enemy)
	for e in expired:
		show_dialog("%s's %s faded." % [current_enemy["name"], e])
		await get_tree().create_timer(0.4).timeout

	await get_tree().create_timer(1.2).timeout

	if GameState.player_hp <= 0:
		handle_defeat()
	else:
		end_round()


# ==============================================================================
# MOVE HELPERS
# ==============================================================================
## Returns the first non-guard, non-buff move from the class move list.
## Called by _on_fight_pressed when no move was pre-selected by the UI.
func _get_default_move() -> Dictionary:
	var moves: Array = GameState.get_class_moves()
	for move in moves:
		var m: Dictionary = move as Dictionary
		var t: String = m.get("type", "attack")
		if t in ["attack", "heal"]:
			return m
	return {}


## Applies a move's `effect` payload to the target (or caster if target="self").
## move:   The move Dictionary from CLASS_DATA (may have effect: null).
## target: The combatant Dictionary to receive the enemy-facing effect.
## caster: The combatant Dictionary to receive self-targeted effects.
func _apply_move_effect(move: Dictionary, target: Dictionary, caster: Dictionary) -> void:
	if move.is_empty():
		return
	if not move.has("effect"):
		return
	var raw_eff = move["effect"]
	if not (raw_eff is Dictionary):
		return
	var eff: Dictionary = raw_eff as Dictionary

	var eff_id    : String = eff.get("id", "")
	var eff_stacks: int    = eff.get("stacks", 1)
	var eff_dur   : int    = eff.get("duration", -1)
	var eff_chance: float  = eff.get("chance", 1.0)
	var eff_target: String = eff.get("target", "enemy")

	if eff_id.is_empty():
		return

	if randf() > eff_chance:
		# Effect did not proc
		var label: String = StatusEffects.STATUS_LABELS.get(eff_id, eff_id)
		show_dialog("%s resisted %s!" % [target.get("name", "Target"), label])
		return

	var recipient: Dictionary = caster if eff_target == "self" else target
	StatusEffects.apply(recipient, eff_id, eff_stacks, eff_dur, "player")

	var label: String = StatusEffects.STATUS_LABELS.get(eff_id, eff_id)
	if eff_target == "self":
		show_dialog("You gained %s!" % label)
	else:
		show_dialog("%s is now %s!" % [target.get("name", "Target"), label])


## Executes a heal-type move (e.g. Priest's Heal).
func execute_player_heal() -> void:
	var move_cost: int = current_move.get("energyCost", 0) if not current_move.is_empty() else 0
	if GameState.energy < move_cost:
		show_dialog("Not enough energy! (%d/%d needed)" % [GameState.energy, move_cost])
		await get_tree().create_timer(0.8).timeout
		set_actions_enabled(true)
		current_state = BattleState.PLAYER_TURN
		return
	GameState.energy -= move_cost
	GameState.player["energy"] = GameState.energy

	var heal: int = calculate_player_heal()
	GameState.player["hp"] = mini(GameState.player["max_hp"], GameState.player["hp"] + heal)
	GameState.sync_hp_from_combatant()
	update_ui()
	_flash_sprite(player_sprite, Color(0.3, 1.0, 0.3, 0.8))

	var move_name: String = current_move.get("name", "Heal") if not current_move.is_empty() else "Heal"
	show_dialog("%s! Restored %d HP." % [move_name, heal])
	emit_signal("action_resolved", "player", "heal", heal)

	_apply_move_effect(current_move, current_enemy, GameState.player)
	_finish_player_action()


## Executes a buff-type move (e.g. Priest's Holy Light applying Regen to self).
func execute_player_self_buff() -> void:
	var move_cost: int = current_move.get("energyCost", 0) if not current_move.is_empty() else 0
	if GameState.energy < move_cost:
		show_dialog("Not enough energy! (%d/%d needed)" % [GameState.energy, move_cost])
		await get_tree().create_timer(0.8).timeout
		set_actions_enabled(true)
		current_state = BattleState.PLAYER_TURN
		return
	GameState.energy -= move_cost
	GameState.player["energy"] = GameState.energy

	_apply_move_effect(current_move, current_enemy, GameState.player)

	var move_name: String = current_move.get("name", "Buff") if not current_move.is_empty() else "Buff"
	show_dialog("Used %s!" % move_name)
	emit_signal("action_resolved", "player", "buff", 0)
	_finish_player_action()






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
	var folder : String = "res://Assets/Sprites/Player/Body/" + gender.capitalize() + "/"

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
