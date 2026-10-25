extends SceneTree
const Destruction=preload("res://scripts/scenery_destruction.gd")
const Scenery=preload("res://scripts/field_scenery.gd")
var passed=0
var failures=[]
var observations={}
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func capture(name=""):
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image=root.get_texture().get_image()
	if name!="":image.save_png("res://research/destruction-"+name+".png")
	return image
func difference(a,b):
	var changed=0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var c=a.get_pixel(x,y);var d=b.get_pixel(x,y)
			if absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b)>.05:changed+=1
	return changed
func cpu_reference(state,key,seconds):
	var result=Node3D.new();state.get_parent().add_child(result)
	var row=Destruction.catalog.models[key];var frame=minf(seconds*30,float(row.frames)-1)
	var first=int(frame);var second=mini(first+1,int(row.frames)-1);var blend=frame-first
	for i in range(row.meshes.size()):
		var geo=row.meshes[i];var arrays=Destruction.create_geometry(key,i).mesh.surface_get_arrays(0)
		var positions=FileAccess.get_file_as_bytes(geo.positions).to_float32_array();var normals=FileAccess.get_file_as_bytes(geo.normal_frames).to_float32_array()
		var vertices=PackedVector3Array();var normal_values=PackedVector3Array()
		for v in range(int(geo.vertex_count)):
			var a=(first*int(geo.vertex_count)+v)*4;var b=(second*int(geo.vertex_count)+v)*4
			vertices.append(Vector3(positions[a],positions[a+1],positions[a+2]).lerp(Vector3(positions[b],positions[b+1],positions[b+2]),blend))
			normal_values.append(Vector3(normals[a],normals[a+1],normals[a+2]).lerp(Vector3(normals[b],normals[b+1],normals[b+2]),blend).normalized())
		arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normal_values
		var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var material=state.batches[key].materials[i].duplicate();var code=material.shader.code
		var shader=Shader.new();shader.code=code.left(code.find("void vertex()"))+"uniform vec4 cpu_pose_color;\nvoid vertex(){pose_color=cpu_pose_color;}\n"+code.substr(code.find("void fragment()"))
		material.shader=shader
		var a=geo.colors[first];var b=geo.colors[second]
		material.set_shader_parameter("cpu_pose_color",Color(a[0],a[1],a[2],geo.alphas[first]).lerp(Color(b[0],b[1],b[2],geo.alphas[second]),blend))
		var node=MeshInstance3D.new();node.mesh=mesh;node.material_override=material;result.add_child(node)
	return result
func run():
	root.size=Vector2i(720,540)
	var world=Node3D.new();root.add_child(world)
	var environment=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(.07,.09,.12);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=1;world.add_child(environment)
	var camera=Camera3D.new();world.add_child(camera);camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	var max_pixels=0
	for key in Destruction.source_catalog().models:
		var row=Destruction.catalog.models[key]
		if row.status!="death":continue
		var state=Destruction.new();world.add_child(state);state.setup(null);state.add_death(key,Transform3D.IDENTITY)
		var bounds=Destruction.create_geometry(key,0).bounds
		for i in range(1,row.meshes.size()):bounds=bounds.merge(Destruction.create_geometry(key,i).bounds)
		var center=bounds.get_center();camera.size=maxf(maxf(bounds.size.x,bounds.size.y),bounds.size.z)*1.45
		camera.position=center+Vector3(1,.6,1).normalized()*camera.size*2;camera.look_at(center)
		var seconds=float(row.duration)*.43;state.advance(seconds)
		var actual=await capture(key+"-gpu" if key in ["LTlt_0","WTst_0","B00C_0"] else "")
		state.hide();var reference=cpu_reference(state,key,seconds)
		var expected=await capture(key+"-cpu" if key in ["LTlt_0","WTst_0","B00C_0"] else "")
		var pixels=difference(actual,expected);max_pixels=maxi(max_pixels,pixels)
		check(pixels<50,"GPU instanced Death matches CPU posed original vertices "+key+" changed pixels "+str(pixels))
		reference.free();state.free()
	observations.max_gpu_cpu_different_pixels=max_pixels
	# Different birth times and an already-dead tree share the same two draws.
	var grouped=Destruction.new();world.add_child(grouped);grouped.setup(null)
	var transforms=[Transform3D(Basis(Vector3.UP,.3).scaled_local(Vector3(.8,1.2,.9)),Vector3(-3,0,0)),Transform3D(Basis.IDENTITY,Vector3.ZERO),Transform3D(Basis.IDENTITY,Vector3(3,0,0))]
	grouped.add_death("LTlt_0",transforms[0]);grouped.advance(.8)
	grouped.add_death("LTlt_0",transforms[1]);grouped.add_death("LTlt_0",transforms[2],true);grouped.advance(.2)
	camera.size=14;camera.position=Vector3(0,8,16);camera.look_at(Vector3(0,2,0))
	var grouped_image=await capture("staggered-gpu");grouped.hide();var references=[]
	for i in range(3):
		var reference=cpu_reference(grouped,"LTlt_0",[1.0,.2,1.5][i]);reference.transform=transforms[i];references.append(reference)
	var reference_image=await capture("staggered-cpu")
	check(difference(grouped_image,reference_image)<50,"independent instance clocks, dead pose and nonuniform transform match CPU reference")
	check(grouped.batches.LTlt_0.nodes.size()==2 and grouped.batches.LTlt_0.entries.size()==3,"three death stages share the same two geoset draws")
	for node in references:node.free()
	grouped.free()
	var field=Scenery.new();world.add_child(field);field.load_field("Sunny_Hills")
	camera.size=35;camera.position=Vector3(-7,25,0);camera.look_at(Vector3(-7,0,-15))
	var before=await capture("field-before");var state=field.destruction_state();state.kill_destructables();state.advance(.5)
	var falling=await capture("field-falling");state.advance(1.5);var after=await capture("field-dead")
	check(difference(before,falling)>1000 and difference(falling,after)>1000,"actual field transitions from trees through Death to stumps")
	var finished=await capture();state.advance(0);var paused=await capture()
	check(difference(finished,paused)==0,"paused destruction produces identical pixels")
	state.clear();var restored=await capture("field-restored")
	check(difference(before,restored)==0,"clearing destruction restores the exact original field pixels")
	observations.field_death_pixel_changes=difference(before,after)
	var native_world=preload("res://scripts/apocalypse_world.gd").new();var random=RandomNumberGenerator.new();random.seed=24
	native_world.setup(0,random)
	var native_tree={}
	for candidate in native_world.candidates():
		if candidate.id=="LTlt" and field.placement_slots.has(int(candidate.editor_id)):
			native_tree=candidate;break
	var center=Vector2(native_world.field.center[0],native_world.field.center[1])
	var first=native_world.lift(native_tree.uid,0);state.apply_tree_replacement(first,center)
	var local=Vector2(native_tree.position[0],native_tree.position[1])-center
	var target=Vector3(local.x,field.height_at(local),-local.y)/100
	camera.size=8;camera.position=target+Vector3(4,5,8);camera.look_at(target+Vector3(0,1,0))
	var second=native_world.lift(first.replacement.uid,7);state.apply_tree_replacement(second,center)
	var replaced=await capture("repeat-tree-second")
	var third=native_world.lift(second.replacement.uid,7);state.apply_tree_replacement(third,center)
	var repeated=await capture("repeat-tree-third")
	check(difference(replaced,repeated)==0,"repeated native dead-tree replacement has identical pixels to one stump, with no old geometry remaining")
	observations.repeated_tree_pixel_difference=difference(replaced,repeated)
	world.free();await process_frame
	FileAccess.open("res://research/scenery-destruction-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"observations":observations},"\t"))
	print("SCENERY DESTRUCTION RENDER ",passed," passed; ",failures.size()," failed; ",observations);quit(1 if not failures.is_empty() else 0)
