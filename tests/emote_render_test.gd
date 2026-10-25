extends SceneTree
var game
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func step(dt):game.sim.advance(dt);game.update_visuals(dt);game.touch_controls.frame(dt)
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	game.enter_practice();game.sim.bot_enabled=false;var s=game.sim;var fx=game.original_effects;var ui=game.touch_controls
	s.advance(40);game.update_visuals(0);ui.frame(0)
	check(fx.pass_tags.size()==2 and fx.pass_tags.all(func(e):return e.node.text=="Lolz acquired"),"source acquisition text renders for both units without a model")
	check(fx.pass_tags[0].origin.is_equal_approx(fx.point(s.Characters.world_position(s.players[0])+Vector3(-40,0,150))),"text begins at original world offset")
	step(1.75);check(is_equal_approx(fx.pass_tags[0].node.modulate.a,.5),"two-second acquisition fades over final half second")
	step(.25);check(fx.pass_tags.is_empty(),"acquisition disappears at two seconds")
	ui.toggle_tools();ui.actions.emotes.call();ui.frame(0)
	check(ui.emotes_open and not ui.diagnostics_open and ui.buttons.taunt.is_visible_in_tree(),"More opens separate emote submenu")
	check(not ui.buttons.benchmark.is_visible_in_tree() and not ui.buttons.shout.is_visible_in_tree(),"emote submenu has no overlapping diagnostics or shout buttons")
	check(ui.tools_panel.get_global_rect().encloses(ui.buttons.sadface.get_global_rect()),"sadface stays inside touch menu")
	ui.actions.taunt.call();s.consume_commands();game.update_visuals(0);ui.frame(0)
	check(fx.pass_tags.size()==1 and fx.pass_tags[0].node.text in s.Emotes.TAUNTS,"real mobile taunt button creates the matching text")
	check(ui.buttons.taunt.disabled and not ui.buttons.sadface.disabled,"mobile cooldowns are separate")
	ui.actions.sadface.call();s.consume_commands();game.update_visuals(0);ui.frame(0)
	check(fx.pass_tags.size()==2 and fx.pass_tags[-1].node.text in s.Emotes.SADFACES,"sadface callback captures its own command rather than taunt")
	check(fx.bursts.is_empty(),"text-only emotes do not fabricate mesh effects")
	ui.back();check(ui.tools_panel.visible and not ui.emotes_open,"Back returns to normal More menu")
	ui.back();check(not ui.tools_panel.visible and not game.paused,"second Back returns to gameplay")
	game.focus=Vector3(-4,0,0);game.zoom=.65;game.update_camera()
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/emote-preview.png")
	step(2.75);check(fx.pass_tags.all(func(e):return is_equal_approx(e.node.modulate.a,.5)),"three-second emotes fade in final half second")
	var origin=fx.pass_tags[0].node.position;game.open_menu();game.update_visuals(0)
	check(fx.pass_tags[0].node.position==origin,"pause freezes text presentation")
	game.close_menu();step(.25);check(fx.pass_tags.is_empty(),"emote tags are removed at three seconds")
	step(2.0);game.mobile_enabled=false
	for keycode in [KEY_T,KEY_A]:
		var event=InputEventKey.new();event.keycode=keycode;event.pressed=true;game._unhandled_input(event)
	s.consume_commands();check(s.native_visuals[-2].message in s.Emotes.TAUNTS and s.native_visuals[-1].message in s.Emotes.SADFACES,"original desktop T and A hotkeys both work")
	game.update_visuals(0);game.enter_practice();game.update_visuals(0);check(fx.pass_tags.is_empty(),"new practice clears previous world text")
	game.sim.bot_enabled=false;game.sim.advance(45);game.update_visuals(0)
	check(fx.pass_tags.is_empty(),"already expired acquisition cannot flash after a long update")
	game.free()
	FileAccess.open("res://research/emote-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("EMOTE RENDER ",passed," passed; ",failures.size()," failed");quit(1 if not failures.is_empty() else 0)
