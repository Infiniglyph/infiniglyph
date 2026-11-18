extends "res://scripts/equation_trace_settings.gd"
## Brush-only tuning. None of these resources are shared with the Manuscript.
@export_range(1,100,1) var light_damage := 30.0
@export_range(.5,2,.05) var light_stroke_length := 1.1
@export_range(.2,.8,.01) var light_duration := .34
@export_range(.2,2,.01) var square_frequency := .55
@export_range(.2,2,.01) var triangle_frequency := .50
@export_range(.1,.5,.01) var pattern_radius := .30

func _init() -> void:
	contact_interval = .3
