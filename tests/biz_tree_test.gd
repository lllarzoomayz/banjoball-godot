extends SceneTree
var passed=0
var failures=[]
var game
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func capture(name: String):
	game.touch_controls.frame(0)
	await process_frame;await RenderingServer.frame_post_draw
	var image=root.get_texture().get_image();image.save_png("res://research/biz-tree-"+name+".png");return image
func changed_pixels(a: Image,b: Image) -> int:
	var changed=0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var c=a.get_pixel(x,y);var d=b.get_pixel(x,y)
			if absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b)>.05:changed+=1
	return changed
func choose_visible_tree():
	var tree=game.biz_tree
	if is_instance_valid(tree.bound_field):tree.bound_field.set_placement_visible(int(tree.chosen.editor_id),true)
	var candidates=tree.catalog.candidates.filter(func(c):return game.field_scenery.placement_slots.has(int(c.editor_id)))
	var best=candidates[0];var distance=INF
	for c in candidates:
		var p=game.field_scenery.placement_slots[int(c.editor_id)].placement.position
		var d=Vector2(p[0],p[1]).distance_to(Vector2(0,2000))
		if d<distance:distance=d;best=c
	tree.chosen=best;tree.removed=false;tree.pending=-1;tree.text_age=-1;tree.bind_field()
	var center=tree.model.global_transform*tree.bounds.get_center()
	game.camera.global_position=center+Vector3(0,10,15);game.camera.look_at(center)
	return game.camera.unproject_position(center)
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.enter_practice()
	var tree=game.biz_tree
	check(tree.catalog.candidates.size()==1124,"source eligible set includes every original playable-map tree, not only current field crop")
	var rng=game.sim.random.state
	for field in [0,3]:
		game.field_select.select(field);game.enter_practice();tree.frame(0)
		var screen=choose_visible_tree();var id=int(tree.chosen.editor_id)
		check(tree.model.data.actor.id==("h01K" if field==0 else "h01L"),"correct imported seasonal BizTree model "+str(field))
		check(is_equal_approx(tree.model.scale.x,2.3) and is_equal_approx(tree.model.rotation.y,1.5*PI),"original unit scale and 270-degree orientation "+str(field))
		var slot=game.field_scenery.placement_slots[id]
		check(game.field_scenery.batch_nodes[slot.key].all(func(n):return n.multimesh.get_instance_transform(slot.index).basis.determinant()==0),"only selected source placement hidden in static batch "+str(field))
		var before=await capture(str(field)+"-before")
		var pending_commands=game.sim.pending_commands.duplicate(true)
		game.aim="kick";check(not tree.try_select(screen),"aiming shot cannot select background tree");game.aim=""
		game.open_menu();check(not tree.try_select(screen),"paused menu cannot trigger tree");game.close_menu()
		check(not tree.try_select(Vector2(-10000,-10000)),"empty/off-screen click misses original model bounds")
		game.touch_controls.frame(0);game.touch_controls.touch_press(900,screen);game.touch_controls.touch_release(900,screen)
		check(is_equal_approx(tree.pending,.5) and game.sim.pending_commands==pending_commands,"native touch starts half-second timer without issuing move")
		tree.frame(.2);tree.try_select(screen);check(is_equal_approx(tree.pending,.3),"repeat taps do not postpone or duplicate pending replacement")
		game.open_menu();tree.frame(1);check(is_equal_approx(tree.pending,.3),"pause freezes scheduled disappearance");game.close_menu()
		tree.frame(.29);check(not tree.removed and is_instance_valid(tree.model),"special tree remains before original half-second boundary")
		tree.frame(.02);await process_frame
		check(tree.removed and not is_instance_valid(tree.model) and is_instance_valid(tree.replacement),"original special unit removed and ordinary tree restored")
		check(tree.chosen.replacement==("LTlt_6" if field==0 else "WTst_6") and tree.replacement.get_child_count()>0,"restoration uses source variation six and seasonal texture")
		check(tree.label.text=="Hue" and is_equal_approx(tree.text_age,.01),"Hue lifetime accounts for frame crossing the .5s event")
		check(tree.label.position.is_equal_approx(tree.origin+Vector3(-.4,2.005,0)),"original x-40 and terrain-relative +200 text origin")
		var after=await capture(str(field)+"-hue")
		check(changed_pixels(before,after)>100,"rendered seasonal tree changes and Hue appears "+str(field))
		check(not tree.try_select(screen),"ordinary replacement cannot trigger another Hue")
		tree.frame(1.24);check(is_equal_approx(tree.label.modulate.a,.5),"final half-second fades text")
		tree.frame(.25);await process_frame;check(not is_instance_valid(tree.label),"text cleans up at original 1.5-second lifespan")
		game.enter_practice();tree.frame(0)
		check(tree.removed and int(tree.chosen.editor_id)==id and is_instance_valid(tree.replacement),"match restart does not reroll the map-wide easter egg")
		# Recreate this fixture to exercise desktop left-click with the same ray.
		screen=choose_visible_tree();var click=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=screen
		game.mobile_enabled=false;game._unhandled_input(click);game.mobile_enabled=true
		check(is_equal_approx(tree.pending,.5),"PC left click selects the original model")
		game.field_select.select(1);game.enter_practice();tree.frame(.5)
		check(tree.removed and not is_instance_valid(tree.model),"pending timer completes while another field is displayed")
		game.field_select.select(field);game.enter_practice();tree.frame(0)
		check(is_instance_valid(tree.replacement) and tree.removed,"returning to original field preserves restored tree")
	# A seed is injected only in this test to independently check the three draws.
	var other=preload("res://scripts/biz_tree.gd").new();game.add_child(other)
	var expected_rng=RandomNumberGenerator.new();expected_rng.seed=7123;var last=0
	for i in range(3):last=expected_rng.randi_range(0,1123)
	var before=game.sim.random.state;other.setup(game,7123)
	check(other.chosen.editor_id==tree.catalog.candidates[last].editor_id and game.sim.random.state==before,"three independent cosmetic draws leave gameplay RNG untouched")
	other.free();game.free();await process_frame
	FileAccess.open("res://research/biz-tree-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("BIZ TREE ",passed," passed; ",failures.size()," failed");quit(1 if not failures.is_empty() else 0)
