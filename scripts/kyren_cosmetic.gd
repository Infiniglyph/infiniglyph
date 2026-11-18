extends Node3D
## Player-size copies of Kyren's costume, using the original pooled effects.
const Hat = preload("res://scripts/kyren_hat.gd")
const Scarf = preload("res://scripts/kyren_scarf.gd")
var phase_source: Node
var hat: Node3D
var scarf: Node3D

func configure(figure: Node3D, kind: String) -> void:
	phase_source=figure.get_parent().get("dodge")
	figure.chest.add_child(self)
	if kind=="kyren_hat":
		name="KyrenHatCopy"
		position.y=.78
		hat=Hat.new()
		add_child(hat)
		hat.embers.phase_source=phase_source
	else:
		name="KyrenScarfCopy"
		position.y=.65
		add_child(Scarf.collar())
		scarf=Scarf.new()
		scarf.anchor=self
		scarf.phase_source=phase_source
		scarf.motion_source=figure.get_parent() as CharacterBody3D
		add_child(scarf)

func _process(_delta: float) -> void:
	visible=not (is_instance_valid(phase_source) and phase_source.active)
