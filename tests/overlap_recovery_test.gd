extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var checks=[]
var failed=false

func check(ok: bool,name: String,detail=""):
	checks.append({"test":name,"passed":ok,"detail":str(detail)})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))

func scene(offset=Vector2.ZERO):
	var s=Sim.new()
	s.players[0].pos=Vector2(-400,0);s.players[1].pos=s.players[0].pos+offset
	s.players[0].body=0;s.players[0].angle=0;s.ball=Vector3(1300,-900,0)
	return s

func walk(s,steps=400):
	var crossed=false;var teleported=false;var last=s.players[0].pos
	for n in range(steps):
		s.step_movement()
		crossed=crossed or not s.arena.point_free(s.players[0].pos,30)
		teleported=teleported or last.distance_to(s.players[0].pos)>9.001
		last=s.players[0].pos
	return not crossed and not teleported

func _initialize():call_deferred("run")

func run():
	var s=scene();s.command(0,Vector2(600,0))
	check(walk(s) and s.players[0].pos.distance_to(Vector2(600,0))<=16,"coincident restored footprints can walk apart",s.players[0].pos)
	for offset in [Vector2(-35,0),Vector2(35,0),Vector2(0,25),Vector2(0,-25)]:
		s=scene(offset);s.arena.add_box(Rect2(-200,-300,70,600),200)
		s.command(0,Vector2(600,0))
		check(walk(s,650) and s.players[0].pos.distance_to(Vector2(600,0))<=16,"overlap escape then detour preserves target "+str(offset),s.players[0].pos)
	s=scene(Vector2(35,0));s.arena.add_box(Rect2(-1000,48,2000,1400),200);s.arena.add_box(Rect2(-1000,-1448,2000,1400),200)
	s.command(0,Vector2(400,0));var stationary=s.players[1].pos
	check(walk(s) and s.players[0].pos.distance_to(stationary)>=59.99 and s.players[0].want_move,"closed narrow corridor separates safely and waits",s.players[0].pos)
	s.players[1].pos=Vector2(1200,0)
	check(walk(s) and s.players[0].pos.distance_to(Vector2(400,0))<=16,"waiting escape route resumes after blocker leaves",s.players[0].pos)
	s=scene(Vector2(35,0));s.command(0,Vector2(600,0));s.stop(0);var before=s.players[0].pos
	for n in range(120):s.step_movement()
	check(s.players[0].pos==before and not s.players[0].want_move,"stop cancels pending recovery")
	s=scene(Vector2(35,0));s.set_unit_pathing(0,false);s.command(0,Vector2(600,0))
	check(s.players[0].route_status=="moving" and s.players[0].path==[Vector2(600,0)],"phased player keeps direct path")
	s=scene(Vector2(35,0));s.arena.add_box(Rect2(-200,-300,70,600),200);s.command(0,Vector2(600,0));s.command(0,Vector2(-1000,0))
	check(walk(s) and s.players[0].pos.distance_to(Vector2(-1000,0))<=16,"new command replaces recovery destination")
	var a=scene(Vector2(35,0));var b=scene(Vector2(35,0))
	for sim in [a,b]:
		sim.arena.add_box(Rect2(-200,-300,70,600),200);sim.command(0,Vector2(600,0))
	for n in range(300):a.advance(1.0/30)
	for n in range(1440):b.advance(1.0/144)
	check(a.players[0].pos.is_equal_approx(b.players[0].pos) and a.players[0].path==b.players[0].path,"overlap routing is independent of render FPS")
	var f=FileAccess.open("res://research/overlap-recovery-tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks},"\t"))
	quit(1 if failed else 0)
