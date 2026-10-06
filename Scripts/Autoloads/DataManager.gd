extends Node

var monsters = {}
var class_data = {}
var item_data = {}
var c_challenges = []
var xp_rewards = {}
var stat_config = {}

func _ready():
	load_all_data()

func load_all_data():
	class_data = load_json("res://Data/CLASS_DATA.json")
	item_data = load_json("res://Data/ITEM_DATA.json")
	c_challenges = load_json("res://Data/C_CHALLENGES.json")
	xp_rewards = load_json("res://Data/XP_REWARDS.json")
	stat_config = load_json("res://Data/STAT_CONFIG.json")
	
	# Load all monsters in the Monsters folder
	var dir = DirAccess.open("res://Data/Monsters")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if !dir.current_is_dir() and file_name.ends_with(".json"):
				var monster_name = file_name.replace(".json", "")
				monsters[monster_name] = load_json("res://Data/Monsters/" + file_name)
			file_name = dir.get_next()
	
	print("CodeQuest Data successfully loaded into Godot!")

func load_json(file_path: String) -> Variant:
	if FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		if error == OK:
			return json.data
		else:
			push_error("JSON Parse Error in " + file_path + " at line " + str(json.get_error_line()) + ": " + json.get_error_message())
	else:
		push_error("File not found: " + file_path)
	return null
