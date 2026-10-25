extends SceneTree
const Model=preload("res://scripts/wc3_model.gd")
var game
var failures=[]
var passed=0
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func capture(name):
	game.touch_controls.frame(0)
	await process_frame;await RenderingServer.frame_post_draw
	var image=root.get_texture().get_image();image.save_png("res://research/event-spawn-"+name+".png");return image
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
	var baseline=await capture("before");var changes={}
	for id in ["h004","h00P","h01I","h01R","h029","h02C"]:
		var actor=Model.new();game.add_child(actor);actor.load_actor(id,Color.WHITE);actor.position=Vector3(0,0,-6);actor.play("Death",true);actor.advance(.34);actor.hide()
		# Isolate spawned models from the actor and the independent ground decal.
		game.event_decals.clear()
		# Source NBDH stays invisible until 2.534s; other blood emitters
		# begin between zero and .3s. Sample inside the authored visible phase.
		var at=2.9 if id=="h004" else .6
		for i in range(roundi(at*60)):game.event_spawns.advance(1.0/60)
		var image=await capture(id);changes[id]=difference(baseline,image)
		check(changes[id]>25,id+" original spawned model contributes visible pixels")
		game.paused=true;game.event_spawns.advance(1)
		# Avoid mobile pause-HUD differences when comparing frozen effects.
		game.paused=false
		var frozen=await capture(id+"-frozen")
		check(difference(image,frozen)<20,id+" pause leaves effect pixels unchanged")
		game.event_spawns.advance(10);actor.free();var cleared=await capture(id+"-expired")
		check(difference(baseline,cleared)<20,id+" end of source sequence restores baseline")
	game.free()
	FileAccess.open("res://research/event-spawn-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"changed_pixels":changes},"\t"))
	print("EVENT SPAWN RENDER ",passed," passed; ",failures.size()," failed");quit(1 if not failures.is_empty() else 0)
