extends SceneTree
var game
var passed=0
var failures=[]
var observations={}
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func capture(name: String):
	game.touch_controls.frame(0)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image=root.get_texture().get_image();image.save_png("res://research/scenery0418-"+name+".png");return image
func difference(a: Image,b: Image) -> int:
	var count=0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var c=a.get_pixel(x,y);var d=b.get_pixel(x,y)
			if absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b)>.05:count+=1
	return count
func warm(scenery,seconds: float):
	for i in range(roundi(seconds*30)):
		scenery.advance(1.0/30);await process_frame
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.enter_practice()
	var scenery=game.field_scenery.dynamic
	await warm(scenery,3)
	var banner=scenery.models.filter(func(m):return m.data.actor.id=="scenery_LOo1_1")[0]
	for child in game.field_scenery.get_children():
		if child!=scenery:child.hide()
	for model in scenery.models:
		if model!=banner:model.hide()
	var center=banner.position+Vector3(0,1.6,0);game.camera.position=center+Vector3(4,3,6);game.camera.look_at(center)
	print("BANNER ",banner.global_transform," meshes ",banner.mesh_nodes.size()," pose ",banner.skeleton.get_bone_pose(1))
	var before=await capture("diagnostic-banner")
	await warm(scenery,.8)
	print("BANNER after ",banner.skeleton.get_bone_pose(1)," visible ",banner.mesh_nodes[0].visible," mesh ",banner.mesh_nodes[0].mesh.get_aabb())
	var after=await capture("diagnostic-banner-moving");print("BANNER DIFF ",difference(before,after))
	game.field_select.select(1);game.enter_practice();scenery=game.field_scenery.dynamic
	game.focus=Vector3(0,0,-31);game.zoom=.78;game.update_camera();await warm(scenery,3)
	for child in game.field_scenery.get_children():
		if child!=scenery:child.hide()
	var batched=await capture("diagnostic-no-water-batch")
	scenery.use_batches=false;scenery.flush_particles()
	var separate=await capture("diagnostic-no-water-separate");print("NO WATER DIFF ",difference(batched,separate))
	for child in game.field_scenery.get_children():child.show()
	for model in scenery.models:
		for emitter in model.particles.emitters:emitter.mesh.material_override.render_priority=1
	for batch in scenery.batches.values():batch.node.material_override.render_priority=1
	scenery.use_batches=true;scenery.flush_particles();batched=await capture("diagnostic-priority-batch")
	scenery.use_batches=false;scenery.flush_particles();separate=await capture("diagnostic-priority-separate")
	print("PRIORITY DIFF ",difference(batched,separate))
	game.free();await process_frame;quit()
