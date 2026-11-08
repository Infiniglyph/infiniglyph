extends Resource
## Shared tuning schema; each actor owns an instance, never a shared mutable meter.
@export var parry_stagger := 1.0
@export var max_psi := 100.0
@export var psi_recovery := 14.0
@export var psi_recovery_delay := 1.0
@export var exhausted_duration := 1.8
@export var exhausted_damage_multiplier := 1.35
@export_range(0,1) var recovered_psi_fraction := 0.25
@export var base_fortitude := 0.8
@export var light_hitstop := 2.5/60.0
@export var heavy_hitstop := 6.0/60.0
@export var parry_hitstop := 7.0/60.0
@export var exhaustion_hitstop := 6.0/60.0
@export_range(0,2) var camera_intensity := 1.0
@export var camera_shake_enabled := true
@export var impact_audio_enabled := true
