extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var results=[]
var failed=false
func check(ok: bool,name: String,detail=""):
	results.append({"test":name,"passed":ok,"detail":str(detail)})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))
func _initialize():call_deferred("run")
func scene(id: String):
	var s=Sim.new();s.selected_character=id;s.reset()
	s.players[0].pos=Vector2(-600,0);s.players[1].pos=Vector2(1700,900)
	s.ball=Vector3(1400,-900,0)
	return s
func run():
	var s=scene("h001")
	s.Characters.use(s,0,Vector2(1200,0));s.advance(0.25)
	check(s.projectiles.size()==1 and s.projectiles[0].pos.distance_to(Vector3(-224.8,0,100))<0.01,"swap projectile preserves 44.4-per-tick velocity and fixed ground-cast height",s.projectiles)
	check(s.players[0].cooldown>17.7 and s.players[0].disabled>0,"swap starts eighteen-second cooldown and channel pose")
	s.command(0,Vector2(-800,-300))
	check(s.players[0].disabled==0 and s.projectiles.size()==1,"movement cancels swap pose without destroying the projectile")
	s=scene("h001");s.players[1].pos=Vector2(-150,0)
	s.players.append(s.make_player(Vector2(500,0),1))
	s.take(0);s.step_ball();s.Characters.use(s,0,Vector2(1200,0));s.advance(0.4)
	check(s.players[0].pos==Vector2(-150,0) and s.players[1].pos==Vector2(-600,0) and s.players[2].pos==Vector2(500,0) and s.projectiles.is_empty(),"swap exchanges with the first contacted player only")
	check(s.holder==0 and Vector2(s.ball.x,s.ball.y).distance_to(s.players[0].pos)<101,"held scoring ball follows a swapped owner immediately")
	s=scene("h001");var a=s.players[0];var b=s.players[1]
	a.z=250;a.knock=Vector2(12,3);a.vz=-4;b.z=50;b.knock=Vector2(-2,7);b.vz=8
	var angle_a=a.body;var angle_b=b.body
	s.Characters.exchange_players(s,0,1)
	check(a.z==50 and b.z==250 and a.knock==Vector2(-2,7) and b.knock==Vector2(12,3) and a.vz==8 and b.vz==-4 and a.body==angle_a and b.body==angle_b,"swap exchanges height and full impulse but preserves each facing")
	s=scene("h001");s.arena.add_box(Rect2(-300,-200,30,400),240)
	s.Characters.use(s,0,Vector2(1000,0));s.advance(0.4)
	check(s.projectiles.size()==1 and s.projectiles[0].velocity.x<0 and absf(s.projectiles[0].velocity.length()-44.4)<0.001,"swap projectile reflects from a solid wall without losing speed")
	s=scene("h001");s.players[1].pos=Vector2(-150,0);s.players[1].z=400
	s.Characters.use(s,0,Vector2(1200,0));s.Characters.step_swap(s,s.projectiles[0])
	check(s.Characters.swap_contact(s,s.projectiles[0],Vector3(-200,0,100),Vector3(100,0,0)).is_empty(),"swap misses a player outside the relative height window")
	s=scene("h001");s.players[1].pos=Vector2(2050,0)
	check(not s.Characters.exchange_players(s,0,1) and s.players[0].pos.x==-600,"swap cannot place an attacker inside the opposing protected goal")
	s=scene("h001");s.players[1].team=0;s.players[1].pos=Vector2(-2090,0)
	check(s.Characters.exchange_players(s,0,1) and s.players[0].pos.x==-2090,"two teammates may swap the single goalkeeper position")
	s=scene("h001");s.Characters.use(s,0,Vector2(1200,0));s.advance(1.82)
	check(s.projectiles.is_empty(),"missed swap projectile expires after 1.8 seconds")
	var constants=s.Characters.curve_constants()
	check(absf(constants.speed-42.99086656)<1e-7 and absf(constants.initial_angle+0.49027806)<1e-7 and absf(constants.force-1.20002304)<1e-7 and absf(constants.angle-1.58486432)<1e-7 and absf(constants.force_delta+0.025318699)<1e-7 and absf(constants.angle_delta+0.000149998)<1e-7,"curve constants agree with independently calculated original chord formula",constants)
	s=scene("h012")
	check(not s.Characters.use(s,0,Vector2(1400,0)) and s.players[0].cooldown==0,"curve requires possession without spending cooldown on rejection")
	var left=scene("h012");var right=scene("h012")
	for sim in [left,right]:sim.take(0);sim.step_ball()
	left.Characters.use(left,0,Vector2(1400,0),false)
	right.Characters.use(right,0,Vector2(1400,0),true)
	check(left.velocity.y>0 and right.velocity.y<0 and left.velocity.z==0 and right.velocity.z==0,"Q and R produce mirrored ground curve launches")
	left.advance(0.65);right.advance(0.65)
	check(absf(left.ball.x-right.ball.x)<0.01 and absf(left.ball.y+right.ball.y)<0.01 and left.ball.y>100,"opposite curves remain mirrored throughout continuous flight",[left.ball,right.ball])
	s=left;s.players[1].team=0;s.players[1].mana=12;s.take(1)
	check(s.players[1].mana==100 and s.curve.is_empty(),"ally catch during active curve restores one hundred mana and ends the curve")
	s=right;s.players[1].mana=12;s.take(1)
	check(s.players[1].mana==12 and s.curve.is_empty(),"enemy catch ends curve without restoring mana")
	s=scene("h012");s.take(0);s.step_ball();s.Characters.use(s,0,Vector2(1400,0));s.advance(1.42)
	check(s.curve.is_empty() and s.holder==-1,"curve force stops after its 1.4-second window while the ball keeps flying")
	s.players[1].team=0;s.players[1].mana=12;s.take(1)
	check(s.players[1].mana==12,"late catch after curve expiration does not restore mana")
	s=scene("h01N")
	check(not s.Characters.use(s,0,Vector2(1400,0)) and s.fake_balls.is_empty(),"trickster requires the real ball")
	s.take(0);s.step_ball();s.Characters.use(s,0,Vector2(1400,0))
	check(s.holder==0 and s.fake_balls.size()==1 and s.fake_balls[0].holder==-1 and s.fake_balls[0].velocity==Vector3(30,0,7) and s.players[0].cooldown==14,"Q kicks a real-physics copy while keeping the scoring ball")
	var copy=s.fake_balls[0]
	var reference=scene("h005");reference.ball=copy.position;reference.velocity=copy.velocity;reference.last_owner=0;reference.intercept=5
	s.players[0].pos=Vector2(-1200,-900);reference.players[0].pos=Vector2(-1200,-900)
	for i in range(30):s.step_ball();reference.step_ball()
	check(copy.position.distance_to(reference.ball)<0.001 and copy.velocity.distance_to(reference.velocity)<0.001,"fake and real ball use identical free-flight calculations")
	s=scene("h01N");s.take(0);s.step_ball();s.Characters.use(s,0,Vector2(1400,0),true);copy=s.fake_balls[0]
	check(s.holder==-1 and copy.holder==0 and s.velocity==Vector3(30,0,7),"R kicks the scoring ball and leaves a held copy")
	s.players[0].pos=Vector2(-800,200);s.step_ball()
	check(copy.position.distance_to(Vector3(-700,200,0))<0.001 and s.has_ball(0),"a held copy follows its owner and counts for local ball controls")
	check(s.kick(0,Vector2(1000,200)) and copy.holder==-1,"W can pass a held fake ball")
	s.players[1].pos=Vector2(copy.position.x+120,copy.position.y)
	s.advance(0.3)
	check(copy.holder==1,"another player can intercept and hold a fake ball")
	check(s.kick(1,Vector2(-1500,200)) and copy.holder==-1,"a receiver can pass a fake ball again")
	s=scene("h01N");s.take(0);s.step_ball();s.Characters.use(s,0,Vector2(1000,0));copy=s.fake_balls[0]
	s.arena.add_box(Rect2(-300,-120,20,240),240);s.advance(0.4)
	check(copy.velocity.x<0 and copy.position.x< -325,"fake ball bounces at the same expanded wall boundary")
	s=scene("h01N");s.take(0);s.step_ball();s.Characters.use(s,0,Vector2(1000,0));copy=s.fake_balls[0]
	copy.position=Vector3(2200,0,50);copy.velocity=Vector3(100,0,0);s.step_ball()
	check(s.score==[0,0] and s.fake_balls.size()==1 and copy.position.x>2240,"fake crossing a goal neither scores nor triggers a round reset")
	copy.life=0.04;s.advance(0.08)
	check(s.fake_balls.is_empty(),"fake expires after its lifetime even inside a goal")
	s=scene("h01N");s.take(0);s.step_ball();s.Characters.use(s,0,Vector2(1000,0));copy=s.fake_balls[0]
	s.players[1].pos=Vector2(1000,400);copy.position=Vector3(950,400,0)
	check(s.TeamAI.observation(s,1).id==copy.id and s.TeamAI.observation(s,0).id==0,"enemy AI can be fooled by a nearby copy while teammates recognize it")
	s.TeamAI.think(s)
	check(s.players[1].target.distance_to(Vector2(950,400))<200,"enemy AI actually pursues the misleading ball")
	s=scene("h01N");s.take(0);s.step_ball();s.Characters.use(s,0,Vector2(1000,0),true);copy=s.fake_balls[0]
	s.take(0)
	check(s.holder==0 and copy.holder==-1,"real-ball interception releases an already held copy")
	s.reset()
	check(s.fake_balls.is_empty() and s.projectiles.is_empty() and s.curve.is_empty(),"round reset clears copies, swap projectiles and curve state")
	var fast=scene("h01N");var slow=scene("h01N")
	for sim in [fast,slow]:sim.take(0);sim.step_ball();sim.Characters.use(sim,0,Vector2(1400,500),true)
	for i in range(120):slow.advance(1.0/30)
	for i in range(576):fast.advance(1.0/144)
	check(fast.ball.distance_to(slow.ball)<0.001 and fast.fake_balls[0].position.distance_to(slow.fake_balls[0].position)<0.001,"real and fake ball states remain independent of rendering frame rate")
	for id in ["h001","h012","h01N"]:
		s=scene(id);s.mixed_roster=true;s.start_match(6);s.controlled=-1
		var valid=true
		for tick in range(400):
			s.advance(0.05)
			for p in s.players:valid=valid and p.pos.is_finite() and is_finite(p.z) and p.z>=0 and absf(p.pos.x)<2530 and absf(p.pos.y)<1320
			for extra in s.fake_balls:valid=valid and extra.position.is_finite() and extra.velocity.is_finite() and extra.life>0
			for projectile in s.projectiles:valid=valid and projectile.pos.is_finite() and projectile.velocity.is_finite()
		check(valid,"mixed twelve-player match with "+id+" stays finite and inside the pitch")
	FileAccess.open("res://research/ball-tricks-tests.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	quit(1 if failed else 0)
