extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
const Skills=preload("res://scripts/original_skill_rules.gd")
var results=[]
var failed=false

func check(ok: bool,name: String,detail=""):
	results.append({"test":name,"passed":ok,"detail":detail})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))

func fresh():
	var s=Sim.new()
	s.players[0].pos=Vector2(-600,0)
	s.players[1].pos=Vector2(1200,900)
	return s

func _initialize():call_deferred("run")

func run():
	# Assertions are derived from the preserved map bodies, not native captures.
	var s=fresh()
	s.players[0].tackle=640
	for i in range(14):s.step_ball()
	check(s.players[0].tackle>0,"tackle remains active after fourteen full steps")
	s.step_ball()
	check(s.players[0].tackle==0 and absf(s.players[0].pos.x-69)<0.002,"fifteenth step ends at 669 units; nominal range is not clamped")
	s=fresh()
	s.arena.add_box(Rect2(-570,-300,32,600),200)
	s.players[0].tackle=640
	for i in range(15):s.step_ball()
	check(s.players[0].pos==Vector2(-600,0) and s.players[0].tackle==0,"blocked steps still consume tackle range")
	s=fresh()
	s.players[1].pos=Vector2(-450,0)
	s.players[0].tackle=640
	s.step_ball()
	check(s.players[0].tackle==0 and s.players[0].knock==Vector2(5,0) and s.players[1].knock==Vector2(10,0),"frontal hit ends tackle and applies 5/10 impulses")
	check(s.players[1].slow==1.5,"enemy receives 1.5 second slow")
	s=fresh()
	s.players[1].team=0
	s.players[1].pos=Vector2(-450,0)
	s.players[0].tackle=640
	s.step_ball()
	check(s.players[1].knock==Vector2(10,0) and s.players[1].slow==0,"ally receives frontal push without enemy slow")
	s=fresh()
	s.players[1].pos=Vector2(-500,150)
	s.players[0].tackle=640
	s.step_ball()
	check(s.players[1].slow==1.5 and s.players[0].tackle>0 and s.players[1].knock==Vector2.ZERO,"side target is slowed without frontal hit")
	s.step_ball()
	check(absf(s.players[1].slow-1.46875)<0.0001,"remaining inside area does not refresh existing slow")
	check(not Skills.tackle_contact(Vector2(201,0),0,true,false).slow,"outside 200 range is unaffected")
	check(Skills.tackle_contact(Vector2(140,0),0,true,false).hit and not Skills.tackle_contact(Vector2(141,0),0,true,false).hit,"frontal push has a separate 140 range")
	check(Skills.tackle_contact(Vector2.from_angle(deg_to_rad(31))*100,0,true,false).hit and not Skills.tackle_contact(Vector2.from_angle(deg_to_rad(33))*100,0,true,false).hit,"frontal cone has 32 degree half-angle")
	s=fresh()
	s.arena.add_box(Rect2(-570,-300,10,600),200)
	s.players[1].pos=Vector2(-500,0)
	s.players[0].tackle=640
	s.step_ball()
	check(s.players[1].knock==Vector2(10,0),"original tackle area has no line-of-sight filter")
	s=fresh()
	s.players[0].tackle=640
	s.take(0)
	check(not s.kick(0,Vector2(600,0)),"cannot kick during active tackle")
	s.stop(0)
	for i in range(15):s.step_ball()
	check(absf(s.players[0].pos.x-69)<0.002,"stop order does not cancel scripted tackle travel")
	s=fresh()
	s.players[0].knock=Vector2(10,0)
	s.step_ball()
	check(absf(s.players[0].pos.x+590.65)<0.001,"ground friction is subtracted before first displacement")
	for i in range(20):s.step_ball()
	check(absf(s.players[0].pos.x+528)<0.002 and s.players[0].knock==Vector2.ZERO,"10-unit ground impulse settles after 72 units")
	var pair=Skills.contact_exchange(Vector2(8,3),Vector2(-2,1),Vector2(60,0))
	check(pair[0]==Vector2(-2,3) and pair[1]==Vector2(8,1),"contact exchanges normal velocity and retains tangent velocity")
	pair=Skills.contact_exchange(Vector2(-8,0),Vector2.ZERO,Vector2(60,0))
	check(pair[0]==Vector2(-8,0) and pair[1]==Vector2.ZERO,"separating units do not exchange momentum")
	var f=FileAccess.open("res://research/skill-rules-tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"basis":"Unchanged local JASS source; not a native runtime equivalence claim","checks":results},"\t"))
	quit(1 if failed else 0)
