extends RefCounted
## The source grants Q/R skills, not a complete replacement of the player's
## unit stats or E. Its temporary second model is purely a spell animation.
const POOL=["h00P","h003","h005","h00F","h00Y","h001","h012","h01I","h01R","h026","h00R","h02C"]
const DURATIONS={"slam":0.36,"black_hole":3.5,"tackle":1.5,"powershot":0.5,"pull":4.5,"swap":1.8,"curve":1.4,"shadow":4.0,"hook":15.0,"smash":0.15,"backflip":1.09,"pillar":0.4}

static func cast(sim,index: int) -> bool:
	var p=sim.players[index]
	if p.cooldown>0 or p.morph_roll>0 or p.morph_kit!="":return false
	sim.stop(index,false)
	p.morph_roll=2.5;p.disabled=2.5;p.sprint=false
	p.action=2.5;p.action_clip="Stand Channel"
	p.morph_preview=POOL[sim.random.randi_range(0,POOL.size()-1)]
	if index==sim.controlled:sim.notice="随机突变中：完成后获得一种技能，可使用三次。"
	return true

static func record(sim,index: int,kind: String):
	var p=sim.players[index]
	if p.character!="h029" or p.morph_kit=="":return
	p.morph_casts=maxi(0,p.morph_casts-1)
	p.morph_ghost=float(DURATIONS.get(kind,0.0))+2.0
	sim.emit_visual("fx_metamorph",sim.Characters.world_position(p),2.0)
	if index==sim.controlled:sim.notice="借用"+sim.Characters.DATA[p.morph_kit].skill+" · 剩余 %d 次"%p.morph_casts

static func reset_kit(sim,index: int,manual: bool=false) -> bool:
	var p=sim.players[index]
	if p.character!="h029" or p.morph_kit=="":return false
	if manual and (p.morph_ghost>0 or p.pull_time>0 or p.shadow_return>0 or not p.hook.is_empty() or p.ability_delay>0 or p.cast_pending):
		sim.notice="当前技能结束后可按 F1 放弃借用。";return false
	p.morph_last=p.morph_kit;p.morph_kit="";p.morph_casts=0;p.morph_ghost=0
	p.cooldown=20.0;p.secondary_cooldown=0;p.ability_kind=""
	if manual:p.slide_order=false
	if index==sim.controlled:sim.notice="随机突变已重置，冷却 20 秒。"
	return true

static func step(sim,index: int):
	var p=sim.players[index]
	if p.character!="h029":return
	if p.morph_roll>0:
		var old=p.morph_roll;p.morph_roll=maxf(0,p.morph_roll-sim.BALL_DT)
		if floori(old*10)!=floori(p.morph_roll*10) and p.morph_roll>0.5:
			var choices=POOL.filter(func(id):return id!=p.morph_last)
			p.morph_preview=choices[sim.random.randi_range(0,choices.size()-1)]
		if p.morph_roll<=0:
			p.morph_kit=p.morph_preview;p.morph_casts=3
			p.disabled=0;p.cooldown=0;p.secondary_cooldown=0
			if index==sim.controlled:sim.notice="获得"+sim.Characters.DATA[p.morph_kit].skill+"，可用 3 次；F1 放弃借用。"
	if p.morph_ghost>0:
		p.morph_ghost=maxf(0,p.morph_ghost-sim.BALL_DT)
		if p.morph_ghost<=0 and p.morph_casts<=0:reset_kit(sim,index)
