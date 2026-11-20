extends Node3D
## A catalog model and readable placard; never an owned item or loot pickup.
const Entry = preload("res://scripts/equipment_entry.gd")
const Preview = preload("res://scripts/equipment_preview.gd")
var type_id: StringName
var price := 0
var model: Node3D
var _pivot: Node3D
var _clock := 0.0

func _ready() -> void:
	name="Merchandise_"+String(type_id)
	var entry := Entry.for_id(type_id)
	if entry.is_empty(): return
	_pivot=Node3D.new()
	add_child(_pivot)
	model=Preview.model(entry)
	_pivot.add_child(model)
	var placard:=Label3D.new()
	placard.text=String(entry.name)+"\n"+str(price)+" Glyph Coins"
	placard.position=Vector3(0,.45,1.35)
	placard.font_size=36
	placard.pixel_size=.008
	placard.outline_size=5
	placard.modulate=Color("bffaff")
	placard.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	placard.no_depth_test=false
	add_child(placard)
	call_deferred("_fit")

func _bounds(node: Node, box: Array) -> void:
	if node is MeshInstance3D and node.mesh!=null:
		var bounds: AABB=node.get_aabb()
		for i in range(8):
			var point:=to_local(node.to_global(bounds.get_endpoint(i)))
			if box.is_empty(): box.append(AABB(point,Vector3.ZERO))
			else: box[0]=box[0].expand(point)
	for child: Node in node.get_children(): _bounds(child,box)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children(): _freeze(child)

func _fit() -> void:
	if not is_inside_tree() or not is_instance_valid(model): return
	var box: Array=[]
	_bounds(model,box)
	if not box.is_empty():
		var bounds: AABB=box[0]
		# Fit to the same pedestal envelope regardless of weapon/garment scale.
		var factor:=clampf(2.2/maxf(.1,maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))),.1,3.5)
		model.scale*=factor
		model.position=Vector3(0,1.35,0)-bounds.get_center()*factor
	_freeze(model)

func _process(delta: float) -> void:
	if not is_instance_valid(_pivot): return
	_clock+=delta
	_pivot.rotation.y=_clock*.22
	_pivot.position.y=sin(_clock*1.4)*.05
