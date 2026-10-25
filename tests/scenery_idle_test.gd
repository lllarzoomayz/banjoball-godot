extends SceneTree
const Model=preload("res://scripts/wc3_model.gd")
var passed=0
var failures=[]
var max_pose_error=0.0
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func run():
	var reference=JSON.parse_string(FileAccess.get_file_as_string("res://research/scenery-idle-reference.json"))
	var world=Node3D.new();root.add_child(world);var camera=Camera3D.new();world.add_child(camera);camera.current=true
	for sample in reference.samples:
		var model=Model.new();world.add_child(model);model.load_actor(sample.id,Color.WHITE)
		var q=sample.camera;var facing=Basis(Quaternion(q[0],q[1],q[2],q[3]))
		camera.basis=Basis(Model.CONVERSION*facing.y,Model.CONVERSION*facing.z,Model.CONVERSION*facing.x)
		model.advance(sample.time)
		var equal=true;var bounds_ok=true
		for i in range(sample.nodes.size()):
			var m=sample.nodes[i];var native=Transform3D(Basis(Vector3(m[0],m[1],m[2]),Vector3(m[4],m[5],m[6]),Vector3(m[8],m[9],m[10])),Vector3(m[12],m[13],m[14]))
			var expected=Transform3D(Model.CONVERSION*native.basis*Model.CONVERSION.inverse(),Model.CONVERSION*native.origin/100)
			var actual=model.skeleton.get_bone_pose(i)
			var error=maxf(actual.origin.distance_to(expected.origin),maxf(actual.basis.x.distance_to(expected.basis.x),maxf(actual.basis.y.distance_to(expected.basis.y),actual.basis.z.distance_to(expected.basis.z))))
			max_pose_error=maxf(max_pose_error,error);equal=equal and error<.002
		check(equal,"original pose including locked/full camera-facing nodes "+sample.id+" time "+str(sample.time)+" camera "+str(sample.camera))
		for g in range(model.data.meshes.size()):
			var geo=model.data.meshes[g]
			for v in range(geo.vertices.size()/3):
				var original=Model.CONVERSION*Vector3(geo.vertices[v*3],geo.vertices[v*3+1],geo.vertices[v*3+2])/100
				var point=Vector3.ZERO;var group=geo.groups[int(geo.vertex_group[v])]
				for bone in group:point+=model.skeleton.get_bone_pose(int(bone))*original
				point/=group.size();bounds_ok=bounds_ok and model.mesh_nodes[g].custom_aabb.has_point(point)
		check(bounds_ok,"animated vertices stay inside renderer bounds "+sample.id)
		model.free()
	world.free()
	var game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.enter_practice()
	var scene=game.field_scenery
	check(scene.dynamic.models.size()==18,"all eighteen Sunny Hills dynamic placements present")
	for key in ["AObd_0","ZWsw_1","ZWsw_2","ZWsw_3","ZWsw_4","LOh1_0","B00C_0","B00D_0"]:
		check(not scene.batch_nodes.has(key) and scene.dynamic.models.any(func(m):return m.get_meta("scenery_key")==key),"dynamic model replaces static copy "+key)
	for f in [1,2,3]:
		game.field_select.select(f);game.enter_practice();scene=game.field_scenery
		var animation=scene.material_animation;var water_nodes=scene.batch_nodes["B000_0"]
		check(water_nodes.size()==2 and water_nodes[0].multimesh.instance_count==(192 if f==1 else 544),"water keeps two batches, including full native frozen grid for peripheral ice, field "+str(f))
		check(animation.bindings.size()==1,"only one animated material clock per field, no per-instance model")
		check(water_nodes[1].material_override==null,"constant second source water layer remains unchanged")
		check(animation.bindings[0].textures.size()==30,"all thirty source water frames loaded")
		for sample in reference.water:
			animation.clock=sample.time;animation.update_materials()
			check(animation.bindings[0].texture_id==sample.texture,"original discrete global water frame "+str(sample.time)+" field "+str(f))
		var row=animation.bindings[0];var clock=animation.clock;var texture=row.material.albedo_texture;var changes=animation.texture_changes
		game.paused=true;game.update_visuals(1)
		check(animation.clock==clock and row.material.albedo_texture==texture and animation.texture_changes==changes,"pause freezes water animation and texture uploads")
		game.paused=false;scene.advance(.05)
		check(animation.clock>clock,"water resumes with field visual clock")
	game.free();await process_frame
	FileAccess.open("res://research/scenery-idle-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"max_pose_error":max_pose_error,"pose_samples":reference.samples.size(),"water_samples":reference.water.size()},"\t"))
	print("SCENERY IDLE ",passed," passed; ",failures.size()," failed; max pose error ",max_pose_error);quit(1 if not failures.is_empty() else 0)
