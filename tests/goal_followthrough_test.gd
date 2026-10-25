extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var checks=[]
var traces=[]
var failed=false
func check(ok: bool,label: String):
	checks.append({"test":label,"passed":ok})
	if not ok:failed=true;push_error(label)
func _initialize():call_deferred("run")
func scene(field: int,match_on: bool,swapped: bool):
	var s=Sim.new()
	s.selected_field=field
	if match_on:
		s.start_match(3,10,90);s.match_state="playing"
	else:s.arena.set_field(field);s.reset()
	s.bot_enabled=false
	if swapped:s.arena.swap_ends()
	for p in s.players:p.pos=Vector2(0,900);p.previous=p.pos;p.target=p.pos
	return s
func run():
	for field in range(4):
		for match_on in [false,true]:
			for swapped in [false,true]:
				for side in [0,1]:
					var s=scene(field,match_on,swapped)
					var goal: Rect2=s.arena.goals[side]
					var direction=signf(goal.get_center().x)
					var plane=goal.position.x if direction>0 else goal.end.x
					var label="field %d match %s swap %s side %d"%[field,match_on,swapped,side]
					s.ball=Vector3(plane-direction*10,0,50);s.velocity=Vector3(direction*70,0,0)
					var expected=Sim.BallFlight.integrate(s.ball,s.velocity)
					var expected_pos=s.ball+expected.delta
					s.step_ball()
					check(s.score[1-side]==1 and s.goal_ball_live,label+" scores once")
					check(s.ball.distance_to(expected_pos)<0.001 and s.velocity.distance_to(expected.velocity)<0.001,label+" retains same-tick flight and momentum")
					var deepest=s.ball.x*direction
					var bounced=false
					var exited=false
					var path=[]
					var clock=s.time_left
					for tick in range(40):
						s.step_ball();deepest=maxf(deepest,s.ball.x*direction)
						bounced=bounced or s.velocity.x*direction<0
						exited=exited or (bounced and s.ball.x*direction<plane*direction)
						path.append([s.ball.x,s.ball.y,s.ball.z,s.velocity.x])
					check(deepest>plane*direction+100 and bounced and exited,label+" travels inside then rebounds back out")
					check(s.score[1-side]==1 and s.score[side]==0,label+" rebound cannot score twice")
					check(not match_on or s.time_left==clock,label+" celebration pauses match clock")
					traces.append({"case":label,"path":path})
					for tick in range(100 if match_on else 30):s.step_ball()
					check(not s.goal_ball_live and s.ball==Vector3.ZERO,label+" round reset clears continuation")
					if match_on:check(s.match_state=="countdown" and s.velocity==Vector3.ZERO,label+" countdown keeps reset ball stationary")
	# A very fast shot scores and strikes the rear boundary in one tick.
	var fast=scene(0,true,false)
	fast.ball=Vector3(2230,0,50);fast.velocity=Vector3(700,0,0);fast.step_ball()
	check(fast.score==[1,0] and fast.velocity.x<0 and fast.ball.x<2528,"same-tick goal and rear collision retain reflected remainder")
	# A held-ball penalty must not detach or launch the ball as a side effect.
	var held=scene(0,true,false);held.take(0);held.award_goal(1);held.step_ball()
	check(held.holder==0 and held.velocity==Vector3.ZERO,"held penalty goal stays attached")
	var final=scene(0,true,false);final.mode="score";final.score_limit=1
	final.ball=Vector3(2230,0,50);final.velocity=Vector3(70,0,0);final.step_ball()
	var before=final.ball;final.step_ball()
	check(final.match_state=="ended" and final.score==[1,0] and final.ball!=before,"winning goal retains simulation momentum without changing winner")
	check(final.reset_delay>3.9,"winning goal has time to rebound before result overlay pauses game")
	for tick in range(128):final.step_ball()
	check(final.reset_delay==0 and final.winner==0 and final.score==[1,0],"winning celebration expires without kickoff or duplicate score")
	FileAccess.open("res://research/goal-followthrough-test.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"traces":traces},"\t"))
	print("Goal follow-through checks: ",checks.size(),"; failed: ",failed)
	quit(1 if failed else 0)
