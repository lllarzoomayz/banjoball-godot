extends SceneTree
const Model=preload("res://scripts/wc3_model.gd")
var game
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func capture(name):
	game.touch_controls.frame(0)
	await process_frame;await RenderingServer.frame_post_draw
	var img=root.get_texture().get_image();img.save_png("res://research/model-light-"+name+".png");return img
func difference(a,b):
	var count=0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var c=a.get_pixel(x,y);var d=b.get_pixel(x,y)
			if absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b)>.04:count+=1
	return count
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.enter_practice()
	game.focus=Vector3(0,0,-6);game.zoom=.25;game.update_camera();game.update_visuals(0)
	for a in game.actors:a.hide()
	var changes={}
	for row in [["h01I","Attack Slam",.1],["h02B","Attack Slam",.1],["h02A","Stand",.1],["fx_angelic_kick","Birth",.4],["fx_swap_caster","Birth",.2],["fx_swap_target","Birth",.5],["h004","Attack",.4]]:
		var actor=Model.new();game.add_child(actor);actor.load_actor(row[0],Color.WHITE);actor.events_enabled=false
		actor.position=Vector3(0,0,-6);actor.play(row[1],true);actor.one_shot=true
		for i in range(roundi(float(row[2])*60)):actor.advance(1.0/60)
		actor.lights.hide();var before=await capture(row[0]+"-off")
		actor.lights.show();var after=await capture(row[0]+"-on")
		changes[row[0]]=difference(before,after)
		check(changes[row[0]]<20 if row[0]=="h004" else changes[row[0]]>50,row[0]+" source-active light visibly illuminates actual scene; inactive light stays dark")
		actor.advance(0);var paused=await capture(row[0]+"-paused");check(difference(after,paused)<20,row[0]+" zero delta preserves illumination")
		actor.free();await process_frame
	# A 6v6 swap burst can create two lights per player. The terrain is one
	# mesh, so the Compatibility default of eight must not silently lose 16.
	game.focus=Vector3.ZERO;game.zoom=.65;game.update_camera()
	var models=[];var points=[]
	for i in range(24):
		var a=Model.new();game.add_child(a);a.load_actor("fx_swap_caster",Color.WHITE);a.events_enabled=false
		a.position=Vector3((i%6-2.5)*3,0,(i/6-1.5)*3);a.play("Birth",true);a.one_shot=true;a.advance(.2)
		for mesh in a.mesh_nodes:mesh.hide()
		if is_instance_valid(a.particles):a.particles.hide()
		if is_instance_valid(a.ribbons):a.ribbons.hide()
		a.lights.hide();models.append(a);points.append(game.camera.unproject_position(a.position))
	var dark=await capture("24-off")
	var baseline_draws=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	for a in models:a.lights.show()
	var lit=await capture("24-on");var visible_spots=0
	for p in points:
		var changed=0
		for y in range(int(p.y)-8,int(p.y)+9):
			for x in range(int(p.x)-8,int(p.x)+9):
				if x<0 or y<0 or x>=lit.get_width() or y>=lit.get_height():continue
				var c=dark.get_pixel(x,y);var d=lit.get_pixel(x,y)
				if absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b)>.04:changed+=1
		if changed>5:visible_spots+=1
	check(visible_spots==24,"24 source lights illuminate all 24 terrain positions without the old eight-light cap")
	var extra_draws=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)-baseline_draws
	for a in models:a.free()
	game.free()
	FileAccess.open("res://research/model-light-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"changed_pixels":changes,"stress_visible_light_positions":visible_spots,"stress_extra_draw_calls":extra_draws},"\t"))
	print("MODEL LIGHT RENDER ",passed," passed; ",failures.size()," failed");quit(1 if not failures.is_empty() else 0)
