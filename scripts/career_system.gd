extends Node
## The existing civilian scheduler calls npc_step; this node has no frame loop.
const Model=preload("res://scripts/career_registry.gd")
signal changed
var model:=Model.new()
var world: Node
var definitions: Dictionary:
	get: return model.definitions
func setup(callbacks: Dictionary) -> void: model.configure(callbacks)
func configure(callbacks: Dictionary) -> void: setup(callbacks)
func select_career(id: String,career: String,workplace: String="") -> String:
	var result:=model.select_career(id,career,workplace)
	if not result.is_empty(): changed.emit()
	return result
func hire(employer: String,employee: String,career: String,workplace: String,quest_id: String,business: String="") -> String:
	var result:=model.hire(employer,employee,career,workplace,quest_id,business)
	if not result.is_empty(): changed.emit()
	return result
func records_for(id: String,include_history: bool=true) -> Array[Dictionary]: return model.records_for(id,include_history)
func set_primary(id: String,key: String) -> bool:
	var ok:=model.set_primary(id,key)
	if ok: changed.emit()
	return ok
func end_employment(id: String,key: String) -> bool:
	var ok:=model.end_employment(id,key)
	if ok: changed.emit()
	return ok
func register_business(owner: String,label: String,workplace: String,kind: String) -> String:
	var result:=model.register_business(owner,label,workplace,kind)
	if not result.is_empty(): changed.emit()
	return result
func npc_step(id: String,now: float) -> Dictionary:
	var before: int=model.revision
	var result:=model.npc_step(id,now)
	if model.revision!=before: changed.emit()
	return result
func on_replacements(changes: Array) -> void:
	for row: Dictionary in changes: model.retire(String(row.old_id))
	if not changes.is_empty(): changed.emit()
func observe_service(event: Dictionary) -> bool:
	var ok:=model.observe_service(event)
	if ok: changed.emit()
	return ok
func transaction_active() -> bool: return model.transaction_active()
func reconcile_contracts(now: float) -> void:
	var before: int=model.revision
	model.reconcile_contracts(now)
	if model.revision!=before: changed.emit()
func serialize() -> Dictionary: return model.serialize()
func restore(data: Variant) -> bool:
	var ok:=model.restore(data)
	if ok: changed.emit()
	return ok
static func validate(data: Variant) -> Dictionary: return Model.validate(data)
