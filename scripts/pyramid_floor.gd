extends Node3D
## Reusable architectural storey. One structural batch; four legacy hub batches.
const Chunk = preload("res://scripts/world_chunk.gd")
const Glyphs = preload("res://scripts/dungeon_glyphs.gd")
const CENTER := Vector3(0,0,-28)
const GOLD := Color(.54,.37,.13)
const INK := Color(.05,.85,.78)
const HUB_LAYOUT := ["####.####","##.....##","##.###.##","#..#...##","#.##.#..#","#....##.#","###.#...#","#...#.#.#","#########"]
var definition: Dictionary
var floor_holes: Array[Rect2] = []
var ceiling_holes: Array[Rect2] = []
var batch: Node3D
var maze_chunks: Array[Node3D] = []
var open_cells: Array[Vector2i] = []
var glyph_count := 0
var content: Node3D
var spawn_anchor: Marker3D
var label: Label3D
var dressing: Node3D
var traversal_lanes: Array[Rect2]=[]

static func half_at(y: float) -> float:
	return 64.0*(1.0-y/82.0)

static func hub_open(x: int, row: int) -> bool:
	return row>=0 and row<HUB_LAYOUT.size() and x>=0 and x<HUB_LAYOUT[row].length() and HUB_LAYOUT[row][x]=="."

static func shaft_for(data: Dictionary) -> Rect2:
	if data.id not in [&"U3",&"U6"]: return Rect2()
	var half:=half_at(data.ceiling)-1.2
	return Rect2(-half*.55-2,CENTER.z-4,4,8)

func _ready() -> void:
	name=String(definition.id)
	batch=Chunk.new()
	batch.name="Architecture"
	add_child(batch)
	var shaft:=shaft_for(definition)
	if shaft.has_area(): floor_holes.append(shaft)
	if definition.id==&"hub": build_hub()
	else: slab(definition.y,half_at(definition.y)-.65,floor_holes,"StoreyFloor")
	slab(definition.ceiling,half_at(definition.ceiling)-.6,ceiling_holes,"StoreyCeiling")
	shell()
	if definition.id!=&"hub": rooms()
	if shaft.has_area(): opening_rail(shaft,definition.y)
	batch.commit()
	batch.body.disable_mode=CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	content=Node3D.new()
	content.name="FloorContent"
	content.position=Vector3(0,definition.y,CENTER.z)
	add_child(content)
	for socket: String in ["CentralSpace","WestGallery","EastGallery"]:
		var anchor:=Marker3D.new()
		anchor.name=socket
		anchor.position=Vector3.ZERO
		if socket!="CentralSpace":
			anchor.position.x=half_at(definition.ceiling)*.55*(-1 if socket=="WestGallery" else 1)
			anchor.position.z+=half_at(definition.ceiling)*.35
		content.add_child(anchor)
	spawn_anchor=Marker3D.new()
	spawn_anchor.name="SafeFloorArrival"
	spawn_anchor.position=Vector3(0,definition.y+.05,CENTER.z+half_at(definition.ceiling)*.45)
	if definition.id==&"hub": spawn_anchor.position=Vector3(0,.05,-1)
	add_child(spawn_anchor)
	label=Label3D.new()
	label.name="FloorInscription"
	label.text=("ENTRY HUB" if definition.id==&"hub" else String(definition.id))+"  /  "+definition.title
	label.position=spawn_anchor.position+Vector3(0,3.2,-2)
	label.font_size=36
	label.pixel_size=.012
	label.modulate=INK
	add_child(label)

static func cut_rectangles(regions: Array[Rect2], hole: Rect2) -> Array[Rect2]:
	var result: Array[Rect2]=[]
	for region in regions:
		var cut:=region.intersection(hole)
		if not cut.has_area():
			result.append(region)
			continue
		for part: Rect2 in [Rect2(region.position,Vector2(cut.position.x-region.position.x,region.size.y)),
			Rect2(Vector2(cut.end.x,region.position.y),Vector2(region.end.x-cut.end.x,region.size.y)),
			Rect2(Vector2(cut.position.x,region.position.y),Vector2(cut.size.x,cut.position.y-region.position.y)),
			Rect2(Vector2(cut.position.x,cut.end.y),Vector2(cut.size.x,region.end.y-cut.end.y))]:
			if part.size.x>.001 and part.size.y>.001: result.append(part)
	return result

func slab(y: float, half: float, holes: Array[Rect2], tag: String) -> void:
	var regions: Array[Rect2]=[Rect2(-half,CENTER.z-half,half*2,half*2)]
	for hole in holes: regions=cut_rectangles(regions,hole)
	for region in regions:
		var center:=region.get_center()
		batch.box(Vector3(center.x,y-.2,center.y),Vector3(region.size.x,.4,region.size.y),tag,GOLD*.65)
		if tag!="StoreyFloor": continue
		var spacing:=4.0 if half<65 else 6.0
		var x:=ceilf(region.position.x/spacing)*spacing
		while x<region.end.x:
			batch.line(Vector3(x,y+.006,region.position.y),Vector3(x,y+.006,region.end.y),GOLD*.55)
			x+=spacing
		var z:=ceilf(region.position.y/spacing)*spacing
		while z<region.end.y:
			batch.line(Vector3(region.position.x,y+.006,z),Vector3(region.end.x,y+.006,z),GOLD*.55)
			z+=spacing

func shell() -> void:
	var low: float=definition.y
	var high: float=definition.ceiling
	var base:=half_at(low)
	var top:=half_at(high)
	for side in range(4):
		var vertices:=PackedVector3Array()
		# Each wall is one sloping frustum panel, continuing the exterior slope.
		for inset: float in [0,.6]:
			for row in range(2):
				var half: float=(base if row==0 else top)-inset
				var y: float=low if row==0 else high
				for edge in [-1,1]:
					var p:=Vector3(edge*half,y,half)
					p=p.rotated(Vector3.UP,side*PI*.5)
					vertices.append(p+CENTER)
		batch.convex(vertices,[[0,1,3,2],[4,6,7,5],[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3]],Vector3.ZERO,"SlopingPyramidWall",GOLD)
		# Bands sit on the real sloping surface, with readable repeated motifs.
		for band in range(2):
			var height:=low+2.2+band*2.4
			var width:=half_at(height)-.63
			var count:=clampi(int(width/2.8),3,25)
			for i in range(count):
				var horizontal:=lerpf(-width*.85,width*.85,float(i)/maxi(1,count-1))
				var at:=Vector3(horizontal,height,width).rotated(Vector3.UP,side*PI*.5)+CENTER
				var right:=Vector3.RIGHT.rotated(Vector3.UP,side*PI*.5)
				var up:=Vector3(0,1,-64.0/82.0).rotated(Vector3.UP,side*PI*.5)
				Glyphs.draw(batch,i+side+band,at,right,.72,INK if band==0 else GOLD.lightened(.15),up)
				glyph_count+=1

func pillar(at: Vector3, height: float, size: float = .8) -> void:
	# Capitals and bases must also clear both relocated stairwells.
	var area:=Rect2(Vector2(at.x,at.z)-Vector2.ONE*size*.85,Vector2.ONE*size*1.7)
	for hole: Rect2 in floor_holes+ceiling_holes:
		if area.intersects(hole.grow(.2)): return
	batch.box(at+Vector3.UP*height*.5,Vector3(size,height,size),"Pillar",GOLD)
	batch.box(at+Vector3.UP*.25,Vector3(size*1.7,.5,size*1.7),"PillarBase",GOLD)
	batch.box(at+Vector3.UP*(height-.25),Vector3(size*1.7,.5,size*1.7),"LotusCapital",INK*.65)

func portal(z: float, span: float, opening: float, height: float) -> void:
	var width: float=(span-opening)*.5
	if width<=.2: return
	for side in [-1,1]:
		var x: float=side*(opening*.5+width*.5)
		var sections: Array[Rect2]=[Rect2(x-width*.5,z-.325,width,.65)]
		# A gallery wall must never cut through either neighboring stair flight.
		for hole: Rect2 in floor_holes+ceiling_holes:
			sections=cut_rectangles(sections,hole.grow(.15))
		for section in sections:
			var center:=section.get_center()
			batch.box(Vector3(center.x,definition.y+height*.5,center.y),Vector3(section.size.x,height,section.size.y),"PartitionWall",GOLD)
		pillar(Vector3(side*(opening*.5+.5),definition.y,z),height,1.0)
	batch.box(Vector3(0,definition.y+height-.3,z),Vector3(opening,.6,.7),"DoorLintel",INK)

func opening_rail(hole: Rect2, y: float) -> void:
	for x: float in [hole.position.x,hole.end.x]:
		batch.rail(Vector3(x,y,hole.position.y),Vector3(x,y,hole.end.y),1.1,"ShaftRail",GOLD)
	for z: float in [hole.position.y,hole.end.y]:
		batch.rail(Vector3(hole.position.x,y,z),Vector3(hole.end.x,y,z),1.1,"ShaftRail",GOLD)

func rooms() -> void:
	var half:=half_at(definition.ceiling)-1.5
	var height: float=definition.ceiling-definition.y-.6
	var index: int=definition.number
	if definition.id==&"U8":
		# A small architectural dais, intentionally empty of reward/puzzle logic.
		batch.box(Vector3(4,definition.y+.1,CENTER.z-4),Vector3(6,.2,6),"SummitDais",INK)
		for x: float in [-7,0]: pillar(Vector3(x,definition.y,CENTER.z+8),5,.45)
		return
	if definition.branch=="upper":
		for side in [-1,1]:
			for z: float in [-half*.48,half*.5]:
				pillar(Vector3(side*half*.65,definition.y,CENTER.z+z),height,.7)
		if index in [2,4,5]: portal(CENTER.z,half*1.7,minf(12,half*.6),height)
		if index in [3,6]:
			var ledges: Array[Rect2]=[Rect2(-half*.875,CENTER.z+half*.4,half*.45,half*.3)]
			for hole: Rect2 in floor_holes+ceiling_holes: ledges=cut_rectangles(ledges,hole.grow(.2))
			for ledge in ledges:
				batch.box(Vector3(ledge.get_center().x,definition.y+.1,ledge.get_center().y),Vector3(ledge.size.x,.2,ledge.size.y),"GalleryLedge",GOLD)
		if index==7:
			for side in [-1,1]:
				batch.box(Vector3(side*half*.7,definition.y+1.3,CENTER.z),Vector3(.65,2.6,half),"ProcessionalScreen",GOLD)
	else:
		var arena: bool=definition.id==&"B8"
		var rows:=3 if index<4 else 5
		var spread:=.83 if arena else .68
		for side in [-1,1]:
			for row in range(rows):
				var z:=lerpf(-half*.65,half*.65,float(row)/(rows-1))
				pillar(Vector3(side*half*spread,definition.y,CENTER.z+z),height,2.4 if arena else 1.3)
		if index in [2,4,6]:
			portal(CENTER.z+half*.1,half*1.65,24 if index>=4 else 16,height)
		if index in [3,5,7]:
			for side in [-1,1]:
				portal(CENTER.z+side*half*.48,half*1.5,28,height)
		if arena:
			# Perimeter supports leave a central arena over 230 m wide and 32 m high.
			for side in [-1,1]:
				batch.box(Vector3(0,definition.y+.1,CENTER.z+side*half*.86),Vector3(half*1.5,.2,8),"ArenaPerimeterDais",GOLD)
			var radius:=half*.7
			for i in range(64):
				var a:=i*TAU/64
				var b:=(i+1)*TAU/64
				batch.line(CENTER+Vector3(cos(a)*radius,definition.y+.012,sin(a)*radius),CENTER+Vector3(cos(b)*radius,definition.y+.012,sin(b)*radius),INK)

func build_hub() -> void:
	for group in range(4):
		var chunk:=Chunk.new()
		chunk.name="CorridorBatch"+str(group)
		add_child(chunk)
		maze_chunks.append(chunk)
	for row in range(HUB_LAYOUT.size()):
		var chunk: Node3D=maze_chunks[mini(3,row/2)]
		for x in range(HUB_LAYOUT[row].length()):
			if not hub_open(x,row): continue
			open_cells.append(Vector2i(x,row))
			var at:=Vector3((x-4)*8,0,-row*8)
			chunk.box(at+Vector3(0,-.2,0),Vector3(8,.4,8),"CorridorFloor",GOLD*.65)
			for seam: float in [-2,0,2]:
				chunk.line(at+Vector3(-4,.006,seam),at+Vector3(4,.006,seam),GOLD*.55)
				chunk.line(at+Vector3(seam,.006,-4),at+Vector3(seam,.006,4),GOLD*.55)
			chunk.box(at+Vector3(0,7.2,0),Vector3(8,.4,8),"CorridorCeiling",GOLD*.5)
			for direction: Vector2i in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
				if hub_open(x+direction.x,row+direction.y): continue
				# Open the two existing rear dead ends into their stair vestibules.
				if row==7 and x in [1,7] and direction==Vector2i(0,1): continue
				var normal:=Vector3(-direction.x,0,direction.y)
				var wall:=at-normal*4
				var right:=normal.cross(Vector3.UP)
				chunk.box(wall+Vector3.UP*3.5,Vector3(.5,7,8.5) if direction.x!=0 else Vector3(8.5,7,.5),"CorridorWall",GOLD)
				var face:=wall+normal*.265
				for h: float in [.65,5.7,6.1]: chunk.line(face-right*3.8+Vector3.UP*h,face+right*3.8+Vector3.UP*h,GOLD)
				for band in range(2):
					for symbol in range(5):
						Glyphs.draw(chunk,x+row+symbol+band,face+right*(symbol-2)*1.22+Vector3.UP*(2+band*2.1),right,.65,INK if band==0 else GOLD.lightened(.12))
						glyph_count+=1
			if row in [1,3,5,7] and x%2==0:
				for side in [-1,1]:
					var p:=at+Vector3(side*3.3,0,0)
					chunk.box(p+Vector3.UP*3.3,Vector3(.65,6.6,.65),"PapyrusPillar",GOLD)
					chunk.box(p+Vector3.UP*6.65,Vector3(1.1,.5,1.1),"LotusCapital",INK*.6)
	for side in [-1,1]:
		batch.box(Vector3(side*24,-.2,-61.5),Vector3(8,.4,3),"RearStairApproach",GOLD)
		for edge in [-1,1]:
			batch.rail(Vector3(side*24+edge*4,0,-60),Vector3(side*24+edge*4,0,-63),1.1,"ApproachRail",GOLD)
	# Seal the shared rear vestibule all the way to the sloping perimeter.
	# Overlap the maze's central dead-end wall, including its empty rear cell.
	var divider:=PackedVector3Array()
	for y: float in [0,7.6]:
		for x: float in [-.35,.35]:
			for z: float in [-51.75,CENTER.z-half_at(y)+.1]: divider.append(Vector3(x,y,z))
	batch.convex(divider,[[0,2,3,1],[4,5,7,6],[0,1,5,4],[2,6,7,3],[0,4,6,2],[1,3,7,5]],Vector3.ZERO,"RearVestibuleDivider",GOLD)
	for side in [-1,1]: batch.box(Vector3(side*2.8,2.9,3.55),Vector3(.45,5.8,.6),"ExitDoorPillar",INK)
	batch.box(Vector3(0,5.9,3.55),Vector3(6.1,.45,.6),"ExitDoorLintel",GOLD)
	batch.line(Vector3(-2.5,.2,3.72),Vector3(2.5,.2,3.72),INK)
	batch.line(Vector3(0,.2,3.72),Vector3(0,5.65,3.72),GOLD)
	for chunk in maze_chunks:
		chunk.commit()
		chunk.body.disable_mode=CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
