extends Node

var monsters   : Dictionary = {}
var class_data : Dictionary = {}
var item_data  : Dictionary = {}
var xp_rewards : Dictionary = {}
var stat_config: Dictionary = {}

func _ready() -> void:
	load_all_data()

func load_all_data() -> void:
	class_data  = load_json_dict("res://Data/CLASS_DATA.json")
	item_data   = load_json_dict("res://Data/ITEM_DATA.json")
	if FileAccess.file_exists("res://Data/XP_REWARDS.json"):
		xp_rewards = load_json_dict("res://Data/XP_REWARDS.json")
	else:
		xp_rewards = {}
	stat_config = load_json_dict("res://Data/STAT_CONFIG.json")

	# Recursively load all monster JSON files from Data/Monsters subfolders
	_load_monsters_from("res://Data/Monsters")

	print("AzBlue Data successfully loaded into Godot!")


func _load_monsters_from(base_path: String) -> void:
	var dir: DirAccess = DirAccess.open(base_path)
	if not dir:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			_load_monsters_from(base_path + "/" + entry)
		elif entry.ends_with(".json"):
			var key: String = entry.replace(".json", "")
			monsters[key] = load_json_dict(base_path + "/" + entry)
		entry = dir.get_next()


## Returns parsed JSON as a Dictionary. Returns {} on error or wrong type.
func load_json_dict(file_path: String) -> Dictionary:
	var result: Variant = _parse_json(file_path)
	if result is Dictionary:
		return result as Dictionary
	return {}


## Returns parsed JSON as an Array. Returns [] on error or wrong type.
func load_json_array(file_path: String) -> Array:
	var result: Variant = _parse_json(file_path)
	if result is Array:
		return result as Array
	return []


## Raw JSON parse — returns Variant (Dictionary, Array, or null on failure).
## Use load_json_dict() or load_json_array() in preference to this.
func load_json(file_path: String) -> Variant:
	return _parse_json(file_path)


func _parse_json(file_path: String) -> Variant:
	if not FileAccess.file_exists(file_path):
		push_error("File not found: " + file_path)
		return null
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Cannot open file: " + file_path)
		return null
	var json: JSON = JSON.new()
	var err: int = json.parse(file.get_as_text())
	if err != OK:
		push_error("JSON Parse Error in %s at line %d: %s" % [
			file_path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
