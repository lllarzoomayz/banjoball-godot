extends RefCounted
## Original match rules from war3map.j: GameEnd, FirstHalfEnd, Game__start,
## score and s__Ball_assist. Kept separate from ball/movement integration.
const EXTENSION_TIME=120.0
const HALF_TIME=600.0
const HALF_DELAY=15.0
const ASSIST_TIME=6.0

static func clear(sim):
	sim.half=1;sim.extra_period=0;sim.elapsed=0.0
	sim.halftime_left=0.0;sim.halftime_swapped=false
	sim.stats.clear();sim.goal_history.clear();sim.assistants.clear();sim.roster.clear()
	sim.overtime=false;sim.winner=-1

static func assist(sim,index: int):
	if index<0 or index>=sim.players.size() or sim.last_owner<0:return
	if sim.players[index].team!=sim.players[sim.last_owner].team:return
	sim.assistants[index]=sim.time+ASSIST_TIME

static func ownership(sim,index: int):
	# Catching by the opposing team clears the entire assist chain.
	if sim.last_owner>=0 and sim.players[index].team!=sim.players[sim.last_owner].team:sim.assistants.clear()
	sim.last_owner=index

static func record_goal(sim,team: int):
	var scorer=sim.last_owner
	var own_goal=scorer>=0 and sim.players[scorer].team!=team
	var helpers=[]
	if scorer>=0 and not own_goal:
		for index in sim.assistants:
			if index!=scorer and sim.assistants[index]>sim.time and sim.players[index].team==team:helpers.append(index)
		if scorer<sim.stats.size():sim.stats[scorer].goals+=1
		for index in helpers:
			if index<sim.stats.size():sim.stats[index].assists+=1
	elif own_goal and scorer<sim.stats.size():sim.stats[scorer].own_goals+=1
	if sim.match_enabled:
		sim.goal_history.append({"elapsed":sim.elapsed,"half":sim.half,"extra_period":sim.extra_period,"team":team,"scorer":scorer,"own_goal":own_goal,"assists":helpers,"score":sim.score.duplicate()})

static func kickoff(sim):
	sim.match_state="playing"
	sim.holder=-1;sim.last_owner=-1;sim.assistants.clear()
	var angle=sim.random.randf_range(0,TAU)
	var speed=sim.random.randf_range(15,20)
	sim.velocity=Vector3(cos(angle)*speed,sin(angle)*speed,0)
	sim.notice="开球！右键移动，W 传射，Q 角色技能，E 冲刺。"

static func period_end(sim):
	if sim.mode=="tournament" and sim.half==1:
		sim.match_state="halftime";sim.half=2
		sim.halftime_left=HALF_DELAY;sim.halftime_swapped=false
		sim.time_left=0;sim.pending_commands.clear();sim.StallRules.reset(sim)
		sim.notice="上半场结束，双方交换场地；中场休息可更换当前角色。"
	elif sim.score[0]==sim.score[1]:
		sim.overtime=true;sim.extra_period+=1;sim.time_left=EXTENSION_TIME
		sim.notice="平局，追加 2 分钟；加时结束仍平局则继续加时。"
	else:sim.finish_match(0 if sim.score[0]>sim.score[1] else 1)

static func tick(sim) -> bool:
	# True permits gameplay. MatchSim separately continues a scored ball during
	# celebration; countdown and halftime retain their stationary reset ball.
	if sim.match_state=="ended":
		sim.reset_delay=maxf(0,sim.reset_delay-sim.BALL_DT)
		return false
	if sim.match_state=="halftime":
		sim.halftime_left=maxf(0,sim.halftime_left-sim.BALL_DT)
		if not sim.halftime_swapped and sim.halftime_left<=HALF_DELAY-3:
			sim.arena.swap_ends();sim.halftime_swapped=true;sim.reset()
			sim.notice="已交换场地；"+sim.team_name(0)+"向左进攻。可在中场休息更换当前角色。"
		if sim.halftime_left<=0:
			sim.reset();sim.time_left=HALF_TIME;sim.match_state="countdown";sim.countdown=3.0
			sim.notice="下半场准备开球"
		return false
	if sim.match_state=="countdown":
		sim.countdown=maxf(0,sim.countdown-sim.BALL_DT)
		if sim.countdown<=0:kickoff(sim)
		return false
	if sim.match_state=="goal":
		sim.reset_delay=maxf(0,sim.reset_delay-sim.BALL_DT)
		if sim.reset_delay<=0:
			sim.reset();sim.match_state="countdown";sim.countdown=3.0
		return false
	if sim.match_state!="playing":return false
	var clock_paused=sim.mode!="score" and sim.apocalypse_active()
	if not clock_paused:sim.elapsed+=sim.BALL_DT
	if sim.mode!="score" and not clock_paused:
		sim.time_left=maxf(0,sim.time_left-sim.BALL_DT)
		if sim.time_left<=0:period_end(sim)
	return sim.match_state=="playing"

static func clock_text(sim) -> String:
	if sim.match_state=="halftime":return "中场休息 · %d 秒"%ceili(sim.halftime_left)
	if sim.mode=="score":return "先得 %d 球 · 不限时"%sim.score_limit
	var clock="%02d:%02d"%[int(ceil(sim.time_left))/60,int(ceil(sim.time_left))%60]
	if sim.overtime:return "加时 %d · "%sim.extra_period+clock
	if sim.mode=="tournament":return ("上半场 · " if sim.half==1 else "下半场 · ")+clock
	return "计时赛 · "+clock
