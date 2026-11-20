extends SceneTree
## Exact decision-component parity plus transient index invalidation.
const Autonomy=preload("res://scripts/code_form_autonomy.gd")
const Registry=preload("res://scripts/code_form_registry.gd")
const Buildings=preload("res://scripts/building_registry.gd")
const Stock=preload("res://scripts/glyphic_wonders_stock.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
class CountingStock:
	extends "res://scripts/glyphic_wonders_stock.gd"
	var calls:=0
	func offers() -> Array[Dictionary]: calls+=1; return super.offers()
class Shop:
	extends Node
	var stock: RefCounted
class Agent:
	extends "res://scripts/code_form_autonomy.gd"
	var vendor: Node
	func _shop() -> Node: return vendor
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func legacy_interest(record: Dictionary,coins: int,stock: RefCounted) -> float:
	var result:=0.0
	for offer: Dictionary in stock.offers():
		if int(offer.get("price",0))<=0 or int(offer.price)>coins: continue
		var definition: Resource=Catalog.get_definition(StringName(offer.type_id))
		if definition==null: continue
		var m: Dictionary=record.motivations
		var value: float=.2+float(m.novelty)*.5
		if String(definition.item_type_id).begins_with("health_glyph") or String(definition.item_type_id).begins_with("shield_glyph"): value+=float(m.security)*.55+float(m.survival)*.35
		elif definition.category==&"weapons": value+=float(m.mastery)*.7
		elif definition.category==&"materials": value+=float(m.knowledge)*.45+float(m.wealth)*.25
		else: value+=float(m.social)*.25+float(m.wealth)*.25
		result=maxf(result,value)
	return result
func row(id: String) -> Dictionary:
	return {"slot":"hub/"+id,"id":id,"name":id,"occupation":"gardener","personality":"curious","respawn":{"location":"overworld","position":[0.0,.05,0.0],"yaw":0.0}}
func descriptor(id: String,x: float) -> Dictionary:
	return {"id":id,"point":Vector3(x,0,0),"size":Vector3(18,7,24)}
func run() -> void:
	var stock:=CountingStock.new()
	stock.configure(1893,86400,7,12)
	var shop:=Shop.new(); shop.stock=stock; root.add_child(shop)
	var agent:=Agent.new(); agent.vendor=shop
	var parity:=true
	var rng:=RandomNumberGenerator.new(); rng.seed=8214
	for sample in range(40):
		var motives: Dictionary={}
		for key: String in Registry.MOTIVATIONS: motives[key]=rng.randf()
		var record:={"motivations":motives}
		for coins: int in [0,11,12,14,15,19,20,25,40,45,60,75,80,200]:
			parity=parity and agent._shopping_interest(record,coins)==legacy_interest(record,coins,stock)
	check(parity,"Four weighted shopping components exactly match the previous item scan across 560 motivation/affordability cases")
	var person:={"motivations":{"novelty":.8,"security":.6,"survival":.5,"mastery":.7,"knowledge":.2,"wealth":.4,"social":.9}}
	agent._batch_active=true; stock.calls=0
	for i in range(12): agent._shopping_interest(person,100)
	check(stock.calls==1 and agent._interest_prices.size()<=4,"A twelve-citizen batch shares one bounded offered-component lookup")
	stock.advance(stock.next_rotation)
	agent._shopping_interest(person,100)
	check(stock.calls==2,"A stock rotation immediately invalidates the current batch's shared components")
	var alternate:=Stock.new(); alternate.configure(1919,86400,7,12,stock.next_rotation-1)
	var revision: int=stock.revision
	check(stock.restore(alternate.serialize()) and stock.revision>revision,"Restoring another valid selection advances the transient stock revision")
	var prior: int=stock.calls
	var interest: float=agent._shopping_interest(person,100)
	check(stock.calls==prior+1 and is_equal_approx(interest,legacy_interest(person,100,stock)),"A restored stock with a matching cycle cannot reuse a previous selection's components")
	agent._batch_active=false; prior=stock.calls
	agent._shopping_interest(person,20); agent._shopping_interest(person,20)
	check(stock.calls==prior+2,"Outside a simulation batch, standalone decisions always observe fresh offers")
	var registry:=Registry.new(); registry.bootstrap([row("zeta"),row("alpha")])
	var census:=registry.active_ids(); census.clear()
	check(registry.active_ids()==["alpha","zeta"],"Mutating a caller's census cannot change shared sorted identities")
	registry.bootstrap([row("middle")])
	check(registry.active_ids()==["alpha","middle","zeta"],"Newly admitted citizens invalidate the sorted census")
	var saved:=registry.serialize()
	registry.advance_to(float(registry.records.alpha.expires_at))
	check(not "alpha" in registry.active_ids() and registry.active_ids().size()==3,"Lifetime replacement refreshes the census without losing a persistent slot")
	check(registry.restore(saved) and registry.active_ids()==["alpha","middle","zeta"],"Checkpoint restore rebuilds identities instead of retaining replacement cache entries")
	var model:=Buildings.new()
	model.register(descriptor("building/earlier",0)); model.register(descriptor("building/later",40))
	check(model.properties_for("alpha").is_empty(),"Unhoused citizens have a cheap empty property lookup")
	model.claim("building/later","alpha",0)
	check(model.properties_for("alpha")==["building/later"],"A claim invalidates a cached negative ownership lookup")
	model.claim("building/earlier","alpha",1)
	check(model.properties_for("alpha")==["building/earlier","building/later"],"Indexed ownership preserves manifest order rather than acquisition order")
	model.admit("building/later","alpha","tenant",2)
	check(model.properties_for("tenant").is_empty() and model.properties_for("tenant",true)==["building/later"],"Tenancies participate in workplace context without conferring ownership")
	var properties:=model.properties_for("alpha"); properties.clear()
	check(model.properties_for("alpha").size()==2,"A caller cannot mutate the shared property index")
	var property_save:=model.serialize()
	check(model.restore(null) and model.properties_for("alpha").is_empty() and model.properties_for("tenant",true).is_empty(),"A legacy/reset restore clears both positive ownership and tenancy caches")
	check(model.restore(property_save) and model.properties_for("alpha").size()==2 and model.properties_for("tenant",true).size()==1,"Saved property ownership and tenancies are rebuilt together")
	shop.queue_free()
	print("CODE FORM CONSTRAINT CACHE: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
