extends RefCounted
## Held balls use the map's range-entry trigger, unlike free-ball interception.
## Snapshot after takeOwnership relocates the ball: relocation itself must not
## create an endless chain of overlapping owners stealing it back next tick.
const RANGE=90.0
static func held_position(sim,index: int) -> Vector3:
	var p=sim.players[index]
	var origin=Vector3(p.pos.x,p.pos.y,p.z)
	var offset=Vector3(cos(p.body)*100,sin(p.body)*100,0)
	var wall=sim.arena.sweep_ball(origin,offset)
	return origin+offset*(maxf(0,wall.t-0.002) if not wall.is_empty() else 1.0)

static func snapshot(sim) -> Dictionary:
	var contacts={}
	for i in range(sim.players.size()):contacts[i]=sim.ball-sim.Characters.world_position(sim.players[i])
	return contacts

static func relocated(sim,index: int):
	# Teleports test the destination, never an imaginary path through players.
	if sim.holder==index:
		sim.ball=held_position(sim,index);sim.previous_ball=sim.ball
		sim.held_ball_contacts.clear()
	else:sim.held_ball_contacts.erase(index)

static func entered(sim,old_ball: Vector3,contacts: Dictionary) -> Dictionary:
	var best={}
	for i in range(sim.players.size()):
		var p=sim.players[i]
		if i==sim.holder or sim.has_ball(i) or not sim.Characters.catchable(p):continue
		var relative: Vector3=sim.ball-sim.Characters.world_position(p)
		var prior: Vector3=contacts.get(i,relative)
		var previous_xy=Vector2(prior.x,prior.y)
		var inside_before=contacts.has(i) and previous_xy.length_squared()<=RANGE*RANGE
		if inside_before:continue
		var entry=0.0
		if previous_xy.length_squared()>RANGE*RANGE:
			var hit=sim.Arena.circle_hit(previous_xy,Vector2(relative.x-prior.x,relative.y-prior.y),Vector2.ZERO,RANGE)
			if hit.is_empty():continue
			entry=hit.t
		var height=lerpf(prior.z,relative.z,entry)
		if height< -RANGE or height>p.catch_height:continue
		var point=old_ball.lerp(sim.ball,entry) if contacts.has(i) else sim.ball
		var hand=point-prior.lerp(relative,entry);hand.z=point.z
		if not sim.arena.sweep_pickup(hand,point-hand).is_empty():continue
		if best.is_empty() or entry<best.t:best={"t":entry,"player":i}
	return best
