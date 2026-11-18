extends Node
## Event-driven emotion; never owns damage, defense windows or movement.
signal changed(value: float, state: StringName)
signal reaction(trigger: StringName)
@export var initial := 10.0
@export var clean_hit := 2.0
@export var dodge_hit := 7.0
@export var player_parry := 8.0
@export var parry_streak_bonus := 12.0
@export var repeated_technique := 5.0
@export var aerial_hit := 8.0
@export var charge_interrupt := 10.0
@export var half_health := 10.0
@export var low_health := 15.0
@export var defeated := 20.0
@export var repeated_defeat := 5.0
@export var successful_parry := -3.0
@export var counterattack := -2.0
@export var victory := -15.0
@export var decay_per_second := .35
@export var aerial_speed := 12.0
@export var bonus_cooldown := 1.0
var value := 10.0
var lingering_floor := 10.0
var active := false
var clock := 0.0
var consecutive_parries := 0
var last_event := ""
var _seen: Dictionary = {}
var _cooldowns: Dictionary = {}
var _half_seen := false
var _low_seen := false
var _last_technique := ""
var _last_technique_serial := ""
var _counter_until := 0.0
var _streak_awarded := false

func state() -> StringName:
	if value<25: return &"smug"
	if value<50: return &"annoyed"
	if value<75: return &"salty"
	return &"meltdown"

func set_value(amount: float) -> void:
	if not is_finite(amount): return
	value = clampf(amount,0,100)
	changed.emit(value,state())

func begin() -> void:
	active = true
	_seen.clear()
	_cooldowns.clear()
	_half_seen = false
	_low_seen = false
	_last_technique = ""
	_last_technique_serial = ""
	consecutive_parries = 0
	_streak_awarded = false
	_counter_until = 0

func end(player_won: bool, consecutive_defeats: int, total_defeats: int) -> void:
	if not active: return
	active = false
	last_event = "defeat" if player_won else "victory"
	set_value(value+(defeated+minf(20,maxi(0,consecutive_defeats-1)*repeated_defeat) if player_won else victory))
	lingering_floor = initial+minf(25,total_defeats*3)
	set_value(maxf(value,lingering_floor))

func advance(delta: float) -> void:
	clock += maxf(0,delta)
	if not active and value>lingering_floor:
		set_value(maxf(lingering_floor,value-decay_per_second*delta))

func _bonus(key: String, amount: float) -> void:
	if clock<float(_cooldowns.get(key,-INF)): return
	_cooldowns[key] = clock+bonus_cooldown
	set_value(value+amount)

func contact(event: Dictionary, kyren_defending: bool) -> bool:
	if not active: return false
	var key: String = event.get("event_id","")
	if key.is_empty() or _seen.has(key): return false
	_seen[key] = true
	if _seen.size()>512: _seen.erase(_seen.keys()[0])
	var parry: bool = event.get("outcome")==&"parry"
	var clean: bool = float(event.get("damage",0))>0 and not event.get("blocked",false)
	var move: Dictionary = event.get("incoming",{})
	if kyren_defending:
		if parry:
			last_event = "kyren_parry"
			_bonus("successful_parry",successful_parry)
			_counter_until = clock+2.5
			reaction.emit(&"kyren_parry")
		elif clean:
			set_value(value+clean_hit)
			last_event = "player_hit"
			if event.get("dodging",false):
				_bonus("dodge_hit",dodge_hit)
				last_event = "dodge_hit"
			if event.get("interrupted_charge",false):
				_bonus("charge_interrupt",charge_interrupt)
				last_event = "charge_interrupt"
			if event.get("attacker_airborne",false) and float(event.get("attacker_speed",0))>=aerial_speed:
				_bonus("aerial_hit",aerial_hit)
				last_event = "aerial_hit"
			var technique := String(move.get("item_id",""))+":"+String(move.get("action",move.get("name","")))
			var serial: String = event.get("attack_key",key)
			if serial!=_last_technique_serial:
				if technique==_last_technique and not technique.ends_with(":" ):
					_bonus("repeat",repeated_technique)
					last_event = "repeat_technique"
				_last_technique = technique
				_last_technique_serial = serial
			reaction.emit(StringName(last_event))
		var ratio := float(event.get("health_ratio",1))
		if ratio<.5 and not _half_seen:
			_half_seen = true
			set_value(value+half_health)
			reaction.emit(&"half_health")
		if ratio<.2 and not _low_seen:
			_low_seen = true
			set_value(value+low_health)
			reaction.emit(&"low_health")
	else:
		if parry:
			set_value(value+player_parry)
			consecutive_parries += 1
			last_event = "player_parry"
			if consecutive_parries>=3 and not _streak_awarded:
				_streak_awarded = true
				set_value(value+parry_streak_bonus)
				last_event = "parry_domination"
			reaction.emit(StringName(last_event))
		elif clean:
			consecutive_parries = 0
			_streak_awarded = false
			last_event = "kyren_hit"
			if clock<_counter_until:
				_counter_until = 0
				_bonus("counterattack",counterattack)
				last_event = "kyren_counter"
			reaction.emit(StringName(last_event))
		else:
			consecutive_parries = 0
			_streak_awarded = false
	return true
