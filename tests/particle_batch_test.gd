extends SceneTree
const Model=preload("res://scripts/wc3_model.gd")
const Geometry=preload("res://scripts/particle_geometry.gd")
var passed=0
var failures=[]
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func _initialize():call_deferred("run")
func run():
	var world=Node3D.new();root.add_child(world)
	var camera=Camera3D.new();world.add_child(camera);camera.position=Vector3(-15,15,25);camera.look_at(Vector3(-20,1,0));camera.current=true
	var model=Model.new();world.add_child(model);model.load_actor("h00H",Color.WHITE);model.position=Vector3(-21.67,2,-2.24)
	model.particles.use_native_geometry=false
	var batch=Geometry.new();var node=MeshInstance3D.new();world.add_child(node)
	for i in range(30):model.advance(1.0/60)
	for frame in range(8):
		model.particles.batch_geometry=null;model.advance(1.0/30)
		var old=model.particles.emitters[0].mesh.mesh.surface_get_arrays(0)
		batch.begin();model.particles.batch_geometry=batch;model.particles.draw_emitter(model.particles.emitters[0]);batch.commit(node)
		var actual=node.mesh.surface_get_arrays(0)
		var equal=true
		check(old[Mesh.ARRAY_VERTEX].size()==batch.vertices.size()/4*6,"same particle triangles "+str(frame))
		for v in range(old[Mesh.ARRAY_VERTEX].size()):
			var index=batch.indices[v]
			equal=equal and old[Mesh.ARRAY_VERTEX][v].is_equal_approx(actual[Mesh.ARRAY_VERTEX][index]) and old[Mesh.ARRAY_TEX_UV][v].is_equal_approx(actual[Mesh.ARRAY_TEX_UV][index]) and old[Mesh.ARRAY_COLOR][v].is_equal_approx(actual[Mesh.ARRAY_COLOR][index])
		check(equal,"all positions, UV and color match unbatched source "+str(frame))
	batch.begin();batch.commit(node);check(not node.visible,"empty batch hides stale geometry")
	# Compare the independent emitter path against the original ImmediateMesh,
	# covering both lifetime segments, head/tail, atlas tiles and model-space FX.
	for id in ["fx_sprint","fx_super_sprint","fx_divine","fx_ogre_left","fx_ogre_right","fx_stun","fx_slow","fx_silence","fx_shadow_trail"]:
		var effect=Model.new();world.add_child(effect);effect.load_actor(id,Color.WHITE)
		if not is_instance_valid(effect.particles):effect.free();continue
		effect.position=Vector3(2,1,-3);effect.rotation=Vector3(.2,.7,.1);effect.scale=Vector3.ONE*.8
		effect.tint=Color(.7,.8,.9,.6);effect.fade_alpha=.7;effect.visibility_amount=.4
		for emitter in effect.particles.emitters:
			var original=emitter.source.duplicate(true)
			for flags in [0,524288,1048576,1572864]:
				for parts in [1,2,3]:
					emitter.source=original.duplicate(true);emitter.source.Flags=flags;emitter.source.FrameFlags=parts
					emitter.source.Rows=2;emitter.source.Columns=4
					for key in ["LifeSpanUVAnim","DecayUVAnim","TailUVAnim","TailDecayUVAnim"]:emitter.source[key]=[1,7,2]
					emitter.particles=[]
					for fraction in [.1,.55,.95]:emitter.particles.append({"pos":Vector3(fraction,1,2),"velocity":Vector3(2,3,-1),"age":float(emitter.source.LifeSpan)*fraction,"angle":fraction*PI,"scale":.8,"gravity":0.0})
					effect.particles.use_native_geometry=false;effect.particles.draw_emitter(emitter)
					var expected=emitter.mesh.mesh.surface_get_arrays(0);var material=emitter.mesh.material_override
					effect.particles.use_native_geometry=true;effect.particles.draw_emitter(emitter)
					var actual=emitter.mesh.mesh.surface_get_arrays(0)
					var indices=actual[Mesh.ARRAY_INDEX];var equal=expected[Mesh.ARRAY_VERTEX].size()==indices.size()
					for v in range(indices.size()):
						var ix=indices[v]
						equal=equal and expected[Mesh.ARRAY_VERTEX][v].distance_to(actual[Mesh.ARRAY_VERTEX][ix])<.0001 and expected[Mesh.ARRAY_TEX_UV][v].is_equal_approx(actual[Mesh.ARRAY_TEX_UV][ix]) and expected[Mesh.ARRAY_COLOR][v].is_equal_approx(actual[Mesh.ARRAY_COLOR][ix])
					check(equal,"native emitter matches legacy vertices UV colors: %s flags %d parts %d"%[id,flags,parts])
					check(emitter.mesh.material_override==material,"emitter keeps its own texture and blending "+id)
				emitter.particles.clear();effect.particles.draw_emitter(emitter)
				check(not emitter.mesh.visible,"drained emitter hides old mesh "+id)
			emitter.source=original
		# Geometry storage must belong to each emitter, never a shared native scratch
		# buffer that overwrites another emitter when the next one is drawn.
		for a in range(effect.particles.emitters.size()):
			for b in range(a):check(effect.particles.emitters[a].geometry!=effect.particles.emitters[b].geometry,"independent emitter storage "+id)
		effect.free()
	world.free()
	FileAccess.open("res://research/particle-batch-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("PARTICLE BATCH CHECKS ",passed," passed; ",failures.size()," failed")
	quit(1 if not failures.is_empty() else 0)
