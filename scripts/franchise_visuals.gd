extends Node3D
const Rules=preload("res://scripts/franchise_rules.gd")
const World=preload("res://scripts/apocalypse_world.gd")
const Model=preload("res://scripts/wc3_model.gd")
var game
var field
var models=[]
var rows=[]
var adapter
var native_rows={}
var placeholder_visibility={}
var signature=""
var panel: Control
var box: Panel
var home
var away
var enabled: CheckButton
var jersey: CheckButton
var message: Label
var apply_button: Button
var previous_paused=false
var roster

func setup(owner_game):
	game=owner_game
	var saved=game.experience.preferences.get_value("play","franchise",{})
	game.sim.franchise_config=Rules.normalized(saved if saved is Dictionary else {})
	game.sim.apocalypse_prepared.connect(bind_world)
	build_ui();get_viewport().size_changed.connect(layout);layout()

func bind_world(state):
	adapter=state;native_rows.clear()
	if not game.sim.franchise_config.get("enabled",false):return
	var world=state.rules.world
	for row in world.objects.values():
		if row.id in ["B006","B00C","B00D"]:world.remove(row.uid)
	for row in Rules.replacements(game.sim.franchise_config,world):
		var added=world.add(row);native_rows[int(row.original_editor)]=added

func restore_world():
	if adapter==null:return
	var world=adapter.rules.world
	for row in world.objects.values():
		if row.get("generated","")=="Franchise":world.remove(row.uid)
	for original in Rules.data().placeholders:
		if not world.objects.values().any(func(row):return row.get("editor_id",-1)==original.editor_id):world.add(original)
	native_rows.clear()

func clear_models():
	for model in models:model.queue_free()
	models.clear();rows.clear()
	if is_instance_valid(field):
		for id in placeholder_visibility:field.set_placement_visible(id,placeholder_visibility[id])
	placeholder_visibility.clear();field=null

func frame(delta: float):
	if not is_same(roster,game.sim.players):signature="";roster=game.sim.players
	if panel.visible:
		apply_button.disabled=enabled.button_pressed and home.selected==away.selected
		message.text="主客队请选择不同球队。" if apply_button.disabled else "队徽与旗帜沿用原图资源；球衣开关只改变队色。"
	if adapter!=null and not is_same(adapter,game.sim.apocalypse):adapter=null;native_rows.clear()
	var next_signature=JSON.stringify(game.sim.franchise_config)
	if not is_instance_valid(field) or field!=game.field_scenery or next_signature!=signature:
		clear_models();signature=next_signature;field=game.field_scenery
		if not game.sim.franchise_config.get("enabled",false):return
		var world=World.new() # Only height lookup; no setup/RNG or copied object pool.
		var definition=game.sim.arena.data
		for row in Rules.replacements(game.sim.franchise_config,world):
			var original=int(row.original_editor)
			# Only replacements of authored visible field placements enter this scene.
			var placed=field.scene_cache[field.field_id].placements.any(func(p):return int(p.editor_id)==original)
			if not placed:continue
			placeholder_visibility[original]=field.is_placement_visible(original);field.set_placement_visible(original,false)
			var source=Rules.data().models[row.id];var model=Model.new();add_child(model);model.load_actor(source.model,Color.WHITE)
			var p=row.position;model.position=Vector3(p[0]-definition.center[0],p[2]-game.sim.arena.world_height_offset,-(p[1]-definition.center[1]))/100
			# The flat logo uses the destructable flyH. Keep zero-height artwork
			# half a map unit above the terrain to avoid coplanar depth flicker.
			if row.id==Rules.team(game.sim.franchise_config,0).logo:model.position.y+=maxf(.5,float(source.source.get("flyH",0)))/100.0
			model.rotation.y=row.angle;model.scale=Vector3.ONE*row.scale[0];model.play("Stand",true)
			model.set_meta("death_started",false);models.append(model);rows.append(row)
	for i in range(models.size()):
		var model=models[i];var native=native_rows.get(int(rows[i].original_editor),{})
		if not native.is_empty() and not native.alive and not model.get_meta("death_started"):
			model.set_meta("death_started",true);model.one_shot=true;model.play("Death",true)
		model.advance(0 if game.paused else delta)

func apply(config: Dictionary) -> bool:
	if game.sim.apocalypse_active():game.sim.notice="末日事件中暂不能更换球队，重新开局后可设置。";return false
	if config.get("enabled",false) and int(config.home)==int(config.away):return false
	restore_world();game.sim.franchise_config=Rules.normalized(config)
	game.experience.preferences.set_value("play","franchise",game.sim.franchise_config.duplicate())
	game.experience.save_settings();signature=""
	if game.sim.apocalypse!=null:bind_world(game.sim.apocalypse)
	frame(0);game.update_visuals(0)
	return true

func build_ui():
	panel=Control.new();panel.hide();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if game.mobile_enabled:
		var root=game.touch_controls.root;root.add_child(panel);root.move_child(game.touch_controls.picker_overlay,-1)
	else:game.get_node("HUD").add_child(panel)
	var shade=ColorRect.new();shade.color=Color(0,0,0,.8);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.add_child(shade)
	box=Panel.new();panel.add_child(box)
	var style=StyleBoxFlat.new();style.bg_color=Color("152b23");style.set_corner_radius_all(16);box.add_theme_stylebox_override("panel",style)
	var title=game.label("球队外观",Vector2.ZERO,30);title.reparent(box);title.name="Title"
	var labels=[]
	for row in Rules.data().teams:labels.append(row.short+" · "+row.name)
	for side in range(2):
		var caption=game.label("主队 · 你控制的队伍" if side==0 else "客队",Vector2.ZERO,23);caption.reparent(box);caption.name="Caption"+str(side)
		var picker
		if game.mobile_enabled:picker=game.touch_controls.picker(box,labels)
		else:
			picker=OptionButton.new();box.add_child(picker);picker.add_theme_font_override("font",game.font);picker.add_theme_font_size_override("font_size",20)
			for text in labels:picker.add_item(text)
		if side==0:home=picker
		else:away=picker
	enabled=CheckButton.new();enabled.text="启用球队外观";box.add_child(enabled)
	jersey=CheckButton.new();jersey.text="使用球队球衣颜色";box.add_child(jersey)
	for toggle in [enabled,jersey]:toggle.add_theme_font_override("font",game.font);toggle.add_theme_font_size_override("font_size",24)
	message=game.label("",Vector2.ZERO,20);message.reparent(box);message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	apply_button=game.button("应用",Rect2(),func():
		if apply({"enabled":enabled.button_pressed,"home":home.selected,"away":away.selected,"jersey":jersey.button_pressed}):close())
	apply_button.reparent(box)
	var back=game.button("取消",Rect2(),close);back.reparent(box);back.name="Back"
	for button in [apply_button,back]:button.add_theme_font_size_override("font_size",26 if game.mobile_enabled else 22)
	if game.mobile_enabled:
		var ui=game.touch_controls;ui.play_button("franchise","球队外观",open);ui.buttons.franchise.reparent(ui.tools_panel);ui.set_tools_page(false)
	else:
		game.desktop_tools.size.y=426
		var button=game.button("球队外观",Rect2(12,374,264,36),open);button.reparent(game.desktop_tools,false)

func layout():
	var safe=game.touch_controls.safe_rect() if game.mobile_enabled else get_viewport().get_visible_rect()
	if game.mobile_enabled:safe.position=Vector2.ZERO # Parent already applies safe-area origin.
	var size=Vector2(minf(980,safe.size.x-48),minf(650,safe.size.y-32))
	box.position=safe.position+(safe.size-size)/2;box.size=size
	box.get_node("Title").position=Vector2(26,18)
	var width=size.x-52;var row_height=(size.y-245)/2
	for i in range(2):
		box.get_node("Caption"+str(i)).position=Vector2(26,116+i*row_height)
		var picker=home if i==0 else away;picker.position=Vector2(26,150+i*row_height);picker.size=Vector2(width,62)
	enabled.position=Vector2(26,65);enabled.size=Vector2(width*.5,45)
	jersey.position=Vector2(size.x*.5,65);jersey.size=Vector2(width*.5,45)
	message.position=Vector2(26,size.y-125);message.size=Vector2(width,48)
	apply_button.position=Vector2(26,size.y-68);apply_button.size=Vector2(width*.48,50)
	var back=box.get_node("Back");back.position=Vector2(size.x*.52,size.y-68);back.size=Vector2(width*.48,50)

func open():
	if game.sim.apocalypse_active():game.sim.notice="末日事件中暂不能更换球队，重新开局后可设置。";return
	previous_paused=game.paused;game.open_menu()
	if game.mobile_enabled:game.touch_controls.cancel_all();game.touch_controls.tools_panel.hide()
	var config=Rules.normalized(game.sim.franchise_config)
	home.select(config.home);away.select(config.away);enabled.button_pressed=config.enabled;jersey.button_pressed=config.jersey
	layout();panel.show();frame(0)

func close():
	panel.hide()
	if not previous_paused:game.close_menu()
