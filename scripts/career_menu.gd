extends Node
## Read-only views of authoritative occupational records and hiring evidence.
const Menu=preload('res://scripts/civilian_menu.gd')
const SECTORS:=['exploration','security','commerce','crafting','hospitality','knowledge','underworld','administration']
var world: Node
var menu: CanvasLayer
var subject:=''
var _clock:=0.0
func _ready() -> void:
	name='CareerMenu'
	menu=Menu.new(); menu.services=self; add_child(menu)
	menu.opened.connect(world.inventory_session._opened)
	menu.closed.connect(world.inventory_session._closed)
func _career() -> Node: return world.get('careers') if is_instance_valid(world) else null
func _person(id: String) -> Dictionary:
	var civic: Node=world.get('civic_interactions') if is_instance_valid(world) else null
	return civic.identity(id) if is_instance_valid(civic) else {}
func _near(id: String) -> bool:
	var civic: Node=world.get('civic_interactions')
	var person:=_person(id)
	if not is_instance_valid(civic) or person.get('kind')!='code_form' or not person.get('active',false): return false
	return civic._recipient_near('player',id)
func _blocked() -> bool:
	var session: Node=world.inventory_session
	if session._loading or session._checkpoint_pending or world.player.health<=0 or world.player.transition_locked: return true
	var combat: Node=world.player.get('weapon_combat')
	if is_instance_valid(combat) and (combat.is_staggered() or not combat.active_move.is_empty()): return true
	if world.start_menu.is_open or session.ui.is_open or session.shop.is_open: return true
	for key: String in ['civilian_services','glyphic_wonders','building_civilization']:
		var service: Node=world.get(key)
		if is_instance_valid(service) and service.get('menu')!=null and service.menu.is_open: return true
	return false
func open(id: String) -> bool:
	if not is_instance_valid(menu) or not is_instance_valid(_career()) or _blocked() or not _near(id): return false
	var communication: Node=world.get('communication')
	if is_instance_valid(communication) and communication.is_open:
		if id not in [communication.speaker_id,communication.listener_id]: return false
		communication.close_conversation('career inspection')
	subject=id
	_home()
	return true
func close_menu() -> void:
	if is_instance_valid(menu): menu.close_menu()
func _choice(text: String,action: Callable) -> Dictionary: return {'text':text,'call':action}
func _name(id: String) -> String:
	var person:=_person(id)
	return String(person.get('name',id.replace('_',' ').capitalize()))
func _title(career: String) -> String: return String(_career().definitions.get(career,{}).get('name',career.replace('_',' ').capitalize()))
func _readable(values: Array) -> String:
	var result: Array[String]=[]
	for value: Variant in values: result.append(String(value).replace('_',' ').capitalize())
	return ', '.join(result)
func _account_label(account: String) -> String:
	if account.begins_with('resident:'): return _name(account.trim_prefix('resident:'))+"'s wallet"
	return account.replace(':',' / ').replace('_',' ').capitalize()
func _workplace(id: String) -> String:
	if id.is_empty(): return 'No fixed premises'
	var buildings: Node=world.get('building_civilization')
	if is_instance_valid(buildings) and buildings.model.records.has(id): return id+' / '+String(buildings.model.records[id].usage).capitalize()
	return id.replace('_',' ')
func _home() -> void:
	if not _near(subject): close_menu(); return
	var worker: Dictionary=_career().model.workers.get(subject,{})
	var primary: Dictionary=_career().model.employments.get(String(worker.get('primary','')),{})
	var body:=_name(subject)+'\nPrimary occupation: '+(_title(primary.career) if not primary.is_empty() else 'Considering their next work')
	if not primary.is_empty(): body+='\nWorkplace: '+_workplace(String(primary.workplace))+'\nEmployment: '+String(primary.status).replace('_',' ').capitalize()
	body+='\n\nThey choose their own work. Employment and payment follow actual agreements and completed services.'
	menu.show_page('CAREER & LIVELIHOOD',body,[_choice('Current work and employment history',_jobs),_choice('Hiring agreements and compensation',_agreements),_choice('Businesses and workplaces',_businesses),_choice('Ask how they choose their work',_plans),_choice('Browse career definitions',_sectors)])
func _jobs() -> void:
	var choices: Array=[]
	for row: Dictionary in _career().records_for(subject):
		choices.append(_choice(_title(row.career)+' / '+String(row.status).replace('_',' ').capitalize(),_job.bind(String(row.id))))
	menu.show_page('OCCUPATIONAL RECORDS',_name(subject)+'\nRecorded jobs remain tied to their original employee, employer and workplace.',choices,_home)
func _job(key: String) -> void:
	var row: Dictionary=_career().model.employments.get(key,{})
	if row.is_empty() or row.employee!=subject: _jobs(); return
	var body:=_title(row.career)+'\n'+String(row.status).replace('_',' ').capitalize()+'\nEmployee: '+_name(row.employee)+'\nEmployer: '+_name(row.employer)+'\nWorkplace: '+_workplace(row.workplace)
	body+='\nStarted at world time: %.0f' % float(row.started_at)
	if row.status=='ended': body+='\nEnded at world time: %.0f' % float(row.ended_at)
	if not row.quest_id.is_empty(): body+='\nAgreement: '+String(row.quest_id)
	if not row.business.is_empty(): body+='\nBusiness: '+String(_career().model.businesses.get(row.business,{}).get('name',row.business))
	body+='\n\n'+String(_career().definitions.get(row.career,{}).get('description',''))
	menu.show_page('EMPLOYMENT DETAILS',body,[],_jobs)
func _agreements() -> void:
	var lines: Array[String]=[]
	for row: Dictionary in _career().records_for(subject,false):
		var compensation: Dictionary=row.compensation
		if compensation.get('type')=='contract':
			lines.append(_title(row.career)+' / '+str(compensation.get('amount',0))+' coins from '+_account_label(String(compensation.get('source','')))+'\nEmployer: '+_name(row.employer)+' / Agreement: '+row.quest_id)
		else: lines.append(_title(row.career)+' / '+String(compensation.get('type','unpaid')).replace('_',' ').capitalize())
	var body:=_name(subject)+'\n\n'+('\n\n'.join(lines) if not lines.is_empty() else 'No active hiring agreement is recorded.')
	body+='\n\nAn agreed amount is a contract reward, not proof that coins were already paid. Payment follows completed work.'
	menu.show_page('HIRING & COMPENSATION',body,[],_home)
func _businesses() -> void:
	var choices: Array=[]
	var related: Dictionary={}
	for row: Dictionary in _career().records_for(subject):
		if not row.business.is_empty(): related[row.business]=true
	for id: String in _career().model.businesses:
		var row: Dictionary=_career().model.businesses[id]
		if row.owner==subject or related.has(id): choices.append(_choice(row.name+' / '+String(row.status).capitalize(),_business.bind(id)))
	menu.show_page('BUSINESSES & PREMISES',_name(subject)+'\nThese records describe actual registered organizations and workplaces.',choices,_home)
func _business(id: String) -> void:
	var row: Dictionary=_career().model.businesses.get(id,{})
	if row.is_empty(): _businesses(); return
	var body:=String(row.name)+'\n'+String(row.kind).capitalize()+' / '+String(row.status).capitalize()+'\nOwner: '+_name(row.owner)+'\nWorkplace: '+_workplace(row.workplace)+'\nTreasury: '+_account_label(row.treasury)+'\nRegistered employments: '+str(row.employees.size())
	menu.show_page('REGISTERED BUSINESS',body,[],_businesses)
func _plans() -> void:
	var person:=_person(subject)
	var motives: Dictionary=person.get('motivations',{})
	var worker: Dictionary=_career().model.workers.get(subject,{})
	var primary: Dictionary=_career().model.employments.get(String(worker.get('primary','')),{})
	var lines: Array[String]=[]
	if not primary.is_empty():
		lines.append('My main work is '+_title(primary.career)+'.')
		var definition: Dictionary=_career().definitions.get(primary.career,{})
		for key: String in definition.get('preferred_traits',{}):
			if float(motives.get(key,.5))>.65: lines.append('I put a lot of value on '+key.replace('_',' ')+'.')
	else: lines.append('I am considering what work suits me.')
	lines.append('I can hold several roles. A change of work depends on my priorities and the opportunities I actually find.')
	menu.show_page('CHOOSING WORK',_name(subject)+'\n\n'+'\n'.join(lines),[],_home)
func _sectors() -> void:
	var choices: Array=[]
	for sector: String in SECTORS: choices.append(_choice(sector.capitalize(),_definitions.bind(sector)))
	menu.show_page('CAREER DEFINITIONS','Inspect the kinds of work available in this civilization.',choices,_home)
func _definitions(sector: String) -> void:
	var choices: Array=[]
	for key: String in _career().definitions:
		if _career().definitions[key].sector==sector: choices.append(_choice(_title(key),_definition.bind(key,sector)))
	menu.show_page(sector.to_upper()+' CAREERS','Definitions describe opportunities; they do not assign anyone a title or grant money.',choices,_sectors)
func _definition(key: String,sector: String) -> void:
	var row: Dictionary=_career().definitions.get(key,{})
	if row.is_empty(): _definitions(sector); return
	var body:=String(row.name)+'\n'+String(row.description)+'\n\nCapabilities: '+_readable(row.capabilities)+'\nWorkplaces: '+_readable(row.workplaces)+'\nEmployment: '+String(row.employment_type).replace('_',' ').capitalize()
	if not row.qualifications.is_empty(): body+='\nQualifications: '+_readable(row.qualifications)
	menu.show_page('CAREER PROFILE',body,[],_definitions.bind(sector))
func _process(delta: float) -> void:
	if not is_instance_valid(menu) or not menu.is_open: return
	_clock-=delta
	if _clock>0: return
	_clock=.2
	var communication: Node=world.get('communication')
	if _blocked() or not _near(subject) or is_instance_valid(communication) and communication.is_open: close_menu()
