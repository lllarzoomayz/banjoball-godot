extends SceneTree
const Model=preload("res://scripts/wc3_model.gd")
var game
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func capture(name: String):
	game.touch_controls.frame(0)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/buff-047-"+name+".png")
func setup_character(id: String):
	game.character_select.select(game.sim.Characters.IDS.find(id));game.character_select.item_selected.emit(game.character_select.selected)
	game.touch_controls.start_practice()
	check(game.sim.players[0].character==id,"selected actual runtime character "+id)
	game.sim.bot_enabled=false;game.sim.players[0].pos=Vector2.ZERO;game.sim.players[0].previous=Vector2.ZERO
	game.sim.players[1].pos=Vector2(1600,700);game.sim.players[1].previous=Vector2(1600,700)
	game.focus=Vector3.ZERO;game.zoom=0.55;game.update_camera();game.update_visuals(0)
func buff_count() -> int:
	return game.original_effects.persistent.keys().filter(func(k):return k.begins_with("buff:")).size()
func check_shadow():
	setup_character("h01I")
	var s=game.sim;var p=s.players[0]
	p.body=PI/2;p.previous_body=PI/2;p.angle=PI/2
	var origin=s.Characters.world_position(p)
	s.Characters.use(s,0,Vector2.ZERO);s.advance(.55);game.update_visuals(.02)
	check(p.shadow_return>0 and p.pos.distance_to(Vector2(origin.x,origin.y))>300,"real shadow cast displaces actor")
	check(s.skill_effects.any(func(e):return e.kind=="blink" and e.pos==origin),"departure smoke is at pre-teleport source position")
	check(game.original_effects.persistent.has("shadow:0"),"original gray recall ghost appears")
	var ghost=game.original_effects.persistent["shadow:0"]
	check(ghost.data.actor.id=="h02B" and ghost.position==Vector3.ZERO and is_equal_approx(ghost.rotation.y,PI/2),"ghost uses source model, saved origin and facing")
	check(is_equal_approx(ghost.fade_alpha,128.0/255) and ghost.tint.is_equal_approx(Color(128.0/255,128.0/255,128.0/255)),"ghost retains original gray RGBA")
	check(game.original_effects.persistent.has("buff:0:shadow_trail"),"permanent original chest trail is attached")
	game.touch_controls.frame(0);await capture("shadow")
	var departure=s.Characters.world_position(p)
	s.Characters.use(s,0,Vector2.ZERO);game.update_visuals(.02)
	check(not game.original_effects.persistent.has("shadow:0") and p.pos.length()<1,"recall returns actor and removes ghost")
	check(s.skill_effects.any(func(e):return e.kind=="blink" and e.pos==departure),"recall smoke stays at its departure point")
	setup_character("h01I");s=game.sim;p=s.players[0]
	s.Characters.use(s,0,Vector2.ZERO);s.advance(.55);game.update_visuals(.02)
	var emitted=s.next_visual;s.advance(2.6);game.update_visuals(.02)
	check(not game.original_effects.persistent.has("shadow:0"),"expired recall removes gray ghost")
	check(s.native_visuals.filter(func(e):return e.id>emitted and e.model=="fx_shadow").size()==1,"expiry emits exactly one original cleanup burst")
	s.advance(1);check(s.native_visuals.filter(func(e):return e.id>emitted and e.model=="fx_shadow").size()==1,"expiry burst never repeats")
	setup_character("h005")
	game.sim.emit_visual("fx_ball_bump",Vector3(0,0,300),1.0,PI/2)
	for i in range(8):game.update_visuals(1.0/60)
	check(game.original_effects.bursts.any(func(e):return e.model.data.actor.id=="fx_ball_bump" and e.model.mesh_nodes.any(func(n):return n.visible)),"high ball impact has visible source geometry")
	await capture("high-ball-impact")
func check_rift():
	setup_character("h027")
	var s=game.sim
	check(s.Characters.use(s,0,Vector2(600,100)),"first portal cast accepted")
	var r=s.players[0].rift
	for i in range(50):
		s.advance(1.0/32);game.update_visuals(1.0/32)
		if r.a!=null:break
	check(r.a!=null and game.rift_models.size()==1,"projectile landing creates first original portal")
	check(game.original_effects.bursts.any(func(e):return e.model.data.actor.id=="h02A" and e.model.active_clip.to_lower().begins_with("death")),"landing projectile runs its native Death clip")
	s.advance(1.6);game.update_visuals(.4)
	check(s.Characters.use(s,0,Vector2(-600,100)),"second portal cast accepted")
	for i in range(50):
		s.advance(1.0/32);game.update_visuals(1.0/32)
		if r.b!=null:break
	check(r.b!=null and game.rift_models.size()==2,"second original portal appears")
	check(is_equal_approx(game.rift_models[str(r.id)+"a"].scale.x,.75) and game.rift_models[str(r.id)+"b"].scale.x<.1,"first portal does not shrink when second lands")
	var link=game.original_effects.rift_link(r)
	check(is_equal_approx(link.a.distance_to(r.a),50) and is_equal_approx(link.b.distance_to(r.b),50),"lightning joins original inner ring edges")
	for i in range(20):s.advance(1.0/32);game.update_visuals(1.0/32)
	await capture("rift-open")
	s.Characters.Complex.rift_finish(s,r);s.advance(1.0/32);game.update_visuals(0)
	check(game.rift_models.is_empty() and game.dying_rifts.size()==2,"portal closure retains two native death animations")
	check(game.dying_rifts.all(func(e):return e.model.active_clip.to_lower().begins_with("death") and is_equal_approx(e.model.rate,2.5)),"portal death runs at original 2.5x rate")
	game.update_visuals(.2);await capture("rift-closing")
	game.update_visuals(2.1)
	check(game.dying_rifts.is_empty(),"closed portals are removed after two seconds")
	s.reset();game.update_visuals(0)
	check(game.rift_models.is_empty() and game.dying_rifts.is_empty(),"reset clears portal render state")
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.set_process(false)
	var refs=JSON.parse_string(FileAccess.get_file_as_string("res://research/attachment-source-reference.json"))
	# One native world unit tolerance: the renderer decomposes sampled bone
	# matrices into TRS; the largest observed discrepancy is <0.8 native units.
	var models={}
	# Compare unbillboarded source transforms in a camera-free world. The
	# following game scenes exercise actual camera-facing attachments too.
	var reference_world=SubViewport.new();reference_world.own_world_3d=true;reference_world.size=Vector2i(8,8);root.add_child(reference_world)
	for row in refs:
		if not models.has(row.actor):
			var model=Model.new();reference_world.add_child(model);model.load_actor(row.actor,Color.WHITE);models[row.actor]=model
		var actor=models[row.actor];actor.play(row.clip,true);actor.advance(row.time)
		var expected=Vector3(row.local[0],row.local[1],row.local[2])
		check(actor.to_local(actor.attachment_transform(row.attachment).origin).distance_to(expected)<0.01,"MDX attachment "+row.actor+" "+row.clip+" "+row.attachment)
	for actor in models.values():actor.free()
	reference_world.queue_free()
	for id in ["h005","h004","h00R","h028","h026","h010"]:
		setup_character(id);game.sim.set_sprint(0,true)
		for i in range(45):
			game.sim.players[0].moving=true;game.sim.players[0].pos=Vector2(i*3,0);game.sim.players[0].previous=game.sim.players[0].pos
			game.update_visuals(1.0/60)
		var expected=1 if id in ["h004","h010"] else 2
		check(buff_count()==expected,"native sprint attachment count "+id)
		var before={}
		for key in game.original_effects.persistent:
			if not key.begins_with("buff:"):continue
			var fx=game.original_effects.persistent[key]
			check(fx.active_clip.to_lower().begins_with("stand"),"birth transitions into Stand "+id)
			check((fx.ribbons.emitters[0].sections.size()>1 if id=="h00R" else fx.particles.particle_count()>0),"original active particles or ribbon emitted "+id)
			before[key]=fx.global_position
		await capture(id)
		game.sim.players[0].pos=Vector2(200,100);game.sim.players[0].previous=Vector2(200,100)
		game.sim.players[0].body=PI/2;game.sim.players[0].previous_body=PI/2;game.sim.players[0].moving=true
		game.update_visuals(.1)
		for key in before:
			var fx=game.original_effects.persistent[key]
			check(fx.global_position.distance_to(before[key])>0.5,"attachment follows translation and turn "+id)
		game.sim.set_sprint(0,false);game.update_visuals(.01)
		check(buff_count()==0,"stopping sprint removes attached effect "+id)
		for i in range(240):game.update_visuals(1.0/30)
		check(game.original_effects.bursts.is_empty(),"sprint death tails finish "+id)
	setup_character("h005")
	var p=game.sim.players[0];p.slow=1.5;p.ogre_slow=1;p.stun=1.5;p.silence=.55
	for i in range(40):game.update_visuals(1.0/60)
	check(buff_count()==4,"all native slow stun silence states render")
	await capture("status")
	p.slow=0;p.ogre_slow=0;p.stun=0;p.silence=0;game.update_visuals(0)
	check(buff_count()==0,"status expiry removes every persistent attachment")
	setup_character("h00R");game.sim.set_sprint(1,true);game.update_visuals(.1)
	check(game.original_effects.persistent.keys().any(func(k):return k.begins_with("buff:1:")),"enemy sprint initially visible")
	game.sim.players[1].invisible=true;game.update_visuals(.1)
	check(not game.original_effects.persistent.keys().any(func(k):return k.begins_with("buff:1:")),"enemy invisibility hides attached particles")
	check(game.original_effects.bursts.is_empty(),"enemy invisibility leaves no revealing death trail")
	game.sim.set_sprint(0,true);game.sim.players[0].invisible=true;game.update_visuals(.1)
	check(game.original_effects.persistent["buff:0:sprint_left"].visibility_amount==.4,"friendly stealth effect shares actor fade")
	var rng=game.sim.random.state
	game.update_visuals(.2);check(game.sim.random.state==rng,"attachments never consume gameplay RNG")
	var fx=game.original_effects.persistent["buff:0:sprint_left"];var clock=fx.animation_time
	game.update_visuals(0);check(fx.animation_time==clock,"pause freezes attached effect animation")
	game.sim.reset();game.update_visuals(0)
	check(buff_count()==0 and game.original_effects.bursts.is_empty(),"reset clears all buff effects")
	await check_shadow()
	await check_rift()
	FileAccess.open("res://research/buff-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("BUFF RENDER CHECKS ",passed," passed; ",failures.size()," failed")
	game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
