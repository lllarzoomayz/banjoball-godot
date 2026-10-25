extends SceneTree
const Visuals=preload("res://scripts/spell_visuals.gd")
var passed=0
var failures=[]
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func _initialize():call_deferred("run")
func run():
	var world=Node3D.new();root.add_child(world)
	var camera=Camera3D.new();world.add_child(camera);camera.position=Vector3(0,12,15);camera.look_at(Vector3.ZERO);camera.current=true
	var scene=Visuals.new();world.add_child(scene)
	var models=[]
	for i in range(6):
		var model=scene.create("fx_sprint",Vector3(i*70,30,20),.75+i*.1,true)
		model.rotation.y=i*.4;model.tint=Color(1,.8,.7);model.fade_alpha=.5+i*.05
		for frame in range(40):model.advance(1.0/60)
		models.append(model)
	var expected={};var particle_count=0
	for model in models:
		for index in range(model.particles.emitters.size()):
			var emitter=model.particles.emitters[index];particle_count+=emitter.particles.size()
			if emitter.particles.is_empty():continue
			var key=str(model.data.actor.id)+":"+str(index)+":"+model.team_color.to_html()
			model.particles.use_native_geometry=false
			model.particles.draw_emitter(emitter)
			var arrays=emitter.mesh.mesh.surface_get_arrays(0)
			if not expected.has(key):expected[key]=[PackedVector3Array(),PackedVector2Array(),PackedColorArray()]
			expected[key][0].append_array(arrays[Mesh.ARRAY_VERTEX]);expected[key][1].append_array(arrays[Mesh.ARRAY_TEX_UV]);expected[key][2].append_array(arrays[Mesh.ARRAY_COLOR])
	check(particle_count>0,"fixture contains live original particles")
	for repeat in range(2):
		scene.flush_particles()
		var drawn=0
		for key in expected:
			var batch=scene.particle_batches[key];var actual=batch.node.mesh.surface_get_arrays(0)
			var indices=actual[Mesh.ARRAY_INDEX];var same=indices.size()==expected[key][0].size()
			for v in range(indices.size()):
				var i=indices[v]
				same=same and actual[Mesh.ARRAY_VERTEX][i].distance_to(expected[key][0][v])<.0001 and actual[Mesh.ARRAY_TEX_UV][i].is_equal_approx(expected[key][1][v]) and actual[Mesh.ARRAY_COLOR][i].is_equal_approx(expected[key][2][v])
			check(same,"group retains every independently rendered position, UV and color "+key+" pass "+str(repeat))
			if batch.node.visible:drawn+=1
		check(drawn<=3,"six sprint effects share at most three particle draws")
	for model in models:
		for emitter in model.particles.emitters:check(not emitter.mesh.visible,"individual particle draw suppressed after batching")
		model.hide()
	scene.flush_particles()
	check(scene.particle_batches.values().all(func(batch):return not batch.node.visible),"hiding all actors removes retained batch geometry")
	models[0].show();models[0].queue_free();scene.flush_particles()
	check(scene.particle_batches.values().all(func(batch):return not batch.node.visible),"queued cleanup cannot leave a visible ghost batch")
	scene.clear();check(scene.particle_batches.is_empty(),"scene reset clears shared particle materials and buffers")
	world.free()
	FileAccess.open("res://research/effect-batch-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("EFFECT BATCH CHECKS ",passed," passed; ",failures.size()," failed")
	quit(1 if not failures.is_empty() else 0)
