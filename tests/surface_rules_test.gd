extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var checks=[]
var failed=false
func check(ok: bool,label: String,detail=""):
	checks.append({"test":label,"passed":ok,"detail":str(detail)})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+label+" "+str(detail))
func _initialize():call_deferred("run")
func scene(field: int,id="h005"):
	var s=Sim.new();s.selected_field=field;s.selected_character=id;s.start_practice()
	s.players[0].pos=Vector2.ZERO;s.players[0].previous=Vector2.ZERO;s.players[1].pos=Vector2(1700,1000)
	s.ball=Vector3(1300,-1000,0)
	return s
func copy_ball(s,position=Vector3(0,-600,0)):
	var c={"id":1,"creator":1,"team":1,"holder":-1,"last_owner":1,"position":position,"previous":position,"velocity":Vector3(30,0,0),"intercept":0,"life":10.0}
	s.fake_balls.append(c)
	return c
func advance_frames(s,seconds: float,fps: int):
	var left=seconds
	while left>0.00000001:
		var dt=minf(left,1.0/fps);s.advance(dt);left-=dt
func run():
	var s
	for field in range(4):
		s=scene(field);s.ball=Vector3(0,-800,0);s.velocity=Vector3(30,0,0);var c=copy_ball(s)
		for i in range(20):s.step_ball()
		var ice=field>=2
		var expected_speed=24.0 if ice else 21.0
		var expected_distance=537.0 if ice else 505.5
		check(absf(s.velocity.x-expected_speed)<0.0001 and absf(s.ball.x-expected_distance)<0.002,"field "+str(field)+" true ball obeys original ground-friction arithmetic",[s.ball.x,s.velocity.x])
		check(c.velocity.distance_to(s.velocity)<0.0001 and absf(c.position.x-s.ball.x)<0.001,"field "+str(field)+" fake and true ball share surface friction")
		s=scene(field);s.players[0].knock=Vector2(10,0);s.step_object_impulses()
		check(absf(s.players[0].pos.x-(9.6 if ice else 9.35))<0.00001,"field "+str(field)+" applies correct player ground drag before displacement")
		s.players[0].knock=Vector2(10,0);s.players[0].z=100;s.players[0].vz=5;s.step_object_impulses()
		var air=Vector3(10,0,3.5)
		check(Vector3(s.players[0].knock.x,s.players[0].knock.y,s.players[0].vz).distance_to(air.normalized()*(air.length()-0.08))<0.00001,"field "+str(field)+" preserves ordinary airborne player friction and gravity")
		s=scene(field);s.ball=Vector3(0,-800,100);s.velocity=Vector3(30,0,8);s.step_ball()
		var ball_air=Vector3(30,0,6.5)
		check(s.velocity.distance_to(ball_air.normalized()*(ball_air.length()-0.07))<0.00001,"field "+str(field)+" preserves airborne ball physics")
		s=scene(field);s.command(0,Vector2(10000,0))
		for i in range(20):s.step_object_impulses()
		check(absf(s.players[0].knock.x-(6.0 if ice else 0.0))<0.0001 and absf(s.players[0].pos.x-(63.0 if ice else 0.0))<0.001,"field "+str(field)+" smart order adds ice impulse independently of native walking",[s.players[0].pos,s.players[0].knock])
		if ice:
			var start=s.players[0].pos;s.stop(0)
			for i in range(20):s.step_object_impulses()
			check(not s.players[0].slide_order and not s.players[0].want_move and s.players[0].knock==Vector2.ZERO and absf(s.players[0].pos.x-start.x-42.0)<0.001,"stop cancels ice thrust while retaining a forty-two-unit stopping distance "+str(field))
	s=scene(2);var p=s.players[0];p.body=PI/2;p.angle=0;s.command(0,Vector2(900,0));s.step_object_impulses()
	check(absf(p.knock.x)<0.00001 and absf(p.knock.y-0.3)<0.00001,"ice push uses displayed facing, not target direction or route heading")
	s=scene(2);p=s.players[0];p.angle=PI;p.body=PI;s.command(0,Vector2(900,0));s.step_movement();s.step_object_impulses()
	check(not p.moving and p.slide_order,"order latch is independent of animation movement flag")
	s=scene(2);p=s.players[0];s.command(0,Vector2(2000,0));p.knock=Vector2(19.9,0);s.step_object_impulses()
	check(absf(p.knock.x-20.2)<0.00001,"ice threshold permits one push beyond twenty rather than clamping it")
	s.step_object_impulses()
	check(absf(p.knock.x-19.8)<0.00001,"velocity at or above threshold only loses friction this step")
	s=scene(2);p=s.players[0];s.command(0,Vector2(2000,0));p.z=100;p.vz=20;s.step_object_impulses()
	check(p.knock==Vector2.ZERO and absf(p.vz-18.42)<0.00001,"vertical velocity counts toward the full three-dimensional ice threshold")
	p.knock=Vector2.ZERO;p.vz=0;s.step_object_impulses()
	check(p.knock.x>0.6 and p.vz< -1.4,"smart-order ice thrust can act in the air, as in original Object loop")
	s=scene(2);p=s.players[0];s.command(0,Vector2(100,0));s.step_object_impulses()
	check(not p.slide_order and p.want_move and absf(p.pos.x-0.3)<0.00001,"hundred-unit arrival check runs after final thrust without canceling native walk order")
	s.step_object_impulses();check(p.knock==Vector2.ZERO,"no new thrust is added after arrival latch clears")
	s=scene(2);p=s.players[0];s.command(0,Vector2(100.1,0));s.step_object_impulses()
	check(p.slide_order,"point just outside hundred-unit arrival radius keeps thrust active")
	s=scene(2);p=s.players[0];s.command(0,Vector2(10,0));p.knock=Vector2(21,0);s.step_object_impulses()
	check(p.slide_order and absf(p.knock.x-20.6)<0.00001,"arrival enumeration is skipped when speed threshold prevents a new thrust")
	s=scene(2);s.players[1].pos=Vector2(0,60);s.players.append(s.make_player(Vector2(0,-60),1))
	s.command(0,Vector2(50,0));s.command(1,Vector2(700,60));s.command(2,Vector2(0,-60))
	s.SurfaceRules.accelerate(s,0)
	check(not s.players[0].slide_order and s.players[1].slide_order and not s.players[2].slide_order,"shared arrival scan checks each nearby player's own target")
	s=scene(2);p=s.players[0];s.command(0,Vector2(900,0));s.set_sprint(0,true)
	check(not p.slide_order and p.want_move,"issuing sprint toggle cancels ice thrust without clearing locomotion")
	s.command(0,Vector2(900,0));s.set_sprint(0,true)
	check(p.slide_order,"unchanged AI sprint setting is not a new order")
	s.set_sprint(0,false);check(not p.slide_order,"sprint-off order also cancels ice thrust")
	var demon=scene(2,"h004");demon.set_sprint(0,true);demon.command(0,Vector2(900,0));demon.players[0].knock=Vector2.ZERO;demon.Characters.step(demon)
	check(not demon.players[0].sprint and not demon.players[0].slide_order,"low-speed automatic demon sprint-off order also clears ice thrust")
	s.command(0,Vector2(900,0));s.take(0);s.ball=s.Copies.held_position(s,0);s.kick(0,Vector2(1800,0))
	check(not p.slide_order,"normal kick cancels ice thrust")
	var c=copy_ball(s);s.Copies.take(s,c,0);s.command(0,Vector2(900,0));s.kick(0,Vector2(1800,0))
	check(not p.slide_order and c.holder==-1,"fake kick cancels ice thrust through same order rule")
	for id in ["h00Y","h00P","h005","h01I","h01R","h027"]:
		s=scene(2,id);s.command(0,Vector2(900,0));s.Characters.use(s,0,Vector2(900,0))
		check(not s.players[0].slide_order,"ability order clears smart-order thrust for "+id)
	s=scene(2,"h00F");s.take(0);s.ball=s.Copies.held_position(s,0);s.Characters.use(s,0,Vector2(1500,0));s.command(0,Vector2(900,0));s.step_object_impulses()
	check(s.players[0].ability_delay>0 and not s.players[0].slide_order and s.players[0].knock==Vector2.ZERO,"smart order during charge dispatches nested stop, clearing ice thrust while retaining charge")
	s=scene(2);s.tackle(0,Vector2(1000,0));s.command(0,Vector2(1000,0));s.advance(0.12)
	check(s.players[0].tackle>0 and s.players[0].knock.x>0 and s.players[0].pos.x>44.6*3,"new smart order during tackle adds ice drift to scripted tackle movement")
	s=scene(2);p=s.players[0];s.arena.add_box(Rect2(80,-300,20,600),240);s.command(0,Vector2(900,0));p.knock=Vector2(19,0)
	for i in range(8):s.step_object_impulses()
	check(p.pos.x<=50.001 and not s.arena.sweep_unit(p.pos,Vector2.ZERO,30).has("t"),"ice inertia cannot cross a solid practice wall",p.pos)
	s=scene(2);p=s.players[0];s.arena.add_pillar(Vector2(120,0),1);p.knock=Vector2(19,0)
	for i in range(3):s.step_object_impulses()
	check(p.knock.x<0 and p.pos.x<30,"ice inertia reflects from totem through existing object collision")
	s=scene(2);p=s.players[0];p.pos=Vector2(1500,0);p.knock=Vector2(19,0)
	for i in range(40):s.step_object_impulses()
	check(not s.arena.in_guard(p.pos,1),"ice slide cannot enter opponent protected goalkeeper area")
	for field in [2,3]:
		s=scene(field);s.ball=Vector3(0,-800,0);s.velocity=Vector3(30,0,0);c=copy_ball(s);s.powershot_active=true;s.step_ball()
		check(absf(s.velocity.x-29.98)<0.0001 and absf(c.velocity.x-29.98)<0.0001,"powershot overrides ice for both balls "+str(field))
		s.take(1);s.Copies.step(s)
		check(not s.powershot_active and absf(c.velocity.x-29.68)<0.0001,"ending powershot restores ice rather than grass friction "+str(field))
		s.reset();s.command(0,Vector2(900,0));s.advance(0.2);s.selected_field=0;s.start_practice();s.command(0,Vector2(1000,0));s.step_object_impulses()
		check(not s.SurfaceRules.icy(s) and s.SurfaceRules.ball_friction(s)==0.45 and s.players[0].knock==Vector2.ZERO,"switching from ice to grass clears accumulated slide state "+str(field))
	var grass_curve=scene(0,"h012");var ice_curve=scene(2,"h012")
	for world in [grass_curve,ice_curve]:world.take(0);world.ball=world.Copies.held_position(world,0);world.Characters.use(world,0,Vector2(1500,0))
	check(grass_curve.velocity.distance_to(ice_curve.velocity)<0.00001,"curve launch keeps original map-initialized coefficients on both surfaces")
	grass_curve.step_ball();ice_curve.step_ball()
	check(absf(ice_curve.velocity.length()-grass_curve.velocity.length()-0.15)<0.00001,"ice alters subsequent curve ground friction without recalibrating the original launch")
	var slow=scene(2);var fast=scene(2)
	for world in [slow,fast]:world.arena.add_box(Rect2(300,-200,80,400),240);world.command(0,Vector2(1400,300))
	advance_frames(slow,1.5,30);advance_frames(fast,1.5,144)
	slow.stop(0);fast.stop(0);advance_frames(slow,0.75,30);advance_frames(fast,0.75,144)
	slow.command(0,Vector2(-300,-600));fast.command(0,Vector2(-300,-600));advance_frames(slow,1.5,30);advance_frames(fast,1.5,144)
	check(slow.players[0].pos.distance_to(fast.players[0].pos)<0.001 and slow.players[0].knock.distance_to(fast.players[0].knock)<0.001 and slow.players[0].slide_order==fast.players[0].slide_order,"ice routing braking and direction changes are independent of render frame rate")
	s=scene(2);s.command(0,Vector2(1000,0));s.advance(0.2);s.reset()
	check(s.players.all(func(player):return not player.slide_order and player.knock==Vector2.ZERO) and s.SurfaceRules.icy(s),"round restart clears motion but retains chosen ice surface")
	for field in [2,3]:
		s=scene(field);s.mixed_roster=true;s.start_match(6);s.controlled=-1
		var finite=true;var within=true
		for tick in range(600):
			s.advance(0.05)
			for player in s.players:
				finite=finite and player.pos.is_finite() and player.knock.is_finite() and is_finite(player.z)
				within=within and s.arena.bounds.grow(1).has_point(player.pos)
		check(finite and within,"twelve-player mixed skills stay finite and bounded on ice "+str(field),s.score)
	FileAccess.open("res://research/surface-tests.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks},"\t"))
	quit(1 if failed else 0)
