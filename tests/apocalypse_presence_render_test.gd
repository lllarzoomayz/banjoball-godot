extends SceneTree
var passed=0
var failures=[]
var game
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func capture(name):
	game.update_visuals(0);game.touch_controls.frame(0)
	await process_frame;await RenderingServer.frame_post_draw
	var image=root.get_texture().get_image();image.save_png("res://research/apocalypse-presence-"+name+".png")
	return image
func run():
	root.size=Vector2i(1280,720)
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.set_process(false);game.touch_controls.start_practice();game.paused=true
	var sim=game.sim;sim.players[0].pos=Vector2(-300,0);sim.players[0].previous=sim.players[0].pos
	sim.players[1].pos=Vector2(600,100);sim.players[1].previous=sim.players[1].pos
	sim.ball=Vector3(200,0,60);sim.previous_ball=sim.ball
	game.focus=Vector3.ZERO;game.update_camera()
	var before=await capture("before")
	check(game.actors[0].is_visible_in_tree() and game.ball_model.visible and game.selection.visible,"actual field shows player, real ball and selection before removal")
	var state=sim.prepare_apocalypse();state.remove_player(0);state.remove_ball()
	var after=await capture("removed")
	check(not game.actors[0].is_visible_in_tree() and game.actors[1].is_visible_in_tree(),"removed actor is hidden while surviving actor remains")
	check(not game.ball_model.visible and not game.shadow.visible,"removed real ball and its ground shadow disappear")
	check(not game.selection.visible,"no selection ring around removed player")
	var changes=0
	for y in range(before.get_height()):
		for x in range(before.get_width()):
			if before.get_pixel(x,y)!=after.get_pixel(x,y):changes+=1
	check(changes>100,"actual rendered field pixels change after unit removal")
	sim.reset();await capture("goal-reset")
	check(not game.actors[0].visible and not game.ball_model.visible,"goal reset cannot visually resurrect native tombstones")
	game.touch_controls.start_practice();game.paused=true;await capture("new-game")
	check(game.actors[0].visible and game.ball_model.visible and game.shadow.visible and game.selection.visible,"new game restores normal render objects")
	game.free();await process_frame
	FileAccess.open("res://research/apocalypse-presence-render-verification.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"changed_pixels":changes,"scope":"unit presence only; full event rendering is tested separately"},"\t"))
	print("APOCALYPSE PRESENCE RENDER ",passed," passed; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
