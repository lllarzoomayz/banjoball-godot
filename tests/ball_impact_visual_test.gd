extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
const Flight=preload("res://scripts/ball_flight.gd")
var passed=0
var failures=[]
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func _initialize():
	var s=Sim.new();s.reset()
	s.arena.boundaries=[{"rect":Rect2(100,-500,100,1000),"normal":Vector3.LEFT,"low":0.0,"high":1000.0,"name":"source_boundary"}]
	s.arena.obstacles.clear();s.arena.goals.clear();s.arena.pillars.clear()
	var empty=func(_a,_b):return {}
	for z in [0.0,250.0,251.0,300.0]:
		var result=Flight.travel(s.arena,Vector3(90,0,z),Vector3(20,0,0),Vector3(20,0,0),empty)
		check(result.impacts.size()==(1 if z>250 else 0),"source high-ball threshold "+str(z))
		check(result.velocity.is_equal_approx(Vector3(-16,0,0)),"visual event leaves reflection unchanged "+str(z))
		if z>250:
			check(result.impacts[0].pos.is_equal_approx(Vector3(100,0,z)),"effect at swept contact, before position repair")
			check(absf(result.impacts[0].facing)<.0001,"effect facing follows incoming normal projection")
	var held=Flight.travel(s.arena,Vector3(90,0,300),Vector3(20,0,0),Vector3(20,0,0),func(_a,_b):return {"t":.1,"player":0})
	check(held.event=="catch" and held.impacts.is_empty(),"earlier catch prevents a spurious wall flash")
	s.arena.boundaries.clear();s.arena.add_box(Rect2(100,-500,100,1000),600)
	var practice=Flight.travel(s.arena,Vector3(50,0,300),Vector3(60,0,0),Vector3(60,0,0),empty)
	check(practice.impacts.is_empty(),"added practice boxes do not masquerade as native boundary effects")
	s.arena.obstacles.clear();s.arena.boundaries=[{"rect":Rect2(100,-500,100,1000),"normal":Vector3.LEFT,"low":0.0,"high":1000.0,"name":"source_boundary"}]
	for p in s.players:p.pos=Vector2(-1200,1000)
	s.holder=-1;s.ball=Vector3(90,0,300);s.velocity=Vector3(20,0,0);s.travel_ball(s.velocity)
	check(s.native_visuals.size()==1 and s.native_visuals[0].model=="fx_ball_bump","real simulation publishes the original blue impact model")
	FileAccess.open("res://research/ball-impact-visual-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("BALL IMPACT VISUAL CHECKS ",passed," passed; ",failures.size()," failed")
	quit(0 if failures.is_empty() else 1)
