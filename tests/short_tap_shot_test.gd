extends SceneTree
var game
var ui
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok: bool,label: String):
	if ok:passed+=1
	else:failures.append(label);printerr("FAIL "+label)
func touch(id: int,point: Vector2,down: bool):
	var e=InputEventScreenTouch.new();e.index=id;e.position=point;e.pressed=down
	Input.parse_input_event(e);Input.flush_buffered_events()
func setup(angle: float):
	ui.cancel_all();game.sim.reset();game.sim.bot_enabled=false
	var p=game.sim.players[0];p.pos=Vector2.ZERO;p.previous=p.pos;p.body=angle;p.angle=angle
	game.sim.players[1].pos=Vector2(1500,900)
	game.sim.take(0);game.update_visuals(0);ui.frame(0);game.sim.pending_commands.clear()
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.set_process(false);ui=game.touch_controls;ui.start_practice();ui.set_movement("stick")
	game.experience.follow_camera=false;game.focus=Vector3.ZERO;game.update_camera()
	for angle in [0.0,0.65,PI/2,PI,PI*1.5]:
		for offset in [Vector2.ZERO,Vector2(40,40),Vector2(-40,40),Vector2(40,-40),Vector2(-40,-40)]:
			setup(angle)
			var point=ui.buttons.kick.get_global_rect().get_center()+offset
			touch(7,point,true)
			var preview=game.experience.overlay.target_world
			touch(7,point,false)
			var shots=game.sim.pending_commands.filter(func(c):return c.kind=="kick")
			var label="angle %.2f offset %s"%[angle,offset]
			check(shots.size()==1,label+" emits one shot")
			if shots.is_empty():continue
			check(shots[0].target.distance_to(preview)<0.01,label+" release retains preview direction")
			game.sim.consume_commands()
			check(Vector2(game.sim.velocity.x,game.sim.velocity.y).normalized().dot(Vector2.from_angle(angle))>.999,label+" actual shot follows facing")
	# Small release jitter is still a tap; a deliberate drag follows finger travel.
	setup(.65)
	var point=ui.buttons.kick.get_global_rect().get_center()+Vector2(40,40)
	touch(7,point,true);touch(7,point+Vector2(3,-4),false);game.sim.consume_commands()
	check(Vector2(game.sim.velocity.x,game.sim.velocity.y).normalized().dot(Vector2.from_angle(.65))>.999,"small release jitter cannot turn a tap into a downward shot")
	for offset in [Vector2.ZERO,Vector2(40,40),Vector2(-40,-40)]:
		setup(0)
		point=ui.buttons.kick.get_global_rect().get_center()+offset
		touch(7,point,true);ui.touch_drag(7,point+Vector2(40,-60))
		var preview=game.experience.overlay.target_world
		touch(7,point+Vector2(40,-60),false)
		var start=game.sim.ball;game.sim.consume_commands()
		for tick in range(50):
			if game.sim.holder!=0:break
			game.sim.advance(game.sim.MOVE_DT)
		check(game.sim.holder==-1,"deliberate drag completes turn before releasing")
		var end=start+game.sim.velocity
		var screen_motion=game.camera.unproject_position(Vector3(end.x,end.z,-end.y)/100)-game.camera.unproject_position(Vector3(start.x,start.z,-start.y)/100)
		check(screen_motion.x>0 and screen_motion.y<0,"up-right finger drag yields up-right shot from offset "+str(offset))
		check(Vector2(game.sim.velocity.x,game.sim.velocity.y).normalized().dot((preview-Vector2(start.x,start.y)).normalized())>.999,"drag release matches preview from offset "+str(offset))
	setup(0);game.sim.holder=-1;game.sim.pending_commands.clear()
	point=ui.buttons.kick.get_global_rect().get_center()+Vector2(40,40)
	touch(7,point,true);touch(7,point,false)
	check(game.sim.pending_commands.is_empty(),"empty-handed short tap cannot queue a stale shot")
	FileAccess.open("res://research/short-tap-shot-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("Short tap shot checks: ",passed," passed; ",failures.size()," failed")
	quit(0 if failures.is_empty() else 1)
