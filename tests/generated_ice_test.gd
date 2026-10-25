extends SceneTree
var game
var passed=0
var failures=[]
var observations={}
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func capture(name):
	game.update_visuals(0);game.touch_controls.frame(0)
	# Inspect ice independently of the cinematic's opaque cleanup mask.
	game.apocalypse_visuals.mask.hide()
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image=root.get_texture().get_image();image.save_png("res://research/generated-ice-"+name+".png");return image
func difference(a,b):
	var changed=0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var c=a.get_pixel(x,y);var d=b.get_pixel(x,y)
			if absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b)>.04:changed+=1
	return changed
func run():
	root.size=Vector2i(960,540)
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.set_process(false)
	var ice=game.generated_ice_visuals
	for field in [0,1,2,3]:
		game.field_select.select(field);game.touch_controls.start_practice();game.update_visuals(0)
		check(ice.models.size()==(5 if field>=2 else 0),"five generated objects only in frozen field family "+str(field))
		if field<2:continue
		var rows=game.sim.generated_ice;var centres=load("res://scripts/apocalypse_world.gd").data().generated_ice_centers
		var scenery=game.field_scenery
		check(scenery.scene_cache[scenery.field_id].placements.filter(func(p):return p.key=="B000_0" and p.editor_id==-1).size()==544,"all original frozen water tiles restored without duplicate placements")
		check(scenery.batch_nodes.B000_0.size()==2 and scenery.material_animation.bindings.size()==1,"full water remains two mesh batches and one animated material clock")
		var backdrop=JSON.parse_string(FileAccess.get_file_as_string("res://assets/scenery/"+scenery.field_id+"_seabed.json"))
		var mesh=scenery.get_node("OriginalSeabedBackdrop").mesh;var skip=backdrop.skip_bounds
		var inside=int((skip[2]-skip[0])/128)*int((skip[3]-skip[1])/128)
		check(mesh.surface_get_array_index_len(0)==((int(backdrop.grid[0])-1)*(int(backdrop.grid[1])-1)-inside)*6,"seabed ring excludes every existing central terrain cell")
		var terrain=load("res://scripts/apocalypse_world.gd").data().terrain;var centre=game.sim.arena.data.center;var accurate=true
		for y in range(int(backdrop.grid[1])):
			for x in range(int(backdrop.grid[0])):
				var ix=roundi((backdrop.bounds[0]+x*128+centre[0]-terrain.origin[0])/128)
				var iy=roundi((backdrop.bounds[1]+y*128+centre[1]-terrain.origin[1])/128)
				if absf(backdrop.heights[y*int(backdrop.grid[0])+x]+game.sim.arena.world_height_offset-terrain.heights[iy*int(terrain.size[0])+ix])>.001:accurate=false
		check(accurate,"every backdrop vertex preserves original W3E absolute height")
		for i in range(5):
			var row=rows[i];var p=row.position;var center=centres[i];var model=ice.models[i]
			check(absf(p[0]-center[0])<=400 and absf(p[1]-center[1])<=400 and p[2]==900,"source random position and absolute Z "+str(i))
			check(row.id in ["B001","B002","B003","B004","B005"] and row.scale[0]>=.9 and row.scale[0]<=1.2,"source model/scale choice "+str(i))
			check(is_equal_approx(model.position.y,(900-game.sim.arena.world_height_offset)/100) and model.data.actor.id==ice.catalog[row.id].model,"render uses actual generated model and absolute height "+str(i))
		var identities=ice.models.duplicate();var placements=rows.duplicate(true)
		game.build_pitch();game.update_visuals(0)
		check(game.sim.generated_ice==placements and ice.models==identities,"rebuilding pitch does not reroll or recreate generated ice")
		game.sim.advance(40);var rng=game.sim.random.state;var state=game.sim.prepare_apocalypse();ice.frame(0)
		check(game.sim.random.state==rng,"preparing Apocalypse does not draw another set of ice")
		check(ice.native_rows.size()==5 and ice.native_rows.values().all(func(row):return row.position==rows[row.generated_index].position),"world pool and visible scene share the same original draws")
		check(ice.models==identities,"preparing Apocalypse keeps existing models without popping")
		var id=1 if field==2 else 3;var p=ice.models[id].position
		game.focus=Vector3(p.x,0,p.z);game.zoom=.3;game.update_camera()
		var image=await capture("field-"+str(field));ice.models[id].hide();var hidden=await capture("field-"+str(field)+"-hidden");ice.models[id].show()
		var pixels=difference(image,hidden);observations[str(field)+"_pixels"]=pixels
		check(pixels>30,"original ice visible at its generated location "+str(field)+": "+str(pixels))
		var state_rng=game.sim.random.state;game.paused=true;var time=ice.models[id].animation_time
		ice.frame(.5);check(game.sim.random.state==state_rng and ice.models[id].animation_time==time,"paused draw does not move ice or consume gameplay RNG")
		game.paused=false;check(state.vote(0),"source gate allows actual cleanup sequence")
		game.sim.advance(51.5);game.update_visuals(0)
		check(ice.killed.size()==5 and ice.native_rows.values().all(func(row):return not row.alive),"real Apocalypse cleanup kills generated native destructables")
		check(ice.models.all(func(model):return model.visible and model.active_clip=="Stand"),"source models without Death retain art rather than fabricated shatter")
		check(game.experience.model_audio.last_event.get("code")=="CrateDeath","native configured destructable sound reaches mixer near ice")
		var count=game.experience.model_audio.played_count;ice.frame(.1);ice.frame(.1)
		check(game.experience.model_audio.played_count==count,"dead generated ice does not replay its death sound every frame")
		await capture("killed-"+str(field))
		game.enter_practice();game.update_visuals(0)
		check(ice.killed.is_empty() and ice.native_rows.is_empty() and ice.models.size()==5,"new match replaces old lifecycle and restores original ice")
	game.field_select.select(0);game.enter_practice();game.update_visuals(0)
	check(ice.models.is_empty() and ice.get_child_count()==0,"switching to grass removes generated frozen objects")
	check(game.perf.mode==0,"new scenery preserves clean HUD preference")
	game.free();await process_frame
	FileAccess.open("res://research/generated-ice-verification.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"observations":observations,"missing_death_native_fallback_calibrated":false},"\t"))
	print("GENERATED ICE CHECKS ",passed," passed; ",failures.size()," failed; ",observations)
	quit(0 if failures.is_empty() else 1)
