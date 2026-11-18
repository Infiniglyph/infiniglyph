extends Resource
## Manuscript-only tuning. Damage/cooldown match the existing vehicle light wave.
const VehicleWave = preload("res://scripts/vehicle_light_wave.gd")
@export_range(.08,2,.01) var x_frequency := .25 # Seconds per complete X.
@export_range(.08,2,.01) var y_frequency := .35 # Seconds per circle.
@export_range(.005,.10,.005) var minimum_mark_size := .025
@export_range(.01,.15,.005) var thickness := .04
@export_range(.2,10,.1) var lifetime := 3.0
@export var damage := VehicleWave.DAMAGE
@export_range(.2,3,.05) var glyph_scale := 1.0
@export_range(.04,.3,.01) var equation_spacing := .13
@export_range(.1,2,.05) var fade_duration := .6
@export_range(1,30,.5) var reflection_speed := 9.0
@export_range(16,512,1) var maximum_sections := 192
@export_range(256,8192,256) var maximum_strokes := 4096
@export_range(.008,.05,.001) var sampling_interval := 1.0/60.0
@export_range(.1,2,.05) var contact_interval := VehicleWave.CONTACT_INTERVAL
