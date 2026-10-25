extends SceneTree
var game
var ui
var passed=0
var failures=[]
var sensitivity=[]

func _initialize():call_deferred("run")
func check(ok: bool,label: String):
	if ok:passed+=1
	else:failures.append(label);printerr("FAIL "+label)
func touch(id: int,point: Vector2,down: bool,canceled=false):
	var e=InputEventScreenTouch.new();e.index=id;e.position=point;e.pressed=down;e.canceled=canceled
	Input.parse_input_event(e);Input.flush_buffered_events()
func drag(id: int,point: Vector2):
	var e=InputEventScreenDrag.new();e.index=id;e.position=point
	Input.parse_input_event(e);Input.flush_buffered_events()
func setup():
	ui.cancel_all();game.sim.reset();game.sim.bot_enabled=false
	var p=game.sim.players[0];p.pos=Vector2.ZERO;p.previous=p.pos;p.body=0;p.angle=0
	game.sim.players[1].pos=Vector2(1500,900);game.sim.take(0)
	game.update_visuals(0);ui.frame(0);game.sim.pending_commands.clear()
func aim_direction() -> Vector2:
	return (game.experience.overlay.target_world-game.sim.players[0].pos).normalized()
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.set_process(false);ui=game.touch_controls;ui.start_practice();ui.set_movement("stick")
	game.experience.follow_camera=false;game.focus=Vector3.ZERO;game.update_camera()
	# Avoid the explicit cancel button above Shoot; it intentionally retains
	# priority even when the finger is outside the wheel.
	for degrees in [-175,-145,-110,-70,-60]:
		setup()
		var origin=ui.buttons.kick.get_global_rect().get_center()+Vector2(-16,12)
		var ray=Vector2.from_angle(deg_to_rad(degrees));var first=Vector2.ZERO
		touch(70,origin,true)
		for distance in [80.0,88.0,90.0,180.0,350.0]:
			var point=origin+ray*distance;drag(70,point)
			var label="%s degrees, %s pixels"%[degrees,distance]
			check(not ui.aim_cancelled,label+" remains active outside wheel")
			check(ui.aim_axis.distance_to(ray*distance/88.0)<.001,label+" retains real finger distance")
			check(ui.aim_pad.axis.length()<=1.00001,label+" display stays within wheel")
			if first==Vector2.ZERO:first=aim_direction()
			check(first.dot(aim_direction())>.999999,label+" crossing wheel edge does not rotate the aim")
		var expected=(game.experience.overlay.target_world-Vector2(game.sim.ball.x,game.sim.ball.y)).normalized()
		touch(70,origin+ray*350,false);game.sim.consume_commands()
		for tick in range(50):
			if game.sim.holder!=0:break
			game.sim.advance(game.sim.MOVE_DT)
		check(game.sim.holder==-1,"long drag fires after required turn "+str(degrees))
		check(Vector2(game.sim.velocity.x,game.sim.velocity.y).normalized().dot(expected)>.99999,"long drag shot agrees with preview "+str(degrees))
	# A fixed 6-pixel sideways adjustment should turn less when the finger is
	# farther out, with no lock or staircase after reaching the wheel rim.
	setup()
	var origin=ui.buttons.kick.get_global_rect().get_center();touch(70,origin,true)
	for distance in [100.0,300.0,600.0]:
		drag(70,origin+Vector2(-distance,0));var before=aim_direction()
		drag(70,origin+Vector2(-distance,-6));var after=aim_direction()
		var change=absf(before.angle_to(after));sensitivity.append(rad_to_deg(change))
		check(change>.0001,"outside finger micro-adjustment changes aim at "+str(distance))
		if sensitivity.size()>1:check(sensitivity[-1]<sensitivity[-2]*.6,"farther finger gives finer angular control at "+str(distance))
	# Release uses its own position even if the OS sends no final drag event.
	var release_point=origin+Vector2(-500,-120)
	touch(70,release_point,false)
	var commands=game.sim.pending_commands.filter(func(c):return c.kind=="kick")
	check(commands.size()==1,"release outside wheel issues exactly one shot")
	var final_target=commands[0].target if commands.size()==1 else Vector2.ZERO
	setup();touch(70,origin,true);drag(70,release_point)
	check(final_target.distance_to(game.experience.overlay.target_world)<.001,"release position matches preview at that position")
	# Return from outside the wheel to the tap dead zone; no stale far aim.
	drag(70,origin+Vector2(3,-4))
	check(aim_direction().dot(Vector2.RIGHT)>.99999,"return to centre restores tap-facing direction")
	touch(70,origin,false);game.sim.consume_commands()
	check(game.sim.holder==-1 and Vector2(game.sim.velocity.x,game.sim.velocity.y).normalized().dot(Vector2.RIGHT)>.99999,"return then release performs a normal tap shot")
	# Point skills keep their authored range and allow a return to self-cast.
	game.sim.selected_character="h02C";setup();game.rebuild_actors();ui.frame(0)
	origin=ui.buttons.ability.get_global_rect().get_center();touch(70,origin,true)
	drag(70,origin+Vector2(-88,0));var edge_target=game.experience.overlay.target_world
	drag(70,origin+Vector2(-500,0))
	check(edge_target.distance_to(game.experience.overlay.target_world)<.01,"outside finger cannot increase totem cast range")
	drag(70,origin+Vector2(3,0))
	check(game.experience.overlay.target_world==game.sim.players[0].pos,"totem can return from long drag to feet")
	ui.cancel_all();game.sim.selected_character="h005";setup()
	origin=ui.buttons.kick.get_global_rect().get_center();touch(70,origin,true);drag(70,origin+Vector2(-450,-120))
	var cancel=ui.buttons.cancel.get_global_rect().get_center();touch(70,cancel,false)
	check(game.sim.pending_commands.is_empty(),"cancel button still cancels a long drag")
	touch(70,origin,true);drag(70,origin+Vector2(-450,-120));touch(70,Vector2(-10,100),false)
	check(game.sim.pending_commands.is_empty(),"screen boundary release cancels without shooting")
	touch(70,origin,true);drag(70,origin+Vector2(-450,-120));touch(70,origin,false,true)
	check(game.sim.pending_commands.is_empty() and ui.aim_id==-1,"OS cancellation clears long aiming gesture")
	# Render a long drag for visual inspection: the entire thumb stays in ring.
	touch(70,origin,true);drag(70,origin+Vector2(-450,-120));ui.frame(0)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/extended-aim.png")
	ui.cancel_all()
	FileAccess.open("res://research/extended-aim-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"angular_change_degrees_for_6px_at_100_300_600px":sensitivity},"\t"))
	print("Extended aim checks: ",passed," passed; ",failures.size()," failed")
	quit(0 if failures.is_empty() else 1)
