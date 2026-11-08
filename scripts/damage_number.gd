extends Label3D
## Bounded, brief impact feedback; reports damage actually applied to health.
var age := 0.0
const LIFETIME := 0.85

static func make_room(tree: SceneTree) -> void:
	var numbers := tree.get_nodes_in_group("damage_numbers")
	while numbers.size()>=24:
		var oldest: Node = numbers.pop_front()
		oldest.remove_from_group("damage_numbers")
		oldest.queue_free()

func _ready() -> void:
	add_to_group("damage_numbers")
	font_size = 40
	pixel_size = 0.005
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	modulate = Color(0.85,1,1)
	outline_size = 8
	no_depth_test = false

func _process(delta: float) -> void:
	age += delta
	position.y += delta*0.65
	modulate.a = 1-smoothstep(0.4,LIFETIME,age)
	if age>=LIFETIME: queue_free()
