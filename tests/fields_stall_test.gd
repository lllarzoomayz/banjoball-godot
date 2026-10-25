extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var rows=[]
var failed=false
func check(ok: bool,name: String,detail=""):
	rows.append({"test":name,"passed":ok,"detail":str(detail)})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))
func _initialize():call_deferred("run")
func match_scene(field: int):
	var s=Sim.new();s.selected_field=field;s.start_match(3)
	s.match_state="playing";s.bot_enabled=false
	for i in range(s.players.size()):s.players[i].pos=Vector2(-900+i*300,900);s.players[i].previous=s.players[i].pos
	s.ball=Vector3(0,-900,0)
	return s
func held_guard():
	var s=match_scene(0);s.players[0].pos=Vector2(-1850,0);s.players[0].body=0
	s.take(0);s.ball=s.Copies.held_position(s,0)
	return s
func run():
	var s=Sim.new()
	check(s.arena.fields.map(func(f):return f.name)==["阳光丘陵","大瀑布","冰封之地","冰冻海岸"],"catalog retains four original Chinese field names")
	for f in range(4):
		s=match_scene(f)
		var large=f in [1,3]
		var half=Vector2(2336,1504) if large else Vector2(2016,1312)
		check(s.arena.half_size==half,"original field dimensions "+str(f),s.arena.half_size)
		check(s.arena.boundaries.size()==18 and s.arena.data.terrain_blocked.is_empty(),"all authored ball boundaries and original walkable field cells loaded "+str(f))
		var goal_x=2560.0 if large else 2240.0
		var hit=s.arena.goal_hit(Vector3(goal_x-20,0,100),Vector3(40,0,0))
		check(not hit.is_empty() and hit.team==0 and absf(hit.t-0.5)<0.001,"scoring plane moves with field "+str(f))
		check(s.arena.goal_hit(Vector3(goal_x-20,0,310),Vector3(40,0,0)).is_empty(),"high shot stays above relocated goal "+str(f))
		check(s.arena.in_guard(s.arena.keeper_position(0),0) and s.arena.in_guard(s.arena.keeper_position(1),1),"keeper positions follow field and goal guards "+str(f))
		check(not s.arena.sweep_ball(Vector3(0,half.y-30,0),Vector3(0,100,0)).is_empty(),"side wall still reflects at selected pitch edge "+str(f))
		s.players[0].pos=Vector2(-half.x+100,half.y-100)
		s.arena.add_box(Rect2(-40,half.y-320,80,320),240)
		s.command(0,Vector2(half.x-100,half.y-100))
		var legal=not s.players[0].path.is_empty();var anchor=s.players[0].pos
		for point in s.players[0].path:
			legal=legal and s.arena.sweep_unit(anchor,point-anchor,30).is_empty();anchor=point
		check(legal and anchor.distance_to(Vector2(half.x-100,half.y-100))<1,"navigation detours around wall using full selected field "+str(f),s.grid.region)
		if large:check(s.grid.region.size==Vector2i(180,96) and s.players[0].destination.y>1312,"large pitch navigation extends beyond old standard-grid limits")
		s.reset()
		check(s.players.filter(func(p):return p.role=="keeper").all(func(p):return s.arena.in_guard(p.pos,p.team)),"round restart keeps both goalkeepers in selected-field goals "+str(f))
	s=match_scene(1);s.selected_field=0;s.start_match(3)
	check(s.arena.half_size==Vector2(2016,1312) and s.nav_cache.is_empty() and s.nav_dirty.is_empty(),"switching back rebuilds geometry and clears expanded navigation cache")
	s=held_guard();s.advance(5.20)
	check(not s.stall_warned and s.stall_counter==208,"holding in goal guard counts exactly twice per independent 20 Hz tick",s.stall_counter)
	s.advance(0.05)
	check(s.stall_warned and s.stall_counter==210,"held goal-area warning occurs after 5.25 seconds")
	s.advance(2.25)
	check(not s.referee.is_empty() and not s.referee.kicked and s.holder==0,"7.5 seconds in guard summons referee before forced kick")
	s.advance(0.56)
	check(s.holder==0,"referee respects its 0.57-second kick windup")
	s.advance(0.01)
	check(s.holder==-1 and s.velocity.x>29 and absf(s.velocity.z-7)<0.001 and s.intercept==8 and s.stall_counter==0,"referee kicks toward center with original 30/7 impulse and eight-tick intercept",s.velocity)
	s.advance(1)
	check(s.referee.is_empty(),"referee disappears after 1.5 seconds")
	s=held_guard();s.advance(5.3);s.players[0].pos=Vector2(0,-500);s.advance(3)
	check(s.stall_counter==0 and not s.stall_warned and s.referee.is_empty(),"leaving protected area clears warning without a forced kick")
	s=match_scene(0);s.players[0].pos=Vector2(-2350,0);s.players[0].body=0;s.take(0);s.ball=s.Copies.held_position(s,0)
	s.advance(7.5)
	check(s.stall_counter==150 and s.score==[0,0],"goal roof boundary has original priority over guard count even at ground height")
	s.advance(7.5)
	check(s.score==[0,1] and s.match_state=="goal" and s.referee.is_empty(),"excessive possession inside own scoring goal awards opponent a goal")
	s=held_guard();s.match_state="countdown";s.countdown=30;s.advance(10)
	check(s.stall_counter==0 and not s.stall_warned,"pregame countdown cannot accumulate stall penalties")
	s=held_guard();s.advance(7.5);s.reset();s.advance(1)
	check(s.referee.is_empty() and s.next_referee==INF and s.stall_counter==0,"round reset cancels pending referee kick")
	s=match_scene(0);s.ball=Vector3(-1800,0,0);s.velocity=Vector3(4,0,0);s.stall_counter=300;s.stall_warned=true
	s.StallRules.step(s)
	check(s.stall_counter==290 and s.referee.is_empty(),"free moving ball defers intervention instead of being stolen mid-flight")
	s.velocity=Vector3.ZERO;s.ball.z=61;s.stall_counter=300;s.StallRules.step(s)
	check(s.stall_counter==290 and s.referee.is_empty(),"ball above sixty defers intervention")
	s=match_scene(0);s.ball=Vector3(-1800,0,0)
	for tick in range(210):s.StallRules.step(s)
	check(s.stall_counter==210 and s.stall_warned,"free stationary guard ball accumulates at half held-ball rate")
	s=match_scene(0);var blocked_boundary=Vector2(INF,INF)
	for cell in s.arena.data.stall_blocked:
		var point=s.arena.rect(cell).get_center()
		if s.arena.boundaries.any(func(b):return b.rect.has_point(point)):blocked_boundary=point;break
	s.ball=Vector3(blocked_boundary.x,blocked_boundary.y,0);s.holder=0;s.StallRules.step(s)
	check(blocked_boundary.is_finite() and s.stall_counter==5,"original unwalkable WPM boundary cell accumulates five per tick")
	s=match_scene(0);var walkable_boundary=Vector2(INF,INF)
	for boundary in s.arena.boundaries:
		var point=boundary.rect.get_center()
		if s.arena.terrain_walkable(point) and not s.arena.point_free(point,0.01):walkable_boundary=point;break
	s.ball=Vector3(walkable_boundary.x,walkable_boundary.y,0);s.holder=0;s.StallRules.step(s)
	check(walkable_boundary.is_finite() and s.stall_counter==1,"source-walkable boundary is not mistaken for unwalkable just because it is outside pitch walls")
	s=held_guard();s.players[0].pos=Vector2(0,-500);s.ball=s.Copies.held_position(s,0);s.advance(20)
	check(s.holder==0 and s.stall_counter==0 and s.referee.is_empty(),"ordinary midfield possession never triggers stall referee")
	var a=held_guard();var b=held_guard()
	for tick in range(270):a.advance(1.0/30)
	for tick in range(1296):b.advance(1.0/144)
	check(a.ball.distance_to(b.ball)<0.001 and a.velocity.distance_to(b.velocity)<0.001 and a.holder==b.holder and a.stall_counter==b.stall_counter,"20 Hz protection and scheduled referee kick are independent of render frame rate")
	for field in [1,3]:
		s=match_scene(field);s.bot_enabled=true;s.advance(18)
		check(s.ball.is_finite() and s.players.all(func(p):return p.pos.is_finite() and s.arena.bounds.has_point(p.pos)),"large-field singleplayer AI remains inside expanded playable bounds "+str(field))
	var out=FileAccess.open("res://research/fields-stall-tests.json",FileAccess.WRITE);out.store_string(JSON.stringify(rows,"\t"));out.close()
	quit(1 if failed else 0)
