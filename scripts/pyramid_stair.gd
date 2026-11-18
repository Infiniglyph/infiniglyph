extends Node3D
## A two-flight stair with smooth, matching ramp collision and bounded batches.
const Chunk = preload("res://scripts/world_chunk.gd")
const GOLD := Color(.54,.37,.13)
const INK := Color(.05,.85,.78)
const FLIGHT_WIDTH := 3.2
const OFFSET := 1.9
var lower_id: StringName
var upper_id: StringName
var lower_y := 0.0
var upper_y := 8.0
var center_x := 26.0
var front_z := -63.0
var direction := 1.0 # +1 opens toward +Z; -1 opens toward -Z.
var batch: Node3D
var route: Array[Vector3] = []

func footprint() -> Rect2:
	var run:=upper_y-lower_y
	return Rect2(center_x-3.8,minf(front_z+3*direction,front_z-(run+3)*direction),7.6,run+6)

func bottom() -> Vector3: return Vector3(center_x-OFFSET,lower_y+.05,front_z+1.5*direction)
func top() -> Vector3: return Vector3(center_x+OFFSET,upper_y+.05,front_z+1.5*direction)

func _ready() -> void:
	name="Stair_"+String(lower_id)+"_"+String(upper_id)
	batch=Chunk.new()
	add_child(batch)
	var rise:=upper_y-lower_y
	var run:=rise
	var mid_y:=lower_y+rise*.5
	var rear:=front_z-run*direction
	var a:=Vector3(center_x-OFFSET,lower_y,front_z)
	var b:=Vector3(center_x-OFFSET,mid_y,rear)
	var c:=Vector3(center_x+OFFSET,mid_y,rear)
	var d:=Vector3(center_x+OFFSET,upper_y,front_z)
	flight(a,b)
	flight(c,d)
	for y: float in [lower_y,upper_y]:
		batch.box(Vector3(center_x,y-.2,front_z+1.5*direction),Vector3(7.6,.4,3),"StairFrontLanding",GOLD)
	batch.box(Vector3(center_x,mid_y-.2,rear-1.5*direction),Vector3(7.6,.4,3),"StairTurnLanding",GOLD)
	# Rails protect the opening on the upper storey; its front is a full landing.
	for x: float in [center_x-3.85,center_x+3.85]:
		batch.rail(Vector3(x,upper_y,front_z+3*direction),Vector3(x,upper_y,rear-3*direction),1.1,"StairwellRail",GOLD)
	batch.rail(Vector3(center_x-3.9,upper_y,rear-3*direction),Vector3(center_x+3.9,upper_y,rear-3*direction),1.1,"StairwellRearRail",GOLD)
	batch.rail(Vector3(center_x-3.9,mid_y,rear-3*direction),Vector3(center_x+3.9,mid_y,rear-3*direction),1.1,"TurnLandingRail",GOLD)
	for side in [-1,1]:
		batch.rail(Vector3(center_x+side*3.8,mid_y,rear),Vector3(center_x+side*3.8,mid_y,rear-3*direction),1.1,"TurnSideRail",GOLD)
	route=[bottom()+Vector3(0,0,2*direction),bottom(),a+Vector3.UP*.05,b+Vector3.UP*.05,
		b+Vector3(0,.05,-1.5*direction),c+Vector3(0,.05,-1.5*direction),c+Vector3.UP*.05,
		d+Vector3.UP*.05,top(),top()+Vector3(0,0,2*direction)]
	batch.commit()
	batch.body.disable_mode=CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE

func flight(a: Vector3, b: Vector3) -> void:
	var side:=Vector3.RIGHT*FLIGHT_WIDTH*.5
	var drop:=Vector3.DOWN*.35
	var vertices:=PackedVector3Array([a-side+drop,a+side+drop,b-side+drop,b+side+drop,
		a-side,a+side,b-side,b+side])
	batch.convex(vertices,[[0,2,3,1],[4,5,7,6],[0,1,5,4],[2,6,7,3],[0,4,6,2],[1,3,7,5]],Vector3.ZERO,"StairRamp",GOLD)
	var count:=ceili(absf(b.y-a.y)/.2)
	# The visual treads and risers follow the same slope as the physical flight.
	for i in range(count+1):
		var p:=a.lerp(b,float(i)/count)+Vector3.UP*.008
		batch.line(p-side,p+side,INK if i%5==0 else GOLD)
	for offset: float in [-FLIGHT_WIDTH*.5,FLIGHT_WIDTH*.5]:
		batch.rail(a+Vector3.RIGHT*offset,b+Vector3.RIGHT*offset,1.1,"FlightRail",GOLD,.12)
