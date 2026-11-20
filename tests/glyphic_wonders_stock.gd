extends SceneTree
const Stock=preload("res://scripts/glyphic_wonders_stock.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func run() -> void:
	Catalog.all()
	Catalog._add(&"wonders_priced","Priced sample","Shared test definition.",&"misc",1,false,true,true,{"price":37,"glyph_coin_value":91})
	Catalog._add(&"wonders_zero","Zero sample","Developer price needs a retail fallback.",&"consumables",1,false,true,true,{"price":0,"glyph_coin_value":0})
	Catalog._add(&"wonders_dev","Developer sample","Not public retail.",&"misc",1,false,true,true,{"developer_only":true})
	Catalog._add(&"wonders_noretail","Disabled retail sample","Not public retail.",&"misc",1,false,true,true,{"retail_enabled":false})
	Catalog._add(&"wonders_bound","Bound sample","Not tradeable.",&"misc",1,false,true,false)
	var pool: Array[String]=Stock.eligible_ids()
	check(pool.size()>12 and pool.has("wonders_priced") and pool.has("wonders_zero"),"Rotating stock reads the shared eligible item catalog")
	check(not pool.has("wonders_dev") and not pool.has("wonders_noretail") and not pool.has("wonders_bound") and not pool.has("civic_key"),"Developer-only, explicitly disabled, bound and key items cannot enter retail stock")
	check(Stock.price_for(&"wonders_priced")==37 and Stock.price_for(&"electron_meal")==8 and Stock.price_for(&"apep_lorai_catalyst")==180,"Positive shared prices take precedence over retail defaults")
	check(Stock.price_for(&"wonders_zero")==15 and Stock.price_for(&"katana")==80 and Stock.price_for(&"wonders_dev")==0,"Missing or developer-zero prices use explicit positive category defaults while excluded items remain unavailable")
	var stock:=Stock.new()
	check(stock.configure(27481,1,7,12,0),"The store configures twelve pedestals on a seven-day world-clock interval")
	check(stock.permanent_ids()==["health_glyph","shield_glyph_light","shield_glyph_medium","shield_glyph_heavy"] and stock.offers().size()==16,"Only existing Health and all three Shield Glyph tiers are permanent counter merchandise")
	var all_positive:=true
	for offer: Dictionary in stock.offers(): all_positive=all_positive and offer.price>0 and Catalog.get_definition(StringName(offer.type_id))!=null
	check(all_positive and stock.offer(&"health_glyph").price==20 and stock.offer(&"shield_glyph_heavy").price==75,"Every pedestal/counter offer has a positive price and existing catalog definition")
	var original:=stock.serialize()
	check(not stock.advance(6.999) and stock.serialize()==original and not stock.configure(9),"Time inside the current interval and repeated entry/configuration cannot reroll offers")
	var copy:=Stock.new()
	check(copy.restore(JSON.parse_string(JSON.stringify(original))) and copy.serialize()==original,"Seed, configuration, saved pool, selection and next rotation survive JSON restoration")
	var same:=Stock.new()
	same.configure(27481,1,7,12,0)
	check(same.rotating_ids()==stock.rotating_ids(),"Identical seed and world cycle produce identical pedestal placement")
	check(stock.advance(7) and stock.cycle==1 and stock.next_rotation==14 and stock.rotating_ids()!=copy.rotating_ids(),"Exactly seven game days rotates the showcase and schedules the next boundary")
	var permanent:=true
	for id: String in stock.permanent_ids(): permanent=permanent and not stock.offer(StringName(id)).is_empty() and stock.offer(StringName(id)).permanent
	check(permanent,"Health and Shield Glyphs remain available after rotating merchandise changes")
	check(stock.advance(700) and stock.cycle==100 and stock.next_rotation==707,"An unloaded shop catches up directly without replaying every missed rotation")
	var state:=stock.serialize()
	check(not stock.advance(1) and stock.serialize()==state,"Clock rollback cannot restore a prior selection")
	var bad:=original.duplicate(true)
	bad.selection[0]="civic_key"
	check(Stock.validate(bad).is_empty(),"A forged or non-purchasable pedestal selection is rejected")
	bad=original.duplicate(true)
	bad.pool.append(bad.pool[0])
	check(Stock.validate(bad).is_empty(),"Saved eligible pools cannot contain duplicates")
	bad=original.duplicate(true)
	bad.next_rotation+=1
	check(Stock.validate(bad).is_empty() and not copy.restore(bad) and copy.serialize()==original,"An altered rotation deadline fails atomically without changing live stock")
	bad=original.duplicate(true)
	bad.config.pedestal_count=0
	check(Stock.validate(bad).is_empty(),"Malformed or unbounded rotation configuration fails closed")
	Catalog._add(&"wonders_later","Later catalog arrival","Added after an existing checkpoint.",&"misc")
	check(copy.restore(original) and not copy.serialize().pool.has("wonders_later") and copy.rotating_ids()==original.selection,"Adding catalog items does not invalidate or reroll a saved current selection")
	check(copy.advance(7) and copy.serialize().pool.has("wonders_later"),"Newly eligible catalog merchandise joins the next scheduled rotation")
	var offered:=copy.rotating_ids()
	offered.clear()
	check(copy.rotating_ids().size()==12,"Public stock arrays are copies rather than mutable internal selection state")
	print("Glyphic Wonders stock verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
