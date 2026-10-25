extends SceneTree
const F=preload("res://scripts/native_float.gd")
const Sim=preload("res://scripts/match_sim.gd")
var results=[]
var failed=false
func check(ok: bool,name: String,detail=""):
	results.append({"test":name,"passed":ok,"detail":detail})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))
func _initialize():call_deferred("run")
func run():
	var fixture=JSON.parse_string(FileAccess.get_file_as_string("res://research/native-waypoint-checks.json"))
	var mismatches=0
	for v in fixture.checks:
		var distance=F.squared_distance(int(v.a[0]),int(v.a[1]),int(v.b[0]),int(v.b[1]))
		var reached=F.value(distance)<=F.value(F.multiply(0x3efae148,0x3efae148))
		var native_reached=int(v.native_next_index)==0 if int(v.remaining)==1 else int(v.native_return)==4
		if reached!=native_reached:mismatches+=1
	check(fixture.checks.size()==1210 and mismatches==0,"1210 original intermediate-waypoint transitions",str(mismatches)+" mismatches")
	for distance in [10.0,15.0,16.0]:
		var s=Sim.new()
		s.players[0].pos=Vector2(100,100)
		s.players[1].pos=Vector2(1500,1000)
		s.command(0,Vector2(600,100))
		s.players[0].path=[Vector2(100+distance,100),Vector2(600,100)]
		s.players[0].replan=1
		s.step_movement()
		check(s.players[0].path.size()==(1 if distance<15.68 else 2),"intermediate threshold at "+str(distance)+" units")
		check(absf(s.players[0].pos.x-109)<0.01,"next segment can move in same tick at "+str(distance)+" units",str(s.players[0].pos))
	var s=Sim.new()
	s.players[0].pos=Vector2(100,100)
	s.players[0].angle=PI
	s.players[1].pos=Vector2(1500,1000)
	s.command(0,Vector2(600,100))
	s.players[0].path=[Vector2(110,100),Vector2(600,100)]
	s.players[0].replan=1
	s.step_movement()
	check(s.players[0].path.size()==1 and s.players[0].pos==Vector2(100,100),"fine route advances without waiting for heading; forward movement still waits")
	var file=FileAccess.open("res://research/waypoint-tests.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":fixture.scope,"checks":results},"\t"))
	quit(1 if failed else 0)
