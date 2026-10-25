extends RefCounted
# Only data properties, no RefCounted/Node instances or executable objects.
const FIELDS=["players","ball","ball_present","previous_ball","velocity","holder","last_owner","intercept","score","time","notice","reset_delay","goal_ball_live","last_goal","timeline","next_move","next_ball","match_enabled","team_size","score_limit","duration","time_left","mode","half","halftime_left","halftime_swapped","extra_period","elapsed","stats","goal_history","match_state","countdown","overtime","winner","pass_request","selected_field","roster","skill_effects","native_visuals","next_visual","powershot_active","no_steal","fake_balls","projectiles","rifts","ball_hook","tackle_shadows","audio_events","next_audio","generated_ice","field_started","referee","stall_counter","stall_warned","franchise_config"]

static func capture(sim) -> Dictionary:
	var data={}
	for field in FIELDS:data[field]=sim.get(field)
	data["pillars"]=sim.arena.pillars
	data["sides_swapped"]=sim.arena.sides_swapped
	return data

static func apply(sim,data: Dictionary):
	for field in FIELDS:
		if field!="players" and data.has(field):sim.set(field,data[field])
	var incoming=data.get("players",[])
	if sim.players.size()!=incoming.size():sim.players=incoming.duplicate(true)
	else:
		# Renderers use player identity to detect a new match. Preserve it between
		# packets, or every frame rebuilds goal/morph/scenery effects.
		for i in range(incoming.size()):
			sim.players[i].clear();sim.players[i].merge(incoming[i])
	if sim.arena.field_index!=sim.selected_field:sim.arena.set_field(sim.selected_field)
	if sim.arena.sides_swapped!=data.get("sides_swapped",false):sim.arena.swap_ends()
	sim.arena.pillars=data.get("pillars",[])
	sim.shout.states=sim.players.map(func(p):return p.get("shout_state",{}))
	sim.bot_enabled=false

static func interpolate(sim,a: Dictionary,b: Dictionary,alpha: float):
	apply(sim,b)
	# Player dictionaries are independent of the immutable snapshots.
	if a.get("players",[]).size()!=sim.players.size():return
	for i in range(sim.players.size()):
		var p=sim.players[i];var prev=a.players[i]
		if prev.pos.distance_to(p.pos)<250:
			p.pos=prev.pos.lerp(p.pos,alpha);p.body=lerp_angle(prev.body,p.body,alpha);p.z=lerpf(prev.z,p.z,alpha)
		p.previous=p.pos;p.previous_body=p.body;p.previous_z=p.z
	if a.get("ball",sim.ball).distance_to(sim.ball)<600:sim.ball=a.ball.lerp(sim.ball,alpha)
	sim.previous_ball=sim.ball
