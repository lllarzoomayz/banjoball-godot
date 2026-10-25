extends SceneTree
var passed=0
var failures=[]
var game
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func capture(name):
	game.touch_controls.frame(0)
	await process_frame;await RenderingServer.frame_post_draw
	var image=root.get_texture().get_image();image.save_png("res://research/event-decals-"+name+".png");return image
func difference(a: Image,b: Image) -> int:
	var count=0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var c=a.get_pixel(x,y);var d=b.get_pixel(x,y)
			if absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b)>.04:count+=1
	return count
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.enter_practice();game.sim.bot_enabled=false
	game.focus=Vector3(0,0,-6);game.zoom=.25;game.update_camera();game.update_visuals(0)
	var renderer=game.event_decals;var actor=game.actors[0]
	actor.hide();var original=await capture("before");actor.show()
	# Use real exported footfall keys at their authored timing and moving origins.
	actor.play("Walk",true)
	for i in range(10):actor.position=Vector3(-3+i*.5,0,-6);actor.advance(.25)
	actor.position=Vector3(-10,0,0);actor.hide()
	var feet=await capture("feet")
	check(renderer.live_count()>0 and renderer.batches.size()==1,"real footfalls render through one shared instance batch")
	check(difference(original,feet)>100,"footfall scene visibly differs from no-event scene")
	renderer.clear();await process_frame
	actor.position=Vector3(-10,0,0);var before=await capture("clear")
	actor.show();actor.position=Vector3(0,0,-6);actor.play("Death",true);actor.advance(.8);actor.hide();renderer.advance(.8)
	var blood=await capture("blood")
	check(renderer.live_count()>0 and difference(before,blood)>50,"real Death events render original ground stains")
	renderer.clear();await process_frame
	var effect=game.original_effects.burst("fx_earth_pillar_end",Vector3(0,600,0))
	effect.advance(.14);effect.hide();renderer.advance(.2)
	var after=await capture("thunder")
	check(renderer.live_count()==1,"real pitched pillar-end produces one original UberSplat")
	check(difference(before,after)>200,"original ThunderClap stamp produces visible pixels on ground")
	var terrain=game.field_scenery;var point=Vector2(350,-500)
	check(is_equal_approx(renderer.height_texture.get_image().get_pixel(0,0).r,float(terrain.scene_cache[terrain.field_id].heights[0])),"GPU height texture carries original W3E height values")
	game.paused=true;var clock=renderer.clock;renderer.advance(2)
	check(renderer.clock==clock,"paused renderer preserves ground animation clock");game.paused=false
	renderer.advance(4.1);var expired=await capture("expired")
	check(renderer.live_count()==0 and difference(before,expired)<20,"expired stamp returns scene to baseline pixels")
	# Stress ordinary 6v6 foot traffic without adding one node/draw per footprint.
	actor.show()
	var ev={"type":"FPT","code":"FBR1","rotation":[0,0,0,1]}
	var baseline_draws=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var started=Time.get_ticks_usec()
	for i in range(336):renderer.model_event(actor,ev,Vector3((i%24-12)*.35,0,-6+(i/24-7)*.35))
	var spawn_ms=(Time.get_ticks_usec()-started)/1000.0;actor.hide()
	var stress=await capture("stress")
	check(renderer.live_count()==336 and renderer.batches.size()==2,"336 active footprints occupy one footprint batch plus idle stamp batch")
	var batch=renderer.batches.values()[-1]
	check(batch.mesh.get_instance_transform(0).is_equal_approx(batch.entries[0].transform),"real renderer preserves transforms when the pool grows")
	var draws=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)-baseline_draws
	check(draws>=0 and draws<=3,"hundreds of footprints add at most three draw calls")
	started=Time.get_ticks_usec()
	for i in range(120):renderer.advance(1.0/60)
	var update_ms=(Time.get_ticks_usec()-started)/120000.0
	FileAccess.open("res://research/event-decal-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"stress_instances":336,"spawn_ms":spawn_ms,"average_update_ms":update_ms,"extra_draw_calls":draws,"footprint_changed_pixels":difference(original,feet),"blood_changed_pixels":difference(before,blood),"ubersplat_changed_pixels":difference(before,after)},"\t"))
	game.free();print("EVENT DECAL RENDER ",passed," passed; ",failures.size()," failed");quit(1 if not failures.is_empty() else 0)
