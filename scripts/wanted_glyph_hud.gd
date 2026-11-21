extends Control
## A view of the existing witness-based law ledger, never a second wanted timer.
const MAX_GLYPHS:=5
const FADE_SECONDS:=.35
const SPACING:=40.0
var law: Node
var offender_id:="player"
var wanted_level:=0
var glyph_alpha:=PackedFloat32Array([0,0,0,0,0])

func _ready() -> void:
	name="WantedGlyphHUD"
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left=-224; offset_right=-24; offset_top=24; offset_bottom=62
	if is_instance_valid(law): law.changed.connect(refresh)
	refresh()

func refresh() -> void:
	wanted_level=clampi(law.wanted_level(offender_id),0,MAX_GLYPHS) if is_instance_valid(law) else 0
	var fading:=false
	for i in range(MAX_GLYPHS):
		if i<wanted_level: glyph_alpha[i]=1
		elif glyph_alpha[i]>0: fading=true
	visible=wanted_level>0 or fading
	set_process(fading)
	queue_redraw()

func _process(delta: float) -> void:
	var fading:=false
	for i in range(wanted_level,MAX_GLYPHS):
		glyph_alpha[i]=maxf(0,glyph_alpha[i]-delta/FADE_SECONDS)
		fading=fading or glyph_alpha[i]>0
	visible=wanted_level>0 or fading
	set_process(fading)
	queue_redraw()

func _draw() -> void:
	for i in range(MAX_GLYPHS):
		var alpha:=glyph_alpha[i]
		if alpha<=0: continue
		var center:=Vector2(size.x-20-i*SPACING,19)
		var points:=PackedVector2Array([center+Vector2(0,-13),center+Vector2(14,12),center+Vector2(-14,12),center+Vector2(0,-13)])
		draw_colored_polygon(PackedVector2Array([points[0],points[1],points[2]]),Color(.035,.025,.008,alpha*.85))
		draw_polyline(points,Color(1,.62,.15,alpha*.24),6,true)
		draw_polyline(points,Color(1,.84,.39,alpha),2,true)
		var inner:=PackedVector2Array([center+Vector2(0,-5),center+Vector2(5,4),center+Vector2(-5,4),center+Vector2(0,-5)])
		draw_polyline(inner,Color(.62,.96,1,alpha),1.3,true)
