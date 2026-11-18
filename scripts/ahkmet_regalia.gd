extends "res://scripts/pyramid_regalia.gd"
## Royal silhouettes shared by Ahkmet and inert, wearable reward copies.
func configure(visual: Node3D, kind: String) -> void:
	figure=visual
	figure.add_child(self)
	name=kind.to_pascal_case()
	if kind in ["ahkmet_full","ahkmet_body"]: royal_torso()
	if kind in ["ahkmet_full","ahkmet_head"]: headdress(false)
	if kind=="union_crown": headdress(true)
	if kind in ["ahkmet_full","ahkmet_legs"]:
		style="glyphweaver_sash"
		skirt()
	if kind in ["ahkmet_full","ahkmet_hands"]:
		for side: String in ["Left","Right"]:
			var root:=anchor(figure.joints[side+"Arm"].get_node("Hinge"),"RoyalBracer")
			panel(root,[[-.07,.02],[.07,.02],[.10,-.29],[0,-.35],[-.10,-.29]],Vector3(0,-.04,.03),.16)
			inscription(root,Vector3(0,-.1,.12),2,1)
	for root: Node3D in external: batch_panels(root)

func royal_torso() -> void:
	style="ibis_scribe_robes"
	torso()
	var root:=anchor(figure.chest,"PharaohMantle")
	for side in [-1,1]:
		for i in range(3):
			var cape:=panel(root,[[-.065,.05],[.065,.05],[.12,-.62],[0,-.83],[-.09,-.66]],Vector3(side*(.11+i*.07),.40,-.22),.025)
			cape.rotation.z=side*(.10+i*.16)
		panel(root,[[-.08,.04],[.08,.04],[.05,-.32],[-.04,-.32]],Vector3(side*.16,.28,.20),.03)
	inscription(root,Vector3(0,.36,.225),4,5)

func headdress(crown_only: bool) -> void:
	var root:=anchor(figure.chest,"SerpentCrown" if crown_only else "RoyalNemes")
	panel(root,[[-.24,0],[.24,0],[.19,.13],[-.19,.13]],Vector3(0,.91,0),.30)
	panel(root,[[-.045,0],[.045,0],[.075,.16],[0,.24],[-.065,.15]],Vector3(0,1.00,.18),.04)
	if not crown_only:
		for side in [-1,1]:
			var flap:=panel(root,[[-.09,.16],[.09,.16],[.15,-.24],[.10,-.48],[-.10,-.36]],Vector3(side*.20,.85,-.04),.18)
			flap.rotation.z=side*.13
			for row in range(6): panel(root,[[-.09,.012],[.09,.012],[.09,-.012],[-.09,-.012]],Vector3(side*.21,.91-row*.08,.065),.015)
		# Undead human face; the unknown Pharaoh has no animal mask.
		panel(root,[[-.11,.10],[.11,.10],[.10,-.11],[0,-.16],[-.10,-.11]],Vector3(0,.79,.12),.14)
		inscription(root,Vector3(0,.84,.20),1,0)
