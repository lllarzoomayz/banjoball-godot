extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func fresh():
	var s=Sim.new();s.selected_character="h02C";s.reset();s.bot_enabled=false
	s.players[0].pos=Vector2(-600,0);s.players[1].pos=Vector2(1400,900)
	s.ball=Vector3(1500,-900,0);s.holder=-1;s.velocity=Vector3.ZERO
	s.players[0].ability_target=Vector2.ZERO
	return s
func run():
	# Native IsUnitInRange + original W3U collision sizes, independently of
	# the constants in the port. Check both sides of each boundary.
	for distance in [64.0,90.0,100.0,124.9,125.1,160.0]:
		var s=fresh();s.ball=Vector3(distance,0,0)
		s.Characters.create_pillar(s,0)
		var expected=distance<125
		check((s.velocity.z==17.5)==expected,"birth ball radius at "+str(distance))
		if expected:check(absf(s.velocity.x-(65-distance/3)*0.1)<0.001,"original horizontal force at "+str(distance))
	for distance in [90.0,120.0,154.9,155.1]:
		var s=fresh();s.players[1].pos=Vector2(distance,0)
		s.Characters.create_pillar(s,0)
		check((s.players[1].vz==35)==(distance<155),"birth player adds its native radius at "+str(distance))
	var s=fresh();s.ball=Vector3(100,0,180);s.velocity=Vector3(8,4,-2)
	s.Characters.create_pillar(s,0)
	check(s.velocity.distance_to(Vector3(8+(65.0-100.0/3.0)*0.1,4,15.5))<0.001,"birth adds momentum, with original half-strength vertical impulse for real ball")
	s=fresh();s.ball=Vector3.ZERO;s.Characters.create_pillar(s,0)
	check(s.velocity==Vector3(0,0,17.5),"exact field centre lifts vertically without invented lateral shove")
	s=fresh();s.take(0);s.players[0].ability_target=s.players[0].pos
	s.Characters.create_pillar(s,0)
	check(s.holder==0 and s.velocity==Vector3.ZERO,"held ball is not independently kicked out by pillar birth")
	s=fresh();s.players[0].pos=Vector2(-400,0)
	check(s.Characters.use(s,0,s.players[0].pos),"self-target cast is accepted")
	check(s.players[0].action_clip=="Attack Slam" and is_equal_approx(s.players[0].action,0.3),"original accelerated attack slam windup")
	s.advance(0.28)
	check(s.native_visuals.is_empty() and s.arena.pillars.is_empty(),"no premature impact or pillar")
	s.advance(0.04)
	check(s.native_visuals.size()==8 and s.arena.pillars.is_empty(),"seven trail effects and endpoint at 0.30s, before pillar birth")
	check(s.native_visuals.all(func(e):return Vector2(e.pos.x,e.pos.y)==Vector2(-400,0)),"self cast effects stay at the feet")
	s.advance(0.12)
	check(s.arena.pillars.size()==1 and s.arena.pillars[0].center==Vector2(-400,0) and s.players[0].z>0,"self placement is not shifted away from caster and launches caster")
	s.advance(3.2)
	check(s.arena.pillars.is_empty() and s.native_visuals.size()==8,"expiry removes collision without replaying the onset explosion")
	s=fresh();s.ball=Vector3(100,0,0);s.Characters.create_pillar(s,0)
	var max_z=0.0;var start=s.ball
	for i in range(40):s.advance(1.0/32);max_z=maxf(max_z,s.ball.z)
	check(max_z>80 and s.ball.x-start.x>40,"formerly missed ball travels away and reaches a visible arc")
	s=fresh();s.players[1].pos=Vector2(110,0);s.Characters.create_pillar(s,0);s.Characters.step(s)
	check(s.arena.pillars[0].knocked_units.has(1),"birth immunity survives within native XY range plus player radius")
	s.players[1].pos=Vector2(121,0);s.Characters.step(s)
	check(not s.arena.pillars[0].knocked_units.has(1),"birth immunity resets after leaving XY detection radius")
	FileAccess.open("res://research/pillar-rules-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("PILLAR CHECKS ",passed," passed; ",failures.size()," failed")
	quit(0 if failures.is_empty() else 1)
