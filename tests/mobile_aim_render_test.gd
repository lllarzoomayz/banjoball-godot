extends SceneTree
var game
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func capture(name: String):
	for i in range(3):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/mobile-047-"+name+".png")

func cap_normal(model) -> Vector3:
	# Check actual animated geometry, not just the root's yaw. The original
	# Birth bones turn this cap upward before the Sfx dummy attachment pitch.
	var geo=model.data.meshes[1];var normal=Vector3.ZERO
	for vertex in range(geo.normals.size()/3):
		var local=model.CONVERSION*model.vec(geo.normals,vertex*3)
		var group=geo.groups[int(geo.vertex_group[vertex])]
		for bone in group:
			normal+=model.skeleton.get_bone_pose(int(bone)).basis*local/float(group.size())
	return (model.global_basis*normal).normalized()

func check_goal_facings():
	for goal in range(2):
		for edge in ["front","top","bottom"]:
			ui_practice_goal(goal)
			var front: Rect2=game.sim.arena.guards[goal][0]
			var left=front.get_center().x<0
			var normal=Vector2.RIGHT if left else Vector2.LEFT
			var contact=Vector2(front.end.x if left else front.position.x,0)
			if edge!="front":
				normal=Vector2(0,1) if edge=="top" else Vector2(0,-1)
				contact=Vector2(front.get_center().x,front.end.y if edge=="top" else front.position.y)
			var p=game.sim.players[0]
			p.pos=contact-normal*5;p.body=(-normal).angle();p.angle=p.body
			check(game.sim.repair_goal_entry(0,contact+normal*5),"goal entry emits contact goal=%d edge=%s"%[goal,edge])
			for player in game.sim.players:
				player.previous=player.pos;player.previous_body=player.body;player.previous_z=player.z
			game.update_visuals(0);game.touch_controls.frame(0)
			var flashes=game.original_effects.bursts.filter(func(e):return e.model.data.actor.id=="fx_goal_block")
			check(flashes.size()==1,"one original blue flash per contact goal=%d edge=%s"%[goal,edge])
			if flashes.is_empty():continue
			var model=flashes[0].model
			var to_player=game.original_effects.point(Vector3(p.pos.x,p.pos.y,p.z+80))-model.global_position
			for age in [0.0,0.15,0.35,0.65]:
				model.play("Birth",true);model.advance(age)
				check(cap_normal(model).dot(to_player.normalized())>0.99,"animated cap faces rejected player goal=%d edge=%s age=%.2f"%[goal,edge,age])
			# A different camera must not turn this directional surface into a billboard.
			var before=cap_normal(model)
			game.focus=game.original_effects.point(Vector3(contact.x,contact.y,0))
			game.experience.follow_camera=false;game.update_camera();model.advance(0)
			check(before.dot(cap_normal(model))>0.999,"goal cap stays contact-facing when camera moves goal=%d edge=%s"%[goal,edge])
			model.play("Birth",true);model.advance(0.15)
			await capture("blue-goal-%d-%s"%[goal,edge])

func ui_practice_goal(goal: int):
	game.touch_controls.start_practice();game.perf.panel.hide()
	game.sim.players[0].team=1-goal;game.sim.players[1].pos=Vector2.ZERO
	game.sim.holder=-1;game.sim.ball=Vector3.ZERO
func check_pillar_render():
	var ui=game.touch_controls
	ui.cancel_all();game.sim.selected_character="h02C";game.sim.reset();game.rebuild_actors();game.sim.bot_enabled=false
	game.sim.players[0].pos=Vector2(-500,0);game.sim.players[0].previous=Vector2(-500,0)
	game.sim.players[0].body=0;game.sim.players[1].pos=Vector2(1600,900)
	game.sim.ball=Vector3(100,0,0);game.sim.previous_ball=game.sim.ball
	game.sim.holder=-1;game.sim.velocity=Vector3.ZERO
	game.focus=Vector3(-2,0,0);game.experience.follow_camera=false;game.zoom=0.65;game.update_camera()
	game.update_visuals(0);ui.frame(0);game.perf.set_mode(0)
	var button=ui.buttons.ability.get_global_rect().get_center()
	ui.touch_press(115,button);ui.frame(0)
	check(game.experience.overlay.target_world==game.sim.players[0].pos,"rendered pillar indicator targets feet on first touch")
	await capture("pillar-feet-aim");ui.cancel_aim()
	game.sim.Characters.use(game.sim,0,Vector2.ZERO)
	game.sim.advance(0.15);game.update_visuals(0.15)
	check(game.actors[0].active_clip=="Attack Slam" and game.actors[0].rate==4.0,"Tauren plays source slam animation at original four-times speed")
	await capture("pillar-slam")
	game.sim.advance(0.18);game.update_visuals(0.18)
	var waves=game.original_effects.bursts.filter(func(e):return e.model.data.actor.id.begins_with("fx_earth_pillar"))
	check(waves.size()==8 and game.pillar_models.is_empty(),"cast wave appears before pillar, seven small ripples plus endpoint")
	check(waves.all(func(e):return e.model.transform.basis.y.normalized().dot(Vector3.RIGHT)>0.99),"pillar effects include source Sfx dummy attachment orientation")
	await capture("pillar-impact")
	game.sim.advance(0.15);game.update_visuals(0.15)
	check(game.pillar_models.size()==1 and game.pillar_models.values()[0].active_clip=="Birth" and game.sim.ball.z>0,"pillar birth and hit ball render together")
	await capture("pillar-birth")
	game.sim.advance(0.18);game.update_visuals(0.18);ui.frame(0)
	check(game.original_effects.bursts.filter(func(e):return e.model.data.actor.id=="fx_earth_pillar_end")[0].model.mesh_nodes.any(func(n):return n.visible),"source impact mesh is visible during the rising pillar")
	await capture("pillar-rising-impact")
	for i in range(40):game.sim.advance(0.03);game.update_visuals(0.03)
	check(game.pillar_models.values()[0].active_clip=="Stand","pillar finishes rising into original standing pose")
	await capture("pillar-standing")
	for i in range(57):game.sim.advance(0.03);game.update_visuals(0.03)
	# Around 3.39s since cast, just before the 3s pillar lifetime ends.
	for i in range(4):game.sim.advance(0.03);game.update_visuals(0.03)
	check(game.pillar_models.is_empty() and game.dying_pillars.size()==1 and game.dying_pillars[0].model.active_clip=="Death","expiry plays original Death instead of abruptly popping away")
	check(not game.original_effects.bursts.any(func(e):return e.model.data.actor.id.begins_with("fx_earth_pillar")),"no misplaced impact effect at expiry")
	await capture("pillar-death")
	game.sim.advance(0.6);game.update_visuals(0.6)
	check(game.dying_pillars.is_empty(),"finished death model is released")
	game.sim.players[0].cooldown=0;game.aim="";game.choose_ability();game.choose_ability();game.sim.consume_commands()
	check(game.aim=="" and game.sim.players[0].ability_target==game.sim.players[0].pos,"PC second Q casts at feet")
	game.sim.advance(0.5);game.update_visuals(0.5);game.sim.reset();game.update_visuals(0)
	check(game.pillar_models.is_empty() and game.dying_pillars.is_empty(),"round reset removes all active and dying pillar visuals")

func check_hook_render():
	var ui=game.touch_controls
	ui.start_practice();ui.cancel_all();game.sim.selected_character="h01R";game.sim.reset();game.rebuild_actors();game.sim.bot_enabled=false
	game.sim.players[0].pos=Vector2(-650,0);game.sim.players[0].previous=Vector2(-650,0)
	game.sim.players[1].pos=Vector2(1400,900);game.sim.ball=Vector3(1400,-900,0);game.sim.previous_ball=game.sim.ball
	game.sim.holder=-1;game.sim.velocity=Vector3.ZERO;game.focus=Vector3.ZERO
	game.experience.follow_camera=false;game.zoom=0.65;game.update_camera();game.perf.set_mode(0)
	game.sim.Characters.use(game.sim,0,Vector2(1400,0));game.sim.advance(0.3);game.update_visuals(0.3);ui.frame(0)
	var hook=game.sim.players[0].hook;var model=game.projectile_models[hook.id]
	check(absf(wrapf(model.rotation.y,-PI,PI))<0.001,"outgoing hook faces forward")
	var arrays=game.original_effects.lightning.nodes.ROPE.mesh.surface_get_arrays(0)
	var vertices=arrays[Mesh.ARRAY_VERTEX];var colors=arrays[Mesh.ARRAY_COLOR]
	var rope_start=(vertices[0]+vertices[1])/2
	var rope_end=(vertices[-4]+vertices[-1])/2
	check(rope_start.distance_to(game.actors[0].position+Vector3.UP*0.75)<0.001,"rope origin follows the rendered caster")
	check(rope_end.distance_to(model.position+Vector3.UP*0.75)<0.001,"rope endpoint follows the rendered hook at original height")
	check(colors[0].is_equal_approx(Color.WHITE),"rope retains original untinted texture for enemy hook")
	check(game.original_effects.lightning.nodes.ROPE.material_override.blend_mode==BaseMaterial3D.BLEND_MODE_ADD,"opaque-black source rope uses additive composition, not a black rectangle")
	check(model.tint.is_equal_approx(Color(1,100.0/255,100.0/255)),"enemy hook head retains exact original red tint")
	await capture("hook-outbound")
	for direction in [Vector2.RIGHT,Vector2.UP,Vector2.LEFT,Vector2.DOWN]:
		hook.returning=false;hook.velocity=Vector3(direction.x,direction.y,0)*40;game.update_projectiles(0)
		var outward=model.basis.x.normalized()
		hook.returning=true;hook.velocity=-hook.velocity;game.update_projectiles(0)
		check(outward.dot(model.basis.x.normalized())>0.999,"hook keeps its outward facing when retracting "+str(direction))
	hook.velocity=Vector3(-40,0,0);game.sim.advance(0.12);game.update_visuals(0.12);ui.frame(0)
	await capture("hook-retract")
	game.sim.advance(1.2);game.update_visuals(1.2)
	check(game.projectile_models.is_empty() and not game.original_effects.lightning.nodes.ROPE.visible,"missed hook and rope disappear after returning")
	for friendly in [false,true]:
		game.sim.reset();game.sim.players[0].pos=Vector2(-600,0);game.sim.players[0].previous=Vector2(-600,0)
		game.sim.players[1].pos=Vector2(50,0);game.sim.players[1].previous=Vector2(50,0);game.sim.players[1].team=0 if friendly else 1
		game.sim.ball=Vector3(1500,-900,0);game.sim.previous_ball=game.sim.ball
		game.sim.Characters.use(game.sim,0,Vector2(1000,0),friendly)
		for i in range(16):game.sim.advance(1.0/32);game.update_visuals(1.0/32)
		hook=game.sim.players[0].hook
		check(not hook.is_empty() and hook.caught==1,"rendered hook catches intended player "+str(friendly))
		var impacts=game.sim.native_visuals.filter(func(e):return e.model=="fx_hook")
		check(impacts.size()==1 and impacts[0].pos==Vector3(50,0,0) and is_equal_approx(impacts[0].scale,0.01),"original hit event occurs once at victim before dragging "+str(friendly))
		check(game.original_effects.bursts.any(func(e):return e.model.data.actor.id=="fx_hook" and e.model.mesh_nodes.any(func(n):return n.visible)),"source Hook SFX is rendered on contact "+str(friendly))
		ui.frame(0);await capture("hook-catch-ally" if friendly else "hook-catch-enemy")
		game.sim.Characters.use(game.sim,0,Vector2.ZERO,friendly);game.sim.advance(1.5);game.update_visuals(1.5)
		check(game.projectile_models.is_empty() and not game.original_effects.lightning.nodes.ROPE.visible,"drop then return cleans rope and head "+str(friendly))
	game.sim.reset();game.sim.players[0].pos=Vector2(-600,0);game.sim.players[1].pos=Vector2(1500,900)
	game.sim.ball=Vector3(0,0,0);game.sim.previous_ball=game.sim.ball;game.sim.holder=-1
	game.sim.Characters.use(game.sim,0,Vector2(1000,0))
	for i in range(14):game.sim.advance(1.0/32);game.update_visuals(1.0/32)
	check(game.sim.native_visuals.filter(func(e):return e.model=="fx_hook").size()==1 and game.sim.ball_hook>0,"free real ball also receives one original hook impact")
	ui.frame(0);await capture("hook-catch-ball")
	game.sim.reset();game.update_visuals(0)
	check(game.projectile_models.is_empty() and game.original_effects.bursts.is_empty(),"round reset clears hook and hit effects")

func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.set_process(false);var ui=game.touch_controls
	ui.start_practice();game.perf.mode=0;game.perf.panel.hide();ui.set_movement("stick")
	for row in [["h005","kick","shot"],["h012","ability","curve"],["h003","ability","area"],["h026","ability","smash"]]:
		game.sim.selected_character=row[0];game.sim.reset();game.rebuild_actors();game.sim.bot_enabled=false
		game.sim.take(0);game.sim.ball=game.sim.Copies.held_position(game.sim,0);game.sim.previous_ball=game.sim.ball
		game.update_visuals(0);game.update_camera();ui.frame(0)
		var start=ui.buttons[row[1]].get_global_rect().get_center()
		ui.touch_press(11,start);ui.touch_drag(11,start+Vector2(65,-40));ui.frame(0.1)
		check(ui.aim_id==11 and not game.experience.overlay.preview.is_empty(),"rendered indicator "+row[2])
		await capture(row[2]);ui.touch_release(11,start+Vector2(65,-40));game.sim.consume_commands()
		if row[0]=="h026":
			game.update_visuals(0.06)
			check(game.actors[0].active_clip=="Attack 2" and game.actors[0].rate==2.0,"render selects original Attack 2 at double speed")
			await capture("ogre-hit")
	ui.start_match();game.sim.match_state="playing";game.sim.bot_enabled=false;game.update_visuals(0);ui.frame(0)
	ui.select_portrait(2);game.update_visuals(0);ui.frame(0);await capture("portraits")
	check(game.sim.controlled==ui.portrait_players[2],"portrait selection is shown in the rendered match")
	ui.chosen_team=6;ui.start_match();game.sim.match_state="playing";game.sim.bot_enabled=false
	game.sim.players[game.sim.controlled].mana=62;game.sim.players[game.sim.controlled].sprint=true
	game.update_visuals(0);ui.frame(0);game.perf.mode=2;game.perf.layout();game.perf.panel.show()
	await capture("vertical-mana")
	ui.start_practice();game.sim.players[0].pos=game.sim.arena.keeper_position(0);game.sim.holder=-1
	game.update_visuals(0);game.update_camera();ui.frame(0);await capture("keeper-ready")
	var jump=ui.buttons.jump.get_global_rect().get_center();ui.touch_press(90,jump);ui.touch_release(90,jump);game.sim.advance(0.15)
	game.update_visuals(0);ui.frame(0);await capture("keeper-jump")
	check(game.sim.players[0].z>0 and ui.buttons.jump.disabled,"rendered keeper jump and cooldown")
	game.open_menu();ui.frame(0);game.perf.panel.hide();ui.pick_character.pressed.emit();await capture("character-list")
	ui.picker_scroll.scroll_vertical=2000;await capture("character-list-bottom");ui.close_picker()
	ui.start_practice();game.perf.panel.hide();game.sim.players[1].pos=Vector2(-1000,900)
	game.sim.players[0].pos=Vector2(1550,0);game.sim.players[0].body=0;game.sim.players[0].angle=0
	game.sim.submit_command("move_direction",0,Vector2.RIGHT)
	for i in range(30):
		game.sim.advance(1.0/60);game.update_visuals(1.0/60)
	game.focus=Vector3(18,0,0);game.experience.follow_camera=false;game.update_camera();ui.frame(0)
	check(game.original_effects.bursts.any(func(e):return e.model.data.actor.id=="fx_goal_block" and is_equal_approx(e.model.scale.x,0.9)),"goal protection uses original blue resource at source scale")
	var blue_model=game.original_effects.bursts.filter(func(e):return e.model.data.actor.id=="fx_goal_block")[0].model
	var tint=blue_model.mesh_nodes[1].material_override.get_shader_parameter("geoset_tint")
	check(tint.b>0.95 and tint.r<0.01,"rendered goal flash retains source blue channel rather than swapped red")
	await capture("blue-goal-contact")
	await check_goal_facings()
	ui.start_practice();game.sim.arena.add_box(Rect2(0,-250,100,500),240);game.build_obstacles()
	game.sim.players[0].pos=Vector2(-160,0);game.sim.players[0].body=0;game.sim.players[0].angle=0
	game.sim.players[1].pos=Vector2(-1000,900);game.sim.submit_command("move_direction",0,Vector2.RIGHT)
	for i in range(120):
		game.sim.advance(1.0/60);game.update_visuals(1.0/60)
	game.focus=Vector3.ZERO;game.update_camera();ui.frame(0)
	check(absf(game.sim.players[0].pos.x+30)<0.01 and absf(game.sim.players[0].pos.y)<0.01,"rendered player stays against the wall without detour")
	await capture("stick-wall-contact")
	ui.start_practice();game.sim.holder=-1;game.sim.ball=Vector3(1200,700,0);game.sim.velocity=Vector3(20,-15,0)
	game.update_visuals(0);game.update_camera();ui.frame(0)
	var shot=ui.buttons.kick.get_global_rect().get_center()
	ui.touch_press(100,shot);ui.touch_drag(100,shot+Vector2(65,-35));ui.frame(0)
	game.perf.set_mode(2);ui.frame(0);await capture("preaim-performance-shown")
	check(ui.aim_id==100 and not game.experience.overlay.preview.trajectory.is_empty(),"rendered empty-handed shot has trajectory")
	ui.tools_panel.show();ui.set_tools_page(true)
	var toggle=ui.buttons.perf_toggle.get_global_rect().get_center()
	ui.touch_press(101,toggle);ui.touch_release(101,toggle);ui.frame(0)
	check(not game.perf.panel.visible and ui.buttons.perf_toggle.text=="显示性能" and ui.aim_id==100,"performance hides without interrupting another finger's preaim")
	ui.tools_panel.hide();await capture("preaim-performance-hidden");ui.tools_panel.show()
	ui.touch_press(102,toggle);ui.touch_release(102,toggle);ui.frame(0)
	check(game.perf.panel.visible and ui.aim_id==100,"performance reopens while preaim stays owned")
	ui.tools_panel.hide();ui.touch_release(100,shot+Vector2(65,-35))
	game.perf.set_mode(0);ui.frame(0);await capture("clean-gameplay")
	await check_pillar_render()
	await check_hook_render()
	FileAccess.open("res://research/mobile-aim-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("MOBILE AIM RENDER CHECKS ",passed," passed; ",failures.size()," failed")
	game.queue_free();await process_frame;await create_timer(0.2).timeout;quit(0 if failures.is_empty() else 1)
