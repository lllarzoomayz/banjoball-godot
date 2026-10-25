extends SceneTree
var game
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func setup(id: String):
	game.character_select.select(game.sim.Characters.IDS.find(id))
	game.character_select.item_selected.emit(game.character_select.selected)
	game.touch_controls.start_practice();game.sim.bot_enabled=false
	game.sim.players[0].pos=Vector2.ZERO;game.sim.players[0].previous=Vector2.ZERO
	game.sim.players[1].pos=Vector2(1600,700);game.sim.players[1].previous=Vector2(1600,700)
	game.focus=Vector3.ZERO;game.zoom=.55;game.update_camera();game.update_visuals(0)
func capture(name: String):
	game.touch_controls.frame(0);await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/shot-attachment-047-"+name+".png")
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	setup("h00F")
	var s=game.sim;var fx=game.original_effects
	s.take(0);s.step_ball()
	check(s.Characters.use(s,0,Vector2(1200,0)),"real powershot starts")
	game.update_visuals(.1)
	check(fx.persistent.has("charge:0"),"charging creates native ManaDrain effect")
	var charge=fx.persistent["charge:0"]
	check(charge.global_transform.is_equal_approx(game.actors[0].attachment_transform("overhead")),"Powershot___chargeSfx binds original overhead point")
	check(charge.global_position.distance_to(fx.point(s.Characters.world_position(s.players[0])+Vector3(0,0,s.players[0].catch_height)))>.1,"head location is not substituted with catch height")
	s.players[0].pos=Vector2(120,200);s.players[0].previous=Vector2(100,200)
	s.players[0].body=PI/2;s.players[0].previous_body=PI/3
	game.update_visuals(.1)
	check(charge.global_transform.is_equal_approx(game.actors[0].attachment_transform("overhead")),"charge follows rendered turn and position")
	var animation_time=charge.animation_time
	game.open_menu();game.update_visuals(0)
	check(charge.animation_time==animation_time,"charge animation freezes while paused")
	game.close_menu()
	for i in range(21):game.update_visuals(1.0/60)
	check(charge.active_clip=="Stand" and charge.particles.particle_count()>0,"resumed charge transitions into emitting Stand")
	await capture("charge")
	s.stop(0);game.update_visuals(.02)
	check(not fx.persistent.has("charge:0"),"cancellation releases persistent charge")
	check(charge.active_clip.to_lower().begins_with("death"),"cancel selects source Death; an empty tail may be cleaned up immediately")
	for i in range(240):game.update_visuals(1.0/60)
	check(not fx.bursts.any(func(e):return e.model==charge),"charge death particles eventually drain")
	setup("h012");s=game.sim
	s.take(0);s.step_ball()
	check(s.Characters.use(s,0,Vector2(1200,0)),"real curve shot starts")
	s.advance(.01);game.update_visuals(.01)
	check(fx.persistent.has("curve"),"curve has original missile effect")
	var curve=fx.persistent.curve
	check(curve.global_transform.is_equal_approx(game.ball_model.attachment_transform("chest")),"Curveshot__cast follows rendered ball chest")
	for i in range(12):
		s.advance(.013);game.update_visuals(.013)
		check(curve.global_transform.is_equal_approx(game.ball_model.attachment_transform("chest")),"no separation at fractional fixed-step time "+str(i))
	await capture("curve")
	var basis=curve.global_basis;s.velocity=Vector3.ZERO;game.update_visuals(0)
	check(curve.global_basis.is_equal_approx(basis),"zero velocity does not snap attachment facing")
	animation_time=curve.animation_time;game.open_menu();game.update_visuals(0)
	check(curve.animation_time==animation_time,"curve freezes while paused")
	game.close_menu();s.curve.clear();game.update_visuals(.02)
	check(not fx.persistent.has("curve"),"curve duration end removes active loop")
	s.reset();game.update_visuals(0)
	check(fx.persistent.is_empty() and fx.bursts.is_empty(),"reset clears old shot attachments")
	game.free()
	FileAccess.open("res://research/shot-attachment-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("SHOT ATTACHMENTS ",passed," passed; ",failures.size()," failed")
	quit(1 if not failures.is_empty() else 0)
