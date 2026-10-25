extends SceneTree
const Model=preload("res://scripts/wc3_model.gd")
const Visuals=preload("res://scripts/spell_visuals.gd")
const Sim=preload("res://scripts/match_sim.gd")
var checks=[]
var failed=false
func check(value: bool,name: String):
	checks.append({"test":name,"passed":value});failed=failed or not value
	print(("PASS " if value else "FAIL ")+name)
func _initialize():call_deferred("run")
func run():
	var world=Node3D.new();root.add_child(world)
	var camera=Camera3D.new();world.add_child(camera)
	camera.position=Vector3(0,12,15);camera.look_at(Vector3.ZERO);camera.current=true
	var effects=JSON.parse_string(FileAccess.get_file_as_string("res://research/spell-assets.json"))
	for entry in effects:
		var model=Model.new();world.add_child(model);model.load_actor(entry.id,Color.WHITE)
		model.one_shot=true
		var peak=0
		# Several missiles emit only in Death; a short Birth may legitimately
		# emit no particles at all. Exercise each original animation sequence.
		for clip in model.data.clips:
			model.play(clip.name,true)
			for frame in range(ceili(float(clip.duration)*60)+2):
				model.advance(1.0/60)
				if is_instance_valid(model.particles):peak=maxi(peak,model.particles.particle_count())
		var expects_particles=not model.data.emitters.is_empty()
		check(not model.clip.is_empty() and (not expects_particles or peak>0),"original effect animates "+entry.id)
		if expects_particles:
			for frame in range(600):model.advance(1.0/30)
			check(model.particles.particle_count()==0,"one-shot particles drain "+entry.id)
		model.free()
	for id in Sim.Characters.IDS:
		var model=Model.new();world.add_child(model);model.load_actor(id,Color("55aaff"))
		for clip in model.data.clips:
			model.play(clip.name,true)
			for frame in range(3):model.advance(0.03)
		check(model.mesh_nodes.size()>0 and model.skeleton.get_bone_count()>0,"roster model and clips "+id)
		model.free()
	var scene=Visuals.new();world.add_child(scene)
	var billboard=Model.new();world.add_child(billboard);billboard.load_actor("fx_black_hole",Color.WHITE)
	billboard.advance(0.2)
	var facing=billboard.skeleton.get_bone_pose(int(billboard.data.billboards[0].bone_index)).basis.x.normalized()
	check(facing.dot(camera.global_basis.z)>0.999,"original black hole billboard faces camera")
	camera.position=Vector3(12,10,4);camera.look_at(Vector3.ZERO);billboard.advance(0)
	facing=billboard.skeleton.get_bone_pose(int(billboard.data.billboards[0].bone_index)).basis.x.normalized()
	check(facing.dot(camera.global_basis.z)>0.999,"paused billboard updates when camera changes")
	billboard.free()
	var s=Sim.new();s.selected_character="h00F";s.reset();s.players[1].pos=Vector2(1500,1000)
	s.take(0);s.step_ball();s.Characters.use(s,0,Vector2(1200,0))
	var rng_state=s.random.state
	scene.sync(s,0.1)
	check(scene.persistent.has("charge:0"),"real charged shot creates original overhead effect")
	var model=scene.persistent["charge:0"]
	var count=model.particles.particle_count();var time=model.animation_time
	scene.sync(s,0)
	check(model.particles.particle_count()==count and model.animation_time==time,"menu pause freezes particles and animation")
	check(s.random.state==rng_state,"render particles do not consume gameplay RNG")
	s.stop(0);scene.sync(s,0.03)
	check(not scene.persistent.has("charge:0"),"stop cancels attached charge effect")
	s.selected_character="h00P";s.reset();s.players[1].pos=Vector2(1500,1000)
	s.Characters.use(s,0,Vector2.ZERO);s.advance(0.4);scene.sync(s,0.02)
	check(scene.bursts.any(func(e):return e.model.data.actor.id=="fx_slam"),"real stomp emits original thunderclap")
	var bursts=scene.bursts.size();scene.sync(s,0)
	check(scene.bursts.size()==bursts,"same simulation event is not replayed every render frame")
	s.selected_character="h003";s.reset();s.players[1].pos=Vector2(1500,1000)
	s.Characters.use(s,0,Vector2(-200,200));scene.sync(s,0.05)
	check(scene.persistent.size()==1 and scene.lightning.nodes.has("BKHL"),"black hole uses native mesh and lightning")
	s.selected_character="h00Y";s.reset();s.Characters.use(s,0,Vector2.ZERO);scene.sync(s,0.05)
	check(scene.lightning.nodes.has("DRAL"),"pull uses original drain texture")
	s.selected_character="h01R";s.reset();s.players[1].pos=Vector2(1500,1000)
	s.Characters.use(s,0,Vector2(1000,0));scene.sync(s,0.05)
	check(scene.lightning.nodes.has("ROPE"),"hook uses original rope texture")
	s.selected_character="h028";s.reset();s.take(0);s.step_ball();s.Characters.use(s,0,Vector2(1000,0));scene.sync(s,0.01)
	check(scene.bursts.any(func(e):return e.model.data.actor.id=="fx_angelic_kick"),"angel kick emits original HolyBolt effect")
	s.reset();scene.sync(s,0)
	check(scene.bursts.is_empty() and scene.persistent.is_empty(),"round reset removes previous scene effects")
	for i in range(180):s.emit_visual("fx_jump",Vector3.ZERO)
	check(s.native_visuals.size()==128,"headless event history stays bounded")
	var f=FileAccess.open("res://research/spell-visuals-tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"passed":not failed},"\t"));f.close()
	world.free();quit(1 if failed else 0)
