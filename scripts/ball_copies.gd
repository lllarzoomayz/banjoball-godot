extends RefCounted
const Flight=preload("res://scripts/ball_flight.gd")

static func held(sim,index: int) -> Dictionary:
	for copy in sim.fake_balls:
		if copy.holder==index and copy.life>0:return copy
	return {}

static func held_position(sim,index: int,include_pillars: bool=true) -> Vector3:
	var p=sim.players[index]
	var origin=Vector3(p.pos.x,p.pos.y,p.z)
	var offset=Vector3(cos(p.body)*100,sin(p.body)*100,0)
	var wall=sim.arena.sweep_ball(origin,offset,sim.arena.BALL_RADIUS,include_pillars)
	return origin+offset*(maxf(0,wall.t-0.002) if not wall.is_empty() else 1.0)

static func create(sim,index: int,keep_real: bool,target: Vector2) -> bool:
	if sim.holder!=index:return false
	if target.distance_to(Vector2(sim.ball.x,sim.ball.y))<0.01:return false
	var p=sim.players[index]
	if p.tackle>0 or p.disabled>0 or p.stun>0 or p.silence>0:return false
	# Ball_addFake has one slot per creator. Reusing it does not refresh its
	# original ten-second expiry, even when another player is holding it.
	var copy={}
	for existing in sim.fake_balls:
		if existing.creator==index and existing.life>0:copy=existing;break
	if copy.is_empty():
		sim.next_fake_id+=1
		copy={"id":sim.next_fake_id,"creator":index,"team":p.team,"position":sim.ball,"previous":sim.ball,"velocity":Vector3.ZERO,"holder":-1,"last_owner":index,"intercept":0,"life":10.0}
		sim.fake_balls.append(copy)
	# Preserve Trickster___cast's take/kick/take order. These takes dispatch
	# global ball events; simply creating a visual copy misses skill resets.
	if keep_real:
		sim.holder=-1;sim.no_steal=0
		take(sim,copy,index)
		kick(sim,copy,target,30,7)
		sim.take(index)
		sim.ball=held_position(sim,index)
	else:
		sim.kick(index,target)
		take(sim,copy,index)
	copy.previous=copy.position
	sim.no_steal=0
	return true

static func kick(sim,copy: Dictionary,target: Vector2,power: float,lift: float) -> bool:
	var index: int=copy.holder
	if index<0:return false
	var p=sim.players[index]
	if p.tackle>0 or p.disabled>0 or p.stun>0 or p.silence>0:return false
	var direction=(target-Vector2(copy.position.x,copy.position.y)).normalized()
	if direction==Vector2.ZERO:return false
	sim.ShotOrder.cancel(p)
	sim.InjuryRules.cancel_pose(p)
	p.slide_order=false
	copy.velocity+=Vector3(direction.x*power,direction.y*power,lift)
	copy.holder=-1;copy.last_owner=index;copy.intercept=5
	p.action=0.7;p.action_clip="Spell";p.cast_pending=false;p.ability_order.clear()
	return true

static func release_held(sim,index: int):
	for copy in sim.fake_balls:
		if copy.holder==index:
			copy.holder=-1;copy.last_owner=index;copy.intercept=5

static func take(sim,copy: Dictionary,index: int):
	if not sim.unit_present(index):return
	if sim.holder==index:return
	var other=held(sim,index)
	if not other.is_empty() and other.id!=copy.id:return
	copy.holder=index;copy.last_owner=index
	sim.players[index].possession_serial+=1
	sim.on_ball_taken()
	copy.velocity=Vector3.ZERO;copy.intercept=0
	copy.position=held_position(sim,index,false)

static func step(sim):
	for copy in sim.fake_balls:
		copy.life-=sim.BALL_DT
		copy.previous=copy.position
		if copy.life<=0:continue
		if copy.holder>=0:
			copy.position=held_position(sim,copy.holder,false)
			for i in range(sim.players.size()):
				if i==copy.holder or sim.has_ball(i) or not sim.Characters.catchable(sim.players[i]):continue
				var p=sim.players[i]
				var height=copy.position.z-p.z
				if p.pos.distance_to(Vector2(copy.position.x,copy.position.y))<90 and height>=-90 and height<=p.catch_height:
					var hand=Vector3(p.pos.x,p.pos.y,copy.position.z)
					if sim.arena.sweep_pickup(hand,copy.position-hand,false).is_empty():take(sim,copy,i);break
		else:
			# Powershot changes global ball friction, including copies. Pillar's
			# original OBJECT filter excludes fake h000 balls, unlike field walls.
			var motion=Flight.integrate(copy.position,copy.velocity,sim.powershot_active,sim.SurfaceRules.ball_friction(sim))
			var contact_query=Callable(sim,"catch_hit").bind(copy.last_owner,copy.intercept,copy.id)
			var result=Flight.travel(sim.arena,copy.position,motion.velocity,motion.delta,contact_query,0.0 if sim.powershot_active else 4.0,false,false)
			for impact in result.impacts:sim.emit_visual("fx_ball_bump",impact.pos,1.0,impact.facing)
			copy.position=result.position;copy.velocity=result.velocity
			if result.event=="catch":take(sim,copy,result.player)
			copy.intercept=maxi(0,copy.intercept-1)
	for copy in sim.fake_balls:
		if copy.life<=0:sim.skill_effects.append({"kind":"fake_pop","pos":copy.position,"life":0.4,"age":0.0,"owner":copy.creator})
	sim.fake_balls=sim.fake_balls.filter(func(c):return c.life>0)
