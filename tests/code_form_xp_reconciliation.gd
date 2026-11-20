extends SceneTree
const Registry=preload("res://scripts/code_form_registry.gd")
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func _initialize() -> void:
	var model:=Registry.new()
	model.config.day_seconds=1.0
	model.config.days_per_year=1
	var descriptor: Dictionary={"id":"test","slot":"hub/test","name":"Test","occupation":"merchant","personality":"curious","respawn":{"location":"overworld","position":[0,0,0],"yaw":0}}
	check(model.bootstrap([descriptor]),"A natural civilian starts with the existing lifetime rules")
	model.grant_xp("test",600)
	check(model.records.test.level==4 and model.records.test.expires_at==400,"Existing level milestones grant their exact lifetime entitlement")
	model.advance_to(40)
	var result:=model.reconcile_xp("test",100)
	check(result.accepted and result.xp_delta==-500 and result.level_delta==-2 and model.records.test.expires_at==200,"Reversal removes only the two unearned level grants")
	check(model.records.test.born_at==0 and model.world_seconds==40 and model.remaining_lifetime("test")==160,"Correction never restores elapsed age or resets the world clock")
	check(model.reconcile_xp("test",100).level_delta==0 and model.records.test.expires_at==200,"Repeated reconciliation cannot subtract lifetime twice")
	model.grant_xp("test",500)
	check(model.records.test.level==4 and model.records.test.expires_at==400,"Earning a revoked level again adds only the new entitlement delta")
	check(not model.reconcile_xp("player",0).accepted and not model.reconcile_xp("monster",0).accepted and not model.reconcile_xp("test",-1).accepted,"Unregistered actors and invalid totals cannot acquire or alter civilian progression")
	model.advance_to(350)
	result=model.reconcile_xp("test",0)
	check(result.expired and model.records.test.expires_at==100 and model.records.test.born_at==0,"Exhausted corrected lifetime retains its honest historical entitlement")
	var replacements:=model.advance_to(model.world_seconds)
	check(replacements.size()==1 and replacements[0].old_id=="test" and model.active_ids().size()==1,"A late correction retires exactly one person without inventing retroactive generations")
	var replacement: Dictionary=model.for_slot("hub/test")
	check(replacement.born_at==350 and replacement.expires_at==450 and model.records.test.retired_at==350,"Normal replacement starts a fresh lifetime at the time the correction is discovered")
	check(not Registry.validate(JSON.parse_string(JSON.stringify(model.serialize()))).is_empty(),"Corrected entitlement and actual retirement survive strict JSON validation")
	check(not model.reconcile_xp("test",100).accepted,"Archived identities cannot regain active progression")
	var legacy:=model.serialize()
	# Legacy records cannot represent delayed correction; test a natural history.
	var natural:=Registry.new()
	natural.config.day_seconds=1.0; natural.config.days_per_year=1
	natural.bootstrap([descriptor]); natural.advance_to(110)
	legacy=natural.serialize()
	for row: Dictionary in legacy.records.values(): row.erase("retired_at")
	var clean:=Registry.validate(legacy)
	check(not clean.is_empty() and clean.records.test.retired_at==100,"Legacy snapshots infer historical natural retirement without resetting anyone")
	print("Code Form XP reconciliation: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
