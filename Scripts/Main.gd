extends Control

# ==============================================================================
# MAIN MENU
# ==============================================================================
# Buttons:
#   New Game  → CharacterSelect.tscn
#   Continue  → loads save, then Battle.tscn  (hidden if no save exists)
#   Quit      → exit
# ==============================================================================

@onready var new_game_btn : Button = $CenterBox/NewGameBtn
@onready var continue_btn : Button = $CenterBox/ContinueBtn
@onready var quit_btn     : Button = $CenterBox/QuitBtn
@onready var title_label  : Label  = $CenterBox/TitleLabel


func _ready() -> void:
	if title_label:
		title_label.text = "AzBlue"

	# Show Continue only if a save exists
	if continue_btn:
		continue_btn.visible = SaveManager.has_save()

	if new_game_btn:
		new_game_btn.pressed.connect(_on_new_game_pressed)
	if continue_btn:
		continue_btn.pressed.connect(_on_continue_pressed)
	if quit_btn:
		quit_btn.pressed.connect(_on_quit_pressed)


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/CharacterSelect.tscn")


func _on_continue_pressed() -> void:
	if SaveManager.has_save():
		SaveManager.load_save()
		get_tree().change_scene_to_file("res://Scenes/Battle.tscn")
	else:
		# Fallback: no save found — go to character creation
		get_tree().change_scene_to_file("res://Scenes/CharacterSelect.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
