extends RefCounted
## Normal pass/shot orders prepare facing before calling the map's kick impulse.
## Readiness uses a dedicated +/-60-degree cone around the visible body.
## This is a user-requested feel setting, not verified native W spell timing.
## Locomotion heading still drives the turn, but adds no second firing gate.
const HALF_ANGLE: float=PI/3.0
const ANGLE_EPSILON: float=0.000001
static func allowed(sim,index: int) -> bool:
	if not sim.unit_present(index) or not sim.has_ball(index):return false
	var p=sim.players[index]
	return p.tackle<=0 and p.disabled<=0 and p.stun<=0 and p.silence<=0 and p.hooked==0 and p.ability_delay<=0 and not p.cast_pending and not sim.Characters.absent(p)

static func cancel(p: Dictionary):
	p.shot_order.clear()

static func ball_position(sim,index: int) -> Vector2:
	var position: Vector3=sim.ball if sim.holder==index else sim.Copies.held(sim,index).position
	return Vector2(position.x,position.y)

static func ready(p: Dictionary) -> bool:
	var facing: float=p.shot_order.direction.angle()
	return absf(wrapf(facing-p.body,-PI,PI))<=HALF_ANGLE+ANGLE_EPSILON

static func request(sim,index: int,target: Vector2,power: float=30.0,lift: float=7.0) -> bool:
	if not target.is_finite() or not allowed(sim,index):return false
	var p=sim.players[index]
	var direction=(target-ball_position(sim,index)).normalized()
	if direction.length_squared()<.01:return false
	var resume: Vector2=p.shot_order.get("resume_axis",p.direct_axis)
	sim.stop(index,false)
	p.shot_order={"direction":direction,"resume_axis":resume,"possession":p.possession_serial,"power":power,"lift":lift}
	if ready(p):finish(sim,index,true)
	else:sim.notice="转身准备射门。"
	return true

static func finish(sim,index: int,fire: bool):
	var p=sim.players[index];var order: Dictionary=p.shot_order.duplicate()
	cancel(p)
	if fire:
		# Freeze the preview's direction, not its world endpoint: the held ball
		# moves around the player as they turn and must not rotate the chosen ray.
		sim.kick(index,ball_position(sim,index)+order.direction*1600,order.power,order.lift)
	elif sim.notice=="转身准备射门。":sim.notice="射门已中断。"
	# A neutral/released stick never restarts movement. The latest stick order
	# during preparation supersedes the direction held when shooting began.
	if order.resume_axis!=Vector2.ZERO:sim.DirectionalMotion.order(sim,index,order.resume_axis)

static func step(sim,index: int) -> bool:
	var p=sim.players[index]
	if p.shot_order.is_empty():return false
	if not allowed(sim,index) or p.possession_serial!=p.shot_order.possession:
		finish(sim,index,false);return true
	var error=wrapf(p.shot_order.direction.angle()-p.angle,-PI,PI)
	p.angle=wrapf(sim.Native.turn_step(error,p.angle,p.turn,0,0,0,true).y,-PI,PI)
	sim.advance_body(p)
	if ready(p):finish(sim,index,true)
	return true
