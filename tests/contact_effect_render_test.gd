extends SceneTree
const Motion=preload("res://scripts/object_motion.gd")
var game
var passed=0
var failures=[]
var pixels={}
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func fresh(id="h005"):
	game.character_select.select(game.sim.Characters.IDS.find(id))
	game.touch_controls.start_practice();game.sim.bot_enabled=false
	var sim=game.sim
	sim.players[0].pos=Vector2.ZERO;sim.players[0].previous=Vector2.ZERO
	sim.players[1].pos=Vector2(70,0);sim.players[1].previous=Vector2(70,0)
	game.focus=Vector3.ZERO;game.zoom=.55;game.update_camera();game.update_visuals(0)
	return sim
func capture(name):
	game.touch_controls.frame(0)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image=root.get_texture().get_image()
	image.save_png("res://research/contact-effect-"+name+".png");return image
func contribution(model,name):
	var a=await capture(name)
	model.hide();game.original_effects.flush_particles()
	var b=await capture(name+"-hidden");var count=0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var c=a.get_pixel(x,y);var d=b.get_pixel(x,y)
			if absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b)>.04:count+=1
	pixels[name]=count;check(count>8,"actual rendered contribution "+name)
	model.show();game.original_effects.flush_particles()
func run():
	root.size=Vector2i(960,540)
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.set_process(false)
	# Source Object_collision uses a strict normal-speed threshold, not total speed.
	for speed in [0.0,29.9,30.0,49.9,50.1]:
		var hit=Motion.contact_flash(Vector3(speed,80,0),Vector3.ZERO,Vector3(10,20,40),Vector3(60,0,80))
		check(hit.is_empty()==(speed*.6<=30),"3D normal projection threshold "+str(speed))
	for speed in [29.9,30.0,30.01]:
		check(Motion.contact_flash(Vector3(speed,80,0),Vector3.ZERO,Vector3.ZERO,Vector3.RIGHT).is_empty()==(speed<=30),"exact strict threshold without tangent inflation "+str(speed))
	check(Motion.contact_flash(Vector3(100,0,0),Vector3.ZERO,Vector3.ZERO,Vector3.ZERO).is_empty(),"coincident centers have no spurious flash")
	var hit=Motion.contact_flash(Vector3(50,0,0),Vector3(-10,0,0),Vector3(10,20,40),Vector3(60,0,80))
	check(hit.pos==Vector3(40,20,40) and is_equal_approx(hit.facing,PI),"source XY midpoint retains initiating Z and opposite facing")
	check(hit.scale==.7 and hit.pitch==0,"original WarStomp scale and dummy sequence")
	var s=fresh();var rng=s.random.state
	s.players[0].knock=Vector2(50,0);s.start_object(0);s.step_object(0)
	var events=s.native_visuals.filter(func(e):return e.model=="fx_player_bump")
	check(events.size()==1,"real player collision publishes previously absent contact effect")
	check(is_equal_approx(s.players[1].knock.x,49.35) and s.players[0].knock.length()<.001,"effect preserves original momentum exchange after ground friction")
	check(s.random.state==rng,"collision presentation consumes no gameplay randomness")
	check(events[0].pos.is_equal_approx(Vector3(59.675,0,0)) and events[0].pitch==0,"event snapshots actual post-motion midpoint before exchange")
	game.update_visuals(0)
	var fx=game.original_effects
	var bumps=fx.bursts.filter(func(e):return e.model.data.actor.id=="fx_player_bump")
	check(bumps.size()==1,"actual main scene consumes contact event once")
	var model=bumps[0].model
	check(model.basis.y.normalized().is_equal_approx(Vector3.LEFT),"contact ring faces the incoming player rather than the sky")
	for i in range(18):game.update_visuals(1.0/60)
	await contribution(model,"player-contact")
	var time=model.animation_time;game.update_visuals(0)
	check(model.animation_time==time and fx.bursts.size()==1,"paused presentation neither advances nor duplicates contact")
	for i in range(180):game.update_visuals(1.0/60)
	check(not fx.bursts.any(func(e):return e.model==model),"one-shot contact drains and is released")
	for speed in [20.0,-50.0]:
		s=fresh();s.players[0].knock=Vector2(speed,0);s.step_object(0)
		check(not s.native_visuals.any(func(e):return e.model=="fx_player_bump"),"slow or separating contacts do not flash "+str(speed))
	s=fresh();s.players[1].pos=Vector2(-1000,-900)
	s.players[0].pos=Vector2(0,s.arena.half_size.y-12);s.players[0].knock=Vector2(0,40);s.step_object(0)
	var impacts=s.skill_effects.filter(func(e):return e.kind=="body_bump")
	check(impacts.size()==1 and absf(wrapf(impacts[0].facing+PI/2,-PI,PI))<.001,"top boundary retains outward contact facing")
	game.update_visuals(0)
	bumps=fx.bursts.filter(func(e):return e.model.data.actor.id=="fx_player_bump")
	check(bumps.size()==1 and bumps[0].model.basis.y.normalized().is_equal_approx(Vector3.BACK),"boundary flash uses source horizontal dummy orientation")
	s=fresh("h028");s.players[1].pos=Vector2(1600,700);s.take(0);s.step_ball()
	check(s.Characters.use(s,0,Vector2(1000,0)),"real AngelicKick executes")
	game.update_visuals(0);var angels=fx.bursts.filter(func(e):return e.model.data.actor.id=="fx_angelic_kick")
	check(angels.size()==1 and angels[0].model.basis.y.normalized().is_equal_approx(Vector3.RIGHT),"AngelicKick 0.50 dummy index truncates to zero")
	for i in range(18):game.update_visuals(1.0/60)
	await contribution(angels[0].model,"angel")
	for facing in [0.0,PI/2,PI]:
		s=fresh("h026");s.players[0].body=facing;s.Characters.smash(s,0);game.update_visuals(0)
		var smash=fx.bursts.filter(func(e):return e.model.data.actor.id=="fx_smash")
		check(smash.size()==3,"three original smash bursts "+str(facing))
		for i in range(3):
			var expected=Vector3.RIGHT if i<2 else Vector3(cos(facing+PI),0,-sin(facing+PI))
			check(smash[i].model.basis.y.normalized().is_equal_approx(expected),"Smash source facing "+str(facing)+" stage "+str(i))
			var offset=Vector2.from_angle(facing)*350*(i+1)/4.0
			check(smash[i].model.position.is_equal_approx(Vector3(offset.x,0,-offset.y)/100),"Smash quarter-segment position "+str(i))
		if facing==PI/2:
			for i in range(18):game.update_visuals(1.0/60)
			await capture("smash")
	s=fresh();check(fx.bursts.is_empty(),"new match clears all corrected effects")
	s.players[0].pos=Vector2(70,0);s.players[1].pos=Vector2(1600,900)
	var state=s.prepare_apocalypse();rng=s.random.state
	var external={"pos":Vector3.ZERO,"apoc_velocity":Vector3(50,0,0)}
	state.collide_players(external)
	check(state.visuals.size()==1 and state.visuals[0].model=="fx_player_bump" and state.visuals[0].pos==Vector3(35,0,0),"external-initiated contact also publishes source midpoint flash")
	check(external.apoc_velocity==Vector3.ZERO and s.players[0].knock==Vector2(50,0),"external contact preserves original exchange")
	check(s.random.state==rng,"explicit external contact facing avoids cosmetic gameplay RNG draw")
	s=fresh();s.players[0].pos=Vector2(2020,700);s.players[0].previous=s.players[0].pos
	s.players[1].pos=Vector2(-1000,-900);game.focus=Vector3(20.2,0,-7);game.zoom=.55;game.update_camera()
	s.apply_impulse(0,Vector3(50,40,0));game.update_visuals(0)
	bumps=fx.bursts.filter(func(e):return e.model.data.actor.id=="fx_player_bump")
	check(bumps.size()==1,"live force-addition flash reaches the renderer")
	for i in range(18):game.update_visuals(1.0/60)
	await contribution(bumps[0].model,"force-wall")
	check(game.perf.mode==0,"clean HUD remains hidden")
	FileAccess.open("res://research/contact-effect-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"pixels":pixels},"\t"))
	print("CONTACT EFFECT CHECKS ",passed," passed; ",failures.size()," failed")
	game.free();quit(0 if failures.is_empty() else 1)
