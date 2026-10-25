extends RefCounted
## Joystick orders carry a direction, never a destination for the route planner.
## The same fixed movement clock, turn readiness and speed modifiers still apply.
static func order(sim,index: int,direction: Vector2):
	if not sim.unit_present(index):return
	var p=sim.players[index]
	if not p.shot_order.is_empty():
		p.shot_order.resume_axis=direction.normalized() if direction.length_squared()>=.0001 else Vector2.ZERO
		return
	if p.cast_pending or p.ability_delay>0 or p.flight_steps>0:return
	if direction.length_squared()<0.0001:release(p);return
	sim.InjuryRules.cancel_pose(p);p.keeper_pose=0.0
	p.direct_axis=direction.normalized();p.path=[];p.ability_order.clear()
	if p.ability_kind in ["black_hole","swap","hook","rift"]:p.disabled=0
	p.target=p.pos+p.direct_axis*360;p.destination=p.target
	p.want_move=true;p.route_status="direct";p.stuck=0.0
	sim.SurfaceRules.smart_order(p,p.target);sim.start_object(index)
	if p.possess_time>0:sim.Characters.possess_order(sim,index,p.target)

static func release(p: Dictionary):
	if not p.shot_order.is_empty():p.shot_order.resume_axis=Vector2.ZERO
	p.direct_axis=Vector2.ZERO;p.path=[];p.moving=false;p.want_move=false
	p.slide_order=false;p.route_status="idle"

static func step(sim,index: int):
	var p=sim.players[index];var axis: Vector2=p.direct_axis
	# Keep the ice order ahead of a held stick, instead of arriving at a stale point.
	p.target=p.pos+axis*360;p.destination=p.target;p.slide_target=p.target
	var error=sim.FloatMath.movement_geometry(axis*360,p.angle).y
	var speed=sim.walking_speed(index)
	var turn=sim.Native.turn_step(error,p.angle,p.turn,deg_to_rad(60),0,speed,false)
	p.angle=wrapf(turn.y,-PI,PI)
	if turn.x<=0 or p.tackle>0 or p.z>=1:return
	# Translation follows the stick; the animated body retains its normal turn.
	var remaining=axis*speed*sim.MOVE_DT
	for _iteration in range(4):
		if remaining.length_squared()<0.000001:break
		# Physical walls/units use the unit radius. GoalBlock is a CENTER entry
		# trigger, so don't expand it into an invisible wall before that entry.
		var hit=sim.unit_sweep(p.pos,remaining,index,true,0,false)
		if hit.is_empty():p.pos+=remaining;break
		p.pos+=remaining*maxf(0,hit.t-0.0001)
		var unused=remaining*(1.0-hit.t)
		remaining=unused.slide(hit.normal)
		# Rounded corners must not manufacture a sideways input or accelerate it.
		remaining.x=clampf(remaining.x,minf(0,unused.x),maxf(0,unused.x))
		remaining.y=clampf(remaining.y,minf(0,unused.y),maxf(0,unused.y))
	sim.repair_goal_entry(index,p.previous)
	p.route_status="direct_blocked" if p.pos.distance_to(p.previous)<0.01 else "direct"
