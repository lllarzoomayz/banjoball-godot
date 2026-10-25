extends SceneTree
const Visual=preload("res://scripts/apocalypse_visuals.gd")
const Model=preload("res://scripts/wc3_model.gd")
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func capture(name):
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image=root.get_texture().get_image();image.save_png("res://research/apocalypse-rubble-"+name+".png");return image
func run():
	root.size=Vector2i(720,540)
	var world=Node3D.new();root.add_child(world)
	var env=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.03,.03,.03)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=1
	world.add_child(env)
	var camera=Camera3D.new();world.add_child(camera);camera.current=true
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=9;camera.position=Vector3(0,8,8);camera.look_at(Vector3.ZERO)
	var models=[];var batches=[]
	for id in range(4):
		var model=Model.new();world.add_child(model);model.load_actor("apoc_rubble_"+str(id),Color.WHITE);model.advance(0)
		var clip=model.clip;var width=model.data.bone_ids.size()*16
		var base=model.frames.slice(int(clip.offset),int(clip.offset)+width);var fixed=true
		for frame in range(int(clip.frames)):
			if model.frames.slice(int(clip.offset)+frame*width,int(clip.offset)+(frame+1)*width)!=base:fixed=false
		check(fixed and model.data.get("billboards",[]).is_empty(),"original rubble Stand is truly static "+str(id))
		model.position=Vector3((id%2)*4-2,0,(id/2)*3-1.5)
		model.rotation.y=id*.63;model.scale=Vector3(.6,.6,.6)
		for index in range(model.mesh_nodes.size()):
			var multi=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D
			multi.mesh=Visual.baked_mesh(model,index);multi.instance_count=1
			var node=MultiMeshInstance3D.new();world.add_child(node);node.multimesh=multi
			node.material_override=model.mesh_nodes[index].material_override
			multi.set_instance_transform(0,model.transform);node.hide();batches.append(node)
		models.append(model)
	var source=await capture("source")
	for model in models:model.hide()
	for node in batches:node.show()
	var batched=await capture("batched");var differences=0;var visible=0
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			var a=source.get_pixel(x,y);var b=batched.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>.015:differences+=1
			if a.r>.1 or a.g>.1 or a.b>.1:visible+=1
	check(visible>500,"comparison contains visible original rubble")
	check(differences<20,"baked MultiMesh preserves original skinned Stand pixels")
	world.free();await process_frame
	FileAccess.open("res://research/apocalypse-rubble-verification.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"pixel_differences":differences,"visible_pixels":visible},"\t"))
	print("APOCALYPSE RUBBLE ",passed," passed; ",failures.size()," failed; pixels ",differences)
	quit(0 if failures.is_empty() else 1)
