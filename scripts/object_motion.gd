extends RefCounted
## Original Object boundary responses. Contact timing uses continuous sweeps;
## native region rasterization and SetUnitPosition recovery remain separate.
const PLAYER_LOSS=15.0
const GOAL_FACTOR=0.5

static func contact_flash(a: Vector3,b: Vector3,origin: Vector3,offset: Vector3) -> Dictionary:
	# Object_collision: compare signed normal projections BEFORE exchanging
	# momentum; strict >30, XY midpoint, and the initiating object's Z.
	if offset.length_squared()<0.000001:return {}
	if absf((a-b).dot(offset.normalized()))<=30.0:return {}
	return {"pos":Vector3(origin.x+offset.x*.5,origin.y+offset.y*.5,origin.z),"facing":atan2(offset.y,offset.x)+PI,"scale":.7,"pitch":0}

static func landing_flash(position: Vector2,vertical_speed: float,world_height_offset: float) -> Dictionary:
	# Object_iterate32 uses the incoming post-gravity velocity, strictly <-30,
	# and passes ABSOLUTE Z=0 to Sfx. Keep that request in event coordinates;
	# the renderer resolves SetUnitFlyHeight against the actual terrain.
	if vertical_speed>=-30.0:return {}
	return {"pos":Vector3(position.x,position.y,-world_height_offset),"scale":.7,"facing":0.0,"pitch":90,"sfx_clamp_to_terrain":true}

static func boundary_reflect(velocity: Vector3,normal: Vector3) -> Vector3:
	var inward=velocity.dot(normal)
	if inward>=0:return velocity
	# Boundary__deflection reduces the reversed NORMAL component only when
	# it is strictly greater than 15. Smaller player impacts fully rebound.
	var outgoing=-inward
	if outgoing>PLAYER_LOSS:outgoing-=PLAYER_LOSS
	return velocity+normal*(outgoing-inward)

static func check_force(arena,position: Vector3,velocity: Vector3,loss: float=PLAYER_LOSS,player_flash: Callable=Callable()) -> Vector3:
	# BoundaryCheck is a distinct callback used when adding force to an object
	# already in a boundary. Preserve its unusual tangent-length condition.
	for boundary in arena.boundaries:
		if position.z<boundary.low or position.z>boundary.high:continue
		if not boundary.rect.has_point(Vector2(position.x,position.y)):continue
		var inward=velocity.dot(boundary.normal)
		if inward>=-0.000001:continue
		var reverse: Vector3=-boundary.normal*inward
		# Only live PLAYER callers supply this sink. Ball/nonplayer response and
		# predictive keeper queries must never publish a player contact effect.
		if reverse.length()>30.0 and player_flash.is_valid():player_flash.call(position,reverse)
		velocity+=reverse
		if loss>0 and velocity.length()>loss:
			velocity=velocity.normalized()*(velocity.length()-loss)+reverse
	return velocity

static func goal_exit(arena,position: Vector2,team: int) -> Dictionary:
	var front: Rect2=arena.guards[team][0]
	var area: Rect2=arena.guards[team][1]
	var left=area.get_center().x<0
	var exit_x=front.end.x+40.0 if left else front.position.x-10.0
	var x=position.x;var y=position.y
	if absf(x)>arena.half_size.x:x=area.end.x if left else area.position.x
	var top=front.end.y+40.0;var bottom=front.position.y-10.0
	var distance=top-y;var edge=top;var normal=Vector2(0,1)
	if y-bottom<=distance:distance=y-bottom;edge=bottom;normal=Vector2(0,-1)
	if distance<absf(x-exit_x):return {"position":Vector2(x,edge),"normal":normal,"origin":Vector2(x,y)}
	return {"position":Vector2(exit_x,y),"normal":Vector2(1,0) if left else Vector2(-1,0),"origin":Vector2(x,y)}

static func goal_response(arena,position: Vector3,velocity: Vector3,team: int,player_flash: Callable=Callable()) -> Dictionary:
	# GoalBlock__enter: first repair coordinates, then add the reversed normal
	# projection twice (second time at half length for players). Both additions
	# dispatch BoundaryCheck, as the original Object_applyVector does.
	var repair=goal_exit(arena,Vector2(position.x,position.y),team)
	position=Vector3(repair.position.x,repair.position.y,position.z)
	var normal=Vector3(repair.normal.x,repair.normal.y,0)
	var inward=velocity.dot(normal)
	if inward<0:
		var reverse=-normal*inward
		velocity=check_force(arena,position,velocity+reverse,PLAYER_LOSS,player_flash)
		velocity=check_force(arena,position,velocity+reverse*GOAL_FACTOR,PLAYER_LOSS,player_flash)
	var effect=position+Vector3(signf(repair.origin.x-position.x)*50,signf(repair.origin.y-position.y)*50,80)
	return {"position":position,"velocity":velocity,"normal":normal,"effect":effect,"facing":(repair.position-repair.origin).angle()}

static func travel(arena,position: Vector3,velocity: Vector3,radius: float,guards: Array,owner: int,ogre_slow: bool=false,team: int=0,player_flash: Callable=Callable()) -> Dictionary:
	var remaining=1.0
	var effects=[];var smash_stun=false;var smash_stopped=false
	for iteration in range(8):
		var delta=Vector2(velocity.x,velocity.y)*remaining
		if delta.length_squared()<0.00000001:break
		var hit=arena.sweep_object(position,delta,radius,guards,owner)
		if hit.is_empty():
			position.x+=delta.x;position.y+=delta.y;break
		position.x+=delta.x*hit.t;position.y+=delta.y*hit.t
		var normal=Vector3(hit.normal.x,hit.normal.y,0)
		var incoming=-velocity.dot(normal)
		var effect_position=position
		var effect_facing=atan2(normal.y,normal.x)
		if hit.kind=="goal":
			var response=goal_response(arena,position,velocity,hit.team,player_flash)
			position=response.position;velocity=response.velocity;normal=response.normal
			effect_position=response.effect
			effect_facing=response.facing
		elif hit.kind=="pillar":
			velocity=velocity.bounce(normal)*0.9
		elif ogre_slow:
			velocity=Vector3.ZERO;smash_stopped=true
			smash_stun=not arena.in_guard(Vector2(position.x,position.y),team)
		elif hit.kind=="boundary":velocity=boundary_reflect(velocity,normal)
		else:velocity=velocity.slide(normal) # Added practice/terrain solids.
		if incoming>30 or hit.kind=="goal":effects.append({"pos":effect_position,"normal":normal,"kind":hit.kind,"facing":effect_facing})
		if hit.kind not in ["practice","terrain"]:position+=normal*0.01
		remaining*=1.0-hit.t
		if smash_stopped:break
	return {"position":position,"velocity":velocity,"effects":effects,"smash_stun":smash_stun,"smash_stopped":smash_stopped}
