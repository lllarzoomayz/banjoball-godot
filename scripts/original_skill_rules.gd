extends RefCounted
## Direct vector algebra from the local map's unchanged JASS functions.
## This file does not claim to reproduce native terrain snapping or cast facing.
const TACKLE_SPEED=44.6
const TACKLE_RANGE=640.0
const TACKLE_AOE=200.0
const TACKLE_HIT_RANGE=140.0
const TACKLE_CONE=32.0
const TACKLE_PUSH=10.0
const GROUND_FRICTION=0.65

static func tackle_contact(offset: Vector2,facing: float,enemy: bool,already_slow: bool) -> Dictionary:
	return tackle_contact_3d(Vector3(offset.x,offset.y,0),facing,enemy,already_slow)

static func tackle_contact_3d(offset: Vector3,facing: float,enemy: bool,already_slow: bool) -> Dictionary:
	var distance=offset.length()
	if distance>TACKLE_AOE:return {"slow":false,"hit":false}
	# s__Tackle_tackle: enemy filtering applies ONLY to the slow. Allies also
	# receive frontal push, and an existing slow is NOT refreshed every tick.
	# The range is spherical, but the cone still uses horizontal Atan2(y,x).
	var angle=acos(clampf(cos(facing-atan2(offset.y,offset.x)),-1,1))
	return {"slow":enemy and not already_slow,"hit":distance<=TACKLE_HIT_RANGE and angle<=deg_to_rad(TACKLE_CONE)}

static func ground_impulse(velocity: Vector2) -> Vector2:
	# s__Object_iterate32 subtracts friction BEFORE displacement, stopping at <=.
	return velocity.normalized()*maxf(0,velocity.length()-GROUND_FRICTION)

static func object_velocity(height: float,velocity: Vector3,ground_friction: float=GROUND_FRICTION) -> Vector3:
	if height>=1:velocity.z-=1.5
	return velocity.normalized()*maxf(0,velocity.length()-(0.08 if height>=1 else ground_friction))

static func contact_exchange(a: Vector2,b: Vector2,offset: Vector2) -> Array:
	# s__Object_collision: exchange normal components, retain tangent components.
	# Ground-plane specialization; original allows vertical difference <=100.
	if offset.length_squared()<0.000001:return [a,b]
	if a.dot(b)<=0:
		if a.dot(offset)<=0:return [a,b]
	else:
		var l1=a.length() if a.dot(offset)<=0 else b.length()
		var l2=b.length() if a.dot(offset)<=0 else a.length()
		if l1>=l2:return [a,b]
	var n=offset.normalized()
	return [a-n*a.dot(n)+n*b.dot(n),b-n*b.dot(n)+n*a.dot(n)]

static func contact_allowed_3d(a: Vector3,b: Vector3,d: Vector3) -> bool:
	if d.length_squared()<0.000001:return false
	if a.dot(b)<=0:
		if a.dot(d)<=0:return false
	else:
		var l1=a.length() if a.dot(d)<=0 else b.length()
		var l2=b.length() if a.dot(d)<=0 else a.length()
		if l1>=l2:return false
	return true

static func contact_exchange_3d(a: Vector3,b: Vector3,d: Vector3) -> Array:
	if not contact_allowed_3d(a,b,d):return [a,b]
	var n=d.normalized()
	# JASS rotates x/y but retains z for the second projection; preserve it.
	var tangent=Vector3(-d.y,d.x,d.z).normalized()
	return [n*b.dot(n)+tangent*a.dot(tangent),n*a.dot(n)+tangent*b.dot(tangent)]
