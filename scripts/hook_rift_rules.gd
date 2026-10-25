extends RefCounted
## Parameters and state transitions from the local 1.27 map. Collision sweeps
## and legal teleport placement use this remake's arena, not native WC3 repair.

static func hook_cast(sim,index: int,target: Vector2,friendly: bool) -> bool:
	var p=sim.players[index]
	if not p.hook.is_empty():
		var h=p.hook
		if h.friendly!=friendly:return false
		if h.caught!=-1:hook_drop(sim,h)
		else:h.returning=true
		return true
	if (p.secondary_cooldown if friendly else p.cooldown)>0:return false
	var direction=Vector3(target.x-p.pos.x,target.y-p.pos.y,-p.z)
	if direction.length()<0.01:return false
	sim.stop(index,false)
	if friendly:p.secondary_cooldown=22.0
	else:p.cooldown=26.0
	sim.next_projectile_id+=1
	var start=sim.Characters.world_position(p)+direction.normalized()*20
	start.z=p.z
	var h={"id":sim.next_projectile_id,"kind":"hook","owner":index,"pos":start,"previous":start,"velocity":direction.normalized()*40,"life":8.5,"age":0.0,"returning":false,"friendly":friendly,"caught":-1,"spent":false,"ball_caught":false}
	p.hook=h;sim.projectiles.append(h)
	p.action=0.96;p.action_clip="Spell";p.disabled=0.96;p.ability_kind="hook"
	if index==sim.controlled:sim.notice="再次按 R 可提前收回或松开队友。" if friendly else "再次按 Q 可提前收回或松开敌人。"
	return true

static func hook_drop(sim,h: Dictionary):
	if h.caught>=0:
		var p=sim.players[h.caught]
		p.hooked=0
		sim.set_unit_pathing(h.caught,true)
		# Restoring ordinary collision must not leave two players overlapping.
		var free=sim.nearby_free(p.pos,h.caught)
		if free.is_finite():p.pos=free;p.previous=free
		if not h.friendly:p.silence=maxf(p.silence,0.5)
		if p.want_move:sim.plan_route(h.caught)
	elif h.caught==-2 and sim.ball_hook==h.id:
		sim.ball_hook=0;sim.velocity=Vector3.ZERO;sim.intercept=0
	h.caught=-1
	h.returning=true

static func hook_finish(sim,h: Dictionary):
	var p=sim.players[h.owner]
	if h.caught==-2 and sim.ball_hook==h.id:
		sim.ball=sim.Characters.world_position(p);sim.previous_ball=sim.ball
		sim.last_owner=h.owner
	hook_drop(sim,h)
	p.hook={};h.life=0
	if p.ability_kind=="hook":p.disabled=0;p.action=0
	if p.character=="h029" and p.morph_ghost>2:p.morph_ghost=2.0

static func hook_candidate(sim,h: Dictionary,start: Vector3,delta: Vector3) -> Dictionary:
	var best={}
	# The source gives the real ball priority in the 100-unit enumeration.
	var candidates=[-2] if sim.ball_present else []
	for i in range(sim.players.size()):candidates.append(i)
	for i in candidates:
		if i==h.owner:continue
		var point: Vector3=sim.ball if i==-2 else sim.Characters.world_position(sim.players[i])
		var height=40.0 if i==-2 else sim.players[i].catch_height
		if i==-2:
			if sim.holder==h.owner:continue
			if sim.holder>=0 and (sim.players[sim.holder].team==sim.players[h.owner].team)!=h.friendly:continue
		else:
			if sim.Characters.absent(sim.players[i]) or (sim.players[i].team==sim.players[h.owner].team)!=h.friendly:continue
		var xy=Vector2(start.x,start.y);var center=Vector2(point.x,point.y)
		var hit=sim.Arena.circle_hit(xy,Vector2(delta.x,delta.y),center,100)
		if xy.distance_to(center)<=100:hit={"t":0.0}
		if hit.is_empty():continue
		var z=start.z+delta.z*hit.t-point.z
		if z< -50 or z>height+50:continue
		# A proximity sphere must not pull a victim through a wall.
		if not sim.arena.sweep_ball(start+delta*hit.t,point-start-delta*hit.t,0,false).is_empty():continue
		if best.is_empty() or hit.t<best.t:best={"t":hit.t,"player":i}
	return best

static func hook_attach(sim,h: Dictionary,index: int):
	if (index==-2 and not sim.ball_present) or (index>=0 and not sim.unit_present(index)):return
	# Source Hook_hook / Hook_ballhook: one impact at the victim, before
	# moving it to the projectile. Original Sfx dummy scale is 0.01.
	var contact: Vector3=sim.ball if index==-2 else sim.Characters.world_position(sim.players[index])
	sim.emit_visual("fx_hook",contact,0.01)
	for other in sim.projectiles:
		if other.kind=="hook" and other!=h and other.caught==index:hook_drop(sim,other)
	h.caught=index;h.spent=true;h.returning=true
	h.ball_caught=index==-2
	if index==-2:
		sim.holder=-1;sim.ball_hook=h.id;sim.velocity=Vector3.ZERO
		sim.curve.clear();sim.powershot_active=false
	else:
		var p=sim.players[index]
		p.hooked=h.id
		sim.set_unit_pathing(index,false)
		if not h.friendly:
			p.silence=0.55
			if p.character=="h004":sim.set_sprint(index,false)
			else:p.sprint=false
			sim.Characters.cancel_charge(p)
			# Silence can interrupt a not-yet-cast order. The active scripted
			# Tackle iterator has its own lifetime: Hook never destroys it.
			p.cast_pending=false

static func projectile_wall(sim,owner: int,start: Vector3,delta: Vector3) -> Dictionary:
	var wall=sim.arena.sweep_ball(start,delta,0,false)
	# GoalBlock exempts projectiles from the one-keeper limit, but still
	# rejects a projectile entering the opposing team's protected region.
	for rect in sim.arena.guards[1-sim.players[owner].team]:
		var hit=sim.Arena.box_hit(start,delta,Vector3(rect.position.x,rect.position.y,-10000),Vector3(rect.end.x,rect.end.y,10000))
		if not hit.is_empty() and delta.dot(hit.normal)<0 and hit.t<wall.get("t",INF):wall=hit
	return wall

static func hook_step(sim,h: Dictionary):
	h.previous=h.pos;h.age+=sim.BALL_DT
	var caster=sim.players[h.owner]
	var origin=sim.Characters.world_position(caster)
	if h.returning and Vector2(h.pos.x,h.pos.y).distance_to(caster.pos)<=40:
		hook_finish(sim,h);return
	if h.age>=0.85:h.returning=true
	if h.returning:h.velocity=(origin-h.pos).normalized()*(20.0 if h.spent and not h.ball_caught else 40.0)
	var delta: Vector3=h.velocity
	if h.pos.z+delta.z<0 and delta.z<0:delta.z=-h.pos.z;h.velocity.z=-h.velocity.z
	var wall=projectile_wall(sim,h.owner,h.pos,delta)
	var contact=hook_candidate(sim,h,h.pos,delta) if not h.spent else {}
	if not contact.is_empty() and contact.t<wall.get("t",INF):
		h.pos+=delta*contact.t;hook_attach(sim,h,contact.player)
	elif not wall.is_empty():
		h.pos+=delta*maxf(0,wall.t-0.002);h.velocity=h.velocity.bounce(wall.normal)
		if h.returning and h.caught!=-1:hook_drop(sim,h)
	else:h.pos+=delta
	if h.caught>=0:
		var p=sim.players[h.caught]
		var destination=Vector2(h.pos.x,h.pos.y)
		var hit=sim.arena.sweep_unit(p.pos,destination-p.pos,p.radius,sim.goal_restrictions(h.caught))
		p.pos=p.pos.lerp(destination,maxf(0,hit.t-0.002) if not hit.is_empty() else 1.0)
		if not h.friendly:p.silence=0.55
		if not hit.is_empty():hook_drop(sim,h)
	elif h.caught==-2:
		sim.ball=h.pos;sim.velocity=Vector3.ZERO
		sim.MatchRules.assist(sim,h.owner)
	h.life-=sim.BALL_DT
	if h.life<=0:hook_finish(sim,h)

static func rift_cast(sim,index: int,target: Vector2) -> bool:
	var p=sim.players[index]
	if not p.rift.is_empty():
		if p.rift.count!=1 or p.rift.unlock>0 or p.rift.projectile!=0:return false
	elif p.cooldown>0:return false
	var offset=target-p.pos
	if offset.length()>775:
		sim.approach_cast(index,target,775.0);return true
	sim.stop(index,false)
	if p.rift.is_empty():
		sim.next_projectile_id+=1
		p.rift={"id":sim.next_projectile_id,"owner":index,"count":0,"projectile":0,"unlock":1.5,"age":0.0,"a":null,"b":null,"traveled":{},"life":5.0}
		sim.rifts.append(p.rift)
	var r=p.rift;r.count+=1
	var duration=minf(offset.length(),750)/1000.0
	var horizontal=offset.normalized() if offset.length()>0.05 else Vector2.from_angle(p.body)
	var vz=32.5*duration*2-16.25 if duration>0.5 else (35*duration*2-17.5 if duration>0.2 else -82.5*pow((0.2-duration)*2,3)-17.5)
	if r.count==2:vz+=3.125;p.cooldown=32.0
	sim.next_projectile_id+=1;r.projectile=sim.next_projectile_id
	var start=sim.Characters.world_position(p)+Vector3(0,0,100)
	sim.projectiles.append({"id":r.projectile,"kind":"rift","owner":index,"pos":start,"previous":start,"velocity":Vector3(horizontal.x*31.25,horizontal.y*31.25,vz),"life":6.0,"rift":r})
	p.action=0.35;p.action_clip="Attack 2";p.ability_kind="rift";p.disabled=0.35
	if index==sim.controlled:sim.notice="第一个入口已投出；1.5 秒后按 Q 放置出口。" if r.count==1 else "出口已投出；落地后隧道开放 3 秒。"
	return true

static func rift_finish(sim,r: Dictionary):
	if r.b==null:sim.players[r.owner].cooldown=10.0
	sim.players[r.owner].rift={};r.life=0
	for projectile in sim.projectiles:
		if projectile.kind=="rift" and projectile.rift==r:projectile.life=0

static func rift_projectile_step(sim,q: Dictionary):
	q.previous=q.pos
	q.velocity.z-=3.125
	var delta: Vector3=q.velocity
	var wall=projectile_wall(sim,q.owner,q.pos,delta)
	var ground_t=-q.pos.z/delta.z if delta.z<0 and q.pos.z+delta.z<=5 else INF
	ground_t=clampf(ground_t,0,1) if ground_t<INF else INF
	if ground_t<=wall.get("t",INF) and ground_t<INF:
		q.pos+=delta*ground_t;q.pos.z=0
		var r=q.rift
		# Keep portal endpoints outside solid practice geometry.
		if not sim.arena.point_free(Vector2(q.pos.x,q.pos.y),1):rift_finish(sim,r);return
		var facing=atan2(q.velocity.y,q.velocity.x)
		if r.a==null:r.a=q.pos;r.life=5.0;r["facing_a"]=facing
		else:r.b=q.pos;r.life=3.0;r["facing_b"]=facing
		# The original projectile is raised 15, killed, then removed after .25s.
		sim.emit_visual("h02A",q.pos+Vector3(0,0,15),1.0,facing)
		r.age=0;r["message_time"]=0.0;r.projectile=0;q.life=0
	elif not wall.is_empty():
		q.pos+=delta*maxf(0,wall.t-0.002);q.velocity=q.velocity.bounce(wall.normal)
	else:q.pos+=delta
	q.life-=sim.BALL_DT
	if q.life<=0 and q.rift.projectile!=0:rift_finish(sim,q.rift)

static func rift_teleport(sim,r: Dictionary,index: int,destination: Vector3) -> bool:
	if r.traveled.has(index):return false
	if index==-2:
		if not sim.ball_present or sim.holder>=0 or sim.ball_hook!=0 or sim.ball.z>25:return false
		if not sim.arena.point_free(Vector2(destination.x,destination.y),25):return false
		var horizontal=Vector2(sim.velocity.x,sim.velocity.y)
		var force=horizontal.normalized()*3.125 if sim.velocity.length()>0.05 else Vector2.from_angle(sim.random.randf_range(-PI,PI))*12.5
		sim.ball=Vector3(destination.x,destination.y,sim.ball.z);sim.previous_ball=sim.ball
		sim.velocity+=Vector3(force.x,force.y,0)
	else:
		var p=sim.players[index]
		if p.z>25 or p.hooked!=0 or sim.Characters.absent(p):return false
		var point=sim.nearby_free(Vector2(destination.x,destination.y),index)
		if not point.is_finite():return false
		p.pos=point;p.previous=point
		var push=(p.knock.normalized() if Vector3(p.knock.x,p.knock.y,p.vz).length()>0.05 else Vector2.from_angle(p.body))*12.5
		sim.apply_impulse(index,Vector3(push.x,push.y,0))
		if p.want_move:sim.plan_route(index)
		sim.Possession.relocated(sim,index)
		for copy in sim.fake_balls:
			if copy.holder==index:copy.position=sim.Copies.held_position(sim,index,false);copy.previous=copy.position
	r.traveled[index]=true
	return true

static func step(sim):
	for r in sim.rifts:
		r.unlock=maxf(0,r.unlock-sim.BALL_DT)
		if r.life<=0:continue
		if r.a!=null:
			var duration=3.0 if r.b!=null else 5.0
			if r.age>=duration:
				# A lone entrance keeps aging while the second projectile flies;
				# destruction waits for that projectile, not a paused timeout.
				if r.b!=null or r.projectile==0:rift_finish(sim,r)
				r.age+=sim.BALL_DT
				continue
			if r.b!=null:
				for pair in [[r.a,r.b],[r.b,r.a]]:
					if Vector2(sim.ball.x,sim.ball.y).distance_to(Vector2(pair[0].x,pair[0].y))<=75:rift_teleport(sim,r,-2,pair[1])
					for i in range(sim.players.size()):
						if sim.players[i].pos.distance_to(Vector2(pair[0].x,pair[0].y))<=100:rift_teleport(sim,r,i,pair[1])
			var message_time=float(r.get("message_time",0.0))
			if r.age>=message_time:
				for endpoint in ([r.a,r.b] if r.b!=null else [r.a]):
					var message=sim.emit_world_text(endpoint,("%.3f"%(duration-message_time)).substr(0,3)+"!",.75)
					message.text_offset=Vector3(-35,0,150)
					if r.b!=null:message.audience_team=sim.players[r.owner].team
					else:message.audience_owner=r.owner
				r["message_time"]=message_time+.5
			r.life=maxf(sim.BALL_DT,duration-r.age)
			r.age+=sim.BALL_DT
	sim.rifts=sim.rifts.filter(func(r):return r.life>0)
