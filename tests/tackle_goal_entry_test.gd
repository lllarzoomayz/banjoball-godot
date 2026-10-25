extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
const Motion=preload("res://scripts/object_motion.gd")
var checks=[]
var failed=false

func check(ok: bool,name: String,detail=""):
	checks.append({"test":name,"passed":ok,"detail":str(detail)});failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))

func scene(field=0):
	var s=Sim.new();s.selected_field=field;s.start_practice()
	s.players[1].pos=Vector2(1000,-900);s.ball=Vector3(-1000,-900,0)
	return s

func approach(s,goal: int,own: bool=false):
	var front: Rect2=s.arena.guards[goal][0]
	var left=front.get_center().x<0
	var direction=-1.0 if left else 1.0
	var edge=front.end.x if left else front.position.x
	var p=s.players[0]
	p.pos=Vector2(edge-direction*5,0);p.body=PI if left else 0.0;p.angle=p.body
	p.team=goal if own else 1-goal;p.tackle=640.0
	return Vector2(edge+(40 if left else -10),0)

func framed(rate: int):
	var s=scene(2);approach(s,1);s.players[0].tackle=0
	s.submit_command("ability",0,Vector2(2200,0))
	for i in range(rate*2):s.advance(1.0/rate)
	return s

func _initialize():call_deferred("run")

func run():
	for field in range(4):
		for swapped in [false,true]:
			for goal in range(2):
				var s=scene(field)
				if swapped:s.arena.swap_ends()
				var expected=approach(s,goal);var old: Vector2=s.players[0].pos
				s.step_tackle(0)
				check(s.players[0].pos.is_equal_approx(expected) and not s.arena.in_guard(s.players[0].pos,goal),"field %d swapped=%s goal %d repairs at source offset after entering"%[field,swapped,goal],s.players[0].pos)
				check(is_equal_approx(s.players[0].tackle,595.4) and s.players[0].knock==Vector2.ZERO and s.tackle_shadows[0].pos==Vector3(old.x,old.y,0),"field %d swapped=%s goal %d keeps tackle, old shadow, and zero impulse"%[field,swapped,goal])
	var s=scene();approach(s,1)
	s.players[0].knock=Vector2(20,4);s.players[0].vz=7;s.players[0].z=125
	s.step_tackle(0)
	check(s.players[0].knock==Vector2(-10,4) and s.players[0].vz==7 and s.players[0].z==125,"entry halves and reverses inward normal impulse; tangent and altitude remain")
	check(s.players[0].body==0 and s.players[0].angle==0,"entry does not reverse caster facing")
	check(s.skill_effects.size()==1 and s.skill_effects[0].pos==Vector3(1640,0,205),"goal impact is fifty units toward old position and eighty units above player")
	s=scene();approach(s,1);s.players[0].knock=Vector2(-12,4);s.players[0].vz=-5;s.step_tackle(0)
	check(s.players[0].knock==Vector2(-12,4) and s.players[0].vz==-5,"already outward impulse is not reflected again")
	s=scene();approach(s,1);s.players[0].ogre_slow=1;s.step_tackle(0)
	check(s.players[0].ogre_slow==1 and s.players[0].stun==0,"goal entry does not invent ogre boundary stun")
	s=scene();approach(s,1);s.players[0].z=500;s.step_tackle(0)
	check(s.players[0].pos.x==1590 and s.players[0].z==500,"goal occupancy restriction still applies above three hundred height")
	for goal in range(2):
		s=scene();approach(s,goal,true);s.step_tackle(0)
		check(s.arena.in_guard(s.players[0].pos,goal) and s.skill_effects.is_empty(),"first own defender may tackle into goal "+str(goal))
		s=scene();var exit=approach(s,goal,true)
		s.players.append(s.make_player(s.arena.keeper_position(goal),goal));s.step_tackle(0)
		check(s.players[0].pos.is_equal_approx(exit) and s.skill_effects.size()==1,"second own defender is moved back from occupied goal "+str(goal))
	s=scene();approach(s,1,true)
	s.players.append(s.make_player(s.arena.keeper_position(1),1));s.players[2].injury_pose=true;s.step_tackle(0)
	check(s.players[0].pos.x==1590,"lying keeper still occupies the goal")
	s=scene();approach(s,1,true)
	s.players.append(s.make_player(s.arena.keeper_position(1),1));s.players[2].possess_time=3;s.step_tackle(0)
	check(s.arena.in_guard(s.players[0].pos,1),"absent possessed unit follows existing goal-occupancy eligibility")
	s=scene();approach(s,1)
	for i in range(15):s.step_tackle(0)
	check(s.players[0].tackle==0 and s.players[0].pos.x==1590 and s.tackle_shadows.size()==15,"repeated forbidden entries consume fifteen full tackle steps without early cancellation")
	check(s.skill_effects.size()==15,"each new forbidden entry creates a new impact response")
	s=scene();approach(s,1);s.players[0].pos.x=1600-44.6-10;s.step_tackle(0)
	check(is_equal_approx(s.players[0].pos.x,1590) and s.skill_effects.is_empty(),"overlapping footprint alone does not trigger scripted center-entry repair")
	s=scene();approach(s,1);s.arena.add_box(Rect2(1600,-100,10,200),200);var old=s.players[0].pos;s.step_tackle(0)
	check(s.players[0].pos==old and s.skill_effects.is_empty() and s.players[0].tackle>0,"physical practice wall still rejects movement before any goal-entry response")
	s=scene();approach(s,1);s.players[1].pos=Vector2(1760,0);s.step_tackle(0)
	check(s.players[0].tackle>0 and s.players[1].slow==1.5 and s.players[1].knock==Vector2.ZERO,"post-step repair position is used for subsequent tackle area query")
	s=scene();s.players[0].pos=Vector2(1800,453);s.players[0].body=-PI/2;s.players[0].tackle=640;s.step_tackle(0)
	check(is_equal_approx(s.players[0].pos.y,488) and s.players[0].tackle>0,"top entry moves beyond upper edge without cancelling tackle")
	s=scene();s.players[0].pos=Vector2(1800,-453);s.players[0].body=PI/2;s.players[0].tackle=640;s.step_tackle(0)
	check(is_equal_approx(s.players[0].pos.y,-458) and s.players[0].tackle>0,"bottom entry preserves original ten-unit asymmetric exit")
	s=scene();s.players[0].pos=Vector2(1800,0);s.players[0].team=1
	check(not s.repair_goal_entry(0,Vector2(1750,0)) and s.skill_effects.is_empty(),"remaining inside a legal goal is not another enter event")
	s=scene();s.players[0].pos=Vector2(1500,0)
	check(not s.repair_goal_entry(0,Vector2(1700,0)) and s.players[0].pos.x==1500,"leaving goal does not trigger entry repair")
	s=scene();var response=Motion.goal_response(s.arena,Vector3(2400,100,60),Vector3(20,-12,8),1)
	check(response.position==Vector3(2016,488,60) and response.velocity==Vector3(0,6,8),"deep repair dispatches BoundaryCheck during both force additions")
	s=scene();approach(s,1);s.players[0].tackle=0;s.Characters.use(s,0,Vector2(2200,0));s.advance(s.BALL_DT)
	check(s.players[0].pos.x==1590 and s.players[0].tackle>0 and s.skill_effects.size()==1,"ordinary skill cast reaches entry response through real game clocks")
	s.stop(0);s.advance(0.6)
	check(not s.players[0].want_move and s.players[0].tackle==0 and s.players[0].path.is_empty(),"stop during rejected entry does not revive movement after tackle expires")
	s=scene();approach(s,1);s.command(0,Vector2(1000,500));s.step_tackle(0)
	check(s.players[0].want_move and s.players[0].target==Vector2(1000,500),"entry repair retains explicitly issued post-tackle movement destination")
	s.advance(4)
	check(s.players[0].pos.distance_to(Vector2(1000,500))<=Sim.Native.MIN_POINT_STOP+0.001 and s.players[0].route_status=="arrived","move issued during tackle reaches target after repaired entry and collision restoration")
	s=scene();approach(s,1);s.step_tackle(0);s.stop(0);s.advance(0.6);s.command(0,Vector2(1000,500));s.advance(4)
	check(s.players[0].pos.distance_to(Vector2(1000,500))<=Sim.Native.MIN_POINT_STOP+0.001,"new move escapes restored footprint overlapping the goal edge")
	s=scene();approach(s,1,true);s.players.append(s.make_player(s.arena.keeper_position(1),1));s.step_tackle(0)
	s.players[2].pos=Vector2(1200,900);s.step_tackle(0)
	check(s.arena.in_guard(s.players[0].pos,1) and s.skill_effects.size()==1,"own keeper leaving reopens entry for next tackle step")
	s.reset();check(s.skill_effects.is_empty() and s.tackle_shadows.is_empty(),"new round clears impact effects and tackle ghosts")
	var a=framed(30);var b=framed(144)
	check(a.players[0].pos.is_equal_approx(b.players[0].pos) and a.players[0].knock.is_equal_approx(b.players[0].knock) and a.players[0].tackle==b.players[0].tackle,"icy goal-entry and tackle clocks are independent of render frame rate")
	FileAccess.open("res://research/tackle-goal-entry-tests.json",FileAccess.WRITE).store_string(JSON.stringify({"basis":"Preserved GoalBlock/Tackle script; continuous step boundary, not native per-axis region timing validation","checks":checks},"\t"))
	quit(1 if failed else 0)
