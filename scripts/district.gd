extends Node3D
const Neon = preload("res://scripts/neon.gd")
const Building = preload("res://scripts/building.gd")
const StreetLight = preload("res://scripts/street_light.gd")
const Metropolis = preload("res://scripts/metropolis.gd")
const HALF_EXTENT := 112

func _ready() -> void:
	name = "CentralDistrict"
	Neon.prepare()
	var paving := Neon.dark.duplicate()
	paving.roughness = 0.24
	paving.metallic = 0.3
	# The foundation reaches beneath the now-accessible outer skyline. Small
	# surface tiles keep each mesh within Compatibility's eight-spotlight budget.
	for x in range(-96,97,32):
		for z in range(-96,97,32):
			Neon.block(self, Vector3(x,-0.3,z), Vector3(32,0.6,32),null,paving)
	var grid := PackedVector3Array()
	for n in range(-HALF_EXTENT,HALF_EXTENT+1,4):
		grid.append_array([Vector3(n,0.008,-HALF_EXTENT),Vector3(n,0.008,HALF_EXTENT),Vector3(-HALF_EXTENT,0.008,n),Vector3(HALF_EXTENT,0.008,n)])
	add_child(Neon.lines(grid, Neon.material(Color(0.008,0.095,0.13))))
	var boulevard := PackedVector3Array()
	for n in range(-56,13,2):
		boulevard.append_array([Vector3(-11.6,0.018,n),Vector3(11.6,0.018,n)])
	for n in range(-10,11,2):
		boulevard.append_array([Vector3(n,0.018,12),Vector3(n,0.018,-56)])
	add_child(Neon.lines(boulevard,Neon.material(Color(0.025,0.52,0.64))))
	# The cross-shaped avenues stay open; blocks have 4m alleys.
	for sx in [-1,1]:
		for sz in [-1,1]:
			Neon.block(self, Vector3(sx*37,0.06,sz*37), Vector3(50,0.12,50))
	var layout := [
		Vector4(-23,-24,12,18), Vector4(-43,-23,16,30), Vector4(-59,-26,10,22),
		Vector4(-24,-46,14,38), Vector4(-46,-48,18,46), Vector4(-61,-51,8,26),
		Vector4(23,-24,12,3), Vector4(43,-24,16,25), Vector4(59,-24,10,34),
		Vector4(24,-47,14,32), Vector4(45,-48,18,42), Vector4(61,-50,8,20),
		Vector4(-24,24,14,24), Vector4(-46,24,16,36), Vector4(-61,25,8,20),
		Vector4(-24,47,14,30), Vector4(-45,48,18,44),
		Vector4(24,24,14,16), Vector4(46,24,16,32), Vector4(61,25,8,24),
		Vector4(24,47,14,26), Vector4(46,48,18,40)]
	for index in range(layout.size()):
		var spec: Vector4 = layout[index]
		var b := Building.new()
		add_child(b)
		b.position = Vector3(spec.x,0.12,spec.y)
		var front := Vector3(-signf(spec.x),0,0) if absf(spec.x)<32 else Vector3(0,0,-signf(spec.y) if absf(spec.y)<35 else signf(spec.y))
		b.build(Vector3(spec.z,spec.w,spec.z),front,StringName("building_%02d" % (index+1)))
	# A broad stair route leads to the low north-east roof and a second terrace.
	for step in range(12):
		var height := (step+1)*0.25
		Neon.block(self,Vector3(23,height*0.5,-10.5-step*0.5),Vector3(4,height,0.5))
	Neon.block(self,Vector3(23,3.0,-17.25),Vector3(4,0.24,2))
	Neon.block(self,Vector3(23,3.12,-32),Vector3(8,0.3,4))
	for step in range(6):
		var height := (step+1)*0.25
		Neon.block(self,Vector3(23,3.27+height*0.5,-34.25-step*0.5),Vector3(4,height,0.5))
	Neon.block(self,Vector3(23,4.62,-39),Vector3(8,0.3,4))
	# Plaza outline and four low plinths leave its middle free for movement tests.
	var plaza := PackedVector3Array()
	for s in [-1,1]:
		plaza.append_array([Vector3(-10,0.025,s*10),Vector3(10,0.025,s*10),Vector3(s*10,0.025,-10),Vector3(s*10,0.025,10)])
	add_child(Neon.lines(plaza))
	for x in [-8,8]:
		for z in [-8,8]: Neon.block(self,Vector3(x,0.2,z),Vector3(1.8,0.4,1.8))
	# Orange exclusively marks real light sources; posts face into the avenues.
	for side in [-1,1]:
		for along in [-48,-24,24,48]:
			add_street_light(Vector3(side*10.5,0,along), side*PI*0.5)
			add_street_light(Vector3(along,0,side*10.5), 0.0 if side == 1 else PI)
	# Retain the old perimeter as low solid walls, with real road openings.
	for s in [-1,1]:
		for span: Vector2 in [Vector2(-HALF_EXTENT,6),Vector2(26,HALF_EXTENT)]:
			Neon.block(self,Vector3(s*HALF_EXTENT,0.7,(span.x+span.y)*0.5),Vector3(0.4,1.4,span.y-span.x))
		for span: Vector2 in [Vector2(-HALF_EXTENT,-10),Vector2(10,HALF_EXTENT)]:
			Neon.block(self,Vector3((span.x+span.y)*0.5,0.7,s*HALF_EXTENT),Vector3(span.y-span.x,1.4,0.4))
		for n in range(-3,4):
			if n == 0: continue # Continue the north/south avenues beyond the hub.
			var height: float = 30.0 + abs(n)*8
			Neon.block(self,Vector3(n*24,height*0.5,s*94),Vector3(14,height,14))
	add_child(Metropolis.new())

func add_street_light(at: Vector3, yaw: float) -> void:
	var fixture := StreetLight.new()
	fixture.position = at
	fixture.rotation.y = yaw
	add_child(fixture)
