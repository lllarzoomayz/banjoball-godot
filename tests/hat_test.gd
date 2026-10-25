extends SceneTree
const Model=preload("res://scripts/wc3_model.gd")
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func run():
	var game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.enter_practice()
	var hats=game.hats;var ui=game.touch_controls
	check(hats.choices.size()==37 and hats.selected(0)==12,"36 original hats plus explicit none, fresh install has no hat")
	check(hats.active.is_empty(),"no extra model nodes when everyone has no hat")
	var commands=game.sim.pending_commands.duplicate(true)
	for id in hats.choices:
		if id==12:continue
		hats.select_hat(id)
		var entry=hats.active["player:0"]
		check(entry.model.data.actor.id==hats.catalog[id].model,"original model for hat "+str(id))
		check(entry.model.global_transform.is_equal_approx(game.actors[0].attachment_transform("head")),"head transform carries source position rotation scale for hat "+str(id))
		hats.frame(10);await process_frame
	check(game.sim.pending_commands==commands,"cosmetic selection never submits gameplay commands")
	hats.select_hat(0)
	var entry=hats.active["player:0"];var origin=entry.model.global_transform
	game.actors[0].position+=Vector3(2,1,3);game.actors[0].rotation.y=.8;game.actors[0].play("Walk",true);game.actors[0].advance(.2);hats.frame(.2)
	check(entry.model.global_transform.is_equal_approx(game.actors[0].attachment_transform("head")) and not entry.model.global_transform.is_equal_approx(origin),"hat follows animated head after moving and turning")
	game.actors[0].hide();hats.frame(0);check(not entry.model.visible,"hidden actor cannot leak hat location");game.actors[0].show()
	game.actors[0].visibility_amount=.4;hats.frame(0);check(is_equal_approx(entry.model.visibility_amount,.4),"hat inherits stealth visibility")
	var time=entry.model.animation_time;game.paused=true;hats.frame(.3);check(entry.model.animation_time==time,"pause freezes own hat animation");game.paused=false
	game.sim.controlled=1;check(hats.selected(1)==12,"teammate keeps independent cosmetic choice");hats.select_hat(27)
	check(hats.active["player:1"].hat==27 and hats.active["player:0"].hat==0,"switching teammate does not move the first player's hat")
	game.sim.controlled=0;game.sim.selected_character="h02C";game.sim.reset();game.rebuild_actors();game.update_visuals(0)
	check(hats.selected(0)==0 and hats.active["player:0"].hat==0,"rebuild keeps saved slot's choice")
	game.sim.Characters.use(game.sim,0,game.sim.players[0].pos);game.sim.advance(.44);game.update_visuals(.44)
	check(not game.sim.arena.pillars.is_empty(),"real pillar skill creates an attachment target")
	var pillar=game.sim.arena.pillars[0];var key="pillar:"+str(pillar.id)
	check(hats.active.has(key) and hats.active[key].hat==0,"original owner hat copied to spawned pillar")
	check(hats.active[key].model.global_transform.is_equal_approx(game.pillar_models[pillar.id].attachment_transform("overhead")),"pillar uses overhead rather than unit head")
	hats.select_hat(1);check(hats.active[key].hat==0,"already-created pillar keeps its original hat selection")
	game.sim.selected_character="h029";game.sim.reset();game.rebuild_actors();game.sim.players[0].morph_kit="h00R";game.sim.players[0].morph_ghost=1.5;game.update_visuals(0)
	check(hats.active.has("morph:0") and hats.active["morph:0"].hat==1,"metamorph animation copy receives caster's hat")
	check(hats.active["morph:0"].model.global_transform.is_equal_approx(game.morph_models[0].attachment_transform("head")),"copied character uses its own animated head")
	game.sim.players[0].morph_ghost=0;game.update_visuals(.1);await process_frame;hats.frame(.1)
	check(not hats.active.has("morph:0"),"hat cleanup follows disappearing morph copy")
	hats.select_hat(15);hats.select_hat(12)
	check(not hats.active.has("player:0") and hats.dying.any(func(e):return e.hat==15 and e.model.active_clip.to_lower().begins_with("death")),"removing animal hat plays original Death when present")
	hats.frame(20);await process_frame;check(hats.dying.is_empty(),"retired hats release after animation and trail lifetime")
	ui.actions.hats.call();check(game.paused and ui.picker_overlay.visible and ui.active_picker==ui.pick_hat,"More hat picker pauses match and owns input")
	ui.frame(.1);await process_frame;ui.frame(.1)
	check(ui.picker_overlay.visible and ui.active_picker==ui.pick_hat,"standalone hat picker stays open after normal UI frames")
	check(ui.picker_list.get_child_count()==37,"touch picker exposes every original hat")
	ui.choose_picker_item(1);check(not game.paused and hats.selected(0)==0,"choosing cosmetic resumes play and equips selected original hat")
	ui.actions.hats.call();ui.back();check(not ui.picker_overlay.visible and game.paused,"canceling picker returns to paused menu")
	game.close_menu();game.rebuild_actors();check(hats.active.is_empty() and hats.dying.is_empty(),"rebuild frees old attachments before recreating actors")
	# stop() is forwarded to the audio mixer asynchronously. Allow its current
	# buffer to release the animal Death playback before tearing down the tree.
	await create_timer(.1).timeout
	game.free()
	await process_frame
	FileAccess.open("res://research/hat-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("HATS ",passed," passed; ",failures.size()," failed");quit(1 if not failures.is_empty() else 0)
