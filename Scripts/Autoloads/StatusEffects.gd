extends Node

# ==============================================================================
# STATUS EFFECT SYSTEM
# ==============================================================================
# Handles all status effects for any combatant (player or enemy).
# Each combatant's effects are stored as an Array of effect Dictionaries.
#
# Effect Dictionary schema:
#   {
#     "id":       String,   # Unique effect identifier (see STATUS_* constants)
#     "stacks":   int,      # Current stack count (1 for most effects)
#     "duration": int,      # Turns remaining (-1 = infinite until cleared)
#     "source":   String,   # "player" or "enemy" — who applied it
#   }
#
# Combatant Dictionary schema used by Battle.gd:
#   {
#     "effects":  Array,    # List of active effect Dictionaries
#     "max_hp":   int,      # Required for Poison / Regeneration calculations
#     "hp":       int,      # Current HP (modified in-place by tick)
#     "fire_dmg": int,      # Base fire damage (for Burn)
#     "bleed_dmg":int,      # Base bleed damage (for Bleed)
#     "dodge":    float,    # 0.0–1.0 dodge chance (modified by Crippled/Shaken)
#     "block":    float,    # 0.0–1.0 block chance (modified by Shaken)
#   }
# ==============================================================================

# ── Effect ID Constants ────────────────────────────────────────────────────────

# DOT (Damage over Time)
const STATUS_BURN    := "burn"    # 2.5× fire damage per tick
const STATUS_BLEED   := "bleed"   # 2 + 1× bleed damage per tick
const STATUS_POISON  := "poison"  # 0.5% max HP per stack per tick

# Debuffs
const STATUS_STUNNED    := "stunned"    # Skip turn
const STATUS_SLEEP      := "sleep"      # Skip 2 turns; broken by being attacked
const STATUS_CRIPPLED   := "crippled"  # Halve dodge chance
const STATUS_VULNERABLE := "vulnerable" # Take 20% more damage
const STATUS_SHAKEN     := "shaken"     # –5% dodge/block, –10% damage dealt

# Buffs
const STATUS_RALLIED    := "rallied"    # +20% damage dealt, –10% damage taken
const STATUS_HOLY_IMBUED:= "holy_imbued"# –10% damage taken
const STATUS_REGEN      := "regen"      # +8% max HP healed per turn

# Self-Applied / Class Effects
const STATUS_OVERFLOW   := "overflow"   # +50% damage dealt; +10–20% damage taken
const STATUS_TAUNT      := "taunt"      # Force 1 enemy to target self
const STATUS_RECKLESS   := "reckless"   # +30% damage dealt, +20% damage taken
const STATUS_PSYCHED_UP  := "psyched_up" # +25% damage dealt


# ── Default Durations (in turns) ──────────────────────────────────────────────
# -1 means the effect has no inherent timer and must be explicitly removed.
const DEFAULT_DURATIONS: Dictionary = {
	STATUS_BURN:       3,
	STATUS_BLEED:      3,
	STATUS_POISON:     3,
	STATUS_STUNNED:    1,
	STATUS_SLEEP:      2,
	STATUS_CRIPPLED:   3,
	STATUS_VULNERABLE: 3,
	STATUS_SHAKEN:     3,
	STATUS_RALLIED:    3,
	STATUS_HOLY_IMBUED:3,
	STATUS_REGEN:      3,
	STATUS_OVERFLOW:  -1,
	STATUS_TAUNT:      3,
	STATUS_RECKLESS:  -1,
	STATUS_PSYCHED_UP: 1,
}

# ── Friendly Labels ────────────────────────────────────────────────────────────
const STATUS_LABELS: Dictionary = {
	STATUS_BURN:        "Burn",
	STATUS_BLEED:       "Bleed",
	STATUS_POISON:      "Poison",
	STATUS_STUNNED:     "Stunned",
	STATUS_SLEEP:       "Sleep",
	STATUS_CRIPPLED:    "Crippled",
	STATUS_VULNERABLE:  "Vulnerable",
	STATUS_SHAKEN:      "Shaken",
	STATUS_RALLIED:     "Rallied",
	STATUS_HOLY_IMBUED: "Holy Imbued",
	STATUS_REGEN:       "Regeneration",
	STATUS_OVERFLOW:    "Overflow",
	STATUS_TAUNT:       "Taunt",
	STATUS_RECKLESS:    "Reckless",
	STATUS_PSYCHED_UP:  "Psyched Up",
}


# ==============================================================================
# PUBLIC API
# ==============================================================================

## Apply or stack a status effect on a combatant.
## combatant: Dictionary with an "effects" Array.
## effect_id: One of the STATUS_* constants above.
## stacks: How many stacks to apply (default 1). Stackable: poison.
## duration: Override default duration (pass -1 to use DEFAULT_DURATIONS).
## source: "player" or "enemy".
func apply(combatant: Dictionary, effect_id: String,
		stacks: int = 1, duration: int = -1, source: String = "player") -> void:
	if not combatant.has("effects"):
		combatant["effects"] = []

	var real_dur: int = duration if duration >= 0 else DEFAULT_DURATIONS.get(effect_id, 3)

	# Poison stacks additively; all others just refresh duration.
	if effect_id == STATUS_POISON:
		var existing: Dictionary = _find(combatant, effect_id)
		if not existing.is_empty():
			existing["stacks"] += stacks
			existing["duration"] = max(existing["duration"], real_dur)
			return

	# For non-stackable effects, refresh duration if already present.
	var existing: Dictionary = _find(combatant, effect_id)
	if not existing.is_empty():
		existing["duration"] = real_dur
		existing["stacks"]   = stacks
		return

	combatant["effects"].append({
		"id":       effect_id,
		"stacks":   stacks,
		"duration": real_dur,
		"source":   source,
	})


## Remove a specific status effect from a combatant.
func remove(combatant: Dictionary, effect_id: String) -> void:
	if not combatant.has("effects"):
		return
	combatant["effects"] = combatant["effects"].filter(
		func(e): return e["id"] != effect_id
	)


## Returns true if the combatant has the given effect active.
func has_effect(combatant: Dictionary, effect_id: String) -> bool:
	return not _find(combatant, effect_id).is_empty()


## Returns the effect Dictionary or empty Dictionary if not found.
func get_effect(combatant: Dictionary, effect_id: String) -> Dictionary:
	return _find(combatant, effect_id)


## Clear ALL status effects from a combatant (e.g., on death / battle end).
func clear_all(combatant: Dictionary) -> void:
	combatant["effects"] = []


# ==============================================================================
# TURN-START TICKS
# Processes DOT / heal effects and returns an Array of message Strings.
# Call at the START of each combatant's turn BEFORE they act.
# ==============================================================================
func tick_dot(combatant: Dictionary) -> Array:
	var messages: Array = []
	if not combatant.has("effects"):
		return messages

	var name_str: String = combatant.get("name", "Target")

	# ── Burn ──────────────────────────────────────────────────────────────────
	var burn: Dictionary = _find(combatant, STATUS_BURN)
	if not burn.is_empty():
		var fire_base: int = combatant.get("fire_dmg", 5)
		var dmg := int(fire_base * 2.5)
		combatant["hp"] = max(0, combatant["hp"] - dmg)
		messages.append("%s is burning! -%d HP" % [name_str, dmg])

	# ── Bleed ─────────────────────────────────────────────────────────────────
	var bleed: Dictionary = _find(combatant, STATUS_BLEED)
	if not bleed.is_empty():
		var bleed_base: int = combatant.get("bleed_dmg", 4)
		var dmg := 2 + bleed_base
		combatant["hp"] = max(0, combatant["hp"] - dmg)
		messages.append("%s is bleeding! -%d HP" % [name_str, dmg])

	# ── Poison ────────────────────────────────────────────────────────────────
	var poison: Dictionary = _find(combatant, STATUS_POISON)
	if not poison.is_empty():
		var stacks: int = poison["stacks"]
		var dmg := int(combatant.get("max_hp", 100) * 0.005 * stacks)
		dmg = max(1, dmg)
		combatant["hp"] = max(0, combatant["hp"] - dmg)
		messages.append("%s is poisoned (×%d)! -%d HP" % [name_str, stacks, dmg])

	# ── Regeneration ──────────────────────────────────────────────────────────
	var regen: Dictionary = _find(combatant, STATUS_REGEN)
	if not regen.is_empty():
		var heal := int(combatant.get("max_hp", 100) * 0.08)
		heal = max(1, heal)
		combatant["hp"] = min(combatant.get("max_hp", 100), combatant["hp"] + heal)
		messages.append("%s regenerates! +%d HP" % [name_str, heal])

	return messages


# ==============================================================================
# TURN-START CHECKS
# Returns true if the combatant's turn should be SKIPPED this round.
# Also handles sleep-break logic (call notify_attacked() when hit).
# ==============================================================================
func should_skip_turn(combatant: Dictionary) -> bool:
	# Stunned: skip 1 turn
	var stunned: Dictionary = _find(combatant, STATUS_STUNNED)
	if not stunned.is_empty():
		return true

	# Sleep: skip turn
	var sleep: Dictionary = _find(combatant, STATUS_SLEEP)
	if not sleep.is_empty():
		return true

	return false


## Call this whenever a SLEEPING combatant takes a hit — breaks Sleep.
func notify_attacked(combatant: Dictionary) -> bool:
	if has_effect(combatant, STATUS_SLEEP):
		remove(combatant, STATUS_SLEEP)
		return true   # sleep was broken
	return false


# ==============================================================================
# DAMAGE MODIFIER QUERIES
# All modifiers are multiplicative factors applied to the raw damage value.
# ==============================================================================

## Returns the OUTGOING damage multiplier for a combatant (what they deal).
func outgoing_multiplier(combatant: Dictionary) -> float:
	var mult := 1.0

	if has_effect(combatant, STATUS_SHAKEN):
		mult *= 0.90    # –10% damage dealt

	if has_effect(combatant, STATUS_RALLIED):
		mult *= 1.20    # +20% damage dealt

	if has_effect(combatant, STATUS_OVERFLOW):
		mult *= 1.50    # +50% damage dealt

	if has_effect(combatant, STATUS_RECKLESS):
		mult *= 1.30    # +30% damage dealt

	if has_effect(combatant, STATUS_PSYCHED_UP):
		mult *= 1.25    # +25% damage dealt

	return mult


## Returns the INCOMING damage multiplier for a combatant (what they take).
func incoming_multiplier(combatant: Dictionary) -> float:
	var mult := 1.0

	if has_effect(combatant, STATUS_VULNERABLE):
		mult *= 1.20    # +20% damage taken

	if has_effect(combatant, STATUS_SHAKEN):
		mult *= 1.0     # (no incoming penalty — only outgoing and dodge/block)

	if has_effect(combatant, STATUS_RALLIED):
		mult *= 0.90    # –10% damage taken

	if has_effect(combatant, STATUS_HOLY_IMBUED):
		mult *= 0.90    # –10% damage taken

	if has_effect(combatant, STATUS_OVERFLOW):
		# Random 10–20% more damage taken
		var penalty := randf_range(0.10, 0.20)
		mult *= (1.0 + penalty)

	if has_effect(combatant, STATUS_RECKLESS):
		mult *= 1.20    # +20% damage taken

	return mult


## Returns effective dodge chance (0.0–1.0) after status modifiers.
func effective_dodge(combatant: Dictionary, base_dodge: float) -> float:
	var dodge := base_dodge

	if has_effect(combatant, STATUS_CRIPPLED):
		dodge *= 0.5    # Halve dodge

	if has_effect(combatant, STATUS_SHAKEN):
		dodge -= 0.05   # –5% dodge

	return clampf(dodge, 0.0, 1.0)


## Returns effective block chance (0.0–1.0) after status modifiers.
func effective_block(combatant: Dictionary, base_block: float) -> float:
	var block := base_block

	if has_effect(combatant, STATUS_SHAKEN):
		block -= 0.05   # –5% block

	return clampf(block, 0.0, 1.0)


## Returns true if this combatant has TAUNT active.
func is_taunting(combatant: Dictionary) -> bool:
	return has_effect(combatant, STATUS_TAUNT)


# ==============================================================================
# DURATION DECAY
# Call at the END of a combatant's turn. Decrements durations and clears
# expired effects. Returns an Array of expired effect label Strings.
# ==============================================================================
func decay(combatant: Dictionary) -> Array:
	var expired: Array = []
	if not combatant.has("effects"):
		return expired

	var still_active: Array = []
	for effect in combatant["effects"]:
		if effect["duration"] == -1:
			still_active.append(effect)
			continue
		effect["duration"] -= 1
		if effect["duration"] <= 0:
			expired.append(STATUS_LABELS.get(effect["id"], effect["id"]))
		else:
			still_active.append(effect)

	combatant["effects"] = still_active
	return expired


## Returns a human-readable summary of all active effects on a combatant.
func describe(combatant: Dictionary) -> String:
	if not combatant.has("effects") or combatant["effects"].is_empty():
		return "None"
	var parts: Array = []
	for e in combatant["effects"]:
		var label: String = STATUS_LABELS.get(e["id"], e["id"])
		var dur_str: String = ("∞" if e["duration"] == -1 else str(e["duration"]) + "t")
		if e["stacks"] > 1:
			parts.append("%s×%d (%s)" % [label, e["stacks"], dur_str])
		else:
			parts.append("%s (%s)" % [label, dur_str])
	return ", ".join(parts)


# ==============================================================================
# PRIVATE HELPERS
# ==============================================================================
func _find(combatant: Dictionary, effect_id: String) -> Dictionary:
	if not combatant.has("effects"):
		return {}
	for e in combatant["effects"]:
		if e["id"] == effect_id:
			return e
	return {}
