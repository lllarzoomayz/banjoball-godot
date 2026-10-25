extends RefCounted
## s__Ball_keepProtection runs at 20 Hz independently of 32 Hz ball physics.
## It prevents extended boundary/goal-area possession, not normal dribbling.
static func reset(sim):
	sim.stall_counter=0;sim.stall_warned=false;sim.referee={};sim.next_referee=INF

static func step(sim):
	if not sim.ball_present or not sim.match_enabled or sim.match_state!="playing":return
	var xy=Vector2(sim.ball.x,sim.ball.y)
	var boundary=false
	for b in sim.arena.boundaries:
		if b.rect.has_point(xy):boundary=true;break
	if boundary and sim.holder>=0:
		sim.stall_counter+=1 if sim.arena.terrain_walkable(xy) else 5
	elif sim.arena.in_guard(xy,0) or sim.arena.in_guard(xy,1):
		sim.stall_counter+=2 if sim.holder>=0 else 1
	elif sim.stall_counter!=0:
		if sim.stall_counter<=4:sim.stall_counter=0;sim.stall_warned=false
		else:sim.stall_counter-=4
	if sim.stall_counter>=210 and not sim.stall_warned:
		sim.stall_warned=true
		var warning=sim.emit_world_text(sim.ball,"!",1.5)
		warning.text_offset=Vector3(6,0,100);warning.text_color="ffcc00";warning.text_size=.0235
		sim.notice="门前或边界停留过久，请及时出球。"
	elif sim.stall_counter>=300:
		for side in [0,1]:
			if sim.arena.goals[side].has_point(xy):
				sim.award_goal(1-side)
				sim.notice="球在球门内停留过久，判对方得分。"
				return
		if (sim.holder<0 and sim.velocity.length()>3) or sim.ball.z>60:
			sim.stall_counter=290
		elif sim.referee.is_empty():
			sim.referee={"pos":referee_position(sim.ball),"age":0.0,"kicked":false}
			sim.next_referee=sim.next_rules+0.57
			sim.stall_counter=-100
			sim.notice="停留过久，裁判将球踢回场内。"

static func referee_position(ball: Vector3) -> Vector3:
	var direction=Vector2(ball.x,ball.y).normalized()
	return ball+Vector3(direction.x*110,direction.y*110,0)

static func kick(sim):
	sim.next_referee=INF
	if not sim.ball_present or sim.referee.is_empty() or not sim.match_enabled or sim.match_state!="playing":return
	# Release a hook before the referee takes control, avoiding competing owners.
	for h in sim.projectiles:
		if h.kind=="hook" and h.caught==-2:sim.Characters.Complex.hook_drop(sim,h)
	if sim.holder>=0:sim.last_owner=sim.holder;sim.Characters.cancel_charge(sim.players[sim.holder])
	sim.MatchRules.assist(sim,sim.last_owner)
	var direction=-Vector2(sim.ball.x,sim.ball.y).normalized()
	sim.velocity+=Vector3(direction.x*30,direction.y*30,7)
	sim.holder=-1;sim.no_steal=0;sim.intercept=8
	sim.stall_counter=0;sim.stall_warned=false
	sim.referee.kicked=true
	sim.notice="裁判已将球踢回场内。"

static func visuals_step(sim):
	if sim.referee.is_empty():return
	sim.referee.age+=sim.BALL_DT
	if sim.ball_present and not sim.referee.kicked:sim.referee.pos=referee_position(sim.ball)
	if sim.referee.age>=1.5:sim.referee={}
