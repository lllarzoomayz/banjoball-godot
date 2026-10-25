extends RefCounted
## war3map.j Jump___jump / Jump___isUnitGoalkeeper. Hold-position (H)
## activates a shared defensive jump, distinct from the Wisp's ball jump.
const COOLDOWN=2.0
const INTENSITY=29.0
const ANGLE=80.0*PI/180.0

static func impulse(facing: float) -> Vector3:
	return Vector3(cos(facing)*cos(ANGLE),sin(facing)*cos(ANGLE),sin(ANGLE))*INTENSITY

static func goalkeeper(sim,index: int) -> bool:
	var p=sim.players[index]
	if sim.Characters.absent(p) or not sim.arena.in_guard(p.pos,p.team):return false
	var regions=sim.arena.guards[p.team]
	var center=(regions[0].get_center()+regions[1].get_center())/2.0
	var closest=-1;var distance=INF
	# The source enumerates actual units in both rectangles, without a roster
	# role test. Locust props/balls are not enumerated; possessed players are absent.
	for i in range(sim.players.size()):
		var other=sim.players[i]
		if sim.Characters.absent(other) or not sim.arena.in_guard(other.pos,p.team):continue
		var d=other.pos.distance_squared_to(center)
		if d<distance:closest=i;distance=d
	return closest==index

static func eligible(sim,index: int) -> bool:
	var p=sim.players[index]
	if sim.match_enabled and sim.match_state!="playing":return false
	if p.keeper_cooldown>0 or sim.holder==index:return false
	# Disabled/absent units cannot issue the native order. Silence is NOT a spell
	# gate for H, and the original has no explicit ground-height requirement.
	if p.disabled>0 or p.stun>0 or p.hooked!=0 or sim.Characters.absent(p):return false
	return goalkeeper(sim,index)

static func hold(sim,index: int) -> bool:
	var p=sim.players[index]
	if sim.match_enabled and sim.match_state!="playing":return false
	if p.disabled>0 or p.stun>0 or p.hooked!=0 or sim.Characters.absent(p):return false
	sim.stop(index,false)
	if not eligible(sim,index):
		if index==sim.controlled:
			sim.notice="已站定。持有真球时不能起跳。" if sim.holder==index else ("已站定。起跳冷却还需 %.1f 秒。"%p.keeper_cooldown if p.keeper_cooldown>0 else "已站定。进入本方门区、不持有真球时可按 H 起跳。")
		return false
	sim.apply_impulse(index,impulse(p.body))
	p.action=0.0
	p.keeper_cooldown=COOLDOWN;p.keeper_pose=COOLDOWN
	p.keeper_origin=sim.Characters.world_position(p)
	var effect=sim.emit_visual("fx_jump",Vector3(p.pos.x,p.pos.y,0))
	effect.destroy_after=COOLDOWN;effect.on_terrain=true
	if index==sim.controlled:sim.notice="守门起跳：空中靠近高球即可接住；冷却 2 秒。"
	return true

static func step(sim):
	for p in sim.players:
		p.keeper_cooldown=maxf(0,p.keeper_cooldown-sim.BALL_DT)
		p.keeper_pose=maxf(0,p.keeper_pose-sim.BALL_DT)

static func clear(sim):
	for p in sim.players:p.keeper_cooldown=0.0;p.keeper_pose=0.0

static func should_jump(sim,index: int,view: Dictionary) -> bool:
	# Added singleplayer AI: predict only the observed ball, so enemy decoys
	# can fool a keeper. Use normal impulse and flight rules, with no teleport.
	var p=sim.players[index]
	if not eligible(sim,index) or view.holder>=0 or p.z>1:return false
	var position: Vector3=view.position;var velocity: Vector3=view.velocity
	var own_goal: Vector2=sim.arena.goals[p.team].get_center()
	if Vector2(velocity.x,velocity.y).dot(own_goal-Vector2(position.x,position.y))<=0:return false
	var jump_pos=sim.Characters.world_position(p)
	var jump_velocity=sim.ObjectMotion.check_force(sim.arena,jump_pos,Vector3(p.knock.x,p.knock.y,p.vz)+impulse(p.body))
	for tick in range(1,15):
		var motion=sim.BallFlight.integrate(position,velocity,sim.powershot_active,sim.SurfaceRules.ball_friction(sim))
		var flight=sim.BallFlight.travel(sim.arena,position,motion.velocity,motion.delta,func(_a,_b):return {},0.0 if sim.powershot_active else 4.0)
		position=flight.position;velocity=flight.velocity
		if flight.event=="goal":return false
		jump_velocity=sim.Skills.object_velocity(jump_pos.z,jump_velocity,sim.SurfaceRules.player_friction(sim))
		var movement=sim.ObjectMotion.travel(sim.arena,jump_pos,jump_velocity,p.radius,sim.goal_restrictions(index),index,p.ogre_slow>0,p.team)
		jump_pos=movement.position;jump_velocity=movement.velocity
		jump_pos.z+=jump_velocity.z
		if jump_pos.z<0:jump_pos.z=0;jump_velocity.z=maxf(0,-jump_velocity.z-15)
		# Do not spend a jump for a ball already reachable from the ground.
		if position.z<=p.catch_height+15:continue
		if Vector2(position.x-jump_pos.x,position.y-jump_pos.y).length()>90:continue
		if position.z-jump_pos.z < -90 or position.z-jump_pos.z>p.catch_height:continue
		var hand=Vector3(jump_pos.x,jump_pos.y,position.z)
		if sim.arena.sweep_ball(hand,position-hand).is_empty():return true
	return false
