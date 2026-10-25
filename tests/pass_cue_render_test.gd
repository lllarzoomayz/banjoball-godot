extends SceneTree
var game
var passed=0
var failures=[]
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func _initialize():call_deferred("run")
func step(seconds: float):
	while seconds>.00001:
		var delta=minf(.05,seconds);game.sim.advance(delta);game.update_visuals(delta);seconds-=delta
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	game.start_game(3);game.sim.countdown=0;game.sim.match_state="playing";game.sim.bot_enabled=false
	game.focus=Vector3.ZERO;game.zoom=.6;game.update_camera()
	var sim=game.sim;var effects=game.original_effects
	game.touch_controls.actions.pass.call()
	var count=sim.native_visuals.size()
	check(count>0 and sim.native_visuals[-1].model=="fx_pass_me" and sim.native_visuals[-1].owner==sim.controlled,"real mobile call-for-pass emits owner-bound source effect")
	check(sim.pass_request==3.0,"existing AI pass request remains active")
	sim.call_for_pass();check(sim.native_visuals.size()==count,"original one-second cue cooldown prevents spam")
	game.update_visuals(0);step(.1)
	var cues=effects.bursts.filter(func(entry):return entry.model.data.actor.id=="fx_pass_me")
	check(cues.size()==1 and cues[0].model.active_clip=="Death","DestroyEffect plays original TalkToMe Death sequence")
	var cue=cues[0].model
	check(cue.global_transform.is_equal_approx(game.actors[sim.controlled].attachment_transform("overhead")),"cue uses actual animated overhead attachment")
	check(cue.mesh_nodes.any(func(node):return node.visible),"source cue contains visible original geometry")
	check(effects.pass_tags.size()==1 and effects.pass_tags[0].node.text=="传给我！","friendly world text appears")
	game.touch_controls.frame(0);await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/pass-cue-047.png")
	var tag=effects.pass_tags[0].node;var old_position=tag.position;var old_time=cue.animation_time
	game.open_menu();game.update_visuals(0)
	check(tag.position==old_position and cue.animation_time==old_time,"pause freezes cue and text lifetime")
	game.close_menu();step(.7)
	check(not effects.bursts.any(func(entry):return entry.model.data.actor.id=="fx_pass_me"),"short original effect cleans up after Death")
	check(effects.pass_tags.size()==1,"three-second text outlives its short original model effect")
	step(.25);sim.call_for_pass();check(sim.native_visuals.size()==count+1,"cue can be repeated after one second")
	sim.select_player(1);sim.call_for_pass();check(sim.native_visuals.size()==count+2,"each teammate has an independent cue cooldown")
	game.update_visuals(0);check(effects.pass_tags.size()==3,"separate friendly requests retain separate text tags")
	step(1.7)
	check(tag.modulate.a>0 and tag.modulate.a<1,"original text fades only in its final half-second")
	step(.3);check(not effects.pass_tags.any(func(entry):return entry.node==tag),"first text expires at three seconds")
	step(1.1);check(effects.pass_tags.is_empty(),"all expired text nodes are released")
	count=sim.native_visuals.size();sim.controlled=3;sim.call_for_pass()
	check(sim.native_visuals.size()==count,"enemy pass requests do not reveal a friendly-only cue")
	sim.controlled=0;sim.reset();sim.call_for_pass();game.update_visuals(0)
	check(effects.pass_tags.size()==1,"new match clears old cues and cooldown state")
	game.free()
	FileAccess.open("res://research/pass-cue-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("PASS CUE CHECKS ",passed," passed; ",failures.size()," failed")
	quit(1 if not failures.is_empty() else 0)
