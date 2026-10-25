extends SceneTree
var game
var ui
var passed=0
var failures=[]
var traces=[]
func _initialize():call_deferred("run")
func check(ok: bool,label: String):
	if ok:passed+=1
	else:failures.append(label);printerr("FAIL "+label)
func touch(id: int,point: Vector2,down: bool):
	var e=InputEventScreenTouch.new();e.index=id;e.position=point;e.pressed=down
	Input.parse_input_event(e);Input.flush_buffered_events()
func step():
	ui.frame(.03);game.sim.advance(.03);game.update_visuals(.03)
func capture(name):
	ui.frame(0);await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/shot-turn-"+name+".png")
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.set_process(false);ui=game.touch_controls;ui.set_movement("stick")
	for mode in ["held","released","changed"]:
		ui.start_practice();ui.cancel_all();game.sim.bot_enabled=false
		var s=game.sim;var p=s.players[0]
		p.pos=Vector2.ZERO;p.previous=p.pos;p.angle=0;p.body=0;p.spin=0
		s.players[1].pos=Vector2(1400,900);s.take(0);game.update_visuals(0);ui.frame(0)
		var stick=ui.joystick.get_global_rect().get_center();var kick=ui.buttons.kick.get_global_rect().get_center()
		touch(10,stick+Vector2(65,0),true);touch(11,kick,true);ui.touch_drag(11,kick+Vector2(-70,40))
		var before: Vector2=p.pos
		for tick in range(10):step()
		check(p.pos.distance_to(before)>30 and ui.aim_id==11,mode+": aiming still allows movement")
		var direction=(game.experience.overlay.target_world-Vector2(s.ball.x,s.ball.y)).normalized()
		check(direction.dot(Vector2.from_angle(p.body))<-.4,mode+": test shot is genuinely behind the facing")
		touch(11,kick+Vector2(-70,40),false);s.consume_commands();before=p.pos
		check(s.holder==0 and not p.shot_order.is_empty() and ui.aim_id==-1,mode+": release queues one turn-to-shoot action")
		if mode=="released":touch(10,stick+Vector2(65,0),false)
		elif mode=="changed":ui.touch_drag(10,stick+Vector2(0,-65))
		var latest=(game.ground_point(root.get_visible_rect().size/2+Vector2(0,-100))-game.ground_point(root.get_visible_rect().size/2)).normalized()
		var trace=[];var paused=true
		for tick in range(40):
			step();trace.append({"tick":tick,"holder":s.holder,"body":p.body,"angle":p.angle,"x":p.pos.x,"y":p.pos.y})
			paused=paused and p.pos.distance_to(before)<.001
			if tick==4 and mode=="held":await capture("preparing")
			if s.holder!=0:break
		check(paused,mode+": preparing blocks stick translation")
		check(s.holder==-1 and p.shot_order.is_empty(),mode+": ball launches and preparation clears")
		check(absf(wrapf(direction.angle()-p.body,-PI,PI))<=s.ShotOrder.HALF_ANGLE+.001,mode+": visible character is inside the shot cone")
		check(Vector2(s.velocity.x,s.velocity.y).normalized().dot(direction)>.999,mode+": flight keeps released preview direction")
		if mode=="held":await capture("released")
		before=p.pos
		for tick in range(22):step()
		var movement: Vector2=p.pos-before
		if mode=="held":check(movement.x>50 and absf(movement.y)<1,mode+": original stick resumes without another touch")
		elif mode=="released":check(movement.length()<.001 and ui.joystick_id==-1,mode+": released stick cannot restart walking")
		else:check(movement.length()>50 and movement.normalized().dot(latest)>.999,mode+": resume follows latest finger direction")
		check(s.pending_commands.filter(func(c):return c.kind=="kick").is_empty(),mode+": no repeated shot commands")
		traces.append({"mode":mode,"frames":trace})
		ui.cancel_all()
	FileAccess.open("res://research/shot-turn-mobile-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"traces":traces},"\t"))
	print("SHOT TURN MOBILE ",passed," passed; ",failures.size()," failed");quit(0 if failures.is_empty() else 1)
