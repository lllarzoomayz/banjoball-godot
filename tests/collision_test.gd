extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
const Native=preload("res://scripts/native_rules.gd")
var results=[]
var failed=false
func check(ok: bool,name: String,detail=""):
	results.append({"test":name,"passed":ok,"detail":detail})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))

func fresh():
	var s=Sim.new()
	s.players[0].pos=Vector2(-600,0)
	s.players[1].pos=Vector2(1200,900)
	return s

func _initialize():call_deferred("run")

func run():
	var started=Time.get_ticks_msec()
	var s=fresh()
	check(s.arena.boundaries.size()==18 and s.arena.data.terrain_blocked.is_empty(),"18 original boundary regions; no blocked terrain inside standard pitch")
	s.arena.add_box(Rect2(-5,-300,10,600),200)
	s.command(0,Vector2(600,0))
	var safe=true
	var detour=0.0
	for i in range(600):
		s.step_movement()
		var p: Vector2=s.players[0].pos
		if absf(p.x)<34.99 and absf(p.y)<300:safe=false
		detour=maxf(detour,absf(p.y))
	check(safe and detour>330 and s.players[0].pos.distance_to(Vector2(600,0))<=Native.MIN_POINT_STOP+0.001,"walk around thin wall without cutting corners",str(s.players[0].pos))
	s=fresh()
	s.set_course(2)
	s.players[0].pos=Vector2(200,0)
	s.command(0,Vector2(-600,0))
	var rightmost=0.0
	for i in range(1000):
		s.step_movement()
		rightmost=maxf(rightmost,s.players[0].pos.x)
	check(rightmost>549 and s.players[0].pos.distance_to(Vector2(-600,0))<=Native.MIN_POINT_STOP+0.001,"escape U-shaped wall via open end",str(s.players[0].pos))
	s=fresh()
	s.arena.add_box(Rect2(-80,-200,160,400),200)
	s.command(0,Vector2.ZERO)
	for i in range(180):s.step_movement()
	# The native partial node is chosen by strict cell distance, not by which
	# side of the rectangle the mover started on. Check access, not old routing.
	check(s.arena.point_free(s.players[0].pos,30) and absf(s.players[0].pos.x)>=109.99 and absf(s.players[0].pos.x)<160 and absf(s.players[0].pos.y)<80 and s.players[0].route_status!="arrived","click inside obstacle reaches accessible edge",str(s.players[0].pos))
	s.arena.obstacles.clear()
	s.arena.revision+=1
	for i in range(120):s.step_movement()
	check(s.players[0].pos.length()<=Native.MIN_POINT_STOP+0.001,"blocked destination resumes after wall removed",str(s.players[0].pos))
	s=fresh()
	s.command(0,Vector2(600,0))
	for i in range(20):s.step_movement()
	s.players[1].pos=Vector2(-200,0)
	safe=true
	for i in range(400):
		s.step_movement()
		if s.players[0].pos.distance_to(s.players[1].pos)<59.99:safe=false
	check(safe and s.players[0].pos.distance_to(Vector2(600,0))<=Native.MIN_POINT_STOP+0.001,"route repairs when unit moves into existing path",str(s.players[0].pos))
	s=fresh()
	s.players[1].pos=Vector2(600,0)
	s.command(0,Vector2(600,0))
	s.command(1,Vector2(-600,0))
	safe=true
	for i in range(800):
		s.step_movement()
		if s.players[0].pos.distance_to(s.players[1].pos)<59.99:safe=false
	check(safe and s.players[0].pos.x>580 and s.players[1].pos.x< -580,"opposing movers pass without overlap or deadlock",str(s.players[0].pos)+" / "+str(s.players[1].pos))
	for gap in [48,96]:
		s=fresh()
		s.arena.add_box(Rect2(-5,-1312,10,1312-gap/2.0),200)
		s.arena.add_box(Rect2(-5,gap/2.0,10,1312-gap/2.0),200)
		s.command(0,Vector2(600,0))
		for i in range(250):s.step_movement()
		check((s.players[0].pos.x< -34.99) if gap==48 else (s.players[0].pos.x>580),"radius-aware gap "+str(gap),str(s.players[0].pos))
	s=fresh()
	s.arena.add_box(Rect2(-5,-300,10,600),200)
	s.players[0].pos=Vector2(-60,0)
	s.players[0].body=0
	s.players[0].tackle=640.0
	for i in range(20):s.step_ball()
	check(s.players[0].pos.x< -5 and s.players[0].tackle==0,"phased tackle center cannot cross practice wall",str(s.players[0].pos))
	var wall_rest_position: Vector2=s.players[0].pos
	s.players[0].knock=Vector2(500,0)
	s.step_ball()
	check(s.players[0].pos.distance_to(wall_rest_position)<0.001,"inward impulse cannot tunnel from an already overlapping footprint",str(s.players[0].pos))
	s=fresh()
	s.players[0].pos=Vector2(-100,0)
	s.players[1].pos=Vector2(0,0)
	s.players[0].knock=Vector2(500,0)
	s.step_ball()
	check(absf(s.players[0].pos.x-399.35)<0.001 and s.players[1].knock==Vector2.ZERO,"original direct impulse checks units at endpoint rather than continuous sweep")
	s=fresh()
	s.players[0].pos=Vector2(-60,0)
	s.players[1].pos=Vector2.ZERO
	s.players[0].tackle=640.0
	var phased_overlap=false
	for i in range(40):
		s.step_ball()
		if s.players[0].pos.distance_to(s.players[1].pos)<59.99:phased_overlap=true
	check(phased_overlap and s.players[0].pos.distance_to(s.players[1].pos)>=59.99 and s.players[0].tackle==0,"point-blank tackle permits transient overlap then separates via original pushes")
	s=fresh()
	s.arena.add_box(Rect2(-5,-300,10,600),200)
	s.players[0].pos=Vector2(40,0)
	s.ball=Vector3(-40,0,0)
	s.step_ball()
	check(s.holder==-1,"cannot catch through a thin wall")
	s.players[0].pos=Vector2(-60,0)
	s.players[0].body=0
	s.take(0)
	s.step_ball()
	check(s.ball.x<=-29.99 and s.ball.x>=-60,"held ball offset clipped before wall",str(s.ball))
	s.kick(0,Vector2(1000,0))
	s.step_ball()
	check(s.ball.x< -29.99 and s.velocity.x<0,"shot from held contact bounces instead of spawning through wall",str(s.ball))
	s=fresh()
	s.arena.add_box(Rect2(-5,-300,10,600),200)
	s.players[0].pos=Vector2(-1200,-900)
	s.ball=Vector3(-200,0,50)
	s.velocity=Vector3(1000,0,0)
	s.step_ball()
	check(s.ball.x< -30 and s.velocity.x<0,"fast ball sweeps thin wall and travels remaining tick",str(s.ball))
	s=fresh()
	s.players[0].pos=Vector2(-1200,-900)
	s.arena.add_box(Rect2(-5,-300,10,600),65)
	s.ball=Vector3(-100,0,150)
	s.velocity=Vector3(200,0,0)
	s.step_ball()
	check(s.ball.x>90 and s.velocity.x>0,"high ball clears low obstacle")
	s.ball=Vector3(0,0,100)
	s.velocity=Vector3(0,0,-30)
	s.step_ball()
	check(s.ball.z>=90 and s.velocity.z>0,"descending ball hits obstacle top",str(s.ball))
	s=fresh()
	s.players[0].pos=Vector2.ZERO
	s.players[1].pos=Vector2(1200,900)
	s.ball=Vector3(-300,0,50)
	s.velocity=Vector3(600,0,0)
	s.step_ball()
	check(s.holder==0,"fast ball catches crossed player instead of tunnelling")
	s=fresh()
	s.ball=Vector3(2100,0,80)
	s.velocity=Vector3(900,0,0)
	s.step_ball()
	check(s.score[0]==1,"fast shot crossing whole goal scores once")
	s=fresh()
	s.ball=Vector3(2100,400,80)
	s.velocity=Vector3(900,0,0)
	s.step_ball()
	check(s.score[0]==0 and s.velocity.x<0,"outside goal opening cannot score")
	s=fresh()
	s.ball=Vector3(2200,0,350)
	s.velocity=Vector3(100,0,0)
	s.step_ball()
	check(s.score[0]==0 and s.velocity.x<0 and s.ball.x<2240,"original goal-height region blocks high shot")
	s=fresh()
	s.players[0].pos=Vector2(1500,0)
	s.command(0,Vector2(2400,0))
	for i in range(150):s.step_movement()
	check(not s.arena.in_guard(s.players[0].pos,1) and s.players[0].pos.distance_to(Vector2(2400,0))>400,"attacker cannot enter opposing protected goal area",str(s.players[0].pos))
	s=fresh()
	s.command(0,Vector2(-2300,0))
	for i in range(300):s.step_movement()
	check(s.players[0].pos.x< -2280,"defender can enter own goal corridor",str(s.players[0].pos))
	s.players.append(s.make_player(Vector2(-1400,0),0))
	s.command(2,Vector2(-2200,0))
	for i in range(150):s.step_movement()
	check(not s.arena.in_guard(s.players[2].pos,0),"second defender cannot occupy same goal area")
	var a=fresh()
	var b=fresh()
	for sim in [a,b]:
		sim.set_course(1)
		sim.submit_command("move",0,Vector2(900,0))
		sim.submit_command("sprint",0)
	for i in range(300):a.advance(1.0/30)
	for i in range(1440):b.advance(1.0/144)
	check(a.players[0].pos.distance_to(b.players[0].pos)<0.001 and a.ball.distance_to(b.ball)<0.001,"ordered local inputs + obstacle movement independent of render FPS")
	check(a.pending_commands.is_empty() and a.input_sequence==2,"local command queue consumes each input once")
	# The authored ball boundary is eighteen disjoint/overlapping regions.
	# Probe corner angles and large displacements for gaps and repeated contacts.
	var escaped=[]
	for height in [0,200,350]:
		for degrees in range(0,360,7):
			s=fresh()
			s.players[0].pos=Vector2(-3500,3500)
			s.players[1].pos=Vector2(3500,3500)
			s.ball=Vector3(0,0,height)
			var v=Vector2.from_angle(deg_to_rad(degrees))*650
			s.velocity=Vector3(v.x,v.y,0)
			for tick in range(40):
				s.step_ball()
				if not s.ball.is_finite() or absf(s.ball.x)>2850 or absf(s.ball.y)>1580:
					escaped.append([height,degrees,tick,str(s.ball)])
					break
				if s.reset_delay>0:break
	check(escaped.is_empty(),"156 high-speed trajectories stay within stadium or score",str(escaped.slice(0,3)))
	# Normal gameplay keeps pathing, holding and AI active together.
	for course in range(4):
		s=fresh()
		s.set_course(course)
		s.bot_enabled=true
		s.submit_command("move",0,Vector2(900,700))
		var valid=true
		for frame in range(1200):
			s.advance(1.0/60)
			for player in s.players:
				if not s.arena.point_free(player.pos,player.radius):valid=false
		check(valid,"20-second gameplay keeps unit footprints outside solids, course "+str(course))
	var f=FileAccess.open("res://research/collision-tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"passed":not failed,"elapsed_ms":Time.get_ticks_msec()-started,"tests":results},"\t"))
	quit(1 if failed else 0)
