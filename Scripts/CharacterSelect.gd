extends Control

# ==============================================================================
# CHARACTER SELECT SCREEN
# ==============================================================================
# Layout:
#   LEFT   — 5 class cards in a horizontal row (click to select)
#   CENTER — Character sprite preview (forward-facing, from spritesheet)
#   RIGHT  — Gender selector, Name field, Difficulty picker, Confirm button
#
# On Confirm:
#   • Sets GameState.player_name, selected_class, gender, difficulty
#   • Calls GameState._rebuild_player_combatant()
#   • Transitions to res://Scenes/Battle.tscn
# ==============================================================================

const FRAME_W        := 65
const FRAME_H        := 81
const FRAMES_PER_ROW := 8
# Row 1 = South (forward-facing) in standard RO spritesheets
const FORWARD_ROW    := 1
const IDLE_FRAME     := 0

const CLASSES: Array = ["mage", "sword", "assassin", "ranger", "priest"]
const CLASS_LABELS: Dictionary = {
	"mage":     "Mage",
	"sword":    "Swordsman",
	"assassin": "Assassin",
	"ranger":   "Ranger",
	"priest":   "Priest",
}
const CLASS_DESCRIPTIONS: Dictionary = {
	"mage":     "Wields elemental magic.\nScales with INT.",
	"sword":    "Sturdy melee fighter.\nScales with STR.",
	"assassin": "Swift and deadly.\nScales with DEX.",
	"ranger":   "Precise ranged attacks.\nScales with DEX.",
	"priest":   "Heals and protects.\nScales with FTH.",
}

# ── State ─────────────────────────────────────────────────────────────────────
var selected_class : String = "sword"
var selected_gender: String = "male"

# ── Node refs ─────────────────────────────────────────────────────────────────
@onready var class_cards_box  : HBoxContainer  = $HBox/LeftPanel/VBox/ClassCards
@onready var preview_sprite   : Sprite2D       = $HBox/CenterPanel/VBox/PreviewSprite
@onready var preview_label    : Label          = $HBox/CenterPanel/VBox/ClassName
@onready var class_desc_label : Label          = $HBox/CenterPanel/VBox/ClassDesc

@onready var male_btn         : Button         = $HBox/RightPanel/VBox/GenderRow/MaleBtn
@onready var female_btn       : Button         = $HBox/RightPanel/VBox/GenderRow/FemaleBtn
@onready var name_field       : LineEdit       = $HBox/RightPanel/VBox/NameField

@onready var baby_btn         : Button         = $HBox/RightPanel/VBox/DiffRow/BabyBtn
@onready var normal_btn       : Button         = $HBox/RightPanel/VBox/DiffRow/NormalBtn
@onready var hardcore_btn     : Button         = $HBox/RightPanel/VBox/DiffRow/HardcoreBtn

@onready var confirm_btn      : Button         = $HBox/RightPanel/VBox/ConfirmBtn
@onready var diff_label       : Label          = $HBox/RightPanel/VBox/DiffDesc


func _ready() -> void:
	_build_class_cards()
	_connect_gender_buttons()
	_connect_difficulty_buttons()
	if confirm_btn:
		confirm_btn.pressed.connect(_on_confirm_pressed)
	_select_class(selected_class)
	_select_gender(selected_gender)
	_select_difficulty("normal")


# ==============================================================================
# CLASS CARDS
# ==============================================================================
func _build_class_cards() -> void:
	if not class_cards_box:
		return
	for cls in CLASSES:
		var card := Button.new()
		card.text = CLASS_LABELS.get(cls, cls.capitalize())
		card.custom_minimum_size = Vector2(90, 60)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.pressed.connect(_select_class.bind(cls))
		class_cards_box.add_child(card)


func _select_class(cls: String) -> void:
	selected_class = cls
	if preview_label:
		preview_label.text = CLASS_LABELS.get(cls, cls.capitalize())
	if class_desc_label:
		class_desc_label.text = CLASS_DESCRIPTIONS.get(cls, "")
	_update_preview_sprite()
	_highlight_class_card(cls)


func _highlight_class_card(cls: String) -> void:
	if not class_cards_box:
		return
	var i := 0
	for card in class_cards_box.get_children():
		var btn: Button = card as Button
		if CLASSES[i] == cls:
			btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		else:
			btn.remove_theme_color_override("font_color")
		i += 1


# ==============================================================================
# SPRITE PREVIEW
# ==============================================================================
func _update_preview_sprite() -> void:
	if not preview_sprite:
		return
	var gender := selected_gender
	var folder : String = "res://Assets/Sprites/Player/Body/" + gender.capitalize() + "/"
	var keyword : String = _class_to_keyword(selected_class)

	var dir := DirAccess.open(folder)
	if not dir:
		preview_sprite.texture = null
		return

	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".png") and keyword in fname:
			var tex: Texture2D = load(folder + fname)
			_apply_frame(preview_sprite, tex, FORWARD_ROW)
			preview_sprite.scale = Vector2(3.0, 3.0)
			break
		fname = dir.get_next()


func _apply_frame(sprite: Sprite2D, tex: Texture2D, dir_row: int) -> void:
	if not sprite or not tex:
		return
	sprite.texture        = tex
	sprite.region_enabled = true
	sprite.region_rect    = Rect2(
		IDLE_FRAME * FRAME_W,
		dir_row    * FRAME_H,
		FRAME_W,
		FRAME_H
	)


func _class_to_keyword(cls: String) -> String:
	var map: Dictionary = {
		"mage":     "Mage",
		"sword":    "Swordsman",
		"assassin": "Thief",
		"ranger":   "Thief",
		"priest":   "Mage",
	}
	return map.get(cls, "Swordsman")


# ==============================================================================
# GENDER
# ==============================================================================
func _connect_gender_buttons() -> void:
	if male_btn:
		male_btn.pressed.connect(_select_gender.bind("male"))
	if female_btn:
		female_btn.pressed.connect(_select_gender.bind("female"))


func _select_gender(gender: String) -> void:
	selected_gender = gender
	if male_btn:
		male_btn.add_theme_color_override("font_color",
			Color(0.4, 0.8, 1.0) if gender == "male" else Color.WHITE)
	if female_btn:
		female_btn.add_theme_color_override("font_color",
			Color(1.0, 0.6, 0.8) if gender == "female" else Color.WHITE)
	_update_preview_sprite()


# ==============================================================================
# DIFFICULTY
# ==============================================================================
func _connect_difficulty_buttons() -> void:
	if baby_btn:
		baby_btn.pressed.connect(_select_difficulty.bind("baby"))
	if normal_btn:
		normal_btn.pressed.connect(_select_difficulty.bind("normal"))
	if hardcore_btn:
		hardcore_btn.pressed.connect(_select_difficulty.bind("hardcore"))


func _select_difficulty(diff: String) -> void:
	GameState.difficulty = diff
	var descriptions: Dictionary = {
		"baby":     "Baby — Enemies deal 50% less damage. Recommended for newcomers.",
		"normal":   "Normal — Balanced experience.",
		"hardcore": "Hardcore — Permadeath. One life only.",
	}
	if diff_label:
		diff_label.text = descriptions.get(diff, "")

	var btns: Dictionary = { "baby": baby_btn, "normal": normal_btn, "hardcore": hardcore_btn }
	for d in btns:
		var b: Button = btns[d] as Button
		if b:
			b.add_theme_color_override("font_color",
				Color(1.0, 0.85, 0.2) if d == diff else Color.WHITE)


# ==============================================================================
# CONFIRM
# ==============================================================================
func _on_confirm_pressed() -> void:
	var name_text: String = name_field.text.strip_edges() if name_field else ""
	if name_text.is_empty():
		name_text = CLASS_LABELS.get(selected_class, "Hero")

	GameState.player_name    = name_text
	GameState.selected_class = selected_class
	GameState.gender         = selected_gender
	# difficulty already set via _select_difficulty()

	# Reset all progress for a fresh run
	GameState.level       = 1
	GameState.xp          = 0
	GameState.xp_to_next  = 100
	GameState.score       = 0
	GameState.stage       = 1
	GameState.stat_points = 0
	GameState.bonus_stats = { "str": 0, "int": 0, "dex": 0, "spd": 0, "hp": 0, "faith": 0 }
	GameState.inventory   = {}
	GameState.materials   = {}

	GameState._rebuild_player_combatant()
	GameState.player_hp = GameState.max_player_hp
	GameState.energy    = GameState.max_energy

	SaveManager.save()
	get_tree().change_scene_to_file("res://Scenes/Battle.tscn")
