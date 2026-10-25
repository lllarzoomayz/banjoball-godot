extends SceneTree
var game
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func step(seconds: float):
	while seconds>.000001:
		var dt=minf(seconds,1.0/60);game.sim.advance(dt);game.update_visuals(dt);seconds-=dt
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	game.start_game(3);var s=game.sim;var ui=game.touch_controls;var fx=game.original_effects
	s.countdown=0;s.match_state="playing";s.bot_enabled=false;game.update_visuals(0);ui.frame(0)
	check(ui.buttons.shout.disabled and not ui.tools_panel.visible,"new shout stays inside hidden More menu and starts locked")
	s.advance(40);game.update_visuals(0);ui.frame(0);ui.toggle_tools()
	check(ui.buttons.shout.visible and not ui.buttons.shout.disabled,"source unlock enables the real tool button")
	check(ui.tools_panel.get_global_rect().encloses(ui.buttons.shout.get_global_rect()),"new tool fits existing panel")
	ui.actions.shout.call();step(.1);ui.frame(0)
	check(s.shout.counts[0]==1 and ui.buttons.shout.disabled,"mobile button casts once and displays cooldown")
	var wave=fx.bursts.filter(func(e):return e.model.data.actor.id=="fx_shout")
	check(wave.size()==1 and wave[0].model.mesh_nodes.any(func(n):return n.visible),"source BattleCryCaster has visible original geometry")
	check(wave[0].model.global_transform.is_equal_approx(game.actors[0].attachment_transform("origin")),"caster wave follows original origin")
	check(fx.pass_tags.any(func(e):return e.node.text.ends_with("!") and e.node.text.begins_with("DD")),"source shout appears as fading world text")
	for number in range(1,6):
		var audio=game.experience.sounds["shout"+str(number)]
		check(audio is AudioStreamMP3 and audio.get_length()>0,"original MP3 decodes "+str(number))
	game.experience.sound_enabled=false;game.experience.frame(0)
	check(game.experience.voices.all(func(v):return not v.playing),"muting also suppresses original shouts")
	game.experience.sound_enabled=true
	s.select_player(1);ui.actions.shout.call();step(.1)
	s.select_player(2);ui.actions.shout.call();step(.4)
	for i in range(3):
		var key="buff:"+str(i)+":adrenaline"
		check(fx.persistent.has(key),"coordinated response adds source Phoenix to ally "+str(i))
		check(fx.persistent[key].global_transform.is_equal_approx(game.actors[i].attachment_transform("chest")),"Phoenix follows original chest "+str(i))
		check(fx.persistent[key].ribbons.emitters.any(func(e):return e.sections.size()>1 and e.nodes.any(func(n):return n.visible)),"Phoenix Stand shows original ribbon flames "+str(i))
	check(not fx.persistent.has("buff:3:adrenaline"),"enemy has no allied response effect")
	ui.tools_panel.hide();game.focus=Vector3(-5,0,0);game.zoom=.7;game.update_camera();ui.frame(0)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/shout-047-team.png")
	var time=s.timeline;var clip_time=fx.persistent["buff:0:adrenaline"].animation_time
	game.open_menu();game.update_visuals(0)
	check(s.timeline==time and fx.persistent["buff:0:adrenaline"].animation_time==clip_time,"pause freezes response duration and animation")
	game.close_menu();step(s.players[0].shout_state.adrenaline_until-8.0+2.0-s.timeline+.001);game.experience.frame(0)
	check(game.experience.voices.any(func(v):return v.stream==game.experience.sounds.shout4 and v.playing),"delayed source chorus reaches audio player")
	step(6.1)
	check(not fx.persistent.has("buff:0:adrenaline"),"eight-second response removes looping chest effect")
	check(fx.bursts.any(func(e):return e.model.data.actor.id=="fx_adrenaline" and e.model.particles.particle_count()>0),"Phoenix emits original particles during Death cleanup")
	game.start_game(3);game.sim.bot_enabled=false;game.sim.countdown=0;game.sim.match_state="playing";game.sim.advance(40)
	game.mobile_enabled=false
	var key=InputEventKey.new();key.pressed=true;key.keycode=KEY_G;game._unhandled_input(key);game.sim.consume_commands()
	check(game.sim.shout.counts[0]==1,"PC G maps to original shout")
	var trace=game.show_trace;key.shift_pressed=true;game._unhandled_input(key)
	check(game.show_trace!=trace and game.sim.shout.counts[0]==1,"Shift G retains diagnostic trace without shouting")
	game.free()
	FileAccess.open("res://research/shout-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("SHOUT RENDER ",passed," passed; ",failures.size()," failed")
	quit(1 if not failures.is_empty() else 0)
