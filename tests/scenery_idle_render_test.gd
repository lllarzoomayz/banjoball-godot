extends SceneTree
const Model=preload("res://scripts/wc3_model.gd")
var game
var passed=0
var failures=[]
var observations={}
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func capture(name):
	if is_instance_valid(game):game.touch_controls.frame(0)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image=root.get_texture().get_image();image.save_png("res://research/scenery0419-"+name+".png");return image
func difference(a,b):
	var changed=0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var c=a.get_pixel(x,y);var d=b.get_pixel(x,y)
			if absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b)>.05:changed+=1
	return changed
func run():
	var world=Node3D.new();root.add_child(world)
	var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.12,.17,.2);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=1;world.add_child(env)
	var camera=Camera3D.new();world.add_child(camera);camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	for key in ["AObd_0","ZWsw_1","ZWsw_2","ZWsw_3","ZWsw_4","LOh1_0","B00C_0","B00D_0"]:
		var model=Model.new();world.add_child(model);model.load_actor("scenery_"+key,Color.WHITE)
		var low=Model.CONVERSION*Vector3(model.data.bounds.min[0],model.data.bounds.min[1],model.data.bounds.min[2])/100
		var high=Model.CONVERSION*Vector3(model.data.bounds.max[0],model.data.bounds.max[1],model.data.bounds.max[2])/100
		var center=(low+high)/2;var size=(high-low).abs();camera.size=maxf(maxf(size.x,size.y),size.z)*1.45
		if key=="AObd_0":
			var geo=model.data.meshes[0];center=Vector3.ZERO
			for v in range(geo.vertices.size()/3):
				var original=Model.CONVERSION*Vector3(geo.vertices[v*3],geo.vertices[v*3+1],geo.vertices[v*3+2])/100
				var group=geo.groups[int(geo.vertex_group[v])]
				for bone in group:center+=(model.skeleton.get_bone_pose(int(bone))*original)/group.size()
			center/=geo.vertices.size()/3;camera.size=3.5
		camera.position=center+Vector3(1,.4,1).normalized()*camera.size*2;camera.look_at(center);model.advance(0)
		var before=await capture(key+"-before");model.advance(.43);var after=await capture(key+"-after")
		var pixels=difference(before,after);observations[key]=pixels
		check(pixels>100,"original idle geometry visibly animates "+key+" pixels "+str(pixels));model.free()
	world.free();await process_frame
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	for f in [1,2,3]:
		game.field_select.select(f);game.enter_practice();game.focus=Vector3(-30,0,0);game.zoom=.78;game.update_camera()
		var scene=game.field_scenery;var before=await capture("water-"+str(f)+"-before");var calls=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		scene.material_animation.advance(.43);var after=await capture("water-"+str(f)+"-after")
		var changed=difference(before,after)
		check(changed>1000,"only shared water texture advances visibly field "+str(f)+" pixels "+str(changed))
		check(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)==calls,"water animation adds no instance draw calls field "+str(f))
		observations["water_"+str(f)]={"changed_pixels":changed,"draw_calls":calls,"bindings":scene.material_animation.bindings.size()}
	game.open_menu();game.update_visuals(0);var paused=await capture("paused");game.update_visuals(1);var still=await capture("paused-after")
	check(difference(paused,still)==0,"paused shared water and scene give identical pixels")
	var begin=Time.get_ticks_usec();for i in range(1000):game.field_scenery.material_animation.advance(1.0/60)
	observations.water_update_mean_ms=(Time.get_ticks_usec()-begin)/1000000.0
	game.free();await process_frame
	FileAccess.open("res://research/scenery-idle-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"observations":observations},"\t"))
	print("SCENERY IDLE RENDER ",passed," passed; ",failures.size()," failed; ",observations);quit(1 if not failures.is_empty() else 0)
