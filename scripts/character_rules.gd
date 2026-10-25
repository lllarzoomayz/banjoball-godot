extends RefCounted
## Playable kits use the extracted local map's data and JASS. Visual effects
## and AI decisions are presentation/singleplayer additions, not native ports.
const Complex=preload("res://scripts/hook_rift_rules.gd")
const Morph=preload("res://scripts/metamorph_rules.gd")
# IsUnitInRange adds BOTH native collision sizes to its distance argument.
# Game.dll 1.27: 6f1e8950 -> 6f03e3a0, body +0x90 (world units /32).
# h02D's native ucol is 60; the real ball h000 has ucol 0.
const PILLAR_NATIVE_RADIUS=60.0
const PILLAR_BIRTH_RANGE=65.0
const IDS=["h005","h003","h00P","h00Y","h01I","h028","h02C","h00F","h026","h004","h00R","h010","h001","h012","h01N","h01R","h027","h029"]
const DATA={
	"h005":{"name":"铁壁萨满","skill":"铁壁滑铲","kind":"tackle","targeted":true,"speed":300.0,"turn":0.6,"height":140.0,"regen":10.0,"drain":30.0,"cooldown":32.0,"description":"Q 选方向滑铲；滑铲时可右键转向。"},
	"h003":{"name":"谜之灵魂","skill":"迷你黑洞","kind":"black_hole","targeted":true,"speed":300.0,"turn":0.6,"height":145.0,"regen":10.0,"drain":30.0,"cooldown":40.0,"description":"Q 选地点制造黑洞，吸引周围人物与自由真球。"},
	"h00P":{"name":"树精卫士","skill":"猛烈践踏","kind":"slam","targeted":false,"speed":300.0,"turn":0.6,"height":170.0,"regen":10.0,"drain":30.0,"cooldown":30.0,"description":"Q 蓄力后击飞周围物体，队友也会受到影响。"},
	"h00Y":{"name":"魅惑女巫","skill":"快速牵引","kind":"pull","targeted":false,"speed":300.0,"turn":0.6,"height":160.0,"regen":10.0,"drain":30.0,"cooldown":0.0,"description":"Q 向球牵引，再按 Q 取消；持续越久冷却越长。"},
	"h01I":{"name":"黑暗流浪者","skill":"暗影闪现","kind":"shadow","targeted":false,"speed":300.0,"turn":0.6,"height":155.0,"regen":10.0,"drain":30.0,"cooldown":26.0,"description":"Q 延迟后向面朝方向闪现；短时间内再按 Q 回溯。"},
	"h028":{"name":"天使射手","skill":"天使一击","kind":"angel","targeted":true,"speed":400.0,"turn":1.0,"height":150.0,"regen":20.0,"drain":60.0,"cooldown":0.0,"description":"Q 强力传射；E 消耗魔法免除持球减速。"},
	"h02C":{"name":"牛头人后卫","skill":"大地图腾","kind":"pillar","targeted":true,"speed":300.0,"turn":0.6,"height":160.0,"regen":10.0,"drain":30.0,"cooldown":28.0,"description":"Q 选地点，再按 Q 放脚下；手机轻点或拖回中心放脚下。升起时顶飞人和真球，持续 3 秒。"},
	"h00F":{"name":"钢铁女武神","skill":"蓄力一击","kind":"powershot","targeted":true,"speed":300.0,"turn":0.6,"height":140.0,"regen":10.0,"drain":30.0,"cooldown":6.0,"description":"Q 选方向蓄力射门；S 取消，强力球会击退接球者。"},
	"h026":{"name":"食人魔","skill":"巨棍撞击","kind":"smash","targeted":false,"speed":300.0,"turn":0.6,"height":165.0,"regen":10.0,"drain":50.0,"cooldown":24.0,"description":"Q 撞击面前的人和球；E 开启狂暴冲刺。"},
	"h004":{"name":"恶魔前锋","skill":"无 Q 技能","kind":"none","targeted":false,"speed":300.0,"turn":0.6,"height":145.0,"regen":10.0,"drain":50.0,"cooldown":0.0,"description":"E 超级冲刺：向面朝方向加速，保留惯性；原版没有 Q 技能。"},
	"h00R":{"name":"忍者","skill":"跳跃空翻","kind":"backflip","targeted":false,"speed":300.0,"turn":0.6,"height":145.0,"regen":10.0,"drain":30.0,"cooldown":24.0,"description":"Q 向前空翻，可在空中 W 射门；E 冲刺 1 秒后潜行。"},
	"h010":{"name":"小精灵","skill":"支配皮球","kind":"possess","targeted":false,"speed":300.0,"turn":0.6,"height":120.0,"regen":10.0,"drain":30.0,"cooldown":40.0,"description":"持球按 Q 钻入皮球 8 秒；右键使球跳跃，空中指令会等到落地执行。"},
	"h001":{"name":"相位精灵","skill":"相位交换","kind":"swap","targeted":true,"speed":300.0,"turn":0.6,"height":145.0,"regen":10.0,"drain":30.0,"cooldown":18.0,"description":"Q 投出会反弹的相位弹，与碰到的第一个球员交换位置和动量。"},
	"h012":{"name":"魔力傀儡","skill":"左弧线球","secondary":"右弧线球","kind":"curve","targeted":true,"speed":300.0,"turn":0.6,"height":150.0,"regen":10.0,"drain":30.0,"cooldown":1.0,"description":"持球 Q 左弧线 / R 右弧线；弯曲期间被队友接到，接球者回复魔法。"},
	"h01N":{"name":"巨魔欺诈师","skill":"假踢动作","secondary":"假持动作","kind":"trickster","targeted":true,"speed":300.0,"turn":0.6,"height":150.0,"regen":10.0,"drain":30.0,"cooldown":14.0,"description":"Q 踢假球并保留真球；R 踢真球并留下假球。己方可辨认蓝色假球。"},
	"h01R":{"name":"强壮屠夫","skill":"钩敌人","secondary":"钩队友","kind":"hook","targeted":true,"speed":300.0,"turn":0.6,"height":150.0,"regen":10.0,"drain":30.0,"cooldown":26.0,"description":"Q 钩敌人 / R 钩队友；再次按同键收回或松开。也能钩真球。"},
	"h027":{"name":"空间法师","skill":"空间隧道","kind":"rift","targeted":true,"speed":300.0,"turn":0.6,"height":155.0,"regen":10.0,"drain":30.0,"cooldown":32.0,"description":"Q 投出入口，1.5 秒后再 Q 放出口；地面人物和自由真球可穿过一次。"},
	"h029":{"name":"变体妖精","skill":"随机突变","kind":"metamorph","targeted":false,"speed":300.0,"turn":0.6,"height":140.0,"regen":10.0,"drain":30.0,"cooldown":20.0,"description":"Q 蓄力 2.5 秒借用随机技能，可用三次；技能结束后 F1 放弃借用。"}
}

static func kit(p: Dictionary) -> Dictionary:
	return DATA[p.morph_kit] if p.character=="h029" and p.morph_kit!="" else DATA[p.character]

static func configure(p: Dictionary,id: String):
	preload("res://scripts/fake_injury_rules.gd").configure(p)
	var data=DATA[id]
	p.character=id
	p.speed=data.speed
	p.turn=data.turn
	p.catch_height=data.height

static func world_position(p: Dictionary) -> Vector3:
	return Vector3(p.pos.x,p.pos.y,p.z)

static func q_available(p: Dictionary,secondary: bool=false) -> bool:
	if p.stun>0 or p.silence>0 or absent(p) or kit(p).kind=="none" or p.morph_roll>0:return false
	if not p.hook.is_empty():return p.hook.friendly==secondary
	if p.character=="h029" and p.morph_kit!="" and p.morph_casts<=0 and p.pull_time<=0 and p.shadow_return<=0:return false
	if not p.rift.is_empty():return p.rift.count==1 and p.rift.unlock<=0 and p.rift.projectile==0 and p.disabled<=0
	if kit(p).kind=="hook":return (p.secondary_cooldown if secondary else p.cooldown)<=0 and p.disabled<=0
	return p.pull_time>0 or p.shadow_return>0 or (p.cooldown<=0 and p.ability_delay<=0 and p.disabled<=0)

static func absent(p: Dictionary) -> bool:
	return p.get("removed",false) or p.possess_time>0 or p.flight_steps>0

static func phased(p: Dictionary) -> bool:
	return absent(p) or not p.pathing_enabled

static func catchable(p: Dictionary) -> bool:
	return not absent(p) and p.eject_time<=0 and p.hooked==0

static func use(sim,index: int,target: Vector2,secondary: bool=false) -> bool:
	var p=sim.players[index]
	var kind=kit(p).kind
	var fresh=p.pull_time<=0 and p.shadow_return<=0 and p.hook.is_empty()
	var result=use_internal(sim,index,target,secondary)
	if result:
		sim.ShotOrder.cancel(p)
		p.keeper_pose=0.0;p.slide_order=false;sim.InjuryRules.cancel_pose(p)
	if result and fresh and kind!="tackle" and kind!="metamorph" and p.ability_order.is_empty():Morph.record(sim,index,kind)
	return result

static func use_internal(sim,index: int,target: Vector2,secondary: bool=false) -> bool:
	var p=sim.players[index]
	var kit=kit(p)
	if not target.is_finite() or not q_available(p,secondary):return false
	if secondary and not kit.has("secondary"):return false
	if kit.kind=="hook":return Complex.hook_cast(sim,index,target,secondary)
	if kit.kind=="rift":return Complex.rift_cast(sim,index,target)
	if kit.kind=="metamorph":return Morph.cast(sim,index)
	if p.pull_time>0:finish_pull(p);return true
	if p.shadow_return>0:
		# Preserve goal restrictions and resolve occupied destinations safely.
		var point=sim.nearby_free(p.shadow_origin,index)
		if not point.is_finite():return false
		var departed=world_position(p)
		sim.stop(index,false)
		p.pos=point;p.previous=point
		sim.Possession.relocated(sim,index)
		p.shadow_return=0;p.cooldown=32.0
		if p.character=="h029" and p.morph_ghost>2:p.morph_ghost=2.0
		sim.skill_effects.append({"kind":"blink","pos":departed,"life":0.5,"age":0.0,"owner":index})
		return true
	if kit.kind=="tackle":sim.tackle(index,target);return true
	if kit.kind=="angel":
		var success=sim.kick(index,target,35.0)
		if success:sim.emit_visual("fx_angelic_kick",sim.ball,0.75)
		return success
	if kit.kind in ["powershot","possess","curve","trickster"] and sim.holder!=index:return false
	if kit.kind in ["curve","swap","trickster"] and target.distance_to(p.pos)<0.01:return false
	if kit.kind=="trickster" and not sim.Copies.create(sim,index,not secondary,target):return false
	if kit.kind=="backflip" and p.z>=20:return false
	if kit.kind=="pull":
		if not sim.ball_present or sim.holder==index:return false
		p.pull_time=4.5;p.pull_level=1
		sim.notice="快速牵引：再次按 Q 可取消。"
		return true
	var cast_range=725.0 if kit.kind=="pillar" else 900.0
	if kit.kind in ["black_hole","pillar"] and p.pos.distance_to(target)>cast_range:
		sim.approach_cast(index,target,cast_range)
		sim.notice="移动到"+kit.skill+"施法范围内。"
		return true
	sim.stop(index,false)
	p.cooldown=kit.cooldown
	p.ability_kind=kit.kind
	p.ability_target=target
	p.action=0.6
	p.action_clip="Attack 2" if kit.kind=="curve" and not secondary else ("Attack" if kit.kind in ["curve","swap"] else "Spell")
	# Original Smash: MDX sequence 6 (Attack 2), 2x speed until the 0.15s hit.
	if kit.kind=="smash":p.action_clip="Attack 2";p.action=0.15
	match kit.kind:
		"curve":cast_curve(sim,index,target,secondary)
		"swap":
			cast_swap(sim,index,target)
			p.disabled=0.96
		"trickster":pass
		"backflip":
			p.flip_time=1.09
			sim.set_unit_pathing(index,false)
			var horizontal=635.0/1.09/32.0+0.08*1.09*16.0
			sim.apply_impulse(index,Vector3(cos(p.body)*horizontal,sin(p.body)*horizontal,1.09*1.5*16.0))
			if sim.holder==index:sim.no_steal=10
		"possess":
			p.flight_steps=4
			sim.set_unit_pathing(index,false)
			sim.holder=-1;sim.no_steal=0
			fly_into_ball(sim,index)
		"black_hole":
			sim.skill_effects.append({"kind":"black_hole","pos":Vector3(target.x,target.y,50),"life":3.5,"age":0.0,"power":0.0,"owner":index})
			p.disabled=1.2 # Channel follow-through; moving/stop can cancel this pose.
		"slam":p.ability_delay=0.36;p.disabled=0.36
		"shadow":p.ability_delay=0.5
		"pillar":
			var delta=target-p.pos
			var manhattan=absf(delta.x)+absf(delta.y)
			p.ability_target=p.pos+delta*(700.0/manhattan) if manhattan>=700 else target
			p.ability_delay=0.4;p.disabled=0.3
			p.action_clip="Attack Slam";p.action=0.3
		"smash":p.ability_delay=0.15;p.disabled=0.15
		"powershot":
			p.ability_delay=0.5;p.disabled=0.5
			if p.power_slow_cooldown<=0:
				for other in sim.players:
					if other!=p and other.pos.distance_to(p.pos)<=400:other.power_slow=0.5
				p.power_slow_cooldown=5.0
	var skill_name=kit.secondary if secondary else kit.skill
	sim.notice=skill_name if index==sim.controlled else sim.team_name(p.team)+str(p.number)+"号施放："+skill_name
	return true

static func curve_constants() -> Dictionary:
	# Curveshot_initValues: preserve its discrete chord construction, including
	# the half-rate updates to both force and angle in overtimeForce.
	var radius=1500.0;var distance=1450.0;var duration=1.4;var friction=0.45
	var omega=acos(distance/2/radius)
	var ox=distance/2;var oy=radius*sin(omega);omega+=PI
	var fi=2*asin(distance/2/radius)
	var speed=(radius*fi/duration*1.25+friction*32*duration/2)/32
	var theta1=speed/radius;var theta2=(speed-friction)/radius;var theta3=(speed-2*friction)/radius
	# Use scalar doubles during coefficient construction. Premature Vector2
	# rounding amplifies cancellation in the very small angle_delta term.
	var v1=[ox+radius*cos(omega+theta1),oy+radius*sin(omega+theta1)]
	var v2=[ox+radius*cos(omega+theta1+theta2)-v1[0],oy+radius*sin(omega+theta1+theta2)-v1[1]]
	var v3=[ox+radius*cos(omega+theta1+theta2+theta3)-v1[0]-v2[0],oy+radius*sin(omega+theta1+theta2+theta3)-v1[1]-v2[1]]
	var length=func(v):return sqrt(v[0]*v[0]+v[1]*v[1])
	var add_length=func(v,amount):
		var size=length.call(v);var factor=(size+amount)/size
		v[0]*=factor;v[1]*=factor
	for v in [v1,v2,v3]:add_length.call(v,friction)
	var initial_angle=atan2(v1[1],v1[0])
	add_length.call(v1,-friction)
	var force_vector=[v2[0]-v1[0],v2[1]-v1[1]]
	var force=length.call(force_vector)
	var angle=acos(clampf((v1[0]*force_vector[0]+v1[1]*force_vector[1])/(length.call(v1)*force),-1,1))
	add_length.call(v2,-friction)
	force_vector=[v3[0]-v2[0],v3[1]-v2[1]]
	return {"speed":speed+friction,"initial_angle":initial_angle,"force":force,"angle":angle,"force_delta":length.call(force_vector)-force,"angle_delta":acos(clampf((v2[0]*force_vector[0]+v2[1]*force_vector[1])/(length.call(v2)*length.call(force_vector)),-1,1))-angle}

static func cast_curve(sim,index: int,target: Vector2,right: bool):
	var values=curve_constants()
	var sign_value=1.0 if right else -1.0
	var direction=(target-sim.players[index].pos).angle()+values.initial_angle*sign_value
	sim.velocity+=Vector3(cos(direction),sin(direction),0)*values.speed
	sim.holder=-1;sim.last_owner=index;sim.intercept=5;sim.no_steal=0
	sim.MatchRules.assist(sim,index)
	sim.curve={"owner":index,"life":1.4,"force":values.force,"angle":values.angle*sign_value,"force_delta":values.force_delta,"angle_delta":values.angle_delta*sign_value}

static func cast_swap(sim,index: int,target: Vector2):
	var p=sim.players[index]
	var xy=(target-p.pos).normalized()
	var front=false
	for name in ["Goal_1_Front_Face","Goal_2_Front_Face"]:
		if sim.Arena.rect(sim.arena.data.regions[name]).has_point(p.pos):front=true
	sim.next_projectile_id+=1
	var start=world_position(p)+Vector3(xy.x*20,xy.y*20,100)
	sim.projectiles.append({"id":sim.next_projectile_id,"kind":"swap","owner":index,"pos":start,"previous":start,"velocity":Vector3(target.x-p.pos.x,target.y-p.pos.y,-p.z).normalized()*44.4,"life":1.8,"front_goal":front})

static func exchange_players(sim,a: int,b: int) -> bool:
	if not sim.unit_present(a) or not sim.unit_present(b):return false
	var first=sim.players[a];var second=sim.players[b]
	# Native goal-entry triggers repair illegal teleports. Keep the existing
	# single-keeper/team restriction until that repair is reproduced precisely.
	if not sim.arena.point_free(second.pos,first.radius,swap_goal_restrictions(sim,a,b)):return false
	if not sim.arena.point_free(first.pos,second.radius,swap_goal_restrictions(sim,b,a)):return false
	var old_position=world_position(first);var old_motion=Vector3(first.knock.x,first.knock.y,first.vz)
	var first_active: bool=first.object_active;var second_active: bool=second.object_active
	first.pos=second.pos;first.z=second.z;first.knock=second.knock;first.vz=second.vz
	# Swap explicitly starts each receiver if the donor's Object iterator was
	# enabled, even with zero velocity. Existing registrations keep their order.
	if second_active:sim.start_object(a)
	second.pos=Vector2(old_position.x,old_position.y);second.z=old_position.z;second.knock=Vector2(old_motion.x,old_motion.y);second.vz=old_motion.z
	if first_active:sim.start_object(b)
	for index in [a,b]:
		var p=sim.players[index]
		p.previous=p.pos;p.previous_z=p.z
		if p.want_move:sim.plan_route(index)
		sim.Possession.relocated(sim,index)
		for copy in sim.fake_balls:
			if copy.holder==index:copy.position=sim.Copies.held_position(sim,index,false);copy.previous=copy.position
	sim.skill_effects.append({"kind":"swap_link","pos":world_position(first),"end":world_position(second),"life":0.6,"age":0.0,"owner":a})
	return true

static func swap_goal_restrictions(sim,index: int,partner: int) -> Array:
	var extra=[]
	for team in [0,1]:
		var blocked=sim.players[index].team!=team
		for j in range(sim.players.size()):
			if j!=index and j!=partner and not absent(sim.players[j]) and sim.players[j].team==team and sim.arena.in_guard(sim.players[j].pos,team):blocked=true
		if blocked:extra.append_array(sim.arena.guards[team])
	return extra

static func swap_contact(sim,projectile: Dictionary,start: Vector3,delta: Vector3) -> Dictionary:
	var best={}
	for i in range(sim.players.size()):
		if i==projectile.owner or absent(sim.players[i]):continue
		var p=sim.players[i]
		var h=sim.Arena.circle_hit(Vector2(start.x,start.y),Vector2(delta.x,delta.y),p.pos,80)
		if Vector2(start.x,start.y).distance_to(p.pos)<=80:h={"t":0.0}
		if h.is_empty():continue
		var point=start+delta*h.t
		if point.z-p.z< -40 or point.z-p.z>p.catch_height+40:continue
		if not projectile.front_goal and (sim.arena.in_guard(Vector2(point.x,point.y),0) or sim.arena.in_guard(Vector2(point.x,point.y),1)):continue
		if best.is_empty() or h.t<best.t:best={"t":h.t,"player":i}
	return best

static func step_swap(sim,projectile: Dictionary):
	projectile.previous=projectile.pos
	var delta: Vector3=projectile.velocity
	if projectile.pos.z+delta.z<0 and delta.z<0:delta.z=-projectile.pos.z;projectile.velocity.z=-projectile.velocity.z
	for iteration in range(8):
		for name in ["Goal_1_Front_Face","Goal_2_Front_Face"]:
			var r=sim.Arena.rect(sim.arena.data.regions[name])
			if not sim.Arena.box_hit(projectile.pos,delta,Vector3(r.position.x,r.position.y,-10000),Vector3(r.end.x,r.end.y,10000)).is_empty():projectile.front_goal=true
		var wall=sim.arena.sweep_ball(projectile.pos,delta,0,false)
		if projectile.front_goal:
			for r in sim.arena.guards[1-sim.players[projectile.owner].team]:
				var hit=sim.Arena.box_hit(projectile.pos,delta,Vector3(r.position.x,r.position.y,-10000),Vector3(r.end.x,r.end.y,10000))
				if not hit.is_empty() and delta.dot(hit.normal)<0 and (wall.is_empty() or hit.t<wall.t):wall=hit
		var contact=swap_contact(sim,projectile,projectile.pos,delta)
		if not contact.is_empty() and contact.t<wall.get("t",INF):
			if exchange_players(sim,projectile.owner,contact.player):
				var owner=sim.players[projectile.owner]
				if owner.character=="h029" and owner.morph_ghost>2:owner.morph_ghost=2.0
				projectile.pos+=delta*contact.t;projectile.life=0;return
		if wall.is_empty():projectile.pos+=delta;break
		projectile.pos+=delta*wall.t+wall.normal*0.01
		projectile.velocity=projectile.velocity.bounce(wall.normal)
		delta=delta.bounce(wall.normal)*(1-wall.t)
	projectile.life-=sim.BALL_DT

static func fly_into_ball(sim,index: int):
	var p=sim.players[index]
	var point=world_position(p).lerp(sim.ball,1.0/p.flight_steps)
	p.pos=Vector2(point.x,point.y);p.z=point.z;p.knock=Vector2.ZERO;p.vz=0
	p.flight_steps-=1
	if p.flight_steps<=0:
		sim.set_unit_pathing(index,true)
		for j in range(sim.players.size()):
			if j!=index and sim.players[j].possess_time>0:eject(sim,j)
		p.possess_time=8.0;p.sprint=false;p.jump_due=false
		sim.emit_visual("fx_possess",sim.ball)
		if sim.holder<0:sim.last_owner=index
		sim.notice="支配皮球：右键指定跳跃方向；空中选点会等待落地。"

static func possess_order(sim,index: int,target: Vector2):
	var p=sim.players[index]
	p.jump_target=target;p.jump_due=true
	possess_jump(sim,index)

static func possess_jump(sim,index: int):
	var p=sim.players[index]
	if not p.jump_due or p.jump_cooldown>0 or sim.ball.z>1 or sim.holder>=0:return
	var direction=(p.jump_target-Vector2(sim.ball.x,sim.ball.y)).normalized()
	if direction==Vector2.ZERO:p.jump_due=false;return
	sim.velocity=sim.velocity.normalized()*maxf(0,sim.velocity.length()-26.0)
	var horizontal=31.0*cos(deg_to_rad(50.0))
	sim.velocity+=Vector3(direction.x*horizontal,direction.y*horizontal,31.0*sin(deg_to_rad(50.0)))
	sim.last_owner=index;p.jump_cooldown=0.2;p.jump_due=false

static func eject(sim,index: int):
	var p=sim.players[index]
	p.pos=Vector2(sim.ball.x,sim.ball.y);p.z=sim.ball.z;p.previous=p.pos;p.previous_z=p.z
	p.possess_time=0;p.flight_steps=0;p.jump_due=false;p.eject_time=1.0
	var angle=sim.random.randf_range(0,TAU)
	var min_z=tan(deg_to_rad(30.0));var max_z=tan(deg_to_rad(60.0))-min_z
	sim.apply_impulse(index,Vector3(cos(angle),sin(angle),sim.random.randf_range(min_z,max_z)).normalized()*38.0)
	sim.skill_effects.append({"kind":"blink","model":"fx_possess_eject","pos":world_position(p),"life":0.5,"age":0.0,"owner":index})

static func finish_pull(p: Dictionary):
	p.pull_time=0
	if p.character=="h029" and p.morph_ghost>2:p.morph_ghost=2.0
	p.cooldown=5.0+5.0*p.pull_level

static func cancel_charge(p: Dictionary):
	if p.ability_kind=="powershot" and p.ability_delay>0:
		p.ability_delay=0;p.disabled=0;p.action=0

static func pillar_cast_effects(sim,index: int):
	var p=sim.players[index]
	var delta: Vector2=p.ability_target-p.pos
	# EarthPillar_endAnimation, at 0.30s: seven small source effects on the
	# caster-target segment, then the full-size impact at the target. Keep
	# cosmetic variation independent of gameplay randomness.
	var cosmetic=RandomNumberGenerator.new()
	cosmetic.seed=index+roundi(sim.timeline*100000)
	for i in range(1,8):
		var size=cosmetic.randf_range(0.05,0.15)
		var offset=delta*float(i)/8.0+delta.orthogonal()*cosmetic.randf_range(-0.1,0.1)
		sim.emit_visual("fx_earth_pillar",Vector3(p.pos.x+offset.x,p.pos.y+offset.y,0),size)
	sim.emit_visual("fx_earth_pillar_end",Vector3(p.ability_target.x,p.ability_target.y,0))

static func create_pillar(sim,index: int):
	var caster=sim.players[index]
	var target: Vector2=caster.ability_target
	# Keep the authored point when occupied by a player. Only invalid terrain
	# needs a nearby placement; birth knock-up is precisely for occupied points.
	if not sim.arena.point_free(target,60):
		var found=false
		for radius in [32,64,96,128]:
			for j in range(16):
				var candidate=target+Vector2.from_angle(j*TAU/16.0)*radius
				if sim.arena.point_free(candidate,60):target=candidate;found=true;break
			if found:break
		if not found:return
	var pillar=sim.arena.add_pillar(target,index)
	for i in range(sim.players.size()):
		var p=sim.players[i]
		if absent(p):continue
		if p.pos.distance_to(target)>PILLAR_BIRTH_RANGE+PILLAR_NATIVE_RADIUS+p.radius:continue
		pillar.knocked_units[i]=true
		sim.apply_impulse(i,pillar_birth_impulse(p.pos-target,target,false))
		if i==sim.last_owner:sim.MatchRules.assist(sim,index)
	if sim.ball_present and sim.holder<0 and Vector2(sim.ball.x,sim.ball.y).distance_to(target)<=PILLAR_BIRTH_RANGE+PILLAR_NATIVE_RADIUS:
		pillar.ball_knocked=true
		sim.velocity+=pillar_birth_impulse(Vector2(sim.ball.x,sim.ball.y)-target,target,true)

static func pillar_birth_impulse(offset: Vector2,center: Vector2,ball: bool) -> Vector3:
	var distance=offset.length()
	var direction=offset.normalized() if distance>0.05 else -center.normalized()
	# At exact field centre the original zero vector stays zero: lift only.
	var horizontal=(65.0-distance/3.0)*0.1 if distance>0.05 else 6.5
	return Vector3(direction.x*horizontal,direction.y*horizontal,17.5 if ball else 35.0)

static func smash_hit(offset: Vector2,facing: float,reach: float) -> bool:
	var direction=Vector2.from_angle(facing)
	var forward=offset.dot(direction)
	return forward>=0 and forward<=reach and absf(offset.dot(direction.orthogonal()))<=200

static func smash(sim,index: int):
	var p=sim.players[index]
	sim.emit_text(index,"OGRE SMASH!",1.0)
	var force=Vector3(cos(p.body)*45,sin(p.body)*45,0)
	for i in range(sim.players.size()):
		var other=sim.players[i]
		if i==index or absent(other) or other.pos.distance_to(p.pos)>350 or absf(other.z-p.z)>=10:continue
		if smash_hit(other.pos-p.pos,p.body,350):
			sim.apply_impulse(i,force)
			if i==sim.last_owner:sim.MatchRules.assist(sim,index)
			if other.team!=p.team:other.ogre_slow=1.0
	var owned=sim.last_owner==index
	if sim.ball_present and sim.holder<0 and sim.ball.z>p.z-25 and sim.ball.z<p.z+50 and smash_hit(Vector2(sim.ball.x,sim.ball.y)-p.pos,p.body,700 if owned else 350):
		if owned:sim.velocity=force.normalized()*55.0
		else:sim.velocity+=force
		sim.last_owner=index
	sim.skill_effects.append({"kind":"smash","pos":world_position(p),"facing":p.body,"life":0.4,"age":0.0,"owner":index})

static func slam(sim,index: int):
	var p=sim.players[index]
	var center=world_position(p)+Vector3(cos(p.body)*100,sin(p.body)*100,0)
	var factor=0.0 if p.z>600 else (1.0-p.z/660.0 if p.z>70 else 1.0)
	for j in range(sim.players.size()):
		if j==index or absent(sim.players[j]) or p.pos.distance_to(sim.players[j].pos)>720:continue
		var v=world_position(sim.players[j])-center+Vector3(0,0,300)
		if v.length()<=720:
			sim.apply_impulse(j,v.normalized()*(66.5-v.length()/12.0)*factor)
			if j==sim.last_owner:sim.MatchRules.assist(sim,index)
	var b=sim.ball-center+Vector3(0,0,300)
	if sim.ball_present and sim.holder<0 and b.length()<=720:
		sim.velocity+=b.normalized()*(69.5-b.length()/12.0)*factor
		sim.last_owner=index
	# Slam___slamEffect iterates every ball slot, unlike Smash/BlackHole.
	for copy in sim.fake_balls:
		var delta=copy.position-center+Vector3(0,0,300)
		if copy.life>0 and copy.holder<0 and delta.length()<=720:
			copy.velocity+=delta.normalized()*(69.5-delta.length()/12.0)*factor
			copy.last_owner=index
	sim.skill_effects.append({"kind":"slam","pos":center,"life":0.65,"age":0.0,"owner":index})

static func blink(sim,index: int):
	var p=sim.players[index]
	var position: Vector2=p.pos
	p.shadow_origin=position
	p["shadow_facing"]=p.body
	var departed=world_position(p)
	var direction=Vector2.from_angle(p.body)
	# Shadow___blink advances ten, checking terrain forty units ahead.
	for step in range(40):
		if not sim.arena.point_free(position+direction*40,0.01,sim.goal_restrictions(index)):break
		position+=direction*10
	var destination=sim.nearby_free(position,index)
	if destination.is_finite():p.pos=destination;p.previous=destination
	sim.Possession.relocated(sim,index)
	p.shadow_return=2.5 # Actual 0.5s counter callbacks, not the stale tooltip.
	p["shadow_message_remaining"]=2.0
	if p.want_move:sim.plan_route(index)
	sim.skill_effects.append({"kind":"blink","pos":departed,"life":0.5,"age":0.0,"owner":index})

static func step(sim):
	if sim.ball_present and not sim.curve.is_empty():
		var c=sim.curve
		var angle=atan2(sim.velocity.y,sim.velocity.x)+c.angle
		sim.velocity+=Vector3(cos(angle),sin(angle),0)*c.force
		c.force+=c.force_delta/2;c.angle+=c.angle_delta/2;c.life-=sim.BALL_DT
		if c.life<=0:sim.curve.clear()
	for projectile in sim.projectiles:
		if projectile.life<=0:continue
		if projectile.kind=="swap":step_swap(sim,projectile)
		elif projectile.kind=="hook":Complex.hook_step(sim,projectile)
		elif projectile.kind=="rift":Complex.rift_projectile_step(sim,projectile)
	Complex.step(sim)
	sim.projectiles=sim.projectiles.filter(func(p):return p.life>0)
	for i in range(sim.players.size()):
		var p=sim.players[i]
		if not sim.unit_present(i):continue
		p.secondary_cooldown=maxf(0,p.secondary_cooldown-sim.BALL_DT)
		p.silence=maxf(0,p.silence-sim.BALL_DT)
		Morph.step(sim,i)
		p.eject_time=maxf(0,p.eject_time-sim.BALL_DT)
		p.jump_cooldown=maxf(0,p.jump_cooldown-sim.BALL_DT)
		if p.flight_steps>0:fly_into_ball(sim,i)
		elif p.possess_time>0:
			p.pos=Vector2(sim.ball.x,sim.ball.y);p.z=sim.ball.z
			p.possess_time=maxf(0,p.possess_time-sim.BALL_DT)
			if p.possess_time<=0:eject(sim,i)
			else:possess_jump(sim,i)
		if p.flip_time>0:
			p.flip_time=maxf(0,p.flip_time-sim.BALL_DT)
			if p.flip_time<=0:sim.set_unit_pathing(i,true)
			if p.flip_time<=0 and p.z<20:
				var motion=Vector3(p.knock.x,p.knock.y,p.vz)
				motion=motion.normalized()*maxf(0,motion.length()-14)
				p.knock=Vector2(motion.x,motion.y);p.vz=motion.z
		p.stealth_time=p.stealth_time+sim.BALL_DT if p.sprint and p.character=="h00R" else 0.0
		p.invisible=p.stealth_time>=1.0
		if p.sprint and p.character=="h004":
			sim.apply_impulse(i,Vector3(cos(p.body)*0.72,sin(p.body)*0.72,0))
			if Vector3(p.knock.x,p.knock.y,p.vz).length()*128<3*p.speed:sim.set_sprint(i,false)
		p.disabled=maxf(0,p.disabled-sim.BALL_DT)
		p.stun=maxf(0,p.stun-sim.BALL_DT)
		p.ogre_slow=maxf(0,p.ogre_slow-sim.BALL_DT)
		p.power_slow=maxf(0,p.power_slow-sim.BALL_DT)
		p.power_slow_cooldown=maxf(0,p.power_slow_cooldown-sim.BALL_DT)
		p.sprint_cooldown=maxf(0,p.sprint_cooldown-sim.BALL_DT)
		var had_shadow=p.shadow_return>0
		p.shadow_return=maxf(0,p.shadow_return-sim.BALL_DT)
		if had_shadow and p.shadow_return>0 and p.shadow_return<=p.get("shadow_message_remaining",2.0):
			var remaining=float(p.get("shadow_message_remaining",2.0))
			var message=sim.emit_world_text(Vector3(p.shadow_origin.x,p.shadow_origin.y,0),("%.3f"%remaining).substr(0,3)+"!",.75)
			message.audience_owner=i
			p.shadow_message_remaining=remaining-.5
		if had_shadow and p.shadow_return<=0:
			sim.emit_visual("fx_shadow",Vector3(p.shadow_origin.x,p.shadow_origin.y,0))
		if p.ability_delay>0:
			var previous_delay: float=p.ability_delay
			p.ability_delay-=sim.BALL_DT
			if p.ability_kind=="pillar" and previous_delay>0.1 and p.ability_delay<=0.1:pillar_cast_effects(sim,i)
			if p.ability_delay<=0:
				if p.ability_kind=="slam":slam(sim,i)
				elif p.ability_kind=="shadow":blink(sim,i)
				elif p.ability_kind=="pillar":create_pillar(sim,i)
				elif p.ability_kind=="smash":smash(sim,i)
				elif p.ability_kind=="powershot":
					p.disabled=0
					if sim.holder==i and sim.kick(i,p.ability_target,51.0,0.0):
						sim.powershot_active=true;p.cooldown=0
						sim.emit_visual("fx_powershot",sim.ball,0.67)
		if p.pull_time>0:
			if sim.holder==i:finish_pull(p)
			else:
				sim.apply_impulse(i,(sim.ball-world_position(p)).normalized()*1.4)
				p.pull_time-=sim.BALL_DT
				p.pull_level=clampi(ceili(5.0-p.pull_time),1,5)
				if p.pull_time<=0:finish_pull(p)
	for effect in sim.skill_effects:
		if effect.kind=="black_hole":
			var ball_delta: Vector3=effect.pos-sim.ball
			if sim.ball_present and ball_delta.length()<=700:
				if sim.holder>=0:effect["ball_caught"]=false
				else:
					if sim.velocity.length()==0 or sim.last_owner<0:sim.last_owner=effect.owner
					sim.MatchRules.assist(sim,effect.owner)
					if not effect.get("ball_caught",false):effect["ball_caught"]=true;effect["ball_angle"]=atan2(sim.velocity.y,sim.velocity.x)
					if ball_delta.length()>0.001:sim.velocity=(sim.velocity+ball_delta.normalized()*effect.power/ball_delta.length_squared()).limit_length(60)
			elif sim.ball_present and effect.get("ball_caught",false):
				effect["ball_caught"]=false
				if sim.holder<0 and absf(angle_difference(effect.ball_angle,atan2(sim.velocity.y,sim.velocity.x)))>deg_to_rad(80):
					sim.MatchRules.assist(sim,sim.last_owner);sim.last_owner=effect.owner
			for i in range(sim.players.size()):
				if i==effect.owner or absent(sim.players[i]):continue
				var p=sim.players[i]
				var v=effect.pos-world_position(p)
				if v.length()>0.001 and v.length()<=700:
					sim.apply_impulse(i,v.normalized()*effect.power/v.length_squared())
					var velocity=Vector3(p.knock.x,p.knock.y,p.vz).limit_length(60)
					p.knock=Vector2(velocity.x,velocity.y);p.vz=velocity.z
			effect.life-=sim.BALL_DT
			if effect.life>2.4:effect.power+=50000.0/1.1/32.0
		else:effect.life-=sim.BALL_DT
		effect.age+=sim.BALL_DT
	sim.skill_effects=sim.skill_effects.filter(func(e):return e.life>0)
	for pillar in sim.arena.pillars:
		pillar.life-=sim.BALL_DT;pillar.age+=sim.BALL_DT
		for i in pillar.knocked_units.keys():
			# IsUnitInRangeXY adds only the queried player's native radius.
			if sim.players[i].pos.distance_to(pillar.center)>90+sim.players[i].radius:pillar.knocked_units.erase(i)
		if sim.holder>=0 or Vector2(sim.ball.x,sim.ball.y).distance_to(pillar.center)>90:pillar.ball_knocked=false
	sim.arena.expire_pillars()
