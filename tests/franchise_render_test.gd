extends SceneTree
const Rules=preload("res://scripts/franchise_rules.gd")
var game
var passed=0
var failures=[]
var pixels={}
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func capture(name):
	game.touch_controls.frame(0)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var im=root.get_texture().get_image();im.save_png("res://research/franchise-"+name+".png");return im
func difference(a,b):
	var total=0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var c=a.get_pixel(x,y);var d=b.get_pixel(x,y)
			if absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b)>.04:total+=1
	return total
func touch(pos):
	for down in [true,false]:
		var e=InputEventScreenTouch.new();e.index=135;e.position=root.get_final_transform()*pos;e.pressed=down
		Input.parse_input_event(e);Input.flush_buffered_events()
func run():
	root.size=Vector2i(1280,720)
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.set_process(false)
	var ui=game.touch_controls;var f=game.franchise;var sim=game.sim
	ui.start_match();sim.bot_enabled=false;sim.match_state="playing";game.update_visuals(0);ui.frame(0)
	check(not sim.franchise_config.enabled and not f.panel.visible,"new install retains existing appearance with settings hidden")
	check(Rules.data().teams.size()==5 and Rules.data().models.size()==10,"five original logo/banner pairs extracted")
	for raw in Rules.data().models:
		check(Rules.data().models[raw].clips==["Stand","Death"],"original idle/death sequences retained "+raw)
	var rng=sim.random.state;var clock=sim.timeline;var positions=sim.players.map(func(p):return p.pos)
	var expected_colors=[Color("0041ff"),Color("ff0202"),Color("fe8a0e"),Color("1ce6b9"),Color("20c000")]
	for chosen in range(5):
		check(f.apply({"enabled":true,"home":chosen,"away":(chosen+1)%5,"jersey":true}),"apply original team "+str(chosen))
		check(f.models.size()==5,"five original placeholders replaced "+str(chosen))
		check(game.actors[0].team_color==expected_colors[chosen],"original jersey color "+str(chosen))
		for i in range(f.models.size()):
			var row=f.rows[i];var model=f.models[i]
			var expected=2.5 if row.original_editor==4449 else (5.0 if int(row.original_editor) in [4451,4452] else 2.0)
			var degrees=270 if int(row.original_editor) in [4449,4451,4452] else (315 if row.original_editor==11 else 225)
			check(model.scale.is_equal_approx(Vector3.ONE*expected) and absf(wrapf(model.rotation.y-deg_to_rad(degrees),-PI,PI))<.001,"authored CreateDestructable scale/facing "+str(row.original_editor))
			check(not game.field_scenery.is_placement_visible(row.original_editor),"original placeholder suppressed without duplicate "+str(row.original_editor))
		await capture("team-"+str(chosen))
	check(sim.timeline==clock and sim.random.state==rng and sim.players.map(func(p):return p.pos)==positions,"cosmetic choices do not reset/move match or consume RNG")
	check(game.score_label.text.contains("雪貂队") and game.actors[0].get_node("PlayerNumber").text.begins_with("雪貂"),"score and live player labels follow selected team")
	var material_count=0
	for model in game.actors:
		for mesh in model.mesh_nodes:
			var material=mesh.material_override
			while material!=null:
				check(material.get_shader_parameter("team_color")==model.team_color,"all material layers follow live jersey color")
				material_count+=1;material=material.next_pass
	check(material_count>0,"jersey check covers actual loaded player materials")
	var anim=game.actors[0].animation_time
	check(f.apply({"enabled":true,"home":4,"away":0,"jersey":false}) and game.actors[0].team_color==Color("4f98ff"),"jersey toggle restores base team color while retaining logos")
	check(game.actors[0].animation_time==anim,"recolor never restarts the character animation")
	check(not f.apply({"enabled":true,"home":2,"away":2,"jersey":true}),"same home and away team rejected without changing current choice")
	f.apply({"enabled":true,"home":2,"away":3,"jersey":true});game.focus=Vector3.ZERO;game.zoom=.8;game.update_camera()
	var with_logos=await capture("applied")
	for model in f.models:model.hide()
	var without=await capture("hidden");pixels.logos=difference(with_logos,without)
	check(pixels.logos>100,"new original artwork contributes visible pixels")
	for model in f.models:model.show()
	var banner=f.models[0];var t=banner.animation_time
	game.paused=true;f.frame(.5);check(banner.animation_time==t,"paused banner clock freezes")
	game.paused=false;f.frame(.5);check(banner.animation_time>t,"original Stand clock resumes")
	# Native touch opens the new entry; picker uses the already tested scroll UI.
	ui.frame(0);touch(ui.buttons.tools.get_global_rect().get_center());touch(ui.buttons.franchise.get_global_rect().get_center())
	check(f.panel.visible and game.paused,"More opens team modal and pauses input")
	await capture("settings")
	touch(f.home.get_global_rect().get_center());await capture("picker")
	check(ui.picker_overlay.visible and ui.active_picker==f.home,"native tap opens home team list above modal")
	touch(ui.picker_list.get_child(1).get_global_rect().get_center())
	check(f.home.selected==1 and not ui.picker_overlay.visible,"native tap selects a team and returns to settings")
	f.away.select(1);f.enabled.button_pressed=true;f.frame(0)
	check(f.apply_button.disabled,"modal prevents duplicate team selection")
	ui.back();check(not f.panel.visible and not game.paused,"Back cancels settings and restores prior pause state")
	check(sim.franchise_config.home==2 and sim.franchise_config.away==3,"cancel leaves applied settings intact")
	f.open();ui.frame(0);await process_frame
	var jersey_before=f.jersey.button_pressed
	touch(f.jersey.get_global_rect().get_center());await process_frame
	check(f.jersey.button_pressed!=jersey_before,"native touch toggles jersey option")
	f.home.select(0);f.away.select(4);f.enabled.button_pressed=true;f.frame(0)
	touch(f.apply_button.get_global_rect().get_center());await process_frame
	check(not f.panel.visible and not game.paused and sim.franchise_config.home==0 and sim.franchise_config.away==4,"native Apply commits settings and resumes play")
	check(game.experience.preferences.get_value("play","franchise")==sim.franchise_config,"saved preference contains the applied cosmetic configuration")
	game.open_menu();f.open();f.close();check(game.paused and game.menu_root.visible,"opening from existing pause preserves pause on cancel");game.close_menu()
	for dimensions in [Vector2i(1280,720),Vector2i(960,540),Vector2i(720,540)]:
		root.size=dimensions;root.content_scale_size=dimensions;await process_frame;ui.layout();f.open();f.layout()
		check(ui.safe_rect().encloses(f.box.get_global_rect()),"team dialog fits viewport "+str(dimensions))
		check(f.box.get_global_rect().encloses(f.apply_button.get_global_rect()) and f.box.get_global_rect().encloses(f.away.get_global_rect()),"team controls fit dialog "+str(dimensions));await capture("settings-"+str(dimensions.x));f.close()
	root.size=Vector2i(1280,720);root.content_scale_size=Vector2i(1280,720);await process_frame;ui.layout()
	# Standalone source objects are replaced in the actual Apocalypse world.
	var state=sim.prepare_apocalypse();var world=state.rules.world
	check(not world.objects.values().any(func(row):return row.id in ["B006","B00C","B00D"]),"native placeholder handles removed")
	check(world.objects.values().filter(func(row):return row.get("generated","")=="Franchise").size()==5,"five real replacement handles enter native enumeration")
	var count=world.objects.size()
	f.apply({"enabled":true,"home":0,"away":4,"jersey":true})
	check(world.objects.size()==count and f.native_rows.size()==5,"reconfiguration replaces existing handles without accumulating objects")
	for row in f.native_rows.values():check(row.id in ["B007","B00E","B00I"],"world follows selected source rawcodes")
	sim.advance(40);state.vote(0);sim.advance(51.5);game.update_visuals(0)
	check(f.models.all(func(model):return model.get_meta("death_started") and model.active_clip=="Death"),"actual Apocalypse cleanup plays original replacement Death clips")
	check(not f.apply({"enabled":false}),"active Apocalypse cannot resurrect scenery through settings")
	ui.start_match();sim.bot_enabled=false;game.update_visuals(0)
	check(f.models.size()==5 and f.models.all(func(model):return model.active_clip=="Stand"),"new match restores live selected artwork")
	for field in [1,2,3,0]:
		game.field_select.select(field);ui.start_practice();game.update_visuals(0)
		check(f.models.size()==(5 if field==0 else 0),"authored replacements stay in their original field "+str(field))
		check(game.actors[0].team_color==expected_colors[0],"chosen jersey survives field change "+str(field))
	f.apply({"enabled":false,"home":0,"away":4,"jersey":true})
	check(f.models.is_empty() and sim.team_name(0)=="蓝队","disable removes custom visuals and restores base names")
	check(Rules.data().placeholders.all(func(row):return game.field_scenery.is_placement_visible(row.editor_id)),"disable restores original placement visibility")
	check(game.perf.mode==0,"no performance HUD enabled by customization")
	FileAccess.open("res://research/franchise-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"pixels":pixels},"\t"))
	print("FRANCHISE CHECKS ",passed," passed; ",failures.size()," failed")
	game.free();quit(0 if failures.is_empty() else 1)
