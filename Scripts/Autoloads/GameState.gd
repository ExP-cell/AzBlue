extends Node

var selected_class: String = "sword"
var gender: String = "male"
var level: int = 1
var xp: int = 0
var xp_to_next: int = 100
var score: int = 0
var stage: int = 1

var player_hp: int = 100
var max_player_hp: int = 100
var energy: int = 100
var max_energy: int = 100

var difficulty: String = "normal" # baby, normal, hardcore
var inventory: Dictionary = {
	"potion": 2,
	"ether": 1,
	"bomb": 1
}
var materials: Dictionary = {}

func _ready() -> void:
	pass

# ── Gameplay Progression Helpers ──────────────────────────────────────────────
func add_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = int(xp_to_next * 1.55)
		max_player_hp += 10
		player_hp = max_player_hp
		print("Level Up! New Level: %d | Max HP: %d" % [level, max_player_hp])

func get_current_class_data() -> Dictionary:
	if DataManager and DataManager.class_data and DataManager.class_data.has(selected_class):
		return DataManager.class_data[selected_class]
	return {}

func get_class_moves() -> Array:
	var data := get_current_class_data()
	return data.get("moves", [])

func get_class_stats() -> Dictionary:
	var data := get_current_class_data()
	return data.get("stats", { "str": 10, "int": 5, "dex": 5, "spd": 5, "hp": 20 })

func use_item(item_id: String) -> bool:
	if inventory.get(item_id, 0) > 0:
		inventory[item_id] -= 1
		return true
	return false

func reset_player() -> void:
	player_hp = max_player_hp
	energy = max_energy
