extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
const Native=preload("res://scripts/native_rules.gd")
var checks=[]
var failed=false

func check(ok: bool,name: String,detail=""):
	checks.append({"test":name,"passed":ok,"detail":detail});failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))

func fresh():
	var s=Sim.new();s.players[0].pos=Vector2.ZERO;s.players[1].pos=Vector2(1500,900)
	s.ball=Vector3(1400,-900,0)
	s.command(0,Vector2(400,0))
	s.players[0].path=[Vector2(10,0),Vector2(100,100),Vector2(250,100),Vector2(400,0)]
	s.players[0].replan=1
	return s

func framed(rate: int):
	var s=fresh();s.submit_command("sprint",0)
	for i in range(rate*2):s.advance(1.0/rate)
	return s

func _initialize():call_deferred("run")

func run():
	var fixture=JSON.parse_string(FileAccess.get_file_as_string("res://research/native-waypoint-visibility.json"))
	var mismatches=0
	for row in fixture.checks:
		var queried=[]
		var selected=Native.visible_waypoint_index(int(row.count),func(candidate):queried.append(candidate);return row.answers[candidate-2])
		if selected!=int(row.native_chosen_forward_index) or queried.size()!=row.native_queries.size():mismatches+=1;continue
		for i in range(queried.size()):
			if queried[i]!=int(row.native_queries[i]):mismatches+=1;break
	check(fixture.checks.size()==1020 and mismatches==0,"1020 original instruction selection/query-order cases",mismatches)
	var s=fresh();s.step_movement()
	var direct=fresh();direct.players[0].path=[Vector2(400,0)];direct.step_movement()
	check(s.players[0].path==[Vector2(400,0)] and s.players[0].pos==direct.players[0].pos,"reached corner skips all clear remaining detours in the same movement update",str(s.players[0].pos))
	check(s.players[0].destination==Vector2(400,0) and s.players[0].want_move and s.players[0].route_status=="moving","shortcut keeps destination and movement order")
	s=fresh();s.players[0].path[0]=Vector2(16,0);s.step_movement()
	check(s.players[0].path.size()==4,"clear later path is not skipped before reaching original fine-point threshold")
	s=fresh();s.players[0].path[0]=Vector2(15,0);s.step_movement()
	check(s.players[0].path.size()==1,"inside 15.68 threshold triggers native visibility scan")
	s=fresh();s.players[0].angle=PI;s.step_movement()
	check(s.players[0].path.size()==1 and s.players[0].pos==Vector2.ZERO,"route skips without waiting for display turn; translation still obeys facing window")
	s=fresh();s.arena.add_box(Rect2(140,45,20,50),200);s.players[0].replan=1;s.step_movement()
	check(s.players[0].path.size()==3 and s.players[0].path[0]==Vector2(100,100),"first blocked candidate retains immediately preceding point")
	check(s.segment(Vector2.ZERO,Vector2(400,0),0),"later destination is clear in nonmonotonic visibility fixture")
	check(s.players[0].path.size()==3,"native first-failure ordering does not jump to a clear point beyond failed ray")
	s=fresh();s.arena.add_box(Rect2(140,-12,20,24),200);s.players[0].replan=1;s.step_movement()
	check(s.players[0].path.size()==2 and s.players[0].path[0]==Vector2(250,100),"second failed ray retains last clear intermediate point")
	s=fresh();s.players[1].pos=Vector2(150,60);s.step_movement()
	check(s.players[0].path.size()==3,"stationary unit blocks candidate ray with both collision radii")
	s.players[1].pos=Vector2(1500,900);s.players[0].pos=Vector2(95,95);s.players[0].replan=1;s.step_movement()
	check(s.players[0].path.size()==1 and s.players[0].path[0]==Vector2(400,0),"moving blocker leaving allows next reached corner to use direct destination")
	s=fresh();s.players[1].pos=Vector2(150,60);s.begin_tackle(1);s.step_movement()
	check(s.players[0].path.size()==1,"currently nonblocking tackle unit does not block visibility shortcut")
	s=fresh();s.players[1].pos=Vector2(150,60);s.players[1].z=120;s.step_object_impulses();s.step_movement()
	check(s.players[0].path.size()==1,"airborne unit uses same navigation eligibility as ordinary movement")
	s=fresh();s.arena.add_box(Rect2(140,75,20,30),200);s.step_movement()
	check(s.players[0].path.size()==3,"ray uses full footprint instead of center-only line across corner")
	s=fresh();s.arena.add_pillar(Vector2(150,60),1);s.step_movement()
	check(s.players[0].path.size()==3,"temporary totem blocks candidate route")
	s=fresh();s.players[0].pos=Vector2(1500,0)
	s.players[0].path=[Vector2(1510,0),Vector2(1550,600),Vector2(2250,0)];s.players[0].replan=1;s.step_movement()
	check(s.players[0].path[0]==Vector2(1550,600) and not s.arena.in_guard(s.players[0].pos,1),"shortcut cannot bypass opposing goal restriction")
	s=fresh();s.players[0].route_status="partial";s.players[0].destination=Vector2(400,0);s.step_movement()
	check(s.players[0].route_status=="partial" and s.players[0].want_move,"partial route remains partial after shortcut")
	s=fresh();s.stop(0);s.step_movement()
	check(s.players[0].path.is_empty() and not s.players[0].want_move,"stop cannot restart a discarded detour")
	s=fresh();s.players[0].tackle=640;s.command(0,Vector2(400,0));s.step_movement()
	check(s.players[0].path==[Vector2(400,0)] and s.players[0].pos==Vector2.ZERO,"active tackle keeps direct steering order without walking")
	s=fresh();s.players[0].tackle=640;s.command(0,Vector2(400,0));s.finish_tackle(0);s.step_movement()
	check(s.players[0].path==[Vector2(400,0)] and s.players[0].pos.x>0,"tackle end resumes explicitly issued move through ordinary route")
	s=fresh();s.players[0].tackle=640;s.stop(0);s.finish_tackle(0);s.step_movement()
	check(s.players[0].pos==Vector2.ZERO and s.players[0].path.is_empty(),"tackle end without move order does not invent continuation")
	var a=framed(30);var b=framed(144)
	check(a.players[0].pos.is_equal_approx(b.players[0].pos) and a.players[0].path==b.players[0].path,"shortcut outcome is identical at 30 and 144 fps")
	var f=FileAccess.open("res://research/route-visibility-tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"scope":fixture.scope,"checks":checks},"\t"))
	quit(1 if failed else 0)
