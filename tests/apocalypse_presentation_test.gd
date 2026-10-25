extends SceneTree
var game
var sim
var state
var visual
var passed=0
var failures=[]
var observations={}
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func step_to(age: float):
	var target=state.rules.started+age
	while sim.timeline+0.000001<target:
		var dt=minf(.1,target-sim.timeline)
		sim.advance(dt);visual.frame();game.field_scenery.advance(dt)
func capture(name):
	game.update_visuals(0);game.touch_controls.frame(0)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image=root.get_texture().get_image();image.save_png("res://research/apocalypse-live-"+name+".png");return image
func difference(a,b):
	var changed=0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var c=a.get_pixel(x,y);var d=b.get_pixel(x,y)
			if absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b)>.04:changed+=1
	return changed
func run():
	root.size=Vector2i(960,540)
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.set_process(false);game.touch_controls.start_practice();game.paused=false
	sim=game.sim;sim.bot_enabled=false;sim.random.seed=4192026;sim.advance(40)
	visual=game.apocalypse_visuals;state=sim.prepare_apocalypse()
	check(is_same(visual.state,state) and state.rules.event.is_connected(visual.on_event),"controller subscribes during prepare before vote")
	sim.players[0].pos=Vector2.ZERO;sim.players[0].z=200;sim.players[0].previous=Vector2.ZERO
	sim.ball=Vector3(900,500,60);sim.previous_ball=sim.ball;sim.holder=-1
	check(state.vote(0),"live vote begins event")
	visual.frame()
	check(visual.hole.position.is_equal_approx(Vector3(0,2,0)) and visual.hole.fade_alpha==0,"source hole begins at native relative height 200 and zero alpha")
	step_to(.125)
	check(not sim.unit_present(0) and visual.absorbed_count>=1,"real absorbed player emits original Orb effect")
	var absorbed=visual.transients.filter(func(e):return e.model.data.actor.id=="apoc_absorb")
	check(not absorbed.is_empty() and absorbed[0].model.active_clip.to_lower().begins_with("death"),"unit absorption chooses Death sequence")
	check(not absorbed.is_empty() and absf(absorbed[0].model.basis.y.y)<.001,"unit absorption uses original horizontal dummy pitch")
	step_to(2)
	check(is_equal_approx(visual.hole_entry.advanced,2.0),"hole clock starts at vote, excludes the 40 second gate")
	check(is_equal_approx(visual.hole.scale.x,state.rules.size) and is_equal_approx(visual.hole.fade_alpha,state.rules.alpha/255.0),"source scale and fade drive model")
	var with_hole=await capture("hole")
	visual.effects.hide();var without_hole=await capture("hole-hidden");visual.effects.show()
	observations.hole_pixels=difference(with_hole,without_hole)
	check(observations.hole_pixels>100,"original black hole produces visible pixels in actual field")
	game.paused=true;var frozen=visual.hole_entry.advanced;var rng=sim.random.state
	for i in range(10):game.update_visuals(.1)
	check(visual.hole_entry.advanced==frozen and sim.random.state==rng,"paused redraw cannot advance effect time or gameplay RNG")
	game.paused=false
	step_to(15)
	check(not state.trees.is_empty() and not visual.tree_history.is_empty(),"live random tree pulls reach presentation")
	check(not game.field_scenery.destruction_state().native_seen.is_empty(),"tree events create source dead replacements in actual field")
	step_to(24)
	check(visual.shake_offset.length()>0 and game.camera.h_offset==visual.shake_offset.x,"native shake envelope reaches camera offsets")
	var focus=game.focus;var zoom=game.zoom;game.update_camera()
	check(game.camera.h_offset==visual.shake_offset.x and game.focus==focus and game.zoom==zoom,"camera follow update preserves shake without changing view settings")
	await capture("pulling")
	step_to(47.4)
	check(visual.explosion_count==1,"one original nuclear model emitted at source explosion time")
	var nuclear=visual.transients.filter(func(e):return e.model.data.actor.id=="apoc_nuclear")
	check(nuclear.size()==1 and is_equal_approx(nuclear[0].model.position.y,-10.24) and is_equal_approx(nuclear[0].model.scale.x,3.5),"nuclear uses source absolute Z zero, scale 3.5")
	check(nuclear.size()==1 and nuclear[0].model.particles.particle_count()>0,"live nuclear model emits original particles")
	var blast=await capture("nuclear")
	visual.effects.hide();var no_blast=await capture("nuclear-hidden");visual.effects.show()
	observations.nuclear_pixels=difference(blast,no_blast)
	check(observations.nuclear_pixels>1000,"nuclear effect visible from gameplay camera at source depth")
	check(game.event_decals.total_emitted>0,"native nuclear model emits terrain decal through real event bridge")
	step_to(48.5)
	check(is_equal_approx(visual.mask.color.a,.5) and is_equal_approx(visual.mask.color.r,.3) and is_equal_approx(visual.mask.color.g,.1),"native brown mask is halfway through two-second fade")
	check(visual.mask.mouse_filter==Control.MOUSE_FILTER_IGNORE and visual.mask_layer.layer<game.touch_controls.layer,"cinematic mask leaves mobile menu input reachable")
	step_to(51.6)
	check(visual.cleaned and not is_instance_valid(visual.hole) and visual.trees.is_empty(),"cleanup removes black hole and floating tree visuals")
	check(not game.original_goals.visible,"cleanup removes neutral goal effect units")
	var rock_count=0
	for node in visual.rubble:rock_count+=node.multimesh.instance_count
	check(rock_count+visual.fires.size()==230 and visual.rubble.size()<=4,"all 230 persistent decorations rendered with rubble batched by source model")
	observations.decorations={"rocks":rock_count,"fires":visual.fires.size(),"rubble_draws":visual.rubble.size()}
	check(visual.mask.color.a==1,"cleanup remains fully masked")
	var covered=await capture("covered")
	var pixel=covered.get_pixel(480,250)
	check(absf(pixel.r-.3)<.03 and absf(pixel.g-.1)<.03 and pixel.b<.03,"rendered viewport is covered by the exact source mask color")
	step_to(55)
	check(is_equal_approx(visual.mask.color.a,.8),"five-second revelation fades from source start")
	step_to(59.3)
	check(not visual.mask.visible and visual.shake_offset==Vector2.ZERO,"revelation clears mask and shake")
	check(visual.skeletons.size()==state.rules.skeletons.size() and visual.skeletons.size()>0,"skeleton visuals follow actual spawn events")
	check(visual.transients.any(func(e):return e.model.data.actor.id=="apoc_animate_dead"),"skeleton spawning plays original AnimateDead effect")
	await capture("reveal")
	step_to(66)
	check(visual.skeletons.size()==20,"practice's two original owners each receive ten skeleton visuals")
	check(visual.transients.all(func(e):return e.model.data.actor.id=="apoc_arrow"),"absorption, nuclear and summon tails finish while ongoing combat may emit arrow impacts")
	check(visual.fires.all(func(e):return e.model.particles.particle_count()>0),"persistent fires continue after one-shot tails finish")
	await capture("aftermath")
	# A new game on the SAME field must also remove nuclear scorch; ordinary
	# field-ID change detection is insufficient for this lifecycle boundary.
	game.enter_practice();game.update_visuals(0)
	await process_frame
	check(visual.state==null and visual.effects.get_child_count()==0,"same-field new game releases every event model and particle batch")
	check(game.event_decals.batches.is_empty() and game.event_spawns.active.is_empty(),"new game clears aftermath scorch and detached effects")
	check(not visual.mask.visible and game.camera.h_offset==0 and game.camera.v_offset==0 and game.original_goals.visible,"new game restores normal view and goals")
	check(not state.rules.event.is_connected(visual.on_event),"old adapter cannot enqueue stale events after restart")
	check(game.perf.mode==0 and not game.perf.panel.visible,"effects do not change clean HUD preference")
	sim.advance(40);var next=sim.prepare_apocalypse();next.vote(0);sim.advance(1);visual.frame()
	check(is_instance_valid(visual.hole),"controller binds a second live activation")
	game.field_select.select(2);game.enter_practice();game.update_visuals(0);await process_frame
	check(visual.state==null and visual.effects.get_child_count()==0 and not visual.mask.visible,"switching fields during an active effect discards that event")
	game.free();await process_frame
	FileAccess.open("res://research/apocalypse-live-presentation-verification.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"observations":observations,"skeleton_control_combat":false,"native_noise_calibrated":false,"android_tested":false},"\t"))
	print("APOCALYPSE PRESENTATION ",passed," passed; ",failures.size()," failed; ",observations)
	quit(0 if failures.is_empty() else 1)
