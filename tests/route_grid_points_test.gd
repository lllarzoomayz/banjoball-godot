extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
const Native=preload("res://scripts/native_rules.gd")
const Search=preload("res://scripts/native_grid_search.gd")
var checks=[]
var failed=false

func check(ok: bool,name: String,detail=""):
	checks.append({"test":name,"passed":ok,"detail":str(detail)})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))

func corner(field: int,mirror: Vector2=Vector2.ONE):
	var s=Sim.new();s.arena.set_field(field)
	s.players[0].pos=Vector2(-600,0)*mirror;s.players[0].angle=0 if mirror.x>0 else PI;s.players[0].body=s.players[0].angle
	s.players[1].pos=Vector2(1500,-900);s.ball=Vector3(1400,-1000,0)
	for r in [Rect2(-1000,48,952,1500),Rect2(48,48,952,1500),Rect2(-1000,-1548,2000,1500)]:
		var a=r.position*mirror;var b=r.end*mirror
		s.arena.add_box(Rect2(a.min(b),(b-a).abs()),200)
	s.command(0,Vector2(0,600)*mirror)
	return s

func _initialize():call_deferred("run")

func run():
	var fixture=JSON.parse_string(FileAccess.get_file_as_string("res://research/native-route-points.json"))
	var mismatches=0
	for row in fixture.checks:
		var cell=Vector2i(int(row.cell[0]),int(row.cell[1]))
		if Native.fine_grid_point(cell)!=Vector2(row.native_path[1][0],row.native_path[1][1])*32 or Native.partial_grid_point(cell)!=Vector2(row.native_partial[0],row.native_partial[1])*32:mismatches+=1
	check(fixture.checks.size()==264 and mismatches==0,"264 original instruction reconstructions match fine and partial points",mismatches)
	mismatches=0
	for row in fixture.floors:
		if Native.path_cell(Vector2(float(row.coordinate)*32,64)).x!=int(row.cell):mismatches+=1
	check(fixture.floors.size()==21 and mismatches==0,"21 original cell floors include initialized negative fractions",mismatches)
	mismatches=0
	for row in fixture.nearest:
		var target=Vector2i(row.goal[0],row.goal[1])
		var current=target+Vector2i(row.current[0],row.current[1]);var candidate=target+Vector2i(row.candidate[0],row.candidate[1])
		if Search.closer_cell(candidate,current,target)!=row.native_replace:mismatches+=1
	check(fixture.nearest.size()==40 and mismatches==0,"40 native closest-node decisions retain first equal-distance node",mismatches)
	check(Native.path_cell(Vector2(23.9,31.99))==Vector2i.ZERO and Native.path_cell(Vector2(32,32))==Vector2i.ONE,"cell edges remain at multiples of32 instead of biased waypoint bisectors")
	for field in range(4):
		for mirror in [Vector2.ONE,Vector2(-1,1),Vector2(1,-1),Vector2(-1,-1)]:
			var s=corner(field,mirror);var valid=true
			var route=s.players[0].path.duplicate();var furthest=0.0
			for i in range(500):
				s.step_movement();valid=valid and s.arena.point_free(s.players[0].pos,30)
				furthest=maxf(furthest,s.players[0].pos.length())
			check(valid and furthest<650 and s.players[0].pos.distance_to(Vector2(0,600)*mirror)<=Native.MIN_POINT_STOP+0.001,"96-unit inside corner stays collision-free and reaches goal field=%d mirror=%s"%[field,mirror],str(s.players[0].pos)+" route="+str(route))
	var s=corner(0);var exact=Vector2(3.25,617.5);s.command(0,exact)
	check(s.players[0].target==exact and s.players[0].destination==exact,"exact off-grid requested destination is not replaced by waypoint bias")
	for i in range(500):s.step_movement()
	check(s.players[0].pos.distance_to(exact)<=Native.MIN_POINT_STOP+0.001 and s.players[0].route_status=="arrived","off-grid endpoint finishes within original stopping radius")
	s=Sim.new();s.players[0].pos=Vector2(-600,0);s.players[1].pos=Vector2(1400,900)
	s.arena.add_box(Rect2(-80,-200,160,400),200);s.command(0,Vector2.ZERO)
	check(s.players[0].route_status=="partial" and s.players[0].destination==Vector2(112,16),"blocked target uses strict native cell choice and +16 partial endpoint",s.players[0].destination)
	s=corner(0);s.tackle(0,Vector2(1000,0));s.command(0,Vector2(0,600))
	for i in range(500):s.advance(0.03)
	check(s.players[0].tackle==0 and s.arena.point_free(s.players[0].pos,30) and s.players[0].pos.distance_to(Vector2(0,600))<=Native.MIN_POINT_STOP+0.001,"turning tackle near corner resumes requested walk",s.players[0].pos)
	s=corner(0);s.arena.add_box(Rect2(-48,250,96,32),150)
	for i in range(300):s.step_movement()
	check(s.players[0].pos.y<220.01 and s.players[0].want_move,"new obstacle closes narrow route without clipping")
	s.arena.obstacles.pop_back();s.arena.revision+=1
	for i in range(300):s.step_movement()
	check(s.players[0].pos.distance_to(Vector2(0,600))<=Native.MIN_POINT_STOP+0.001,"removing narrow-route obstruction resumes same order")
	s=Sim.new();s.set_course(4)
	check(s.players.all(func(p):return s.arena.point_free(p.pos,p.radius)) and s.arena.point_free(Vector2(s.ball.x,s.ball.y),25),"new corner practice has legal player and ball spawns")
	s.submit_command("move",0,Vector2(0,600))
	for i in range(400):s.advance(0.03)
	check(s.holder==0 and s.players[0].pos.distance_to(Vector2(0,600))<=Native.MIN_POINT_STOP+0.001,"playable corner practice can walk to and take ball")
	s.reset()
	check(s.arena.course==4 and s.players[0].pos==Vector2(-600,0) and s.ball==Vector3(0,600,0),"practice reset keeps corner geometry and restores start")
	var a=corner(0);var b=corner(0)
	for i in range(150):a.advance(1.0/30)
	for i in range(720):b.advance(1.0/144)
	check(a.players[0].pos.is_equal_approx(b.players[0].pos) and a.players[0].path==b.players[0].path,"biased-node corner movement agrees at 30/144 render FPS")
	var f=FileAccess.open("res://research/route-grid-points-tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks},"\t"))
	quit(1 if failed else 0)
