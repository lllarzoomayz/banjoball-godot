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
	var waterfall=scenery.models.filter(func(m):return m.data.actor.id=="scenery_D000_0")[0]
	var center=waterfall.position+Vector3(0,1,0)
	game.camera.position=center+Vector3(0,12,17);game.camera.look_at(center)
	var falls=await capture("waterfall")
	await warm(scenery,.4);var flowing=await capture("waterfall-moving")
	check(difference(falls,flowing)>100,"waterfall source texture and particles visibly move")
	var banner=scenery.models.filter(func(m):return m.data.actor.id=="scenery_LOo1_1")[0]
	# Source placement sits behind a larger custom sign from this camera angle.
	# Inspect the actual banner without moving or deleting either source object.
	var covering=scenery.models.filter(func(m):return m.get_meta("scenery_key","")=="B00C_0")
	for node in covering:node.hide()
	center=banner.position+Vector3(0,1.6,0);game.camera.position=center+Vector3(4,3,6);game.camera.look_at(center)
	var flag=await capture("banner")
	await warm(scenery,.8);var moving=await capture("banner-moving")
	check(difference(flag,moving)>100,"original banner mesh and hanging ornaments animate")
	for node in covering:node.show()
	check(banner.particles.particle_count()==0,"normal animated banner remains free of invented death smoke")
	game.field_select.select(1);game.enter_practice();scenery=game.field_scenery.dynamic
	game.focus=Vector3(0,0,-31);game.zoom=.78;game.update_camera()
	await warm(scenery,3)
	var batched=await capture("steam-batched");var batch_calls=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var particles=scenery.particle_count()
	scenery.use_batches=false;scenery.flush_particles()
	var separate=await capture("steam-separate");var separate_calls=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var diff=difference(batched,separate)
	check(diff<float(batched.get_width()*batched.get_height())*.005,"additive batch matches original separate emitters: "+str(diff)+" differing pixels")
	check(scenery.particle_count()==particles,"batching preserves every original steam particle")
	check(separate_calls>batch_calls+40,"steam uses fewer actual draw calls: "+str(batch_calls)+" vs "+str(separate_calls))
	scenery.use_batches=true;scenery.flush_particles()
	game.open_menu();game.update_visuals(0);var frozen=await capture("paused")
	game.update_visuals(1);var still=await capture("paused-after")
	check(difference(frozen,still)==0,"paused scenery and camera produce identical pixels")
	game.close_menu()
	var timings=[];var simulation=[];var geometry=[]
	for i in range(40):
		var start=Time.get_ticks_usec();scenery.advance(1.0/60);var ms=(Time.get_ticks_usec()-start)/1000.0
		if i>=10:timings.append(ms);simulation.append(scenery.profile.simulation_ms);geometry.append(scenery.profile.geometry_ms)
		await process_frame
	timings.sort()
	observations={"steam_particles":particles,"batched_draw_calls":batch_calls,"separate_draw_calls":separate_calls,"batch_pixel_difference":diff,"desktop_scenery_cpu_mean_ms":timings.reduce(func(a,b):return a+b,0.0)/timings.size(),"desktop_scenery_cpu_p95_ms":timings[roundi((timings.size()-1)*.95)],"desktop_simulation_mean_ms":simulation.reduce(func(a,b):return a+b,0.0)/simulation.size(),"desktop_geometry_mean_ms":geometry.reduce(func(a,b):return a+b,0.0)/geometry.size(),"note":"Desktop renderer only; no phone bottleneck/performance claim."}
	game.free();await process_frame
	FileAccess.open("res://research/dynamic-scenery-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"observations":observations},"\t"))
	print("SCENERY RENDER ",passed," passed; ",failures.size()," failed; ",observations);quit(1 if not failures.is_empty() else 0)
