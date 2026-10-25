extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
const Characters=preload("res://scripts/character_rules.gd")
const Native=preload("res://scripts/native_rules.gd")
var checks=[]
var failed=false

func check(ok: bool,name: String,detail=""):
	checks.append({"test":name,"passed":ok,"detail":str(detail)})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))

func corridor(gap=128.0,blocker_radius=30.0):
	var s=Sim.new()
	s.players[0].pos=Vector2(-400,0);s.players[1].pos=Vector2.ZERO
	s.ball=Vector3(1400,900,0)
	s.players[1].radius=blocker_radius
	s.arena.add_box(Rect2(-1000,gap/2,2000,1500),200)
	s.arena.add_box(Rect2(-1000,-1500-gap/2,2000,1500),200)
	s.command(0,Vector2(400,0))
	for i in range(140):s.step_movement()
	return s

func advance_walk(s,steps=180):
	for i in range(steps):s.step_movement()

func seed_phase(s,index: int,state: String,value):
	# These route-only fixtures do not execute spell/Object callbacks. Seed
	# their explicit SetUnitPathing result as well as the unrelated skill data.
	s.players[index][state]=value
	if state!="possess_time":s.set_unit_pathing(index,value<=0)

func _initialize():call_deferred("run")

func run():
	var s=corridor()
	check(s.players[0].pos.x< -59.99 and s.players[0].want_move and s.players[0].path.is_empty(),"occupied narrow corridor leaves a pending move",s.players[0].pos)
	for state in ["tackle","flip_time","hooked","possess_time","flight_steps","z"]:
		s=corridor();seed_phase(s,1,state,120)
		advance_walk(s)
		check(s.players[0].pos.distance_to(Vector2(400,0))<=Native.MIN_POINT_STOP+0.001,"pending route resumes when stationary blocker changes "+state,s.players[0].pos)
	s=corridor();Characters.configure(s.players[1],"h004");s.set_sprint(1,true)
	advance_walk(s)
	check(s.players[0].pos.distance_to(Vector2(400,0))<=Native.MIN_POINT_STOP+0.001,"demon sprint removes stationary unit from pending route",s.players[0].pos)
	s=corridor();seed_phase(s,0,"flip_time",120)
	advance_walk(s)
	check(s.players[0].pos.distance_to(Vector2(400,0))<=Native.MIN_POINT_STOP+0.001,"owner becoming phased can traverse occupied corridor",s.players[0].pos)
	s=corridor(192,80);s.players[1].radius=5
	advance_walk(s,300)
	check(s.players[0].pos.distance_to(Vector2(400,0))<=Native.MIN_POINT_STOP+0.001,"smaller stationary blocker opens enough room to detour",s.players[0].pos)
	s=corridor();seed_phase(s,1,"z",120);s.command(0,Vector2(400,0))
	check(not s.players[0].path.is_empty() and s.players[0].route_status=="moving","same-target move sees changed collision eligibility immediately")
	for state in ["tackle","flip_time","hooked","possess_time","flight_steps","z"]:
		s=corridor();seed_phase(s,1,state,120);s.command(0,Vector2(400,0))
		var open_stamp=s.blocker_stamp(0)
		s.players[1][state]=119
		check(open_stamp==s.blocker_stamp(0),"nonblocking countdown/height does not dirty route "+state)
		seed_phase(s,1,state,0)
		advance_walk(s)
		check(s.players[0].pos.x<0 and s.players[0].pos.distance_to(s.players[1].pos)>=59.99 and s.players[0].want_move,"restored stationary collision blocks previously open route "+state,s.players[0].pos)
	s=corridor();s.stop(0);seed_phase(s,1,"tackle",640);advance_walk(s)
	check(not s.players[0].want_move and s.players[0].path.is_empty(),"stop discards pending route even when blocker disappears")
	s=corridor();seed_phase(s,1,"tackle",640)
	s.submit_command("move",0,Vector2(400,0));s.submit_command("move",0,Vector2(-600,0));advance_walk(s)
	check(s.players[0].pos.distance_to(Vector2(-600,0))<=Native.MIN_POINT_STOP+0.001,"rapid new target replaces old pending route after collision toggle",s.players[0].pos)
	s=corridor();seed_phase(s,0,"flip_time",120)
	check(s.free_point(s.players[1].pos,0) and s.segment(s.players[0].pos,s.players[1].pos,0),"phased owner point and sweep agree on occupied destination")
	seed_phase(s,0,"flip_time",0)
	check(not s.free_point(s.players[1].pos,0) and not s.segment(s.players[0].pos,s.players[1].pos,0),"restored owner point and sweep both reject occupied destination")
	s=corridor();seed_phase(s,0,"flip_time",120)
	check(not s.segment(s.players[0].pos,Vector2(-400,400),0),"removing unit collision does not remove practice terrain walls")
	# A partial destination inside a temporarily occupied own goal must recover
	# even when the keeper becomes absent without changing its XY coordinates.
	s=Sim.new();s.players[0].pos=Vector2(-1400,0);s.players[1].pos=Vector2(-2200,0);s.players[1].team=0
	s.command(0,Vector2(-2050,0));advance_walk(s,200)
	check(not s.arena.in_guard(s.players[0].pos,0) and s.players[0].want_move,"second defender waits outside occupied own goal")
	s.players[1].possess_time=5;advance_walk(s,120)
	check(s.players[0].pos.distance_to(Vector2(-2050,0))<=Native.MIN_POINT_STOP+0.001,"absent keeper frees goal without XY motion",s.players[0].pos)
	s=Sim.new();s.players[0].pos=Vector2(-1400,0);s.players[1].pos=Vector2(-2200,0);s.players[1].team=0
	s.command(0,Vector2(-2050,0));advance_walk(s,200)
	seed_phase(s,1,"tackle",640);advance_walk(s,120)
	check(not s.arena.in_guard(s.players[0].pos,0) and s.players[0].want_move,"phased but present keeper still reserves own goal")
	# Moving out of an overlapping tackle footprint must still route around
	# the wall instead of clearing it or dropping the explicit move order.
	s=Sim.new();s.players[1].pos=Vector2(1400,900);s.ball=Vector3(1400,-900,0)
	s.arena.add_box(Rect2(-5,-300,10,600),200)
	s.players[0].pos=Vector2(-60,0);s.players[0].body=0;s.players[0].tackle=640
	s.command(0,Vector2(600,0))
	for i in range(15):s.step_tackle(0)
	var min_x=s.players[0].pos.x;var detour=0.0;var tunneled=false
	for i in range(500):
		s.step_movement();detour=maxf(detour,absf(s.players[0].pos.y));min_x=minf(min_x,s.players[0].pos.x)
		if absf(s.players[0].pos.x)<5 and absf(s.players[0].pos.y)<300:tunneled=true
	check(not tunneled and detour>330 and min_x< -35 and s.players[0].pos.distance_to(Vector2(600,0))<=Native.MIN_POINT_STOP+0.001,"tackle overlapping wall escapes and resumes explicit route",s.players[0].pos)
	var a=corridor();var b=corridor()
	for sim in [a,b]:sim.players[1].possess_time=8
	for i in range(90):a.advance(1.0/30)
	for i in range(432):b.advance(1.0/144)
	check(a.players[0].pos.is_equal_approx(b.players[0].pos) and a.players[0].path==b.players[0].path,"state-triggered route repair agrees at 30 and 144 render FPS")
	var f=FileAccess.open("res://research/navigation-state-tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks},"\t"))
	quit(1 if failed else 0)
