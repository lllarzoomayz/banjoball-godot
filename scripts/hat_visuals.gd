extends Node3D
## Original Pick__hats. Per-player cosmetic choice; no simulation RNG/state.
const Model=preload("res://scripts/wc3_model.gd")
const CosmeticAnimation=preload("res://scripts/cosmetic_animation.gd")
var game
var catalog=[]
var choices=[]
var slots={}
var active={}
var dying=[]
var desktop_picker: OptionButton

func setup(owner_game):
	game=owner_game
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/cosmetics/hats.json"))
	choices=[12]
	for row in catalog:
		if row.model!="":choices.append(int(row.index))
	slots=game.experience.preferences.get_value("cosmetics","hats",{}).duplicate()
	if not game.mobile_enabled:
		desktop_picker=OptionButton.new();desktop_picker.add_theme_font_override("font",game.font);desktop_picker.add_theme_font_size_override("font_size",16)
		for id in choices:desktop_picker.add_item("帽子："+catalog[id].name)
		game.desktop_tools.add_child(desktop_picker);desktop_picker.position=Vector2(12,324);desktop_picker.size=Vector2(264,36)
		game.desktop_tools.size.y=382
		desktop_picker.item_selected.connect(func(i):select_hat(choices[i]))

func selected(slot: int) -> int:
	if game.sim.networked and slot<game.sim.players.size():return int(game.sim.players[slot].get("hat",12))
	var value=int(slots.get(str(slot),12))
	return value if value in choices else 12

func select_hat(index: int):
	if game.sim.networked:return
	if index not in choices:return
	slots[str(game.sim.controlled)]=index
	game.experience.preferences.set_value("cosmetics","hats",slots.duplicate())
	game.experience.save_settings()
	frame(0)

func clear():
	for entry in active.values():entry.model.free()
	for entry in dying:
		if is_instance_valid(entry.model):entry.model.free()
	active.clear();dying.clear()

func retire(key):
	var entry=active[key];active.erase(key)
	if entry.model.play("Death",true):
		entry.model.one_shot=true;entry.age=0.0
		var tail=0.0
		for emitter in entry.model.data.emitters:tail=maxf(tail,float(emitter.LifeSpan))
		entry.life=float(entry.model.clip.duration)+tail;dying.append(entry)
	else:entry.model.hide();entry.model.queue_free()

func place(entry,delta):
	var parent=entry.parent;var model=entry.model
	model.global_transform=parent.attachment_transform(entry.point)
	model.set_team_color(parent.team_color)
	model.visibility_amount=parent.visibility_amount
	model.fade_alpha=parent.fade_alpha
	model.visible=parent.is_visible_in_tree() and not parent.is_queued_for_deletion()
	entry.animation.advance(model,delta)

func bind(key,parent,index: int,point: String,alive: Dictionary,delta: float):
	if index==12:return
	alive[key]=true
	if active.has(key) and (active[key].hat!=index or active[key].parent!=parent):retire(key)
	if not active.has(key):
		var model=Model.new();add_child(model);model.load_actor(catalog[index].model,parent.team_color)
		var animation=CosmeticAnimation.new();animation.setup(model)
		active[key]={"model":model,"parent":parent,"point":point,"hat":index,"animation":animation}
	place(active[key],delta)

func frame(delta: float):
	if game.paused:delta=0
	var alive={}
	for i in range(game.actors.size()):
		bind("player:"+str(i),game.actors[i],selected(i),"head",alive,delta)
	for i in game.morph_models:
		var parent=game.morph_models[i]
		if not parent.has_meta("hat_index"):parent.set_meta("hat_index",selected(i))
		bind("morph:"+str(i),parent,int(parent.get_meta("hat_index")),"head",alive,delta)
	for pillar in game.sim.arena.pillars:
		if not game.pillar_models.has(pillar.id):continue
		var parent=game.pillar_models[pillar.id]
		if not parent.has_meta("hat_index"):parent.set_meta("hat_index",selected(int(pillar.owner)))
		bind("pillar:"+str(pillar.id),parent,int(parent.get_meta("hat_index")),"overhead",alive,delta)
	for key in active.keys():
		if not alive.has(key):retire(key)
	var remaining=[]
	for entry in dying:
		if not is_instance_valid(entry.parent) or entry.parent.is_queued_for_deletion():entry.model.queue_free();continue
		place(entry,delta);entry.age+=delta
		if entry.age>=entry.life or entry.model.visual_tail_finished():entry.model.queue_free()
		else:remaining.append(entry)
	dying=remaining
	if is_instance_valid(desktop_picker):desktop_picker.select(choices.find(selected(game.sim.controlled)))
