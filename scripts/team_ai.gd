extends RefCounted
## Singleplayer opponents and teammates, separate from movement/ball rules.
## AI submits the same move, sprint, tackle and kick actions as local players.
static func pursuit_target(sim,index: int,view: Dictionary) -> Vector2:
	var p=sim.players[index]
	var ball=Vector2(view.position.x,view.position.y)
	var region: Rect2=sim.arena.field_rect
	# Keep the defending player's target inside an accessible goal corridor too.
	# Clamping everything to the field would make a keeper run AWAY from a ball
	# behind the endline. The normal planner still enforces every goal restriction.
	if sim.arena.in_guard(ball,p.team) and not sim.goal_blocked(index,p.team):
		for area in sim.arena.guards[p.team]:region=region.merge(area)
	# The former 86/132 inset left an arrived chaser outside the 90-unit catch
	# radius (especially at corners). Use footprint clearance, leaving room for
	# the normal movement stopping distance without changing catching or walls.
	var clearance=Vector2.ONE*(p.radius+4.0)
	return (ball+Vector2(view.velocity.x,view.velocity.y)*4).clamp(region.position+clearance,region.end-clearance)

static func steer(sim,index: int,target: Vector2):
	var p=sim.players[index]
	if p.cast_pending or not p.shot_order.is_empty() or p.tackle>0 or p.disabled>0 or p.stun>0 or not p.ability_order.is_empty():return
	if not sim.free_point(target,index):
		var chosen=target;var best=INF
		for radius in [80.0,160.0,240.0]:
			for direction in range(8):
				var candidate=target+Vector2.from_angle(direction*TAU/8)*radius
				var score=p.pos.distance_to(candidate)+radius*2
				if score<best and sim.free_point(candidate,index):chosen=candidate;best=score
			if best<INF:break
		target=chosen
	if not p.want_move or p.target.distance_to(target)>90:sim.command(index,target)

static func clear_pass(sim,index: int,target: Vector2) -> bool:
	var p=sim.players[index].pos
	return sim.arena.sweep_ball(Vector3(p.x,p.y,40),Vector3(target.x-p.x,target.y-p.y,0)).is_empty()

static func pass_target(sim,index: int) -> int:
	var p=sim.players[index]
	var direction=sim.arena.attack_direction(p.team)
	var best=-1;var best_score=-INF
	for j in range(sim.players.size()):
		var other=sim.players[j]
		if j==index or other.team!=p.team or sim.Characters.absent(other) or sim.has_ball(j):continue
		var distance=p.pos.distance_to(other.pos)
		if distance<160 or distance>1500 or not clear_pass(sim,index,other.pos):continue
		var space=1000.0
		for enemy in sim.players:
			if enemy.team!=p.team:space=minf(space,enemy.pos.distance_to(other.pos))
		var value=(other.pos.x-p.pos.x)*direction+space*0.6-distance*0.1
		if sim.pass_request>0 and j==(sim.pass_player if sim.pass_player>=0 else sim.controlled):value+=3000
		if value>best_score:best_score=value;best=j
	return best

static func observation(sim,team: int) -> Dictionary:
	var real={"position":sim.ball,"velocity":sim.velocity,"holder":sim.holder,"id":0}
	if sim.holder>=0 and sim.players[sim.holder].team==team:return real
	var options=[real]
	for copy in sim.fake_balls:
		# Same-team copies are blue in the original client. Enemy copies look real.
		if copy.team!=team and copy.life>0:options.append(copy)
	var chosen=real;var best=INF
	for option in options:
		for p in sim.players:
			if p.team!=team or sim.Characters.absent(p):continue
			var distance=p.pos.distance_squared_to(Vector2(option.position.x,option.position.y))
			if distance<best:chosen=option;best=distance
	return chosen

static func think(sim):
	if not sim.ball_present:return # Football AI has no target after RemoveUnit(ball).
	var half=sim.arena.half_size
	var dx=half.x-2016.0
	var dy=half.y-1312.0
	var views=[observation(sim,0),observation(sim,1)]
	var chasers=[-1,-1];var distances=[INF,INF]
	for i in range(sim.players.size()):
		var p=sim.players[i]
		if p.role=="keeper" or sim.Characters.absent(p):continue
		var view=views[p.team]
		var predicted=pursuit_target(sim,i,view)
		var d=p.pos.distance_to(predicted)
		if d<distances[p.team]:distances[p.team]=d;chasers[p.team]=i
	for i in range(sim.players.size()):
		if (i in sim.human_slots if sim.networked else i==sim.controlled) or not sim.unit_present(i):continue
		var p=sim.players[i]
		var view=views[p.team]
		var ball=Vector2(view.position.x,view.position.y)
		var predicted=pursuit_target(sim,i,view)
		if p.possess_time>0:
			if not p.jump_due and sim.holder<0:sim.command(i,sim.arena.shot_target(p.team,-ball.y*0.15))
			continue
		if p.flight_steps>0 or p.hooked!=0:continue
		if p.cast_pending or not p.shot_order.is_empty() or p.tackle>0 or p.disabled>0 or p.stun>0 or not p.ability_order.is_empty():continue
		var skill_id=p.morph_kit if p.morph_kit!="" else p.character
		var direction=sim.arena.attack_direction(p.team)
		var target_goal=sim.arena.shot_target(p.team,-ball.y*0.15)
		var own_goal=sim.arena.keeper_position(p.team)+Vector2(0,clampf(ball.y*0.35,-160,160))
		if sim.KeeperRules.should_jump(sim,i,view):
			sim.KeeperRules.hold(sim,i);p.ai_action=0.6;continue
		if p.character=="h029" and p.morph_kit=="" and p.cooldown<=0:
			sim.Characters.use(sim,i,p.pos);continue
		if skill_id=="h027" and sim.Characters.q_available(p):
			var target=p.pos+Vector2(direction*600,0) if not p.rift.is_empty() else p.pos
			if sim.Characters.use(sim,i,target):continue
		if sim.has_ball(i):
			var pressure=INF
			for opponent in sim.players:
				if opponent.team!=p.team:pressure=minf(pressure,p.pos.distance_to(opponent.pos))
			var receiver=pass_target(sim,i)
			var should_pass=p.role=="keeper" or pressure<260 or (sim.pass_request>0 and sim.unit_present(sim.pass_player) and p.team==sim.players[sim.pass_player].team)
			if p.character=="h01N" and sim.holder==i and p.cooldown<=0 and pressure<650 and sim.pass_request<=0:
				var keep_real=p.number%2==0
				var decoy_target=target_goal if not keep_real else p.pos+Vector2(direction*900,500 if p.pos.y<0 else -500)
				if sim.Characters.use(sim,i,decoy_target,not keep_real):continue
			if p.character=="h010" and p.cooldown<=0 and pressure<450 and sim.pass_request<=0:
				sim.Characters.use(sim,i,p.pos);continue
			if skill_id=="h00R" and p.cooldown<=0 and pressure<350 and Vector2.from_angle(p.body).x*direction>0.5:
				sim.Characters.use(sim,i,p.pos)
			if receiver>=0 and should_pass and p.ai_action<=0:
				if sim.ShotOrder.request(sim,i,sim.players[receiver].pos):
					p.ai_action=0.8
					if receiver==sim.pass_player:sim.pass_request=0
			elif p.pos.distance_to(target_goal)<1250 and absf(p.pos.y)<750 and clear_pass(sim,i,target_goal) and p.ai_action<=0:
				if skill_id=="h012" and sim.holder==i and p.cooldown<=0:
					if sim.Characters.use(sim,i,target_goal,p.pos.y<0):p.ai_action=0.8
				elif skill_id=="h00F" and sim.holder==i and p.cooldown<=0:
					if sim.Characters.use(sim,i,target_goal):p.ai_action=0.8
				elif sim.ShotOrder.request(sim,i,target_goal,35.0 if p.character=="h028" else 30.0):p.ai_action=0.8
			else:
				var lane=clampf(p.pos.y*0.65,-650,650)
				steer(sim,i,Vector2(direction*(1580+dx),lane))
			sim.set_sprint(i,p.mana>35 and (p.pos.distance_to(target_goal)>1000 or p.character=="h028"))
			if not p.shot_order.is_empty():continue
			if skill_id=="h01I" and p.cooldown<=0 and p.pos.x*direction<1300+dx and Vector2.from_angle(p.body).x*direction>0.8:
				sim.Characters.use(sim,i,p.pos)
			continue
		if p.role=="keeper":
			var close=ball.x*direction < -1550-dx and absf(ball.y)<380
			steer(sim,i,predicted if close and view.holder<0 else own_goal)
			sim.set_sprint(i,false)
		else:
			var team_has_ball=view.holder>=0 and sim.players[view.holder].team==p.team
			var target=predicted
			if i!=chasers[p.team] or team_has_ball:
				var lane=-1.0 if p.number%2==0 else 1.0
				if team_has_ball:
					target=Vector2(clampf(ball.x+direction*(350+p.number*80),-1550-dx,1550+dx),lane*(320+p.number*75))
				else:
					target=Vector2(clampf(ball.x-direction*(450+p.number*100),-1700-dx,1700+dx),clampf(ball.y*0.4+lane*(240+p.number*55),-1000-dy,1000+dy))
			steer(sim,i,target)
			sim.set_sprint(i,p.mana>35 and p.pos.distance_to(target)>500 and p.character!="h028")
		if p.cooldown<=0 and sim.holder!=i:
			match skill_id:
				"h01R":
					if p.hook.is_empty() and p.pos.distance_to(ball)<1000:sim.Characters.use(sim,i,ball)
				"h001":
					if view.holder>=0 and sim.players[view.holder].team!=p.team and p.pos.distance_to(ball)<1200:sim.Characters.use(sim,i,sim.players[view.holder].pos)
				"h00Y":
					if p.pull_time<=0 and p.pos.distance_to(ball)>450 and p.pos.distance_to(ball)<1500:sim.Characters.use(sim,i,ball)
				"h003":
					if sim.holder<0 and p.pos.distance_to(ball)<850:sim.Characters.use(sim,i,ball)
				"h00P":
					if p.pos.distance_to(ball)<430 and (sim.holder<0 or sim.players[sim.holder].team!=p.team):sim.Characters.use(sim,i,ball)
				"h02C":
					if p.pos.distance_to(ball)<700 and (sim.holder<0 or sim.players[sim.holder].team!=p.team):sim.Characters.use(sim,i,ball)
				"h026":
					if sim.Characters.smash_hit(ball-p.pos,p.body,320):sim.Characters.use(sim,i,ball)
		if view.holder>=0 and sim.players[view.holder].team!=p.team and p.cooldown<=0:
			var enemy=sim.players[view.holder]
			if enemy.invisible:continue
			if skill_id=="h005" and p.pos.distance_to(enemy.pos)<390:
				sim.tackle(i,enemy.pos+(enemy.pos-enemy.previous)*4)
