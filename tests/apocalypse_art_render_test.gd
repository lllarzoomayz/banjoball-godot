extends SceneTree
const Model=preload("res://scripts/wc3_model.gd")
var passed=0
var failures=[]
var observations={}
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func capture(name):
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image=root.get_texture().get_image();image.save_png("res://research/apocalypse-art-"+name+".png");return image
func difference(a,b):
	var changed=0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var c=a.get_pixel(x,y);var d=b.get_pixel(x,y)
			if absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b)>.04:changed+=1
	return changed
func run():
	root.size=Vector2i(720,540)
	var world=Node3D.new();root.add_child(world)
	var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(.01,.01,.01);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=1;world.add_child(env)
	var camera=Camera3D.new();world.add_child(camera);camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=6;camera.position=Vector3(0,9,10);camera.look_at(Vector3.ZERO)
	var empty=await capture("empty")
	var hole=Model.new();world.add_child(hole);hole.load_actor("apoc_black_hole",Color.WHITE);hole.play("Stand",true)
	hole.advance(.6);hole.particles.hide()
	var full=await capture("hole-full");hole.fade_alpha=.4;hole.advance(0);hole.particles.hide()
	var partial=await capture("hole-partial");hole.fade_alpha=0;hole.advance(0);hole.particles.hide()
	var hidden=await capture("hole-zero")
	check(difference(empty,full)>500,"black hole original mesh is visible")
	check(difference(full,partial)>500,"black hole mesh alpha visibly fades")
	check(difference(empty,hidden)==0,"zero alpha removes all additive black hole mesh pixels")
	hole.free()
	var nuke=Model.new();world.add_child(nuke);nuke.load_actor("apoc_nuclear",Color.WHITE);nuke.play("Birth",true)
	for i in range(36):nuke.advance(1.0/60)
	camera.size=32;camera.position=Vector3(0,35,35);camera.look_at(Vector3(0,2,0))
	var explosion=await capture("nuclear-full")
	check(difference(empty,explosion)>1000,"original thirteen-emitter nuclear burst renders")
	# Isolate source geosets so the smoke cannot hide a missing second layer.
	nuke.particles.hide()
	for geo in [2,3]:
		for i in range(nuke.mesh_nodes.size()):nuke.mesh_nodes[i].visible=i==geo
		var first=nuke.mesh_nodes[geo].material_override;var second=first.next_pass
		first.set_shader_parameter("model_alpha",.2);second.set_shader_parameter("model_alpha",.2)
		var both=await capture("geo-"+str(geo)+"-both")
		first.next_pass=null;var only_first=await capture("geo-"+str(geo)+"-first")
		first.next_pass=second;first.set_shader_parameter("model_alpha",0)
		var only_second=await capture("geo-"+str(geo)+"-second")
		var second_pixels=difference(both,only_first);var first_pixels=difference(both,only_second)
		check(second_pixels>100,"source second layer contributes pixels geo "+str(geo))
		check(first_pixels>100,"source first layer contributes pixels geo "+str(geo))
		observations[str(geo)]={"first_layer_contribution":first_pixels,"second_layer_contribution":second_pixels}
		first.set_shader_parameter("model_alpha",.2)
	nuke.free();world.free();await process_frame
	FileAccess.open("res://research/apocalypse-art-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"observations":observations},"\t"))
	print("APOCALYPSE ART RENDER ",passed," passed; ",failures.size()," failed; ",observations)
	quit(1 if not failures.is_empty() else 0)
