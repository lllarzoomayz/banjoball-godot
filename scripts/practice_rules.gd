extends RefCounted
## Manual singleplayer conveniences, separate from authored skill rules.

static func available(sim,index: int) -> bool:
	return sim.unit_present(index) and not sim.match_enabled and sim.match_state=="practice" and sim.reset_delay<=0 and index>=0 and index<sim.players.size()

static func skill_busy(sim,index: int) -> bool:
	var p=sim.players[index]
	if p.tackle>0 or p.cast_pending or p.ability_delay>0 or p.disabled>0 or p.hooked!=0 or sim.Characters.absent(p):return true
	if p.flip_time>0 or p.pull_time>0 or p.shadow_return>0 or p.morph_roll>0 or not p.hook.is_empty() or not p.rift.is_empty():return true
	for projectile in sim.projectiles:
		if projectile.owner==index and projectile.life>0:return true
	for effect in sim.skill_effects:
		if effect.owner==index and effect.kind=="black_hole" and effect.life>0:return true
	return false

static func refresh(sim,index: int) -> bool:
	if not available(sim,index):return false
	if skill_busy(sim,index):
		sim.notice="当前技能结束后，按 F6 补满魔法并刷新冷却。"
		return false
	var p=sim.players[index]
	p.mana=100.0
	for key in ["cooldown","secondary_cooldown","sprint_cooldown","keeper_cooldown","power_slow_cooldown"]:p[key]=0.0
	if p.has("shout_state"):p.shout_state.ready_at=0.0
	sim.notice="已补满魔法、刷新冷却；位置与练习场景保留。"
	return true

static func recall_ball(sim,index: int) -> bool:
	if not sim.ball_present:return false
	if not available(sim,index):return false
	var p=sim.players[index]
	if not sim.Characters.catchable(p) or p.stun>0 or p.disabled>0 or p.tackle>0:
		sim.notice="角色恢复行动后，按 F7 拿回足球。"
		return false
	if sim.ball_hook!=0 or sim.players.any(func(player):return sim.Characters.absent(player)):
		sim.notice="足球正被技能控制；结束后可按 F7 拿回。"
		return false
	# A practice recall is not a physical high-speed catch. Dispatch regular
	# ownership cleanup, but don't transfer the old ball's momentum to a player.
	if sim.holder>=0 and sim.holder!=index:sim.Characters.cancel_charge(sim.players[sim.holder])
	sim.velocity=Vector3.ZERO
	sim.take(index)
	sim.last_owner=index
	sim.ball=sim.Copies.held_position(sim,index);sim.previous_ball=sim.ball
	sim.notice="足球已拿回，按 W 传射或使用持球技能。"
	return true
