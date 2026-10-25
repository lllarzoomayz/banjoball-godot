extends SceneTree
const Model=preload("res://scripts/wc3_model.gd")
const Geometry=preload("res://scripts/particle_geometry.gd")
var passed=0
var failures=[]
var compared=0
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func run():
	var world=Node3D.new();root.add_child(world)
	var camera=Camera3D.new();world.add_child(camera);camera.position=Vector3(3,8,14);camera.look_at(Vector3.ZERO)
	for id in ["scenery_D000_0","scenery_D002_0","scenery_LOo1_1"]:
		for flags in [0,524288,1048576,1572864]:
			var dense=Model.new();var reference=Model.new();world.add_child(dense);world.add_child(reference)
			dense.load_actor(id,Color.WHITE);reference.load_actor(id,Color.WHITE)
			check(dense.particles.accelerator!=null and dense.particles.accelerator.has_method("draw_packed_particles"),"dense native library loaded")
			for model in [dense,reference]:
				model.transform=Transform3D(Basis.from_euler(Vector3(.1,.7,.2)).scaled_local(Vector3(1.5,.8,1.5)),Vector3(-13,2,7))
				model.tint=Color(.7,.8,.9,.6);model.fade_alpha=.7;model.visibility_amount=.8
				model.particles.defer_geometry=true;model.particles.rng.seed=3591
				if id=="scenery_LOo1_1":model.play("Death",true)
				for emitter in model.particles.emitters:
					emitter.source=emitter.source.duplicate(true);emitter.source.Flags=flags;emitter.source.FrameFlags=3
			for emitter in dense.particles.emitters:emitter.packed=PackedFloat64Array()
			for frame in range(240):
				var delta=[1.0/60,1.0/30,0,.004,.12][frame%5]
				if frame==160:dense.hide();reference.hide()
				if frame==163:dense.show();reference.show()
				dense.advance(delta);reference.advance(delta)
				var equal=dense.particles.particle_count()==reference.particles.particle_count() and dense.particles.rng.state==reference.particles.rng.state
				for e in range(dense.particles.emitters.size()):
					var packed=dense.particles.emitters[e].packed;var particles=reference.particles.emitters[e].particles
					equal=equal and packed.size()==particles.size()*10
					if packed.size()!=particles.size()*10:continue
					for i in range(particles.size()):
						var p=particles[i];var j=i*10;compared+=1
						equal=equal and Vector3(packed[j],packed[j+1],packed[j+2])==p.pos and Vector3(packed[j+3],packed[j+4],packed[j+5])==p.velocity
						equal=equal and packed[j+6]==p.age and packed[j+7]==p.angle and packed[j+8]==p.scale and packed[j+9]==p.gravity
				check(equal,"exact source state, lifetime and RNG %s flags %d frame %d"%[id,flags,frame])
				if frame%20==0:
					for e in range(dense.particles.emitters.size()):
						var a=Geometry.new();var b=Geometry.new();a.begin();b.begin()
						dense.particles.draw_batched(dense.particles.emitters[e],camera,a);reference.particles.draw_batched(reference.particles.emitters[e],camera,b)
						var actual=a.accelerator.geometry_arrays();var expected=b.accelerator.geometry_arrays()
						check(actual==expected,"dense head/tail geometry UV color identical %s flags %d frame %d emitter %d"%[id,flags,frame,e])
			dense.free();reference.free()
	world.free();await process_frame
	FileAccess.open("res://research/scenery-particle-storage-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"compared_particles":compared},"\t"))
	print("SCENERY STORAGE ",passed," passed; ",failures.size()," failed; ",compared," particle states compared");quit(1 if not failures.is_empty() else 0)
