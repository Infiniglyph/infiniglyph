extends Node3D
## Glowing interior panes, baked once into opaque spatial batches. The existing
## building remains the solid wall; these inlays add no bodies or realtime lights.
const CELL_SIZE := 128.0
const PALETTE := [
	Color(0.06,0.90,1.0), Color(0.18,0.48,1.0), # Cyan, blue.
	Color(0.53,0.22,1.0), Color(0.78,0.12,1.0), # Violet, purple.
	Color(1.0,0.25,0.68), Color(1.0,0.11,0.15), # Pink, red.
	Color(1.0,0.40,0.075), Color(1.0,0.76,0.18), # Orange, gold.
	Color(0.12,1.0,0.36), Color(0.30,1.0,0.76), # Green, mint.
	Color(0.88,0.94,1.0)] # Soft white.
var cells: Dictionary = {}
var pane_count := 0
var building_count := 0
var batch_count := 0

static func code(at: Vector3, salt: int) -> int:
	return absi((roundi(at.x*10)*73856093) ^ (roundi(at.z*10)*19349663) ^ ((salt+71)*83492791))

func build(district: Node3D, regions: Node3D) -> void:
	name = "WindowLights"
	for facade: Dictionary in district.facades:
		facade_windows(facade.base,facade.size,3.0)
	for facade: Dictionary in district.get_node("Metropolis").facades:
		facade_windows(facade.base,facade.size,3.0)
	if is_instance_valid(regions):
		for facade: Dictionary in regions.buildings:
			if facade.region == "city": facade_windows(facade.point,facade.size,4.0)
			else: home_windows(facade.point,facade.size)
	commit()

func facade_windows(at: Vector3, size: Vector3, pitch: float) -> void:
	building_count += 1
	var occupancy := 19+code(at,0)%12
	for face in range(4):
		var normal := Vector3.FORWARD.rotated(Vector3.UP,face*PI*0.5).snapped(Vector3.ONE)
		var tangent := normal.cross(Vector3.UP)
		var width := size.x if face%2==0 else size.z
		var depth := size.z if face%2==0 else size.x
		var columns := maxi(1,floori((width-1.0)/pitch))
		# Start above the real ground-floor entrances and leave parapets dark.
		for row in range(1,floori((size.y-0.6)/pitch)):
			for column in range(columns):
				var choice := code(at,face*10007+row*101+column*17)
				if choice%100>=occupancy: continue
				var center := at+normal*(depth*0.5+0.024)+Vector3.UP*((row+0.5)*pitch)
				center += tangent*((column-(columns-1)*0.5)*pitch)
				pane(center,tangent,Vector2(pitch*0.36,pitch*0.46),shade(choice))

func home_windows(at: Vector3, size: Vector3) -> void:
	building_count += 1
	# Match the two existing front-window frames, clear of the central door.
	for side in [-1,1]:
		var choice := code(at,side+3)
		if choice%100>=58: continue
		pane(at+Vector3(side*3.5,2.45,size.z*0.5+0.024),Vector3.RIGHT,Vector2(1.58,1.28),shade(choice))

func shade(choice: int) -> Color:
	# Use different hash bits from occupancy so every hue reaches lit panes.
	return PALETTE[(choice >> 8)%PALETTE.size()]*lerpf(0.38,0.78,float(choice%7)/6.0)

func pane(center: Vector3, tangent: Vector3, size: Vector2, color: Color) -> void:
	var key := Vector3i((center/CELL_SIZE).floor())
	if not cells.has(key): cells[key] = {"vertices":PackedVector3Array(),"colors":PackedColorArray()}
	var cell: Dictionary = cells[key]
	var local := center-Vector3(key)*CELL_SIZE
	var across := tangent*size.x*0.5
	var up := Vector3.UP*size.y*0.5
	for vertex: Vector3 in [local-across-up,local+across-up,local+across+up,local-across-up,local+across+up,local-across+up]:
		cell.vertices.append(vertex)
		cell.colors.append(color)
	pane_count += 1

func commit() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for key: Vector3i in cells:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = cells[key].vertices
		arrays[Mesh.ARRAY_COLOR] = cells[key].colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh.surface_set_material(0,material)
		var batch := MeshInstance3D.new()
		batch.name = "WindowCell"
		batch.position = Vector3(key)*CELL_SIZE
		batch.mesh = mesh
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(batch)
		batch_count += 1
	cells.clear()
