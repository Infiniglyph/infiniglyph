extends Node3D
## Two articulated wing roots; cached feather meshes never rebuild during flight.
const Geometry = preload("res://scripts/equipment_geometry.gd")
const Neon = preload("res://scripts/neon.gd")
const Surface = preload("res://scripts/garment_surface.gd")
static var mesh_cache: Dictionary={}
var bones := false
var roots: Array[Node3D]=[]
var clock := 0.0
var spread := 0.0

func _ready() -> void:
	name="ArticulatedWings"
	for side: int in [-1,1]:
		var wing:=Node3D.new()
		wing.name="LeftWing" if side<0 else "RightWing"
		add_child(wing)
		wing.position=Vector3(side*.14,.42,-.16)
		roots.append(wing)
		# Keep reflection on a static child. Decomposing a negative scale while
		# animating its rotation can flip the opposite wing's Euler frame.
		var mirror:=Node3D.new()
		wing.add_child(mirror)
		mirror.scale.x=side
		if not mesh_cache.has(bones): mesh_cache[bones]=build_meshes(bones)
		for mesh: Mesh in mesh_cache[bones]:
			var instance:=MeshInstance3D.new()
			instance.mesh=mesh
			instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mirror.add_child(instance)
	pose(0,false,false)

static func build_meshes(skeletal: bool) -> Array:
	var builder:=Geometry.new()
	var accent:=PackedVector3Array()
	builder.edges.append_array([Vector3.ZERO,Vector3(.55,.22,0),Vector3(.55,.22,0),Vector3(1.55,.72,0)])
	for i in range(12):
		var length:=.48+i*.042
		var origin:=Vector2(.20+i*.108,.07+i*.052)
		var angle:=.15+i*.073
		var outline: Array=[]
		for point: Vector2 in [Vector2(-.05,.06),Vector2(.05,.06),Vector2(.075,-.24),Vector2(.025,-length),Vector2(-.04,-length*.83),Vector2(-.07,-.23)]:
			if skeletal: point.x*=.35
			outline.append(point.rotated(angle)+origin)
		builder.prism(outline,.023)
		if i%3==0:
			var end:=Vector2(0,-length*.70).rotated(angle)+origin
			accent.append_array([Vector3(origin.x,origin.y,.016),Vector3(end.x,end.y,.016)])
	var solid:=Surface.surface("FeatherSurfaces",builder.faces,Color("030507"))
	var wire:=Neon.lines(builder.edges,Neon.shared_material(Color("ffd170")))
	var cyan:=Neon.lines(accent,Neon.shared_material(Color("6cffff")))
	var meshes: Array=[solid.mesh,wire.mesh,cyan.mesh]
	# Neon.lines already binds its ink to the mesh surface. Keep that material
	# when sharing the resource; its instance override is intentionally empty.
	solid.free()
	wire.free()
	cyan.free()
	return meshes

func pose(delta: float, airborne: bool, striking: bool) -> void:
	clock+=delta
	spread=lerpf(spread,1.0 if airborne or striking else .08,1-exp(-7*delta))
	for i in range(roots.size()):
		var side: int=-1 if i==0 else 1
		roots[i].scale=Vector3.ONE*lerpf(.58,1,spread)
		roots[i].rotation=Vector3(.12*sin(clock*5)*spread,side*(1-spread)*.45,side*(lerpf(-1.30,.20,spread)+sin(clock*7)*.16*spread))
