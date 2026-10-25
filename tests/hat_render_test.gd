extends SceneTree
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
	var img=root.get_texture().get_image();img.save_png("res://research/hat-"+name+".png");return img
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
	game.actors[0].position=Vector3(0,0,-6);game.actors[0].play("Stand",true);game.actors[0].advance(0)
	var baseline=await capture("none");var changes={}
	for id in game.hats.choices:
		if id==12:continue
		game.hats.select_hat(id);game.hats.frame(.2)
		var image=await capture(str(id).pad_zeros(2));changes[str(id)]=difference(baseline,image)
		check(changes[str(id)]>10,"original hat "+str(id)+" is visible on the original head attachment")
		var entry=game.hats.active["player:0"]
		if entry.animation.stands.size()>1:
			for variant in entry.animation.stands:
				entry.model.play(variant.name,true);entry.model.advance(float(variant.duration)*.55)
				var key=str(id).pad_zeros(2)+"-variant-"+str(int(variant.source_index))
				var variant_image=await capture(key);changes[key]=difference(baseline,variant_image)
				check(changes[key]>10,"original hat "+str(id)+" renders alternate pose "+variant.name)
		game.hats.clear();await process_frame
	game.hats.select_hat(27);game.hats.frame(.2)
	var before=await capture("pause-before");game.paused=true;game.hats.frame(1);game.paused=false
	var after=await capture("pause-after");check(difference(before,after)<20,"paused hat animation leaves identical pixels")
	game.actors[0].hide();game.hats.frame(0);var hidden=await capture("hidden")
	game.hats.clear();var absent=await capture("hidden-without-hat")
	check(difference(hidden,absent)<20,"invisible character leaves no hat pixels")
	game.free();await process_frame
	FileAccess.open("res://research/hat-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"changed_pixels":changes},"\t"))
	print("HAT RENDER ",passed," passed; ",failures.size()," failed");quit(1 if not failures.is_empty() else 0)
