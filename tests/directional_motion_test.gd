extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok: bool,label: String):
	if ok:passed+=1
	else:failures.append(label);printerr("FAIL "+label)
func fresh(field=0):
	var s=Sim.new();s.selected_field=field;s.start_practice()
	s.players[0].pos=Vector2(-250,0);s.players[0].angle=0;s.players[0].body=0
	s.players[1].pos=Vector2(-1400,900);s.ball=Vector3(1000,-900,0)
	return s
func push(s,axis: Vector2,seconds: float):
	s.submit_command("move_direction",0,axis);s.advance(seconds)
func run():
	var s=fresh();s.arena.add_box(Rect2(0,-200,100,400),240)
	push(s,Vector2.RIGHT,4)
	check(absf(s.players[0].pos.x+30)<0.01 and absf(s.players[0].pos.y)<0.001,"straight input stays against the wall without detouring")
	check(s.players[0].path.is_empty() and s.profile.route_calls==0,"held joystick never invokes pathfinding")
	var before: Vector2=s.players[0].pos;push(s,Vector2(1,1),0.5)
	check(absf(s.players[0].pos.x+30)<0.02 and s.players[0].pos.y>90 and s.players[0].pos.y<120,"diagonal input slides only at its original tangent speed")
	before=s.players[0].pos;push(s,Vector2.RIGHT,0.5)
	check(s.players[0].pos.distance_to(before)<0.02,"removing sideways input stops sliding immediately")
	push(s,Vector2.LEFT,0.8);check(s.players[0].pos.x<before.x-100,"opposite input leaves the wall after turning")
	s=fresh();s.arena.add_box(Rect2(0,-200,100,400),240);s.players[0].pos.y=220
	push(s,Vector2.RIGHT,3)
	check(absf(s.players[0].pos.y-220)<0.001 and s.players[0].pos.x<0,"rounded corner cannot manufacture a sideways component")
	s=fresh();s.players[1].pos=Vector2(0,20);push(s,Vector2.RIGHT,3)
	check(absf(s.players[0].pos.y)<0.001 and s.players[0].pos.x<0,"unit-circle contact does not auto-orbit a player")
	s=fresh();s.arena.set_course(2);push(s,Vector2.RIGHT,4)
	check(s.players[0].pos.x<-180 and absf(s.players[0].pos.y)<0.01,"held stick does not escape a U by choosing a route")
	s=fresh();s.arena.add_box(Rect2(0,-200,100,400),240)
	s.command(0,Vector2(450,0));s.advance(6)
	check(s.players[0].pos.x>300,"point movement still routes around the same wall")
	s=fresh();push(s,Vector2.RIGHT,0.3);s.submit_command("move_release",0);s.advance(0.06);before=s.players[0].pos;s.advance(1)
	check(s.players[0].pos==before and s.players[0].direct_axis==Vector2.ZERO,"lifting stick clears persistent direction")
	s=fresh(2);push(s,Vector2.RIGHT,0.6);s.submit_command("move_release",0);s.advance(0.06);before=s.players[0].pos;s.advance(0.2)
	check(s.players[0].pos.x>before.x and not s.players[0].slide_order,"lifting stick preserves existing ice momentum without further input")
	s=fresh();push(s,Vector2.RIGHT,0.2);s.tackle(0,Vector2(1000,0))
	check(s.players[0].direct_axis==Vector2.ZERO,"spell order clears stored joystick translation")
	s.players[0].ability_delay=0.5;s.players[0].cast_pending=true
	s.submit_command("move_direction",0,Vector2.UP);s.consume_commands()
	check(s.players[0].direct_axis==Vector2.ZERO and s.players[0].cast_pending and s.players[0].ability_delay==0.5,"stale joystick command cannot cancel a prepared spell")
	s=fresh();s.players[0].ability_kind="black_hole";s.players[0].disabled=1.2
	push(s,Vector2.RIGHT,0.2)
	check(s.players[0].pos.x>-220 and s.players[0].disabled==0,"stick cancels movable spell follow-through like an ordinary movement order")
	var positions=[]
	for rate in [30,60,144]:
		s=fresh();s.arena.add_box(Rect2(0,-200,100,400),240);s.submit_command("move_direction",0,Vector2(1,0.25))
		for i in range(rate*3):s.advance(1.0/rate)
		positions.append(s.players[0].pos)
	check(positions[0].distance_to(positions[1])<0.001 and positions[0].distance_to(positions[2])<0.001,"collision and sliding are independent of display frame rate")
	for field in range(4):
		for swapped in [false,true]:
			for team in range(2):
				s=fresh(field)
				if swapped:s.arena.swap_ends()
				var front: Rect2=s.arena.guards[team][0];var left=front.get_center().x<0
				var axis=Vector2(-1 if left else 1,0);var edge=front.end.x if left else front.position.x
				s.players[0].team=1-team;s.players[0].pos=Vector2(edge-axis.x*70,0);s.players[0].angle=axis.angle();s.players[0].body=axis.angle()
				push(s,axis,1)
				var expected=edge+(40 if left else -10)
				check(not s.arena.in_guard(s.players[0].pos,team) and absf(s.players[0].pos.x-expected)<40,"protected goal rejects direct entry field=%d swapped=%s team=%d"%[field,swapped,team])
				check(s.skill_effects.any(func(e):return e.get("model","")=="fx_goal_block" and e.scale==0.9 and e.pos.z==80),"repeated pushing shows original blue protection effect field=%d swapped=%s team=%d"%[field,swapped,team])
				check(s.profile.route_calls==0 and absf(s.players[0].pos.y)<0.01,"goal rejection cannot cause a sideways route field=%d swapped=%s team=%d routes=%d pos=%s"%[field,swapped,team,s.profile.route_calls,s.players[0].pos])
	s=fresh();s.players[0].pos=Vector2(-1500,0);s.players[0].angle=PI;s.players[0].body=PI;push(s,Vector2.LEFT,1)
	check(s.arena.in_guard(s.players[0].pos,0) and s.skill_effects.is_empty(),"first own defender can enter without false collision or flash")
	s=fresh();s.players[0].pos=Vector2(-1500,0);s.players[0].angle=PI;s.players[0].body=PI
	s.players.append(s.make_player(s.arena.keeper_position(0),0));push(s,Vector2.LEFT,1)
	check(not s.arena.in_guard(s.players[0].pos,0) and not s.skill_effects.is_empty(),"occupied own goal rejects a second defender")
	s.players[2].pos=Vector2(-900,900);push(s,Vector2.LEFT,1)
	check(s.arena.in_guard(s.players[0].pos,0),"vacating the keeper slot immediately reopens entry")
	FileAccess.open("res://research/directional-motion-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("DIRECTIONAL CHECKS ",passed," passed; ",failures.size()," failed");quit(0 if failures.is_empty() else 1)
