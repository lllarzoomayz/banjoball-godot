extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
const Motion=preload("res://scripts/object_motion.gd")
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func fixture():
	var s=Sim.new();s.start_practice();s.bot_enabled=false
	s.players[0].pos=Vector2(2020,700);s.players[1].pos=Vector2(-1000,-900)
	return s
func flashes(s):return s.native_visuals.filter(func(e):return e.model=="fx_player_bump")
func run():
	for speed in [-50.0,0.0,29.9,30.0,30.01,50.0]:
		var s=fixture();var rng=s.random.state
		var input=Vector3(speed,40,0);var position=Sim.Characters.world_position(s.players[0])
		var expected=Motion.check_force(s.arena,position,input)
		s.apply_impulse(0,input)
		check(Vector3(s.players[0].knock.x,s.players[0].knock.y,s.players[0].vz).is_equal_approx(expected),"force math unchanged "+str(speed))
		check(flashes(s).size()==(1 if speed>30 else 0),"only incoming normal strictly above thirty emits "+str(speed))
		check(s.random.state==rng,"no RNG consumed "+str(speed))
		if speed>30:
			var event=flashes(s)[0]
			check(event.pos==position and event.scale==.7 and event.pitch==0 and absf(wrapf(event.facing-PI,-PI,PI))<.001,"original snapshot, scale and reverse facing "+str(speed))
			s.apply_impulse(0,Vector3.ZERO)
			check(flashes(s).size()==1,"already outward result does not flash on zero force "+str(speed))
	var s=fixture();s.players[0].pos=Vector2(0,0);s.apply_impulse(0,Vector3(50,40,0))
	check(flashes(s).is_empty(),"force away from boundary regions has no wall effect")
	for z in [-1.0,0.0,100.0,101.0]:
		s=fixture();s.players[0].z=z
		s.arena.boundaries=[{"rect":Rect2(2000,600,200,200),"normal":Vector3.LEFT,"low":0.0,"high":100.0,"name":"height_fixture"}]
		s.apply_impulse(0,Vector3(50,40,0))
		check(flashes(s).size()==(1 if z>=0 and z<=100 else 0),"height interval is inclusive and out-of-range silent "+str(z))
	# Two overlapping source regions process the successively modified vector.
	s=fixture();s.arena.boundaries=[
		{"rect":Rect2(-100,-100,200,200),"normal":Vector3.LEFT,"low":0,"high":100,"name":"x"},
		{"rect":Rect2(-100,-100,200,200),"normal":Vector3(0,-1,0),"low":0,"high":100,"name":"y"}]
	s.players[0].pos=Vector2.ZERO;s.players[0].z=50
	s.apply_impulse(0,Vector3(50,50,0))
	check(flashes(s).size()==2 and s.players[0].knock.is_equal_approx(Vector2(-35,-35)),"corner emits once for each qualifying region in source order")
	s=fixture();s.players[0].pos=Vector2(2400,100);s.players[0].z=60;s.players[0].knock=Vector2(50,-12);s.players[0].vz=8
	var expected=Motion.goal_response(s.arena,Vector3(2400,100,60),Vector3(50,-12,8),1)
	check(s.repair_goal_entry(0,Vector2.ZERO),"actual goal-entry repair executes")
	check(flashes(s).size()==1 and flashes(s)[0].pos==Vector3(2016,488,60),"goal repair forwards BoundaryCheck flash at repaired coordinates")
	check(s.players[0].pos==Vector2(expected.position.x,expected.position.y) and Vector3(s.players[0].knock.x,s.players[0].knock.y,s.players[0].vz)==expected.velocity,"goal nested checks leave exact velocity intact")
	check(s.skill_effects.size()==1 and s.skill_effects[0].model=="fx_goal_block","blue goal protection remains a separate original event")
	# Live collision recipients can receive a force while already inside a wall.
	s=fixture();s.players[0].pos=Vector2(1950,700);s.players[0].knock=Vector2(50,0);s.players[1].pos=Vector2(2020,700)
	s.step_object(0)
	check(flashes(s).size()==2,"player collision publishes contact plus recipient force-addition wall flash")
	check(flashes(s)[1].pos==Vector3(2020,700,0),"recipient boundary flash is not misplaced at the initiating player")
	# Nonplayer/ball math has no PLAYER type, even with a large normal force.
	s=fixture();var adapter=s.prepare_apocalypse()
	var object={"pos":Vector3(2020,700,0),"apoc_velocity":Vector3.ZERO}
	adapter.apply_nonplayer(object,Vector3(80,40,0))
	check(flashes(s).is_empty() and adapter.visuals.is_empty(),"nonplayer BoundaryCheck emits no player flash")
	# AI prediction uses the pure API and must not fabricate gameplay effects.
	s=fixture();s.players[0].pos=s.arena.guards[0][0].get_center();s.players[0].knock=Vector2(60,0)
	s.arena.boundaries=[{"rect":Rect2(s.players[0].pos-Vector2(100,100),Vector2(200,200)),"normal":Vector3.LEFT,"low":0,"high":1000,"name":"prediction"}]
	check(s.KeeperRules.eligible(s,0),"keeper prediction fixture meets real eligibility")
	var view={"holder":-1,"position":Vector3(s.players[0].pos.x+180,s.players[0].pos.y,300),"velocity":Vector3(-40,0,-1)}
	s.KeeperRules.should_jump(s,0,view)
	check(s.native_visuals.is_empty(),"keeper planning never emits a BoundaryCheck flash")
	# Only the actual input invokes the live force-addition path.
	check(s.KeeperRules.hold(s,0) and flashes(s).size()==1,"actual keeper jump still produces qualifying wall effect")
	FileAccess.open("res://research/force-flash-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("FORCE FLASH CHECKS ",passed," passed; ",failures.size()," failed")
	quit(0 if failures.is_empty() else 1)
