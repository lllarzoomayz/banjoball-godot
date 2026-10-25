extends SceneTree
const Motion=preload("res://scripts/object_motion.gd")
const Sfx=preload("res://scripts/sfx_rules.gd")
var game
var passed=0
var failures=[]
var pixels={}
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func fresh(field=0):
	game.field_select.select(field);game.touch_controls.start_practice();game.sim.bot_enabled=false
	game.sim.players[1].pos=Vector2(1500,900);game.sim.players[1].previous=Vector2(1500,900)
	game.sim.players[0].pos=Vector2.ZERO;game.sim.players[0].previous=Vector2.ZERO
	game.update_visuals(0);return game.sim
func capture(name):
	game.touch_controls.frame(0)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var im=root.get_texture().get_image();im.save_png("res://research/landing-"+name+".png");return im
func difference(a,b):
	var count=0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var c=a.get_pixel(x,y);var d=b.get_pixel(x,y)
			if absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b)>.04:count+=1
	return count
func run():
	root.size=Vector2i(960,540)
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.set_process(false)
	var native=JSON.parse_string(FileAccess.get_file_as_string("res://research/native-fly-height-checks.json"))
	check(native.engine_sha256=="e04d1716603c075eb0c8e1e21cf1093a664adc5249efab396bfa08d7b09d0c3a","clamp reference is the verified local 1.27 engine")
	for row in native.checks:
		check(row.passed and is_equal_approx(Sfx.fly_height(row.input_height),row.actual.height),"ported clamp matches executed wrapper "+str(row.input_height))
	for speed in [-80.0,-30.01,-30.0,-29.99,0.0,50.0]:
		var hit=Motion.landing_flash(Vector2(25,60),speed,1024)
		check(hit.is_empty()==(speed>=-30),"strict incoming vertical threshold "+str(speed))
		if not hit.is_empty():check(hit.pos==Vector3(25,60,-1024) and hit.pitch==90 and hit.scale==.7 and hit.facing==0,"source absolute zero and upward dummy preserved")
	for ground in [-2048.0,-100.0,0.0,1024.0,2000.0]:
		var p=Sfx.terrain_position(Vector3(10,20,0),ground)
		check(is_equal_approx(p.z,0.0 if ground<0 else ground+.01) and p.x==10 and p.y==20,"absolute zero request resolved against ground "+str(ground))
	for field in range(4):
		var sim=fresh(field);var p=sim.players[0]
		p.pos=Vector2(-1280,-960) if field==1 else Vector2.ZERO;p.previous=p.pos
		p.z=10;p.previous_z=10;p.vz=-45
		var expected=sim.Skills.object_velocity(p.z,Vector3(0,0,p.vz),sim.SurfaceRules.player_friction(sim));var rng=sim.random.state
		sim.start_object(0);sim.step_object(0)
		var events=sim.native_visuals.filter(func(e):return e.get("sfx_clamp_to_terrain",false))
		check(events.size()==1,"live player landing emits once on field "+str(field))
		check(p.z==0 and is_equal_approx(p.vz,-expected.z-15) and p.knock==Vector2.ZERO,"landing visual preserves rebound velocity "+str(field))
		check(sim.random.state==rng,"landing consumes no gameplay randomness "+str(field))
		game.focus=Vector3(p.pos.x/100,0,-p.pos.y/100);game.zoom=.55;game.update_camera();game.update_visuals(0)
		var fx=game.original_effects;var entries=fx.bursts.filter(func(e):return e.model.data.actor.id=="fx_player_bump")
		check(entries.size()==1,"landing enters real renderer "+str(field))
		var model=entries[0].model;var ground=game.field_scenery.height_at(p.pos)
		check(is_equal_approx(model.position.y,(ground+.01)/100) and model.basis.y.normalized().is_equal_approx(Vector3.UP),"landing ring uses rendered terrain and upward orientation "+str(field))
		if field==1:check(ground<0,"Waterfall test covers source terrain below the flat simulation plane")
		for i in range(18):game.update_visuals(1.0/60)
		var shown=await capture("field-"+str(field));model.hide();fx.flush_particles();var hidden=await capture("field-"+str(field)+"-hidden")
		pixels[str(field)]=difference(shown,hidden);check(pixels[str(field)]>20,"original WarStomp contributes pixels "+str(field));model.show();fx.flush_particles()
		var age=model.animation_time;game.update_visuals(0);game.update_visuals(0)
		check(model.animation_time==age and fx.bursts.size()==1,"pause neither advances nor repeats landing "+str(field))
		for i in range(180):game.update_visuals(1.0/60)
		check(fx.bursts.is_empty(),"landing effect and tails drain "+str(field))
	for scenario in ["slow","airborne","rising","exact_floor"]:
		var sim=fresh();var p=sim.players[0]
		p.z=5;p.vz=-10
		if scenario=="airborne":p.z=300;p.vz=-45
		if scenario=="rising":p.z=10;p.vz=45
		if scenario=="exact_floor":
			p.z=100;p.vz=-45
			var velocity=sim.Skills.object_velocity(p.z,Vector3(0,0,p.vz),sim.SurfaceRules.player_friction(sim));p.z=-velocity.z
		sim.start_object(0);sim.step_object(0)
		check(not sim.native_visuals.any(func(e):return e.get("sfx_clamp_to_terrain",false)),"no false landing flash: "+scenario)
	var sim=fresh();sim.holder=-1;sim.ball=Vector3(500,0,10);sim.velocity=Vector3(0,0,-60);sim.step_ball()
	check(not sim.native_visuals.any(func(e):return e.get("sfx_clamp_to_terrain",false)),"ball landing never emits PLAYER landing ring")
	check(game.perf.mode==0,"landing keeps the clean HUD")
	FileAccess.open("res://research/landing-effect-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"pixels":pixels},"\t"))
	print("LANDING EFFECT CHECKS ",passed," passed; ",failures.size()," failed")
	game.free();quit(0 if failures.is_empty() else 1)
