extends RefCounted
## Shared flight/contact solver for the scoring ball and Trickster copies.
static func integrate(position: Vector3,velocity: Vector3,power: bool=false,ground_friction: float=0.45) -> Dictionary:
	if position.z<1:
		velocity=velocity.normalized()*maxf(0,velocity.length()-(0.02 if power else ground_friction))
	else:
		velocity.z-=1.5
		velocity=velocity.normalized()*maxf(0,velocity.length()-(0.02 if power else 0.07))
	var delta=velocity
	if position.z+delta.z<0 and delta.z<0:
		delta.z=-position.z
		velocity.z=maxf(0,-velocity.z-(0.75 if power else 4.75))
	return {"delta":delta,"velocity":velocity}

static func travel(arena,position: Vector3,velocity: Vector3,delta: Vector3,catch_query: Callable,loss: float=4.0,detect_goals: bool=true,include_pillars: bool=true) -> Dictionary:
	var impacts=[]
	for iteration in range(8):
		var wall=arena.sweep_ball(position,delta,arena.BALL_RADIUS,include_pillars)
		var contact=catch_query.call(position,delta)
		var goal=arena.goal_hit(position,delta) if detect_goals else {}
		var wall_t: float=wall.get("t",INF)
		var catch_t: float=contact.get("t",INF)
		var goal_t: float=goal.get("t",INF)
		if catch_t<wall_t and catch_t<=goal_t:
			return {"impacts":impacts,"position":position+delta*catch_t,"velocity":velocity,"event":"catch","player":contact.player}
		if goal_t<wall_t:
			return {"impacts":impacts,"position":position+delta*goal_t,"velocity":velocity,"event":"goal","team":goal.team,"remaining_delta":delta*(1.0-goal_t)}
		if wall.is_empty():return {"impacts":impacts,"position":position+delta,"velocity":velocity,"event":"none"}
		var contact_position=position+delta*wall.t
		if wall.get("kind","")=="boundary" and contact_position.z>250.0 and velocity.dot(wall.normal)<0:
			var projected: Vector3=wall.normal*velocity.dot(wall.normal)
			impacts.append({"pos":contact_position,"facing":atan2(projected.y,projected.x)})
		position+=delta*wall.t+wall.normal*0.01
		var normal: Vector3=wall.normal
		if wall.has("damping"):
			velocity=velocity.bounce(normal)*wall.damping
			delta=delta.bounce(normal)*wall.damping*(1-wall.t)
			continue
		var speed=velocity.dot(normal)
		if speed<0:velocity-=normal*(speed-maxf(0,-speed-loss))
		var motion=delta.dot(normal)
		delta=(delta-normal*(motion-maxf(0,-motion-loss)))*(1-wall.t)
		if delta.length()<0.001:return {"impacts":impacts,"position":position,"velocity":velocity,"event":"none"}
	return {"impacts":impacts,"position":position,"velocity":Vector3.ZERO,"event":"none"}
