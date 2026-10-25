extends SceneTree
const Model=preload("res://scripts/wc3_model.gd")
const UV=preload("res://scripts/wc3_uv.gd")
var passed=0
var failures=[]
var max_pose_error=0.0
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func run():
	var reference=JSON.parse_string(FileAccess.get_file_as_string("res://research/dynamic-scenery-reference.json"))
	for sample in reference.samples:
		var model=Model.new();root.add_child(model);model.load_actor(sample.id,Color.WHITE)
		model.particles.emitting=false;model.particles.defer_geometry=true;model.play("Stand",true);model.advance(sample.time)
		for i in range(sample.nodes.size()):
			var m=sample.nodes[i];var native=Transform3D(Basis(Vector3(m[0],m[1],m[2]),Vector3(m[4],m[5],m[6]),Vector3(m[8],m[9],m[10])),Vector3(m[12],m[13],m[14]))
			var expected=Transform3D(Model.CONVERSION*native.basis*Model.CONVERSION.inverse(),Model.CONVERSION*native.origin/100)
			var actual=model.skeleton.get_bone_pose(i)
			var error=maxf(actual.origin.distance_to(expected.origin),maxf(actual.basis.x.distance_to(expected.basis.x),maxf(actual.basis.y.distance_to(expected.basis.y),actual.basis.z.distance_to(expected.basis.z))))
			max_pose_error=maxf(max_pose_error,error)
			check(error<.0002,"original local/global bone pose "+sample.id+" at "+str(sample.time)+" bone "+str(i))
		for i in range(sample.uv.size()):
			var row=sample.uv[i];var r=row.rotation;var s=row.scaling;var t=row.translation
			var matrix=Basis(Quaternion(r[0],r[1],r[2],r[3]))*Basis.from_scale(Vector3(s[0],s[1],s[2]))
			var expected=Basis(Vector3(matrix.x.x,matrix.x.y,0),Vector3(matrix.y.x,matrix.y.y,0),Vector3(t[0],t[1],1))
			var actual=UV.transform(model.data.texture_animations[i],model.clip.interval[0]+model.animation_time*1000,model.clip.interval,model.visual_time,model.data.global_sequences)
			check((actual.x-expected.x).length()+(actual.y-expected.y).length()+(actual.z-expected.z).length()<.0002,"original waterfall UV clock "+str(sample.time)+" track "+str(i))
		model.free()
	var game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.enter_practice()
	var scenery=game.field_scenery.dynamic
	check(scenery.models.size()==18,"Sunny Hills includes original dynamic waterfalls, flags, birds and seaweed without duplicates")
	check(not game.field_scenery.batch_nodes.has("D000_0") and not game.field_scenery.batch_nodes.has("LOo1_1"),"old static meshes excluded from batches")
	var banner=scenery.models.filter(func(m):return m.data.actor.id=="scenery_LOo1_1")[0]
	for i in range(90):scenery.advance(1.0/30)
	check(banner.particles.particle_count()==0,"banner Stand does not invent Death-only smoke")
	check(scenery.particle_count()>70,"both waterfalls emit source foam and shoreline particles")
	banner.play("Death",true)
	for i in range(9):scenery.advance(1.0/30)
	check(banner.particles.particle_count()>0,"explicit original banner Death emits its authored smoke")
	game.field_select.select(1);game.enter_practice();scenery=game.field_scenery.dynamic
	check(scenery.models.size()==126,"all 126 meshless authored Steamcloud placements restored")
	var rng=game.sim.random.state
	for i in range(90):scenery.advance(1.0/30)
	var count=scenery.particle_count()
	check(count>=17500 and count<=18700,"original 50/sec and 2.9s lifetime retained across 126 sources: "+str(count))
	check(scenery.batches.size()==1,"all additive steam shares one geometry batch")
	check(scenery.models[0].particles.rng.state!=scenery.models[1].particles.rng.state,"different placements have independent cosmetic randomness")
	check(game.sim.random.state==rng,"scenery rendering never consumes gameplay randomness")
	var clock=scenery.models[0].visual_time;var emitter=scenery.models[0].particles.emitters[0];var first=emitter.get("packed",emitter.particles).duplicate()
	game.paused=true;game.update_visuals(1)
	check(scenery.models[0].visual_time==clock and emitter.get("packed",emitter.particles)==first,"menu pause freezes both clocks and particles")
	game.paused=false
	var old=scenery;game.field_select.select(2);game.enter_practice();await process_frame
	check(not is_instance_valid(old) and game.field_scenery.dynamic.models.is_empty(),"changing to a field without these effects frees every old emitter")
	game.free();await process_frame
	FileAccess.open("res://research/dynamic-scenery-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"source_samples":reference.samples.size(),"max_pose_error":max_pose_error,"steam_particles":count},"\t"))
	print("DYNAMIC SCENERY ",passed," passed; ",failures.size()," failed; pose error ",max_pose_error);quit(1 if not failures.is_empty() else 0)
