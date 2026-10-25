extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok: bool,label: String):
	if ok:passed+=1
	else:failures.append(label);printerr("FAIL "+label)
func fresh():
	var s=Sim.new();s.start_practice();s.bot_enabled=false
	var p=s.players[0];p.pos=Vector2.ZERO;p.previous=p.pos;p.angle=0;p.body=0
	s.players[1].pos=Vector2(1500,900);s.take(0);return s
func request(s,angle: float):
	s.submit_command("kick",0,Vector2(s.ball.x,s.ball.y)+Vector2.from_angle(angle)*1600)
func run():
	for angle in [0.0,PI/2,-PI/2,PI,2.4,-2.4]:
		var s=fresh();var p=s.players[0]
		s.submit_command("move_direction",0,Vector2.RIGHT);s.advance(.15)
		var start: Vector2=p.pos;request(s,angle);s.consume_commands()
		if angle!=0:check(s.holder==0,"side/back shot waits for turn "+str(angle))
		var released=false;var paused=true;var fire_error=0.0;var fire_time=0.0
		for tick in range(50):
			# A held stick continues delivering move orders, including after the shot.
			s.submit_command("move_direction",0,Vector2.RIGHT);s.advance(.03)
			if s.holder!=0:
				released=true;fire_error=absf(wrapf(p.body-angle,-PI,PI));fire_time=float(tick+1)*.03;break
			paused=paused and p.pos.distance_to(start)<.001
		check(released,"shot eventually fires "+str(angle))
		check(paused,"turning suspends active walking "+str(angle))
		if angle!=0:check(fire_error<=s.ShotOrder.HALF_ANGLE+.001,"visible facing is ready at release "+str(angle)+" error="+str(fire_error))
		check(Vector2(s.velocity.x,s.velocity.y).normalized().dot(Vector2.from_angle(angle))>.999,"locked aim direction survives ball orbit "+str(angle))
		var after: Vector2=p.pos
		s.advance(.5);check(p.pos.x>after.x+30,"held stick resumes after release "+str(angle)+" turn_seconds="+str(fire_time))
	var s=fresh();var p=s.players[0]
	s.submit_command("move_direction",0,Vector2.RIGHT);request(s,PI);s.advance(.06)
	s.submit_command("move_release",0);s.advance(1)
	check(s.holder==-1 and p.pos==Vector2.ZERO and p.direct_axis==Vector2.ZERO,"lifting stick during turn preserves shot and prevents automatic walking")
	s=fresh();p=s.players[0];s.submit_command("move_direction",0,Vector2.RIGHT);request(s,PI);s.advance(.06)
	s.submit_command("move_direction",0,Vector2.UP);s.advance(1)
	check(s.holder==-1 and p.pos.y< -50 and absf(p.pos.x)<.01,"latest stick direction is used after shot")
	for replacement in ["stop","move","move_order"]:
		s=fresh();p=s.players[0];request(s,PI);s.advance(.06);s.submit_command(replacement,0,Vector2(500,0));s.advance(1)
		check(s.holder==0 and p.get("shot_order",{}).is_empty(),"explicit "+replacement+" cancels uncast shot")
	s=fresh();p=s.players[0];request(s,PI);s.advance(.06);s.take(1);s.take(0);s.advance(1)
	check(s.holder==0 and p.get("shot_order",{}).is_empty(),"losing then regaining possession cannot fire a stale shot")
	s=fresh();p=s.players[0];request(s,PI);s.advance(.06);p.stun=.2;s.advance(1)
	check(s.holder==0 and p.get("shot_order",{}).is_empty(),"stun interrupts pending shot without late release")
	s=fresh();s.holder=-1;request(s,PI);s.advance(.06);s.take(0);s.advance(1)
	check(s.holder==0,"empty-handed command never waits for a future catch")
	s=fresh();s.players[1].pos=Vector2(0,80);s.take(0);request(s,PI*.75);s.advance(.8)
	check(s.holder==1 and s.players[0].shot_order.is_empty(),"turning held ball remains stealable and stolen ball cannot shoot")
	s=fresh();p=s.players[0];s.Copies.create(s,0,false,Vector2(1600,0));var copy=s.Copies.held(s,0)
	s.submit_command("kick",0,Vector2(copy.position.x-1600,copy.position.y));s.advance(.03)
	check(copy.holder==0 and not p.shot_order.is_empty(),"held fake ball also waits for facing")
	s.advance(.7);check(copy.holder==-1 and copy.velocity.x<0 and p.shot_order.is_empty(),"held fake ball launches after turning")
	s=fresh();s.selected_field=2;s.start_practice();p=s.players[0];s.players[1].pos=Vector2(1400,900)
	s.take(0);s.submit_command("move_direction",0,Vector2.RIGHT);s.advance(.3);var drift=p.knock.length()
	request(s,PI);s.advance(.06)
	check(drift>0 and p.knock.length()>0 and not p.shot_order.is_empty(),"turning stops active walking without erasing ice momentum")
	s=fresh();p=s.players[0];request(s,PI);s.advance(.06);s.submit_command("ability",0,Vector2(1000,0));s.advance(.06)
	check(p.shot_order.is_empty() and (p.tackle>0 or p.cast_pending) and s.holder==0,"another explicit ability replaces an uncast shot")
	s=fresh();request(s,PI);s.advance(.06);s.reset();s.advance(1)
	check(s.players.all(func(actor):return actor.get("shot_order",{}).is_empty()),"new round clears pending shots")
	var states=[]
	for rate in [30,60,144]:
		s=fresh();s.submit_command("move_direction",0,Vector2.RIGHT);request(s,PI)
		for frame in range(rate):s.advance(1.0/rate)
		states.append([s.players[0].pos,s.ball,s.velocity])
	for i in [1,2]:
		check(states[i][0].distance_to(states[0][0])<.001 and states[i][1].distance_to(states[0][1])<.001 and states[i][2].distance_to(states[0][2])<.001,"shot/resume independent of render rate "+str(i))
	FileAccess.open("res://research/shot-turn-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("SHOT TURN ",passed," passed; ",failures.size()," failed");quit(0 if failures.is_empty() else 1)
