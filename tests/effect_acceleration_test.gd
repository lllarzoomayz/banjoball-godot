extends SceneTree
const Model=preload("res://scripts/wc3_model.gd")
var passed=0
var failures=[]
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func _initialize():call_deferred("run")
func run():
	var native=preload("res://scripts/acceleration.gd").create()
	check(native!=null and native.has_method("apply_billboards") and native.has_method("spawn_particles") and native.has_method("draw_ribbons"),"new native effect methods are loaded")
	if not failures.is_empty():finish();return
	var world=Node3D.new();root.add_child(world)
	var camera=Camera3D.new();world.add_child(camera);camera.position=Vector3(-3,12,15);camera.look_at(Vector3.ZERO);camera.current=true
	for filename in DirAccess.get_files_at("res://assets/models"):
		if not filename.ends_with(".json"):continue
		var data=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/"+filename))
		if data.get("billboards",[]).is_empty():continue
		var model=Model.new();world.add_child(model);model.load_actor(filename.trim_suffix(".json"),Color.WHITE)
		model.position=Vector3(2,1,-4);model.rotation=Vector3(.2,.7,-.15);model.scale=Vector3(1.1,.7,1.3)
		for clip in data.clips:
			model.play(clip.name,true)
			for fraction in [.0,.23,.87]:
				model.use_native_billboards=false;model.last_visual=[];model.animation_time=float(clip.duration)*fraction;model.advance(0)
				var expected=[]
				for b in range(model.skeleton.get_bone_count()):expected.append(model.skeleton.get_bone_pose(b))
				model.use_native_billboards=true;model.last_visual=[];model.animation_time=float(clip.duration)*fraction;model.advance(0)
				var equal=true
				for b in range(expected.size()):
					var actual=model.skeleton.get_bone_pose(b)
					equal=equal and actual.origin.distance_to(expected[b].origin)<.0001
					for column in range(3):equal=equal and actual.basis[column].distance_to(expected[b].basis[column])<.0001
				check(equal,"billboard bones match reference %s %s %.2f"%[filename,clip.name,fraction])
		model.free()
	for id in ["fx_sprint","fx_super_sprint","fx_divine","fx_ogre_left","fx_shadow_trail"]:
		var model=Model.new();world.add_child(model);model.load_actor(id,Color.WHITE)
		model.position=Vector3(3,2,-1);model.rotation=Vector3(.1,.6,-.2);model.scale=Vector3.ONE*1.3
		var particles=model.particles
		for emitter in particles.emitters:
			var original=emitter.source.duplicate(true)
			for flags in [0,131072,524288,655360]:
				emitter.source=original.duplicate(true);emitter.source.Flags=flags
				var values=[1.0,200.0,.3,45.0,90.0,20.0,10.0,10.0,0.0,1.0]
				emitter.particles=[];particles.rng.seed=772;particles.use_native_emission=false
				particles.emit_particles(emitter,values,64)
				var expected=emitter.particles.duplicate(true);var state=particles.rng.state
				emitter.particles=[];particles.rng.seed=772;particles.use_native_emission=true
				particles.emit_particles(emitter,values,64)
				check(state==particles.rng.state,"emission preserves RNG sequence %s flags %d"%[id,flags])
				var equal=expected.size()==emitter.particles.size()
				for i in range(expected.size()):
					var a=expected[i];var b=emitter.particles[i]
					equal=equal and a.pos.distance_to(b.pos)<.0001 and a.velocity.distance_to(b.velocity)<.0001 and is_equal_approx(a.gravity,b.gravity) and is_equal_approx(a.angle,b.angle) and is_equal_approx(a.scale,b.scale) and a.age==b.age
				check(equal,"emission positions, velocities, lifetime and scale match %s flags %d"%[id,flags])
			emitter.source=original
		model.free()
	world.free();finish()
func finish():
	FileAccess.open("res://research/effect-acceleration-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("EFFECT ACCELERATION CHECKS ",passed," passed; ",failures.size()," failed")
	quit(1 if not failures.is_empty() else 0)
