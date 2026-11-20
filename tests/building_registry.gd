extends SceneTree
const Model=preload("res://scripts/building_registry.gd")
const Shell=preload("res://scripts/building_shell.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
const Inventory=preload("res://scripts/inventory.gd")
const Item=preload("res://scripts/item_instance.gd")
var checks:=0
var failures:=0
var model:=Model.new()
var id:="building/fixture/0/0"
var descriptor: Dictionary
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func item(type: StringName,quantity: int=1) -> Dictionary:
	var entry: Resource=Catalog.create(type,quantity)
	entry.owner_id=Model.owner_key(id)
	return entry.to_dict()
func run() -> void:
	var shell:=Shell.new(); shell.configure(id,Vector3(18,14,24))
	descriptor=shell.descriptor(Vector3(32,0,96),"city")
	check(model.register(descriptor) and not model.register(descriptor) and model.serialize().records.is_empty(),"Physical identities register once while vacant untouched buildings remain sparse")
	var manual:=descriptor.duplicate(); manual.id="building/manual"; manual.manual_review=true
	check(model.register(manual) and not model.claim(manual.id,"player",10),"A manual-review building is recorded but cannot be occupied")
	check(model.claim(id,"player",10) and not model.claim(id,"civilian_1",11),"One active owner can claim a vacant shell without stealing an occupied one")
	var physical: Dictionary=model.records[id].layout.duplicate(true)
	check(model.set_use(id,"player","workshop",12) and model.records[id].layout==physical and not model.set_use(id,"civilian_1","shop",13),"Purpose changes preserve geometry and require the current owner")
	check(model.admit(id,"player","civilian_1",13) and model.set_access(id,"player","tenants",14) and model.records[id].tenants==["civilian_1"],"Tenancy and access are persistent property data")
	var bed:=item(&"basic_bed")
	check(model.can_place(id,bed,[-4.0,0.0,-4.0],0) and not model.can_place(id,bed,[0.0,0.0,0.0],0),"Useful floor space accepts a bed while the continuous exit aisle stays clear")
	check(not model.can_place(id,bed,[6.0,0.0,-6.0],0) and not model.can_place(id,bed,[8.5,0.0,0.0],0),"Stair landings and wall volumes cannot be obstructed")
	check(not model.can_place(id,bed,[7.48,0.0,0.0],PI*.25),"Diagonal rotations cannot exploit quarter-turn bounds to protrude through a wall")
	check(not model.can_place(id,bed,[-4.0,14.0,0.0],0) and not model.can_place(id,bed,[-4.0,.8,0.0],0),"Placements need an indexed supporting floor rather than floating in the air or above the roof")
	var wrong:=bed.duplicate(true); wrong.owner_id="civilian_1"
	var stacked:=item(&"basic_bed",2)
	check(not model.install(id,"player",wrong,[-4.0,0.0,-4.0],0,15) and not model.install(id,"player",stacked,[-4.0,0.0,-4.0],0,15),"Installed objects require one real item owned by the destination property")
	check(model.install(id,"player",bed,[-4.0,0.0,-4.0],0,15) and not model.install(id,"player",bed,[-4.0,0.0,-1.0],0,16),"One furnishing identity cannot be installed twice")
	check(not model.can_place(id,item(&"basic_bed"),[-4.0,0.0,-4.0],0),"Existing furnishings prevent physical overlap")
	var clock:=item(&"neon_wall_clock")
	check(model.can_place(id,clock,[-8.225,1.2,4.0],0) and not model.can_place(id,clock,[-4.0,1.2,4.0],0),"Wall-mounted objects must actually meet an interior wall")
	check(not model.can_place(id,clock,[0.0,1.2,11.5],0) and not model.can_place(id,clock,[-8.225,3.1,4.0],0),"Wall decorations cannot cover the exit or cross a ceiling")
	var hanging:=item(&"hanging_light_fixture")
	check(model.can_place(id,hanging,[-4.0,2.6,0.0],0) and not model.can_place(id,hanging,[-4.0,0.0,0.0],0),"Ceiling fixtures snap below the ceiling and reject a floor-level mounting")
	var table:=item(&"dining_table"); var lantern:=item(&"table_lantern")
	check(not model.can_place(id,lantern,[-4.0,.9,4.0],0) and model.install(id,"player",table,[-4.0,0.0,4.0],0,17),"Surface decorations cannot float and an actual table supplies support")
	check(model.install(id,"player",lantern,[-4.0,.9,4.0],0,18) and model.remove(id,"player",table.instance_id,19).is_empty(),"A supporting table cannot be removed beneath an installed lantern")
	var reclaimed:=model.remove(id,"player",lantern.instance_id,20)
	check(reclaimed.instance_id==lantern.instance_id and not model.remove(id,"player",table.instance_id,21).is_empty(),"Dependent objects can be reclaimed in order without changing their identities")
	var source:=Inventory.new(); source.owner_id="player_inventory"
	var stock: Resource=Catalog.create(&"single_chair",3); source.add_item(stock)
	var extracted: Resource=source.take_item(stock.instance_id,1); extracted.owner_id=Model.owner_key(id)
	check(source.count_type(&"single_chair")==2 and model.install(id,"player",extracted.to_dict(),[-4.0,3.5,4.0],0,22),"Splitting an owned stack transfers exactly one physical chair onto an upper storey")
	var storage:=Inventory.new(); storage.owner_id=Model.owner_key(id)
	storage.add_item(Catalog.create(&"byte_bites",2))
	model.records[id].storage=storage.serialize()
	check(model.records[id].storage.owner_id==Model.owner_key(id) and model.records[id].storage.items[0].quantity==2,"Property storage retains owned stack quantities independently of installed furniture")
	var saved:=model.serialize()
	var decoded: Variant=JSON.parse_string(JSON.stringify(saved))
	var copy:=Model.new(); copy.register(descriptor); copy.register(manual)
	var valid:=Model.validate(decoded)
	var restored:=copy.restore(decoded)
	if valid.is_empty() or not restored: print("ROUNDTRIP valid=",not valid.is_empty()," restore=",restored," layout=",JSON.stringify(saved.records[id].layout)," decoded=",decoded.records[id].layout)
	check(not valid.is_empty() and restored and Item.same_properties(copy.serialize(),decoded),"Sparse ownership, tenancy, use, furniture and storage survive a real JSON round trip")
	var corrupt: Dictionary=saved.duplicate(true); corrupt.records[id].position[0]+=5
	check(not copy.restore(corrupt) and Item.same_properties(copy.serialize(),decoded),"A save cannot move a building or partially overwrite valid property state")
	corrupt=saved.duplicate(true); corrupt.records[id].layout.floor_height+=1
	check(not copy.restore(corrupt),"A save cannot redefine the shell's physical floor manifest")
	corrupt=saved.duplicate(true); corrupt.records[id].storage.owner_id="foreign"
	check(Model.validate(corrupt).is_empty(),"Property storage cannot impersonate a foreign inventory owner")
	corrupt=saved.duplicate(true); corrupt.records[id].storage.items.append(bed.duplicate(true))
	check(Model.validate(corrupt).is_empty(),"The same item cannot exist in property storage and an installed placement")
	corrupt=saved.duplicate(true); corrupt.records[id].placements[bed.instance_id].item.quantity=2
	check(Model.validate(corrupt).is_empty(),"A checkpoint cannot multiply a single installed furnishing into a stack")
	corrupt=saved.duplicate(true); corrupt.records[id].placements[bed.instance_id].position=[0.0,0.0,0.0]
	check(Model.validate(corrupt).is_empty(),"Restored placements undergo the same exit-clearance rules as new installations")
	check(copy.restore(null) and copy.serialize().records.is_empty() and copy.records.has(id) and Item.same_properties(copy.records[id].layout,decoded.records[id].layout),"A legacy absent building state clears occupancy while preserving the generated physical census")
	storage.free(); source.free(); shell.free()
	print("Building registry verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
