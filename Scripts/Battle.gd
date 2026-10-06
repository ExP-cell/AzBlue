extends Node2D

# ─────────────────────────────────────────────────────
#  SPRITE SHEET FRAME CONFIG  (adjust if frames look off)
#  Ragnarok Online sprite sheet directions (8-dir):
#    Row 0 = South  | Row 1 = SW  | Row 2 = West
#    Row 3 = NW     | Row 4 = North
#    Row 5 = NE     | Row 6 = East | Row 7 = SE
#
#  We want:
#    Player → NW  (row 3) — faces upper-left
#    Enemy  → SE  (row 7) — faces lower-right
# ─────────────────────────────────────────────────────
const FRAME_W   := 65    # pixel width  of one sprite frame  — tweak me
const FRAME_H   := 81    # pixel height of one sprite frame  — tweak me
const FRAMES_PER_ROW := 8

const PLAYER_DIR_ROW := 3   # NW direction (faces upper-left)
const ENEMY_DIR_ROW  := 7   # SE direction (faces lower-right)
const IDLE_FRAME     := 0   # first frame of the row = standing still

# ─────────────────────────────────────────────────────
#  SCENE LAYOUT POSITIONS (1280x720 base)
# ─────────────────────────────────────────────────────
const ENEMY_POS    := Vector2(850, 200)
const ENEMY_SCALE  := Vector2(4.0, 4.0)

const PLAYER_POS   := Vector2(280, 440)
const PLAYER_SCALE := Vector2(4.0, 4.0)

# ─────────────────────────────────────────────────────
#  NODES
# ─────────────────────────────────────────────────────
@onready var player_sprite : Sprite2D = $PlayerSprite
@onready var enemy_sprite  : Sprite2D = $EnemySprite

@onready var enemy_name_lbl  : Label       = $EnemyInfoBox/EnemyName
@onready var enemy_hp_bar    : ProgressBar = $EnemyInfoBox/EnemyHP

@onready var player_name_lbl : Label       = $PlayerInfoBox/PlayerName
@onready var player_hp_bar   : ProgressBar = $PlayerInfoBox/PlayerHP
@onready var player_exp_bar  : ProgressBar = $PlayerInfoBox/PlayerEXP

@onready var dialog_label    : Label       = $DialogBox/DialogText


func _ready() -> void:
	setup_player_sprite()
	setup_ui()
	show_dialog("A wild enemy appeared!")


# ─────────────────────────────────────────────────────
#  LOAD PLAYER SPRITE (from GameState class + gender)
# ─────────────────────────────────────────────────────
func setup_player_sprite() -> void:
	var cls    : String = GameState.selected_class   # "mage" | "sword" | "thief"
	var gender : String = GameState.gender           # "male"  | "female"
	var folder : String = "res://Assets/Player/Body/" + gender.capitalize() + "/"

	# Map class name to filename keyword
	var class_map := { "mage": "Mage", "sword": "Swordsman", "thief": "Thief" }
	var keyword   : String = class_map.get(cls, "Mage")

	# Find the file that contains the keyword
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


# ─────────────────────────────────────────────────────
#  LOAD ENEMY SPRITE (called from CombatManager)
# ─────────────────────────────────────────────────────
func load_enemy_sprite(monster_data: Dictionary) -> void:
	var sprite_path : String = monster_data.get("sprite", "")
	if sprite_path == "":
		return

	if ResourceLoader.exists(sprite_path):
		var tex : Texture2D = load(sprite_path)
		# If enemy uses an RO-style sheet, crop SE direction
		# If it's a single standalone image, just show it as-is
		if tex.get_width() > FRAME_W * 2:
			_apply_directional_frame(enemy_sprite, tex, ENEMY_DIR_ROW)
		else:
			enemy_sprite.texture        = tex
			enemy_sprite.region_enabled = false

	enemy_sprite.position = ENEMY_POS
	enemy_sprite.scale    = ENEMY_SCALE

	# Update enemy info box
	enemy_name_lbl.text = monster_data.get("name", "???")
	var stats := monster_data.get("stats", {})
	enemy_hp_bar.max_value = stats.get("hp", 100)
	enemy_hp_bar.value     = stats.get("hp", 100)


# ─────────────────────────────────────────────────────
#  CROP ONE DIRECTIONAL FRAME FROM A SPRITE SHEET
# ─────────────────────────────────────────────────────
func _apply_directional_frame(sprite: Sprite2D, tex: Texture2D, dir_row: int) -> void:
	sprite.texture        = tex
	sprite.region_enabled = true
	sprite.region_rect    = Rect2(
		IDLE_FRAME * FRAME_W,   # x: which frame column (0 = first/idle)
		dir_row    * FRAME_H,   # y: which direction row
		FRAME_W,
		FRAME_H
	)


# ─────────────────────────────────────────────────────
#  UI SETUP
# ─────────────────────────────────────────────────────
func setup_ui() -> void:
	player_name_lbl.text     = GameState.selected_class.capitalize()
	player_hp_bar.max_value  = GameState.max_player_hp
	player_hp_bar.value      = GameState.player_hp
	player_exp_bar.max_value = GameState.xp_to_next
	player_exp_bar.value     = GameState.xp


func show_dialog(text: String) -> void:
	dialog_label.text = text


# ─────────────────────────────────────────────────────
#  ACTION BUTTONS
# ─────────────────────────────────────────────────────
func _on_fight_pressed()  -> void:
	show_dialog("Choose a move!")

func _on_items_pressed()  -> void:
	show_dialog("Choose an item!")

func _on_guard_pressed()  -> void:
	show_dialog(GameState.selected_class.capitalize() + " is guarding!")

func _on_run_pressed()    -> void:
	show_dialog("Got away safely!")
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")
