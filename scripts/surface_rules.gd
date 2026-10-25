extends RefCounted
## Fields__choose and s__Object_isMoving / iterate32 / checkEnd in war3map.j.
## Original selections 3 and 4 are our zero-based frozen fields 2 and 3.
const ICE_BALL_FRICTION=0.30
const ICE_PLAYER_FRICTION=0.40
const ICE_PUSH=0.70
const SLIDE_SPEED_THRESHOLD=20.0
const ARRIVAL_RADIUS=100.0

static func icy(sim) -> bool:
	return sim.arena.field_index in [2,3]

static func ball_friction(sim) -> float:
	return ICE_BALL_FRICTION if icy(sim) else 0.45

static func player_friction(sim) -> float:
	return ICE_PLAYER_FRICTION if icy(sim) else 0.65

static func smart_order(p: Dictionary,target: Vector2):
	# This is an issued-order latch, not animation movement or route progress.
	# Keep the actual click point, independently of the navigation destination.
	p.slide_order=true;p.slide_target=target

static func accelerate(sim,index: int):
	var p=sim.players[index]
	if not icy(sim) or not p.slide_order:return
	# The source tests FULL velocity before adding, without clamping afterward.
	# It also has no ground-height gate on the facing-based horizontal impulse.
	if Vector3(p.knock.x,p.knock.y,p.vz).length()>=SLIDE_SPEED_THRESHOLD:return
	sim.apply_impulse(index,Vector3(cos(p.body),sin(p.body),0)*ICE_PUSH)
	# checkEnd enumerates around this order's target, then checks each enumerated
	# player's OWN target. Arrival cancels further push, not existing momentum.
	for other in sim.players:
		if sim.Characters.absent(other):continue
		if other.pos.distance_to(p.slide_target)<=ARRIVAL_RADIUS and other.pos.distance_to(other.slide_target)<=ARRIVAL_RADIUS:
			other.slide_order=false
