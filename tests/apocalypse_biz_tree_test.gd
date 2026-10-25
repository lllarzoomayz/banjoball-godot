extends SceneTree
var game
var sim
var tree
var state
var bridge
var passed=0
var failures=[]
var observations={}
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func fresh(field=0,clicked=false,outside=false,text_age=-1.0):
	game.field_select.select(field);game.enter_practice();tree.frame(0)
	if tree.bound_field.placement_slots.has(int(tree.chosen.editor_id)):tree.bound_field.set_placement_visible(int(tree.chosen.editor_id),true)
	var candidates=tree.catalog.candidates.filter(func(c):return game.field_scenery.placement_slots.has(int(c.editor_id))!=outside)
	tree.chosen=candidates[0];tree.removed=clicked;tree.pending=-1;tree.text_age=text_age;tree.bind_field()
	sim=game.sim;sim.random.seed=1321;sim.advance(40);state=sim.prepare_apocalypse();bridge=state.biz_tree
	game.paused=false
func update():
	tree.frame(0);game.apocalypse_visuals.frame()
func capture(name,unmasked=false):
	game.update_visuals(0);game.touch_controls.frame(0)
	if unmasked:game.apocalypse_visuals.mask.hide()
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image=root.get_texture().get_image();image.save_png("res://research/apocalypse-biz-"+name+".png");return image
func run():
	root.size=Vector2i(960,540)
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.set_process(false);tree=game.biz_tree
	fresh()
	check(state.rules.world.find_editor(int(tree.chosen.editor_id)).is_empty(),"original destructable removed from native pool on BizTree initialization")
	check(state.external_objects.size()==1 and is_same(state.external_objects[0],bridge.object),"renderer and native ANCIENT registry use one shared unit record")
	check(not state.properties[bridge.object.apoc_rawcode].locust and state.properties[bridge.object.apoc_rawcode].radius==0,"original BizTree has no path radius but remains enumerable")
	check(not game.field_scenery.is_placement_visible(int(tree.chosen.editor_id)),"original static tree hidden when binding after a field rebuild")
	state.vote(0)
	bridge.object.pos=Vector3(500,600,80);bridge.object.previous=bridge.object.pos
	var before=bridge.object.pos;sim.advance(sim.BALL_DT);update()
	check(bridge.object.pos!=before and bridge.object.apoc_velocity.length()>0,"real 32 Hz pull moves the live special tree")
	check(tree.model.position.is_equal_approx(tree.native_point(bridge.object.pos)),"rendered special tree follows live physics position")
	var expected=tree.model.global_transform*tree.bounds.get_center()
	game.camera.position=expected+Vector3(0,10,15);game.camera.look_at(expected)
	var screen=game.camera.unproject_position(expected)
	check(tree.try_select(screen),"moved airborne special tree remains selectable")
	var due=bridge.next_time;var start=bridge.object.pos
	game.paused=true;tree.frame(1)
	check(bridge.next_time==due and not bridge.object.removed,"paused render does not run selection's native timer")
	game.paused=false;sim.advance(.49);update()
	check(not bridge.object.removed and bridge.replacement.is_empty(),"selection does not replace the unit early")
	sim.advance(.01);update()
	check(bridge.object.removed and bridge.replacement_present() and not is_instance_valid(tree.model),"half-second simulation callback removes special unit and creates ordinary destructable")
	check(bridge.text_position!=state.absolute(start),"selection callback reads current moving unit coordinates, not click coordinates")
	var row=bridge.replacement;var p=Vector3(row.position[0],row.position[1],row.position[2])
	check(row.variation==6 and row.scale==[2.3,2.3,2.3] and is_equal_approx(row.angle,1.5*PI),"clicked tree retains original variation, scale and facing")
	check(is_equal_approx(p.z,state.rules.world.ground_height(Vector2(p.x,p.y))),"CreateDestructable grounds replacement independently of airborne unit")
	check(is_instance_valid(tree.label) and tree.label.position.y>tree.origin.y+2,"Hue remains at removed airborne unit Z plus 200")
	await capture("clicked-airborne")
	var previous_uid=int(row.uid)
	var lifted=state.rules.world.lift(previous_uid,3);lifted.time=sim.clock_now();state.rules.event.emit("tree",lifted);update()
	check(not bridge.replacement_present() and not is_instance_valid(tree.replacement),"ordinary replacement vanishes when native treePull removes its UID")
	check(game.field_scenery.destruction_state().native_dead.has(int(lifted.replacement.uid)),"treePull renders the new dead replacement for runtime-created tree")
	check(state.trees.any(func(t):return t.model==tree.chosen.model),"clicked tree can become a real floating tree unit")
	sim.advance(.2);update();await capture("lifted-replacement")
	# Whole-map membership must not depend on whether the selected field draws it.
	fresh(1,false,true);state.vote(0)
	check(not game.field_scenery.placement_slots.has(int(tree.chosen.editor_id)) and state.external_objects.size()==1,"out-of-crop special tree still exists in native pool")
	bridge.object.pos=Vector3(300,100,200);update()
	check(is_instance_valid(tree.model) and tree.model.position.is_equal_approx(Vector3(3,2,-1)),"outside-origin tree can enter the current visible field")
	bridge.select();bridge.object.pos=Vector3(0,0,200);sim.advance(sim.BALL_DT);update()
	check(bridge.object.removed and not is_instance_valid(tree.model) and bridge.replacement.is_empty(),"absorption removes special tree without restoring original scenery")
	sim.advance(.5);update()
	check(bridge.invalid_selection_callbacks==1 and bridge.replacement.is_empty(),"removed-index timer is explicitly recorded as uncalibrated, not silently resurrected")
	# Grounded runtime replacement participates in real cleanup and Death posing.
	fresh(3,true);state.vote(0);state.rules.next_tree=INF;state.rules.refresh_next()
	check(bridge.object.removed and bridge.replacement_present() and state.external_objects.is_empty(),"already clicked map tree initializes as destructable, not duplicate unit")
	var alive_uid=int(bridge.replacement.uid)
	sim.advance(51.5);update()
	var destruction=game.field_scenery.destruction_state()
	check(not bridge.replacement.alive and not is_instance_valid(tree.replacement),"global cleanup kills the runtime replacement and retires its living model")
	check(destruction.native_dead.has(alive_uid),"runtime replacement receives original Death animation in scene")
	var slot=destruction.native_dead.get(alive_uid,{})
	if not slot.is_empty():
		var entry=destruction.batches[slot.key].entries[slot.index]
		check(entry.transform.basis.get_scale().is_equal_approx(Vector3.ONE*2.3),"Death uses actual runtime replacement scale 2.3, not original placement scale")
	var count=destruction.native_seen.size();tree.frame(0);tree.frame(0)
	check(destruction.native_seen.size()==count,"repeated render frames cannot duplicate runtime Death")
	game.apocalypse_visuals.mask.hide();game.focus=tree.origin;game.zoom=.55;game.update_camera()
	# Render only the replacement's Death transition at an inspectable camera.
	await capture("snow-death-start",true)
	destruction.advance(.7);await capture("snow-death",true)
	game.enter_practice();tree.frame(0)
	check(tree.bridge==null and tree.removed and is_instance_valid(tree.replacement),"new match reloads pre-Apocalypse clicked state without rerolling map Easter egg")
	# Original object collision can push non-Locust zero-radius units; navigation
	# must not acquire an invented tree-radius obstacle as a side effect.
	fresh();state.vote(0)
	sim.players[0].pos=Vector2.ZERO;sim.players[0].z=0;sim.players[0].knock=Vector2(50,0);sim.players[0].vz=0
	sim.players[1].pos=Vector2(1600,900);bridge.object.pos=Vector3(70,0,0);bridge.object.apoc_velocity=Vector3.ZERO
	var walls=sim.arena.walls.size();var rng=sim.random.state
	sim.start_object(0);sim.step_object(0);update()
	check(bridge.object.apoc_velocity.x>40 and sim.players[0].knock.x<1,"real player object step exchanges momentum with enumerable BizTree")
	check(sim.arena.walls.size()==walls and sim.random.state==rng,"object contact adds neither navigation wall nor random gameplay draw")
	check(state.visuals.any(func(v):return v.model=="fx_player_bump" and v.pitch==0 and is_equal_approx(v.scale,.7)),"strong collision emits original directional WarStomp bump effect")
	check(game.apocalypse_visuals.transients.any(func(e):return e.model.data.actor.id=="fx_player_bump"),"contact effect reaches the live presentation layer")
	# The original ring reaches full opacity at 0.3s; inspect that authored
	# peak rather than requiring an arbitrary large footprint during its birth.
	sim.advance(.3);update();game.focus=Vector3(.6,0,0);game.zoom=.55;game.update_camera()
	var bump=game.apocalypse_visuals.transients.filter(func(e):return e.model.data.actor.id=="fx_player_bump")
	if not bump.is_empty():
		var with_bump=await capture("contact")
		bump[0].model.hide();game.apocalypse_visuals.effects.flush_particles()
		var without_bump=await capture("contact-hidden");var changed=0
		for y in range(with_bump.get_height()):
			for x in range(with_bump.get_width()):
				var a=with_bump.get_pixel(x,y);var b=without_bump.get_pixel(x,y)
				if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>.04:changed+=1
		observations.bump_pixels=changed
		check(changed>100,"original directional impact effect contributes visible field pixels")
	else:check(false,"original impact remains alive at its authored opacity peak")
	fresh(0,true,false,.25)
	check(is_instance_valid(tree.label) and is_equal_approx(tree.text_age,.25),"preparing Apocalypse preserves a still-visible preexisting Hue cue")
	sim.advance(1.25);update();await process_frame
	check(not is_instance_valid(tree.label),"inherited Hue expires at its original time rather than replaying")
	observations.invalid_native_index_callbacks=1
	game.free();await process_frame
	FileAccess.open("res://research/apocalypse-biz-tree-verification.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"observations":observations,"invalid_native_index_behavior_calibrated":false,"android_tested":false},"\t"))
	print("APOCALYPSE BIZ TREE ",passed," passed; ",failures.size()," failed")
	quit(0 if failures.is_empty() else 1)
