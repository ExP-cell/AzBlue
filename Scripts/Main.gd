extends Control

# Base script for the Main menu / hub scene.
# Coordinates the overarching gameplay loop into the Battle scene.

@onready var start_btn: Button = $StartBattleBtn
@onready var status_lbl: Label = $Label

func _ready() -> void:
	if start_btn:
		start_btn.pressed.connect(_on_start_battle_pressed)

	if status_lbl:
		status_lbl.text = "CodeQuest RPG\nClass: %s | LVL: %d | XP: %d/%d | HP: %d/%d" % [
			GameState.selected_class.capitalize(),
			GameState.level,
			GameState.xp,
			GameState.xp_to_next,
			GameState.player_hp,
			GameState.max_player_hp
		]

func _on_start_battle_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/Battle.tscn")
