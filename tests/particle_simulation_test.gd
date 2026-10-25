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
	check(native!=null and native.has_method("advance_emitters"),"native particle simulation actually loaded")
	if not failures.is_empty():finish();return
	var world=Node3D.new();root.add_child(world)
	var camera=Camera3D.new();world.add_child(camera);camera.position=Vector3(0,12,15);camera.look_at(Vector3.ZERO);camera.current=true
	for id in ["h00H","h000","h003","h02A","h02E","fx_sprint","fx_stealth_sprint","fx_super_sprint","fx_divine","fx_ogre_left","fx_shadow_trail","fx_earth_pillar"]:
		var reference=Model.new();var actual=Model.new();world.add_child(reference);world.add_child(actual)
		reference.load_actor(id,Color.WHITE);actual.load_actor(id,Color.WHITE)
		reference.particles.use_native_simulation=false;reference.particles.use_native_emission=false
		for model in [reference,actual]:
			model.particles.defer_geometry=true;model.scale=Vector3.ONE*.85
		for clip in actual.data.clips:
			for model in [reference,actual]:
				model.play(clip.name,true);model.particles.rng.seed=664
				model.one_shot=false;model.particles.emitting=true;model.show()
				for emitter in model.particles.emitters:emitter.particles=[];emitter.credit=0.0;emitter.key=""
			for frame in range(90):
				var delta=[1.0/60,.037,0.0,.1][frame%4]
				for model in [reference,actual]:
					model.position=Vector3(frame*.02,1,2);model.rotation.y=frame*.01
					model.visible=frame<30 or frame>=35
					model.particles.emitting=frame<50 or frame>=55
					model.one_shot=frame>=70
					model.advance(delta)
				var same=reference.particles.rng.state==actual.particles.rng.state
				for index in range(actual.particles.emitters.size()):
					var a=reference.particles.emitters[index];var b=actual.particles.emitters[index]
					same=same and a.particles.size()==b.particles.size() and is_equal_approx(a.credit,b.credit) and a.key==b.key
					if a.particles.size()!=b.particles.size():continue
					for p in range(a.particles.size()):
						var left=a.particles[p];var right=b.particles[p]
						same=same and left.pos.distance_to(right.pos)<.0001 and left.velocity.distance_to(right.velocity)<.0001 and is_equal_approx(left.age,right.age) and is_equal_approx(left.gravity,right.gravity)
				check(same,"particle trajectory/count/RNG/credit/Squirt match %s %s frame %d"%[id,clip.name,frame])
			reference.show();actual.show()
		reference.free();actual.free()
	world.free();finish()
func finish():
	FileAccess.open("res://research/particle-simulation-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("PARTICLE SIMULATION CHECKS ",passed," passed; ",failures.size()," failed")
	quit(1 if not failures.is_empty() else 0)
