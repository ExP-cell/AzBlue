extends Node

# This replaces your gs object from state.js
var selected_class = ""
var level = 1
var xp = 0
var xp_to_next = 100
var score = 0
var stage = 0

var player_hp = 100
var max_player_hp = 100
var energy = 100
var max_energy = 100

var difficulty = "normal" # baby, normal, hardcore
var inventory = {}
var materials = {}

# We will load data here
func _ready():
    pass
