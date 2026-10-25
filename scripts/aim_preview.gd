extends RefCounted
## Read-only indicators in Warcraft world units. No orders, RNG or cloned match.
const Characters=preload("res://scripts/character_rules.gd")
const Flight=preload("res://scripts/ball_flight.gd")
const STEPS=64 # Two seconds of unobstructed motion; no collision queries.
const SAMPLE_STRIDE=4
static var curve_parameters={}

static func spec(p: Dictionary, action: String) -> Dictionary:
	var kit=Characters.kit(p)
	var kind="kick" if action=="kick" else kit.kind
	var result={"kind":kind,"range":1000.0,"radius":0.0,"mode":"direction"}
	match kind:
		"black_hole":result.merge({"mode":"point","range":900.0,"radius":700.0},true)
		"pillar":result.merge({"mode":"point","range":700.0,"radius":Characters.PILLAR_BIRTH_RANGE+Characters.PILLAR_NATIVE_RADIUS},true)
		"rift":result.merge({"mode":"point","range":750.0,"radius":100.0},true)
		"tackle":result.range=669.0;result.radius=140.0 # Fifteen 44.6-unit ticks.
		"hook":result.range=1100.0;result.radius=100.0
		"swap":result.range=2595.2;result.radius=80.0 # 20 start offset + 58 ticks.
		"smash":result.merge({"mode":"self","range":350.0,"radius":200.0},true)
		"slam":result.merge({"mode":"self","range":720.0,"radius":720.0},true)
		"shadow":result.mode="self";result.range=400.0
		"backflip":result.mode="self";result.range=635.0
		"pull","possess","metamorph","none":result.mode="self";result.range=0.0
	if (kind=="hook" and not p.hook.is_empty()) or (kind=="shadow" and p.shadow_return>0) or (kind=="pull" and p.pull_time>0):
		result.mode="self";result.range=0.0
	return result

static func target(p: Dictionary, info: Dictionary, direction: Vector2, strength: float) -> Vector2:
	if direction.length_squared()<0.0001:direction=Vector2.from_angle(p.body)
	var distance: float=info.range
	if info.mode=="point":distance*=clampf(strength,0,1)
	if info.mode=="self":direction=Vector2.from_angle(p.body)
	var offset=direction.normalized()*(distance if info.mode=="point" else maxf(1,distance))
	if info.kind=="pillar" and absf(offset.x)+absf(offset.y)>700:offset*=700.0/(absf(offset.x)+absf(offset.y))
	return p.pos+offset

static func world(point: Vector2,z: float=4.0) -> Vector3:
	return Vector3(point.x,point.y,z)

static func circle(center: Vector2,radius: float) -> PackedVector3Array:
	var points=PackedVector3Array()
	for i in range(33):points.append(world(center+Vector2.from_angle(TAU*i/32.0)*radius))
	return points

static func build(sim,index: int,action: String,point: Vector2) -> Dictionary:
	var p=sim.players[index];var info=spec(p,action);var kind=info.kind
	var out={"lines":[],"areas":[],"trajectory":PackedVector3Array(),"note":"松手施放 · 上滑到取消区取消"}
	var direction=(point-p.pos).normalized();var facing=Vector2.from_angle(p.body)
	if direction==Vector2.ZERO:direction=facing
	if info.mode=="point":
		if kind=="pillar":
			var diamond=PackedVector3Array()
			for v in [Vector2(700,0),Vector2(0,700),Vector2(-700,0),Vector2(0,-700),Vector2(700,0)]:diamond.append(world(p.pos+v))
			out.areas.append(diamond)
		else:out.areas.append(circle(p.pos,info.range))
		out.lines.append(PackedVector3Array([world(p.pos),world(point)]));out.areas.append(circle(point,info.radius))
		out.note="距离 %d · 松手施放"%roundi(p.pos.distance_to(point))
		if kind=="pillar":out.note="脚下施放 · 拖动选择距离" if point.distance_to(p.pos)<0.01 else "距离 %d · 拖回瞄准起点放脚下"%roundi(p.pos.distance_to(point))
	elif info.mode=="direction" and kind not in ["kick","angel","powershot","curve","trickster"]:
		out.areas.append(circle(p.pos,info.range))
		var side=direction.orthogonal()*info.radius
		out.lines.append(PackedVector3Array([world(p.pos+side),world(point+side),world(point-side),world(p.pos-side)]))
		out.lines.append(PackedVector3Array([world(p.pos),world(point)]));out.note="射程 %d · 松手施放"%roundi(info.range)
	elif info.mode=="self":
		out.note="自身技能 · 松手施放"
		if kind=="slam":out.areas.append(circle(p.pos+facing*100,sqrt(720.0*720-300.0*300)))
		elif kind=="smash":
			var footprint=PackedVector3Array([world(p.pos+facing.orthogonal()*200)])
			for i in range(33):
				var side=200.0-400.0*i/32.0
				footprint.append(world(p.pos+facing*sqrt(350.0*350-side*side)+facing.orthogonal()*side))
			footprint.append(world(p.pos-facing.orthogonal()*200));footprint.append(footprint[0]);out.areas.append(footprint)
			var reach=700.0 if sim.last_owner==index else 350.0;var side=facing.orthogonal()*200
			out.lines.append(PackedVector3Array([world(p.pos+side),world(p.pos+facing*reach+side),world(p.pos+facing*reach-side),world(p.pos-side)]))
			out.note="当前朝向 · 蓝色人物范围 / 金色击球范围"
		elif info.range>0:out.lines.append(PackedVector3Array([world(p.pos),world(p.pos+facing*info.range)]));out.note="当前朝向 · 位移上限 %d"%int(info.range)
		else:out.areas.append(circle(p.pos,70))
	if kind in ["kick","angel","powershot","curve","trickster"]:
		out.trajectory=ball_path(sim,index,kind,point,action=="ability_secondary")
		out.note="简化轨迹 · 不预测碰撞和反弹"
		if kind=="kick" and not sim.has_ball(index):out.note="预瞄中 · 接到球后松手射出"
	elif kind=="rift":out.trajectory=rift_path(sim,index,point);out.note="距离 %d · 简化抛物线，不预测反弹"%roundi(p.pos.distance_to(point))
	var ground=PackedVector3Array()
	for v in out.trajectory:ground.append(Vector3(v.x,v.y,4))
	out["ground"]=ground
	return out

static func ball_path(sim,index: int,kind: String,point: Vector2,secondary=false) -> PackedVector3Array:
	var position: Vector3=sim.ball;var velocity: Vector3=sim.velocity
	var copy=sim.Copies.held(sim,index) if kind in ["kick","angel"] else {}
	if not copy.is_empty():position=copy.position;velocity=copy.velocity
	elif kind=="kick" and sim.holder!=index:
		# Read-only hypothetical catch at this player's held-ball offset.
		# Never aim from somebody else's ball, inherit its velocity or perform
		# collision queries while the player is only preparing a direction.
		var p=sim.players[index];var offset=Vector2.from_angle(p.body)*100.0
		position=Vector3(p.pos.x+offset.x,p.pos.y+offset.y,p.z);velocity=Vector3.ZERO
	if kind=="trickster" and secondary:velocity=Vector3.ZERO # Fake-ball take resets velocity.
	var direction=(point-Vector2(position.x,position.y)).normalized()
	var power=kind=="powershot" or (not copy.is_empty() and sim.powershot_active)
	var curve={}
	if kind=="curve":
		if curve_parameters.is_empty():curve_parameters=Characters.curve_constants()
		curve=curve_parameters.duplicate();var sign_value=1.0 if secondary else -1.0
		var angle=(point-sim.players[index].pos).angle()+curve.initial_angle*sign_value
		velocity+=Vector3(cos(angle),sin(angle),0)*curve.speed
		curve.angle*=sign_value;curve.angle_delta*=sign_value;curve["life"]=1.4
	else:
		var speed=51.0 if kind=="powershot" else (35.0 if kind=="angel" else 30.0)
		velocity+=Vector3(direction.x*speed,direction.y*speed,0 if kind=="powershot" else 7)
	var points=PackedVector3Array([position]);var friction=sim.SurfaceRules.ball_friction(sim)
	for step in range(STEPS):
		if not curve.is_empty() and curve.life>0:
			var angle=atan2(velocity.y,velocity.x)+curve.angle
			velocity+=Vector3(cos(angle),sin(angle),0)*curve.force
			curve.force+=curve.force_delta/2;curve.angle+=curve.angle_delta/2;curve.life-=sim.BALL_DT
		var motion=Flight.integrate(position,velocity,power,friction)
		position+=motion.delta;velocity=motion.velocity
		# The UI draws an unobstructed guide. After landing it rolls flat;
		# all wall/goal/pillar and ground bounces belong to the real simulation.
		if position.z<=0:position.z=0;velocity.z=0
		if (step+1)%SAMPLE_STRIDE==0 or step==STEPS-1 or velocity.length_squared()<0.001:points.append(position)
		if velocity.length_squared()<0.001:break
		if power and velocity.length()<=5:power=false
	return points

static func rift_path(sim,index: int,point: Vector2) -> PackedVector3Array:
	var p=sim.players[index];var offset=point-p.pos;var duration=minf(offset.length(),750)/1000.0
	var direction=offset.normalized() if offset.length()>0.05 else Vector2.from_angle(p.body)
	var vz=32.5*duration*2-16.25 if duration>0.5 else (35*duration*2-17.5 if duration>0.2 else -82.5*pow((0.2-duration)*2,3)-17.5)
	if not p.rift.is_empty() and p.rift.count==1:vz+=3.125
	var position=Characters.world_position(p)+Vector3(0,0,100);var velocity=Vector3(direction.x*31.25,direction.y*31.25,vz)
	var points=PackedVector3Array([position])
	for step in range(STEPS):
		velocity.z-=3.125
		var ground=-position.z/velocity.z if velocity.z<0 and position.z+velocity.z<=5 else INF
		if ground<INF:ground=clampf(ground,0,1)
		if ground<INF:position+=velocity*ground;position.z=0;points.append(position);break
		position+=velocity
		if (step+1)%2==0 or step==STEPS-1:points.append(position)
	return points
