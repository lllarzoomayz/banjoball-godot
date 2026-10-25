extends RefCounted
signal apocalypse_prepared(adapter)
var generated_ice=[]
var franchise_config={}
const Franchise=preload("res://scripts/franchise_rules.gd")
func team_name(index: int) -> String:return Franchise.name_for(franchise_config,index)
func team_color(index: int) -> Color:return Franchise.color_for(franchise_config,index)
const Emotes=preload("res://scripts/emote_rules.gd")
## XY are original Warcraft ground coordinates; Z is height. Rendering alone
## converts centimeters to Godot meters. Locomotion 0.03s, map ball 1/32s.
const Native=preload("res://scripts/native_rules.gd")
const Search=preload("res://scripts/native_grid_search.gd")
const Arena=preload("res://scripts/arena_collision.gd")
const Skills=preload("res://scripts/original_skill_rules.gd")
const FloatMath=preload("res://scripts/native_float.gd")
const TeamAI=preload("res://scripts/team_ai.gd")
const Characters=preload("res://scripts/character_rules.gd")
const BallFlight=preload("res://scripts/ball_flight.gd")
const Possession=preload("res://scripts/ball_possession.gd")
const Copies=preload("res://scripts/ball_copies.gd")
const StallRules=preload("res://scripts/stall_rules.gd")
const MatchRules=preload("res://scripts/match_rules.gd")
const KeeperRules=preload("res://scripts/keeper_rules.gd")
const SurfaceRules=preload("res://scripts/surface_rules.gd")
const ObjectMotion=preload("res://scripts/object_motion.gd")
const InjuryRules=preload("res://scripts/fake_injury_rules.gd")
const TackleVisuals=preload("res://scripts/tackle_visuals.gd")
const PracticeRules=preload("res://scripts/practice_rules.gd")
const DirectionalMotion=preload("res://scripts/directional_motion.gd")
const ShotOrder=preload("res://scripts/shot_order.gd")
var shout=preload("res://scripts/shout_rules.gd").new()
var benchmark_driver
const BALL_DT=0.03125
const MOVE_DT=0.03
var players=[]
var ball=Vector3.ZERO
var ball_present=true
var apocalypse
var field_started=0.0
var previous_ball=Vector3.ZERO
var velocity=Vector3.ZERO
var holder=-1
var held_ball_contacts={}
var held_contact_owner=-1
var last_owner=-1
var intercept=0
var score=[0,0]
var time=0.0
var notice="靠近足球接球；W 选择射门方向。"
var bot_enabled=false
var reset_delay=0.0
var goal_ball_live=false
var last_goal=0
var bot_clock=0.0
var grid=AStarGrid2D.new()
var search=Search.new()
var timeline=0.0
var next_move=MOVE_DT
var next_ball=BALL_DT
var next_rules=0.05
var next_referee=INF
var next_injury=INF
var injury_events=[]
var injury_sequence=0
var fake_injury_enabled=true
var event_time=-1.0
var stall_counter=0
var stall_warned=false
var referee={}
var arena=Arena.new()
var nav_cache={}
var nav_grid_key=""
var nav_dirty={}
var nav_bits=PackedByteArray()
var profile={}
var pending_commands=[]
var input_sequence=0
var movement_tick=0
var controlled=0
var networked=false
var remote_client=false
var human_slots=[]
var network_lineup=[]
var network_formation="tactical"
var command_sink: Callable
var pass_player=-1
var match_enabled=false
var team_size=3
var score_limit=10
var duration=0.0
var time_left=0.0
var mode="score"
var half=1
var halftime_left=0.0
var halftime_swapped=false
var extra_period=0
var elapsed=0.0
var stats=[]
var goal_history=[]
var assistants={}
var roster=[]
var match_state="practice"
var countdown=0.0
var overtime=false
var winner=-1
var pass_request=0.0
var selected_character="h005"
var selected_field=0
var mixed_roster=false
var skill_effects=[]
var native_visuals=[]
var next_visual=0
var powershot_active=false
var no_steal=0
var random=RandomNumberGenerator.new()
var fake_balls=[]
var next_fake_id=0
var curve={}
var projectiles=[]
var next_projectile_id=0
var rifts=[]
var ball_hook=0
var tackle_shadows=[]
var next_tackle_shadow=0
var next_tackle_order=0
var object_members=[]
var next_object_order=0
var audio_events=[]
var next_audio=0

func unit_present(index: int) -> bool:
	return index>=0 and index<players.size() and not players[index].get("removed",false)

func prepare_apocalypse():
	if apocalypse==null:
		apocalypse=load("res://scripts/apocalypse_sim.gd").new();apocalypse.setup(self)
		apocalypse_prepared.emit(apocalypse)
	return apocalypse

func apocalypse_due() -> float:
	return INF if apocalypse==null else apocalypse.next_time

func apocalypse_active() -> bool:
	return apocalypse!=null and apocalypse.active

func emit_audio(kind: String):
	next_audio+=1
	audio_events.append({"id":next_audio,"kind":kind})
	if audio_events.size()>32:audio_events.pop_front()

func emit_visual(model: String,pos: Vector3,size: float=1.0,facing: float=0.0):
	# Bounded presentation history, independent of gameplay RNG and collisions.
	next_visual+=1
	var event={"id":next_visual,"time":timeline,"model":model,"pos":pos,"scale":size,"facing":facing}
	native_visuals.append(event)
	if native_visuals.size()>128:native_visuals.pop_front()
	return event

func emit_text(index: int,message: String,lifetime: float=3.0):
	var event=emit_world_text(Characters.world_position(players[index]),message,lifetime)
	event.owner=index
	return event

func emit_world_text(pos: Vector3,message: String,lifetime: float=3.0):
	var event=emit_visual("",pos)
	event.time=clock_now();event.message=message;event.text_lifetime=lifetime
	return event

func submit_command(kind: String,index: int,target: Vector2=Vector2.ZERO):
	if remote_client:
		if index==controlled and command_sink.is_valid():command_sink.call(kind,target)
		return
	if not unit_present(index) or not target.is_finite():return
	if match_enabled and match_state!="playing":return
	input_sequence+=1
	pending_commands.append({"kind":kind,"player":index,"target":target,"sequence":input_sequence})

func consume_commands():
	for c in pending_commands:
		if not unit_present(c.player):continue
		match c.kind:
			"pass":request_pass(c.player)
			"move":command(c.player,c.target)
			"move_order":command(c.player,c.target,false)
			"move_direction":DirectionalMotion.order(self,c.player,c.target)
			"stop":stop(c.player)
			"move_release":
				# Lifting a stick stops locomotion, not a spell/charge already cast.
				DirectionalMotion.release(players[c.player])
			"hold":KeeperRules.hold(self,c.player)
			"kick":ShotOrder.request(self,c.player,c.target)
			"tackle":tackle(c.player,c.target)
			"ability":Characters.use(self,c.player,c.target)
			"ability_secondary":Characters.use(self,c.player,c.target,true)
			"sprint":toggle_sprint(c.player)
			"morph_reset":Characters.Morph.reset_kit(self,c.player,true)
			"practice_refresh":PracticeRules.refresh(self,c.player)
			"practice_ball":PracticeRules.recall_ball(self,c.player)
			"shout":shout.cast(self,c.player)
			"taunt","sadface":Emotes.cast(self,c.player,c.kind)
	pending_commands.clear()

func advance(delta: float):
	profile={"grid_ms":0.0,"search_ms":0.0,"smooth_ms":0.0,"route_calls":0}
	# Original one-shot presentation timers share the ordered simulation clock.
	timeline+=delta
	while minf(minf(minf(minf(next_move,next_ball),minf(next_rules,next_referee)),minf(next_injury,shout.next_time)),apocalypse_due())<=timeline+0.0000001:
		var next=minf(minf(minf(minf(next_move,next_ball),minf(next_rules,next_referee)),minf(next_injury,shout.next_time)),apocalypse_due())
		event_time=next
		if apocalypse_due()<=next:
			apocalypse.step(next)
		elif shout.next_time<=next:
			shout.step(self,next)
		elif next_injury<=next:
			InjuryRules.step(self,next)
		elif next_move<=next:
			step_movement()
			next_move+=MOVE_DT
		elif next_ball<=next:
			step_ball()
			next_ball+=BALL_DT
		elif next_rules<=next:
			StallRules.step(self)
			next_rules+=0.05
		else:StallRules.kick(self)
	event_time=-1.0
	if apocalypse!=null:apocalypse.rules.advance_to(timeline)

func clock_now() -> float:
	return event_time if event_time>=0 else timeline

func _init():
	random.seed=270127
	reset()

func make_player(p: Vector2, team: int) -> Dictionary:
	var result={"pos":p,"previous":p,"target":p,"destination":p,"path":[],"angle":0.0 if team==0 else PI,"body":0.0 if team==0 else PI,"previous_body":0.0 if team==0 else PI,"spin":0.0,"speed":300.0,"turn":0.6,"radius":30.0,"moving":false,"mana":100.0,"sprint":false,"tackle":0.0,"cast_pending":false,"cast_target":p,"cooldown":0.0,"knock":Vector2.ZERO,"slow":0.0,"team":team,"action":0.0,"want_move":false,"replan":0.0,"stuck":0.0,"route_status":"idle","planned_revision":-1,"blocker_stamp":[],"role":"field","number":1,"ai_action":0.0,"character":"h005","catch_height":140.0,"z":0.0,"previous_z":0.0,"vz":0.0,"ability_delay":0.0,"ability_kind":"","ability_order":{},"ability_target":p,"disabled":0.0,"pull_time":0.0,"pull_level":1,"shadow_return":0.0,"shadow_origin":p,"stun":0.0,"ogre_slow":0.0,"power_slow":0.0,"power_slow_cooldown":0.0,"sprint_cooldown":0.0,"flip_time":0.0,"flight_steps":0,"possess_time":0.0,"jump_due":false,"jump_target":p,"jump_cooldown":0.0,"eject_time":0.0,"stealth_time":0.0,"invisible":false,"hook":{},"hooked":0,"silence":0.0,"secondary_cooldown":0.0,"rift":{},"morph_roll":0.0,"morph_preview":"","morph_last":"","morph_kit":"","morph_casts":0,"morph_ghost":0.0,"keeper_cooldown":0.0,"keeper_pose":0.0,"keeper_origin":Vector3.ZERO,"slide_order":false,"slide_target":p}
	InjuryRules.configure(result)
	result.tackle_order=0
	result.pathing_enabled=true
	result.object_active=false
	result.object_order=0
	result.direct_axis=Vector2.ZERO
	result.shot_order={}
	result.possession_serial=0
	result.removed=false
	return result

func start_match(size: int=3,limit: int=10,seconds: float=0.0,tournament: bool=false):
	apocalypse=null;ball_present=true;field_started=clock_now()
	prepare_generated_ice()
	MatchRules.clear(self)
	if networked:roster=network_lineup.map(func(s):return s.hero)
	shout.clear()
	match_enabled=true
	team_size=clampi(size,1,6)
	mode="tournament" if tournament else ("timed" if seconds>0 else "score")
	score_limit=clampi(limit,1,200) if mode=="score" else 0
	duration=MatchRules.HALF_TIME if tournament else maxf(0,seconds)
	time_left=duration
	controlled=0
	for i in range(team_size*2):stats.append({"goals":0,"assists":0,"own_goals":0})
	score=[0,0]
	overtime=false
	winner=-1
	bot_enabled=true
	arena.set_field(selected_field)
	arena.set_course(0)
	nav_cache.clear();nav_dirty.clear();nav_grid_key=""
	reset()
	match_state="countdown"
	countdown=3.0
	notice="准备开球"

func start_practice():
	apocalypse=null;ball_present=true;field_started=clock_now()
	prepare_generated_ice()
	MatchRules.clear(self)
	shout.clear()
	arena.set_field(selected_field)
	nav_cache.clear();nav_dirty.clear();nav_grid_key=""
	match_enabled=false
	match_state="practice"
	controlled=0
	bot_enabled=false
	score=[0,0]
	reset()

func prepare_generated_ice():
	generated_ice=load("res://scripts/apocalypse_world.gd").generate_ice(random) if selected_field in [2,3] else []

func switch_player():
	if networked:return
	if not match_enabled:return
	var candidates=[]
	for i in range(players.size()):
		if unit_present(i) and players[i].team==0 and i!=controlled:candidates.append(i)
	if candidates.is_empty():return
	var point=Vector2(ball.x,ball.y)
	candidates.sort_custom(func(a,b):return players[a].pos.distance_squared_to(point)<players[b].pos.distance_squared_to(point))
	select_player(candidates[0])

func select_player(index: int) -> bool:
	if networked:return false
	if not match_enabled or not unit_present(index) or players[index].team!=0:return false
	if index==controlled:return true
	controlled=index
	stop(controlled,false)
	notice="已切换到%s %d 号"%[team_name(players[controlled].team),players[controlled].number]
	return true

func call_for_pass():
	if remote_client:submit_command("pass",controlled);return
	request_pass(controlled)

func request_pass(index: int):
	if not unit_present(index):return
	pass_player=index
	pass_request=3.0
	notice="已呼叫队友传球"
	var player=players[index]
	if timeline<float(player.get("pass_cue_until",-1.0)):return
	player.pass_cue_until=timeline+1.0
	var event=emit_visual("fx_pass_me",Characters.world_position(player))
	event.owner=index;event.attachment="overhead";event.message="传给我！"

func has_ball(index: int) -> bool:
	return unit_present(index) and ((ball_present and holder==index) or not Copies.held(self,index).is_empty())

func choose_halftime_character(id: String) -> bool:
	if networked:return false
	if match_state!="halftime" or controlled<0 or not Characters.DATA.has(id):return false
	roster[controlled]=id
	Characters.configure(players[controlled],id)
	shout.bind_players(self)
	if controlled==0:selected_character=id
	return true

func reset():
	StallRules.reset(self)
	InjuryRules.reset(self)
	players=[make_player(Vector2(-500,0),0),make_player(Vector2(650,260),1)]
	if match_enabled:
		players=[]
		var formation=[Vector2(-540,0),Vector2(-1100,500),Vector2(-1100,-500),Vector2(-1450,750),Vector2(-1450,-750)]
		for team in [0,1]:
			for slot in range(team_size):
				var keeper=slot==team_size-1 and team_size>=3
				var position=Vector2(-arena.half_size.x-74,0) if keeper else formation[slot]*Vector2(arena.half_size.x/2016.0,arena.half_size.y/1312.0)
				position.x*=arena.attack_direction(team)
				if networked and network_formation=="row":
					var side=1 if arena.attack_direction(team)>0 else 2
					var rect=arena.rect(arena.data.regions["Start_"+str(side)])
					position=Vector2(rect.get_center().x,rect.end.y-(slot+1)*rect.size.y/(team_size+1))
				var p=make_player(position,team)
				p.angle=0.0 if arena.attack_direction(team)>0 else PI;p.body=p.angle;p.previous_body=p.angle
				p.number=slot+1
				p.role="keeper" if keeper else "field"
				var index=players.size()
				if networked and index<network_lineup.size():
					p.nickname=network_lineup[index].nickname;p.hat=network_lineup[index].hat
				if index<roster.size():Characters.configure(p,roster[index])
				else:
					if mixed_roster:Characters.configure(p,Characters.IDS[(slot+team*team_size+Characters.IDS.find(selected_character))%Characters.IDS.size()])
					if index==0:Characters.configure(p,selected_character)
					roster.append(p.character)
				players.append(p)
	elif arena.course==4:
		players=[make_player(Vector2(-600,0),0),make_player(Vector2(1400,700),1)]
	elif arena.course!=0:
		players=[make_player(Vector2(-900,-650),0),make_player(Vector2(1150,550),1)]
	if not match_enabled:Characters.configure(players[0],selected_character)
	shout.bind_players(self)
	skill_effects.clear()
	native_visuals.clear()
	arena.clear_pillars()
	powershot_active=false
	no_steal=0
	fake_balls.clear();projectiles.clear();curve.clear();rifts.clear();ball_hook=0
	tackle_shadows.clear()
	next_tackle_order=0
	object_members.clear();next_object_order=0
	ball=Vector3.ZERO
	if arena.course==4:
		ball=Vector3(0,600,0)
	elif arena.course!=0:
		ball=Vector3(-700,-650,0)
	previous_ball=ball
	velocity=Vector3.ZERO
	holder=-1
	last_owner=-1
	assistants.clear()
	intercept=0
	reset_delay=0.0
	goal_ball_live=false
	held_ball_contacts.clear();held_contact_owner=-1
	pending_commands.clear()
	bot_clock=0.0
	pass_request=0.0
	pass_player=-1
	notice="靠近足球接球；W 选择射门方向。"
	ball_present=true
	if apocalypse!=null:apocalypse.restore_removed_flags()

func set_course(index: int):
	arena.set_course(index)
	nav_cache.clear()
	reset()
	notice=arena.COURSE_NAMES[arena.course]+"：右键绕行；W 射门试反弹。"

static func signed_turn_to(target: float, current: float) -> float:
	var d=wrapf(target-current,-PI,PI)
	return PI if absf(d+PI)<0.000001 else d

func legal(p: Vector2) -> bool:
	return arena.point_free(p,30)

func goal_blocked(owner: int,team: int) -> bool:
	if players[owner].team!=team:return true
	for j in range(players.size()):
		if j!=owner and not Characters.absent(players[j]) and players[j].team==team and arena.in_guard(players[j].pos,team):return true
	return false

func goal_restrictions(owner: int) -> Array:
	# GoalBlock__enter: opponents cannot enter; at most one defender per area.
	var extra=[]
	for team in [0,1]:
		if goal_blocked(owner,team):extra.append_array(arena.guards[team])
	return extra

func repair_goal_entry(index: int,previous: Vector2) -> bool:
	var p=players[index]
	for team in range(2):
		if arena.in_guard(previous,team) or not arena.in_guard(p.pos,team) or not goal_blocked(index,team):continue
		var response=ObjectMotion.goal_response(arena,Characters.world_position(p),Vector3(p.knock.x,p.knock.y,p.vz),team,emit_boundary_flash)
		p.pos=Vector2(response.position.x,response.position.y)
		p.knock=Vector2(response.velocity.x,response.velocity.y);p.vz=response.velocity.z
		skill_effects.append({"kind":"body_bump","model":"fx_goal_block","scale":0.9,"facing":response.facing,"pos":response.effect,"life":0.35,"age":0.0,"owner":index})
		if index==controlled:notice="对方门前保护区，不能进入。" if p.team!=team else "本方门区已有队友，暂时不能进入。"
		return true
	return false

func free_point(p: Vector2, owner: int) -> bool:
	if not arena.point_free(p,players[owner].radius,goal_restrictions(owner)): return false
	for i in range(players.size()):
		if unit_blocks_navigation(owner,i) and p.distance_to(players[i].pos)<players[owner].radius+players[i].radius-0.001:return false
	return true

static func navigation_solid(p: Dictionary) -> bool:
	return not Characters.phased(p)

func set_unit_pathing(index: int,enabled: bool):
	# Map wrappers call SetUnitPathing directly, without a reference counter.
	# The latest callback wins even if another skill remains active. Route
	# stamps observe this effective flag on the next movement update.
	players[index].pathing_enabled=enabled

func unit_blocks_navigation(owner: int,other: int) -> bool:
	return owner!=other and navigation_solid(players[owner]) and navigation_solid(players[other])

func nearby_free(point: Vector2,owner: int) -> Vector2:
	if free_point(point,owner):return point
	for radius in [32,64,96,128]:
		for direction in range(16):
			var candidate=point+Vector2.from_angle(direction*TAU/16.0)*radius
			if free_point(candidate,owner):return candidate
	return Vector2(INF,INF)

func unit_sweep(a: Vector2,d: Vector2,owner: int,units: bool=true,padding: float=0,include_guards: bool=true) -> Dictionary:
	var radius: float=players[owner].radius+padding
	var best=arena.sweep_unit(a,d,radius,goal_restrictions(owner) if include_guards else [],players[owner].z,owner)
	if units:
		for i in range(players.size()):
			if not unit_blocks_navigation(owner,i):continue
			# Restoring pathing may leave two centers identical. Any nonzero
			# direction increases their separation; the general circle query is
			# also used for hits, so keep this movement-only escape here.
			if a.distance_squared_to(players[i].pos)<0.000001 and d.length_squared()>0:continue
			var h=Arena.circle_hit(a,d,players[i].pos,radius+players[i].radius)
			if not h.is_empty() and (best.is_empty() or h.t<best.t):best=h
	return best

func segment(a: Vector2,b: Vector2,owner: int,padding: float=0) -> bool:
	return unit_sweep(a,b-a,owner,true,padding).is_empty() and free_point(b,owner)

func command(index: int, target: Vector2,smart_order: bool=true):
	if not unit_present(index):return
	if not target.is_finite():return
	var p=players[index]
	p.direct_axis=Vector2.ZERO
	InjuryRules.cancel_pose(p)
	p.keeper_pose=0.0
	# Native move (M) and smart (right click) share locomotion, but only smart
	# starts Object_isMoving / the ice push. Possess explicitly accepts both.
	if smart_order:
		SurfaceRules.smart_order(p,target)
		start_object(index)
	else:p.slide_order=false
	if p.possess_time>0:
		Characters.possess_order(self,index,target)
		return
	if p.flight_steps>0:return
	if smart_order and p.ability_kind=="powershot" and p.ability_delay>0:
		# Powershot___stopCommandPowershot issues a nested stop and marks it
		# exempt from charge cancellation. Object_isMoving still sees that stop,
		# clearing its smart latch; an already running impulse keeps decaying.
		p.slide_order=false;p.path=[];p.want_move=false;p.route_status="idle"
		p.ability_order.clear();InjuryRules.stop_order(self,index)
		return
	walk_to(index,target)

func approach_cast(index: int,target: Vector2,cast_range: float):
	if not unit_present(index):return
	# Internal movement belonging to a spell order is not another issued smart
	# order. In particular, do not wake a sleeping Object callback or restore
	# collision from its next zero-speed update while another skill has phased it.
	walk_to(index,target)
	players[index].ability_order={"target":target,"range":cast_range}

func walk_to(index: int,target: Vector2):
	if not unit_present(index):return
	var p=players[index]
	ShotOrder.cancel(p)
	p.direct_axis=Vector2.ZERO
	p.cast_pending=false
	p.ability_order.clear()
	if p.ability_kind in ["black_hole","swap","hook","rift"]:p.disabled=0
	var bounded=target.clamp(arena.bounds.position,arena.bounds.end)
	if p.want_move and p.target.distance_to(bounded)<1 and p.planned_revision==arena.revision and p.blocker_stamp==blocker_stamp(index):return
	p.target=bounded
	p.want_move=true
	p.stuck=0.0
	if p.tackle>0:
		# Tackle keeps the native prop window at zero. This direct steering is
		# still an approximation when another callback has re-enabled pathing;
		# native detour selection during that overlap remains to be reconstructed.
		p.path=[p.target]
		p.destination=p.target
		return
	plan_route(index)

func blocker_stamp(index: int) -> Array:
	# Collision toggles can open a route without changing any XY coordinates.
	# Store the effective occupancy, not countdown values or irrelevant airborne
	# motion. Goal qualification is independent of ordinary unit collision.
	var positions=[players[index].radius,navigation_solid(players[index]),goal_blocked(index,0),goal_blocked(index,1)]
	for j in range(players.size()):
		if unit_blocks_navigation(index,j):positions.append([j,players[j].pos,players[j].radius])
	return positions

func paint_navigation(r: Rect2,radius: float,circle: Vector2=Vector2(INF,INF)):
	var lo=Vector2i(((r.position-Vector2.ONE*radius-grid.offset)/32).floor()).clamp(Vector2i.ZERO,grid.region.size-Vector2i.ONE)
	var hi=Vector2i(((r.end+Vector2.ONE*radius-grid.offset)/32).ceil()).clamp(Vector2i.ZERO,grid.region.size-Vector2i.ONE)
	for y in range(lo.y,hi.y+1):
		for x in range(lo.x,hi.x+1):
			var cell=Vector2i(x,y)
			var position=grid.get_point_position(cell)
			var blocked=position.distance_squared_to(circle)<radius*radius if circle.is_finite() else Arena.circle_overlaps_rect(position,radius,r)
			if blocked:
				grid.set_point_solid(cell,true);nav_dirty[cell]=true
				nav_bits[cell.y*grid.region.size.x+cell.x]=1

func make_navigation_base(dimensions: Vector2i,radius: float) -> PackedByteArray:
	# Rasterize only obstacle bounding cells. Exact disk/rectangle predicates
	# match point_free(), without scanning every wall for every empty cell.
	var base=PackedByteArray();base.resize(dimensions.x*dimensions.y)
	var rectangles=arena.walls.duplicate()
	for obstacle in arena.obstacles:rectangles.append(obstacle.rect)
	for r in rectangles:
		var lo=Vector2i(((r.position-Vector2.ONE*radius-grid.offset)/32).floor()).clamp(Vector2i.ZERO,dimensions-Vector2i.ONE)
		var hi=Vector2i(((r.end+Vector2.ONE*radius-grid.offset)/32).ceil()).clamp(Vector2i.ZERO,dimensions-Vector2i.ONE)
		for y in range(lo.y,hi.y+1):
			for x in range(lo.x,hi.x+1):
				if Arena.circle_overlaps_rect(grid.get_point_position(Vector2i(x,y)),radius,r):base[y*dimensions.x+x]=1
	for pillar in arena.pillars:
		var reach: float=radius+pillar.radius
		var lo=Vector2i(((pillar.center-Vector2.ONE*reach-grid.offset)/32).floor()).clamp(Vector2i.ZERO,dimensions-Vector2i.ONE)
		var hi=Vector2i(((pillar.center+Vector2.ONE*reach-grid.offset)/32).ceil()).clamp(Vector2i.ZERO,dimensions-Vector2i.ONE)
		for y in range(lo.y,hi.y+1):
			for x in range(lo.x,hi.x+1):
				if grid.get_point_position(Vector2i(x,y)).distance_to(pillar.center)<reach:base[y*dimensions.x+x]=1
	return base

func overlap_exit(index: int) -> Vector2:
	# Local recovery for restored overlapping footprints, not a claimed native
	# depenetration algorithm. Move normally, never teleport or ignore walls.
	var p=players[index]
	var overlapping=false
	for j in range(players.size()):
		if unit_blocks_navigation(index,j) and p.pos.distance_to(players[j].pos)<p.radius+players[j].radius-0.001:
			overlapping=true;break
	if not overlapping:return Vector2(INF,INF)
	var heading=(p.target-p.pos).angle()
	for radius in [32,48,64,80,96,128,160,192]:
		var best=Vector2(INF,INF);var cost=INF
		for turn in range(16):
			var point=p.pos+Vector2.from_angle(heading+turn*TAU/16.0)*radius
			# Leave enough room for the ordinary terminal stopping distance.
			var clear=true
			for j in range(players.size()):
				if unit_blocks_navigation(index,j) and point.distance_to(players[j].pos)<p.radius+players[j].radius+Native.MIN_POINT_STOP+2:
					clear=false;break
			if not clear or not segment(p.pos,point,index):continue
			var distance=point.distance_squared_to(p.target)
			if distance<cost:best=point;cost=distance
		if best.is_finite():return best
	return Vector2(INF,INF)

func plan_route(index: int):
	if not unit_present(index):return
	profile.route_calls=int(profile.get("route_calls",0))+1
	var p=players[index]
	p.path=[]
	p.replan=0.24
	p.planned_revision=arena.revision
	p.blocker_stamp=blocker_stamp(index)
	p.route_status="moving"
	if segment(p.pos,p.target,index):
		p.path=[p.target]
	else:
		var escape=overlap_exit(index)
		if escape.is_finite():
			p.path=[escape];p.destination=escape;p.route_status="escaping";p.moving=true
			return
		# Radius-aware occupancy. Native flat-search ordering is retained;
		# route repairs and continuous sweeps are this recreation's implementation.
		var grid_started=Time.get_ticks_usec()
		var dimensions=Vector2i(arena.bounds.size/32)+Vector2i(2,2)
		var grid_origin=arena.bounds.position-Vector2(32,32)
		grid.region=Rect2i(Vector2i.ZERO,dimensions)
		grid.cell_size=Vector2(32,32)
		grid.offset=Native.fine_grid_point(Vector2i.ZERO,grid_origin)
		grid.update()
		var key=str(arena.revision)+":"+str(p.radius)
		if not nav_cache.has(key):
			# Expired pillar revisions need no retained occupancy snapshots.
			for old in nav_cache.keys():
				if not str(old).begins_with(str(arena.revision)+":"):nav_cache.erase(old)
			nav_cache[key]=make_navigation_base(dimensions,p.radius+4)
		if nav_grid_key!=key:
			nav_bits=nav_cache[key].duplicate()
			for y in range(dimensions.y):
				for x in range(dimensions.x):grid.set_point_solid(Vector2i(x,y),nav_cache[key][y*dimensions.x+x]!=0)
			nav_grid_key=key
		else:
			for cell in nav_dirty:
				var value=nav_cache[key][cell.y*dimensions.x+cell.x]
				grid.set_point_solid(cell,value!=0);nav_bits[cell.y*dimensions.x+cell.x]=value
		nav_dirty.clear()
		for r in goal_restrictions(index):paint_navigation(r,p.radius+4)
		for j in range(players.size()):
			if unit_blocks_navigation(index,j):paint_navigation(Rect2(players[j].pos,Vector2.ZERO),p.radius+players[j].radius+4,players[j].pos)
		var from=Native.path_cell(p.pos,grid_origin).clamp(Vector2i.ZERO,grid.region.size-Vector2i.ONE)
		var to=Native.path_cell(p.target,grid_origin).clamp(Vector2i.ZERO,grid.region.size-Vector2i.ONE)
		grid.set_point_solid(from,false)
		nav_bits[from.y*dimensions.x+from.x]=0
		nav_dirty[from]=true
		var search_started=Time.get_ticks_usec()
		profile.grid_ms=float(profile.get("grid_ms",0))+(search_started-grid_started)/1000.0
		var raw=search.find_path(grid,from,to,Vector2.ONE*(Native.PARTIAL_POINT_OFFSET-Native.FINE_POINT_OFFSET),nav_bits)
		var smooth_started=Time.get_ticks_usec()
		profile.search_ms=float(profile.get("search_ms",0))+(smooth_started-search_started)/1000.0
		var anchor: Vector2=p.pos
		var k=1
		while k<raw.size():
			var far=-1
			for j in range(k,raw.size()):
				# The original partial endpoint is centered differently from fine
				# corners. Like an exact requested endpoint, validate its real
				# footprint rather than rejecting it on extra smoothing clearance.
				if segment(anchor,raw[j],index,0 if j==raw.size()-1 else 2):far=j
				else: break
			if far<0:break
			p.path.append(raw[far])
			anchor=raw[far]
			k=far+1
		if segment(anchor,p.target,index):p.path.append(p.target)
		else:p.route_status="partial"
		profile.smooth_ms=float(profile.get("smooth_ms",0))+(Time.get_ticks_usec()-smooth_started)/1000.0
	p.destination=p.path[-1] if not p.path.is_empty() else p.pos
	if p.path.is_empty():p.route_status="blocked";p.replan=0.9
	p.moving=not p.path.is_empty()

func stop(index: int,issued_order: bool=true):
	ShotOrder.cancel(players[index])
	players[index].direct_axis=Vector2.ZERO
	InjuryRules.cancel_pose(players[index])
	players[index].keeper_pose=0.0
	players[index].slide_order=false
	Characters.cancel_charge(players[index])
	players[index].cast_pending=false
	players[index].ability_order.clear()
	if players[index].ability_kind in ["black_hole","swap","hook","rift"]:players[index].disabled=0
	players[index].path=[]
	players[index].moving=false
	players[index].want_move=false
	players[index].route_status="idle"
	if issued_order:InjuryRules.stop_order(self,index)

func advance_fine_route(index: int):
	var p=players[index]
	while p.path.size()>1 and FloatMath.waypoint_reached(p.pos,p.path[0]):
		var selected=Native.visible_waypoint_index(p.path.size(),func(candidate):return segment(p.pos,p.path[candidate],index))
		p.path=p.path.slice(selected)

func step_movement():
	if benchmark_driver!=null:benchmark_driver.feed(self)
	if match_enabled and match_state!="playing":return
	movement_tick+=1
	consume_commands()
	for i in range(players.size()):
		var p=players[i]
		p.previous=p.pos
		p.previous_body=p.body
		if not unit_present(i):continue
		p.replan=maxf(0,p.replan-MOVE_DT)
		if ShotOrder.step(self,i):
			p.moving=false
			continue
		if not p.ability_order.is_empty() and p.pos.distance_to(p.ability_order.target)<=p.ability_order.range:
			var destination: Vector2=p.ability_order.target
			Characters.use(self,i,destination)
		if p.disabled>0 or p.stun>0 or p.hooked!=0 or Characters.absent(p):p.moving=false;continue
		if p.cast_pending:
			var cast_error=FloatMath.movement_geometry(p.cast_target-p.pos,p.angle).y
			# Original v4 traces: reverse cast activates after five 0.6 turns,
			# leaving locomotion heading at 3.0 rad (not PI); visible body keeps
			# turning. Check readiness BEFORE another heading increment.
			if absf(cast_error)<=Native.ARRIVAL_ANGLE:
				begin_tackle(i)
			else:
				p.angle=wrapf(Native.turn_step(cast_error,p.angle,p.turn,0,0,0,true).y,-PI,PI)
		if p.direct_axis!=Vector2.ZERO:
			DirectionalMotion.step(self,i);advance_body(p)
			p.moving=p.previous.distance_to(p.pos)>0.01
			continue
		if p.want_move and p.replan<=0 and p.tackle<=0:
			var changed=p.planned_revision!=arena.revision or (p.path.is_empty() and p.blocker_stamp!=blocker_stamp(i))
			if changed or p.stuck>0.12 or (not p.path.is_empty() and not segment(p.pos,p.path[0],i)):
				plan_route(i)
				p.stuck=0.0
		# Native fine-route advancement (0x1137c0 / 0x1125b0) uses squared
		# distance <=0.49^2 internally, without waiting for the old heading.
		# It supplies the next point to this same movement update. Coarse-block
		# transitions and their waiting state remain part of the unported planner.
		# Native visibility scan can discard several now-unnecessary fine points
		# at this transition; it stops at the first obstructed candidate.
		advance_fine_route(i)
		if not p.path.is_empty():
			var delta: Vector2=p.path[0]-p.pos
			var native_geometry=FloatMath.movement_geometry(delta,p.angle)
			var error=native_geometry.y
			var terminal=p.path.size()==1
			var arrival=Native.arrival_state(native_geometry.x,error)
			if terminal and arrival.y!=0:
				p.path.pop_front()
				if p.path.is_empty():
					if p.route_status=="moving":p.want_move=false;p.route_status="arrived"
					elif p.route_status=="escaping":plan_route(i)
					else:p.replan=0.9
			else:
				var speed=walking_speed(i)
				var next=Native.turn_step(error,p.angle,p.turn,deg_to_rad(60),0,speed,terminal and arrival.x!=0)
				p.angle=wrapf(next.y,-PI,PI)
				if next.x>0 and p.tackle<=0 and p.z<1:
					var candidate: Vector2=p.pos+Vector2.from_angle(p.angle)*minf(speed*MOVE_DT,delta.length())
					var h=unit_sweep(p.pos,candidate-p.pos,i)
					if h.is_empty():p.pos=candidate;p.stuck=0.0
					else:
						p.pos=p.pos.lerp(candidate,maxf(0,h.t-0.002))
						p.stuck+=MOVE_DT
		advance_body(p)
		p.moving=p.previous.distance_to(p.pos)>0.01

func walking_speed(index: int) -> float:
	var p=players[index]
	var speed=p.speed if p.character=="h028" else (400.0 if p.sprint else p.speed)
	if p.character=="h026":speed=p.speed*(1.66 if p.sprint else 1.0)
	if p.character=="h004" and p.sprint:speed=20.0
	if has_ball(index) and not (p.character=="h028" and p.sprint):speed*=0.85
	if p.slow>0 or p.ogre_slow>0 or p.power_slow>0:speed*=0.2
	if p.get("shout_state",{}).get("adrenaline_until",0.0)>clock_now():speed*=1.05
	return speed

func advance_body(p: Dictionary):
	var body_error=signed_turn_to(p.angle,p.body)
	p.spin=move_toward(p.spin,clampf(body_error*0.7,-0.2,0.2),0.07)
	var change: float=p.spin
	if absf(change)>absf(body_error) and signf(change)==signf(body_error):change=body_error
	p.body=wrapf(p.body+change,-PI,PI)

func toggle_sprint(index: int):
	set_sprint(index,not players[index].sprint)

func set_sprint(index: int,enabled: bool):
	var p=players[index]
	if enabled and (p.mana<=1 or p.disabled>0 or p.stun>0 or p.silence>0 or Characters.absent(p)):return
	if enabled and not p.sprint and p.character in ["h026","h004"]:
		if p.sprint_cooldown>0:return
		p.sprint_cooldown=8.0 if p.character=="h026" else 6.0
		if p.character=="h004":apply_impulse(index,Vector3(cos(p.body)*20.2,sin(p.body)*20.2,0))
	if p.sprint!=enabled:
		p.slide_order=false;InjuryRules.cancel_pose(p)
		if p.character=="h004":set_unit_pathing(index,not enabled)
	p.sprint=enabled
	if not enabled:p.stealth_time=0;p.invisible=false

func tackle(index: int, target: Vector2):
	if not unit_present(index):return
	var p=players[index]
	if p.cooldown>0 or p.stun>0 or p.silence>0 or p.disabled>0 or not target.is_finite():return
	stop(index,false)
	p.cast_target=target
	p.cast_pending=true
	if absf(FloatMath.movement_geometry(target-p.pos,p.angle).y)<=Native.ARRIVAL_ANGLE:
		begin_tackle(index)

func begin_tackle(index: int):
	if not unit_present(index):return
	var p=players[index]
	p.cast_pending=false
	p.cooldown=32.0
	p.tackle=640.0
	next_tackle_order+=1
	p.tackle_order=next_tackle_order
	set_unit_pathing(index,false)
	Characters.Morph.record(self,index,"tackle")
	# A spell target is not a move order. Only a later explicit move command
	# steers the active tackle and resumes walking after it (native v4 trials).
	notice="铁壁滑铲：可以继续右键调整方向。"

func kick(index: int, target: Vector2,power: float=30.0,lift: float=7.0) -> bool:
	if not unit_present(index):return false
	if holder!=index:
		var copy=Copies.held(self,index)
		return Copies.kick(self,copy,target,power,lift) if not copy.is_empty() else false
	if not ball_present or holder!=index or players[index].tackle>0 or players[index].disabled>0 or players[index].stun>0 or players[index].silence>0:return false
	var direction=(target-Vector2(ball.x,ball.y)).normalized()
	if direction.length_squared()<0.01:return false
	InjuryRules.cancel_pose(players[index])
	ShotOrder.cancel(players[index])
	players[index].cast_pending=false
	players[index].slide_order=false
	# war3map.j s__Ball_kick: add vector (30 horizontal,7 up),5 ticks intercept.
	players[index].keeper_pose=0.0
	velocity+=Vector3(direction.x*power,direction.y*power,lift)
	last_owner=index
	MatchRules.assist(self,index)
	holder=-1
	no_steal=0
	intercept=5
	players[index].action=0.7
	players[index].action_clip="Spell"
	players[index].ability_order.clear()
	notice="射门！"
	emit_audio("kick")
	return true

func take(index: int):
	if not ball_present or not unit_present(index):return
	players[index].possession_serial+=1
	if holder!=index:emit_audio("catch")
	Copies.release_held(self,index)
	holder=index
	no_steal=0
	MatchRules.ownership(self,index)
	on_ball_taken()
	velocity=Vector3.ZERO
	intercept=0
	# s__Ball_takeOwnership immediately puts the ball in the new owner's hand.
	ball=Possession.held_position(self,index)
	held_ball_contacts=Possession.snapshot(self);held_contact_owner=index

func on_ball_taken():
	# EVENT_BALL_TAKE is global, but these original callbacks inspect ball[0].
	# A fake catch resets Powershot without blasting the fake's receiver.
	if powershot_active:
		if holder>=0:
			apply_impulse(holder,velocity*0.85)
			emit_visual("fx_powershot_blast",Characters.world_position(players[holder]),0.7)
		powershot_active=false
	else:
		for i in range(players.size()):
			if i!=last_owner:Characters.cancel_charge(players[i])
	if not curve.is_empty():
		if holder>=0 and players[holder].team==players[curve.owner].team:players[holder].mana=100
		curve.clear()
	# Pull also refers to the main ball's last owner, even if it is free.
	if last_owner>=0 and players[last_owner].pull_time>0:Characters.finish_pull(players[last_owner])

func start_object(index: int):
	if not unit_present(index):return
	var p=players[index]
	if p.object_active and p.object_order>0:return
	next_object_order+=1
	p.object_active=true;p.object_order=next_object_order
	object_members.append({"player":index,"order":p.object_order})

func stop_object(index: int):
	# Keep the visited node as a tombstone until this pass finishes. A later
	# collision can wake the same player at the tail without skipping a sibling.
	players[index].object_active=false;players[index].object_order=0

func emit_boundary_flash(position: Vector3,reverse: Vector3):
	# BoundaryCheck snapshots the position before modifying the force. This is
	# separate from a later region-entry event; inward force must exceed 30.
	var event=emit_visual("fx_player_bump",position,.7,atan2(reverse.y,reverse.x))
	event.pitch=0

func checked_player_velocity(position: Vector3,velocity: Vector3) -> Vector3:
	return ObjectMotion.check_force(arena,position,velocity,ObjectMotion.PLAYER_LOSS,emit_boundary_flash)

func apply_impulse(index: int,force: Vector3):
	if not unit_present(index):return
	var p=players[index]
	var result=checked_player_velocity(Characters.world_position(p),Vector3(p.knock.x,p.knock.y,p.vz)+force)
	p.knock=Vector2(result.x,result.y);p.vz=result.z
	start_object(index) # Even a zero vector starts the original Object loop.

func finish_tackle(index: int):
	var p=players[index]
	p.tackle=0.0
	p.tackle_order=0
	set_unit_pathing(index,true)
	if p.character=="h029" and p.morph_ghost>2:p.morph_ghost=2.0
	# Restore ordinary pathing; no speculative position teleport on restoration.
	if p.want_move and p.direct_axis==Vector2.ZERO:plan_route(index)

func step_object_impulses():
	# JASS Object_II32 walks a live tail-appended list, not player-number order.
	# Accepted contact calls applyVector on BOTH objects. A previously sleeping
	# victim joins this same pass; an already active victim is not re-enqueued.
	for i in range(players.size()):
		var p=players[i]
		p.previous_z=p.z
		if not unit_present(i) or (Characters.absent(p) and not apocalypse_active()):continue
		# Existing direct motion inputs (e.g. swap/fixtures) also need a first
		# callback. All authored applyVector/smart activations already have order.
		if p.object_active or p.knock.length_squared()!=0 or p.vz!=0 or p.z>=1:start_object(i)
	var cursor=0
	while cursor<object_members.size():
		var entry=object_members[cursor];cursor+=1
		var p=players[entry.player]
		if p.object_active and p.object_order==entry.order and unit_present(entry.player) and (not Characters.absent(p) or apocalypse_active()):step_object(entry.player)
	object_members=object_members.filter(func(entry):return players[entry.player].object_active and players[entry.player].object_order==entry.order)

func step_object(i: int):
	var p=players[i]
	# Hook changes XY without stopping Object: friction, gravity and contact
	# continue independently. Retain the final zero-speed landing callback.
	SurfaceRules.accelerate(self,i)
	if p.z<1:
		set_unit_pathing(i,true)
		if Vector3(p.knock.x,p.knock.y,p.vz).length()<=SurfaceRules.player_friction(self):
			p.z=0;p.knock=Vector2.ZERO;p.vz=0;stop_object(i)
			return
	var motion=Skills.object_velocity(p.z,Vector3(p.knock.x,p.knock.y,p.vz),SurfaceRules.player_friction(self))
	var flight=ObjectMotion.travel(arena,Characters.world_position(p),motion,p.radius,goal_restrictions(i),i,p.ogre_slow>0,p.team,emit_boundary_flash)
	p.pos=Vector2(flight.position.x,flight.position.y)
	p.knock=Vector2(flight.velocity.x,flight.velocity.y);p.vz=flight.velocity.z
	if flight.smash_stopped:p.ogre_slow=0
	if flight.smash_stun:p.stun=1.5
	for hit in flight.effects:
		var effect={"kind":"body_bump","pos":hit.pos,"facing":hit.get("facing",0.0),"life":0.35,"age":0.0,"owner":i}
		if hit.kind=="goal":effect.merge({"model":"fx_goal_block","scale":0.9,"facing":hit.get("facing",0.0)})
		skill_effects.append(effect)
	if p.z+p.vz<0 and p.vz<0:
		p.z=0
		var flash=ObjectMotion.landing_flash(p.pos,p.vz,arena.world_height_offset)
		if not flash.is_empty():
			var event=emit_visual("fx_player_bump",flash.pos,flash.scale,flash.facing)
			event.pitch=flash.pitch;event.sfx_clamp_to_terrain=true
		p.vz=maxf(0,-p.vz-15.0)
	else:
		p.z+=p.vz
		# Source checks z = GetUnitZ + velocity.z, not relative fly height.
		# All four original pitches have a +1024 center offset and every
		# playable terrain corner is >1. Thus a moving ground Object also
		# disables pathing here; its final zero-speed callback enables it.
		if arena.world_height_offset+p.z>=1:set_unit_pathing(i,false)
	if p.knock==Vector2.ZERO and p.vz==0:return
	for j in range(players.size()):
		if i==j or Characters.absent(players[j]) or absf(players[j].z-p.z)>100 or players[j].pos.distance_to(p.pos)>80:continue
		var offset=Characters.world_position(players[j])-Characters.world_position(p)
		var source=Vector3(p.knock.x,p.knock.y,p.vz);var other=Vector3(players[j].knock.x,players[j].knock.y,players[j].vz)
		if not Skills.contact_allowed_3d(source,other,offset):continue
		var flash=ObjectMotion.contact_flash(source,other,Characters.world_position(p),offset)
		if not flash.is_empty():
			var event=emit_visual("fx_player_bump",flash.pos,flash.scale,flash.facing)
			event.pitch=flash.pitch
		var exchanged=Skills.contact_exchange_3d(source,other,offset)
		exchanged[0]=checked_player_velocity(Characters.world_position(p),exchanged[0])
		exchanged[1]=checked_player_velocity(Characters.world_position(players[j]),exchanged[1])
		p.knock=Vector2(exchanged[0].x,exchanged[0].y);p.vz=exchanged[0].z;start_object(i)
		players[j].knock=Vector2(exchanged[1].x,exchanged[1].y);players[j].vz=exchanged[1].z;start_object(j)
	if apocalypse_active():apocalypse.collide_external_from_player(i)

func step_tackles():
	# List_addElement appends to the tail; Tackle_II32 walks head.next onward.
	# Actual spell activation, after any facing preparation, determines order.
	# Unstamped debug fixtures use player index only to break equal zero stamps.
	var active=[]
	for i in range(players.size()):
		if players[i].tackle>0:active.append(i)
	active.sort_custom(func(a,b):return players[a].tackle_order<players[b].tackle_order if players[a].tackle_order!=players[b].tackle_order else a<b)
	for i in active:
		if players[i].tackle>0:step_tackle(i)

func step_tackle(index: int):
	var p=players[index]
	# Source creates this at the old position on every step, even rejected steps.
	TackleVisuals.create(self,index)
	var delta=Vector2.from_angle(p.body)*Skills.TACKLE_SPEED
	var target: Vector2=p.pos+delta
	# Original checks the target terrain point, not unit-circle overlap. Keep
	# full 44.6 steps (15 steps = 669), including a rejected step at a wall.
	if arena.in_playable_region(target) and arena.point_free(target,0.01) and arena.sweep_unit(p.pos,delta,0.01).is_empty():
		var previous: Vector2=p.pos
		p.pos=target
		# Pathing is disabled during tackle. GoalBlock is an entry response, not
		# a footprint wall that rejects this step. Native per-axis region event
		# scheduling is still approximated here by checking the completed step.
		repair_goal_entry(index,previous)
	var contacted=false
	for j in range(players.size()):
		if index==j or Characters.absent(players[j]):continue
		var offset: Vector3=Characters.world_position(players[j])-Characters.world_position(p)
		var contact=Skills.tackle_contact_3d(offset,p.body,players[j].team!=p.team,players[j].slow>0)
		# The original AoE has no line-of-sight filter, including behind terrain.
		if contact.slow:players[j].slow=1.5
		if contact.hit:
			var push=offset.normalized()*Skills.TACKLE_PUSH
			apply_impulse(j,push)
			apply_impulse(index,Vector3(cos(p.body),sin(p.body),0)*(Skills.TACKLE_PUSH/2))
			contacted=true
	p.tackle-=Skills.TACKLE_SPEED
	if p.tackle<=0 or contacted:finish_tackle(index)

func catch_hit(a: Vector3,d: Vector3,excluded: int=-2,cooldown_ticks: int=-1,copy_id: int=0) -> Dictionary:
	if copy_id==0 and not ball_present:return {}
	var best={}
	if excluded==-2:excluded=last_owner
	if cooldown_ticks<0:cooldown_ticks=intercept
	for i in range(players.size()):
		if not Characters.catchable(players[i]):continue
		if copy_id>0 and has_ball(i):continue
		if cooldown_ticks>0 and i==excluded:continue
		var xy=Vector2(a.x,a.y)
		var delta=Vector2(d.x,d.y)
		var enter=0.0
		if xy.distance_to(players[i].pos)>90:
			var h=Arena.circle_hit(xy,delta,players[i].pos,90)
			if h.is_empty():continue
			enter=h.t
		var upper=players[i].z+players[i].catch_height
		var lower=players[i].z-90.0
		if a.z+d.z*enter>upper:
			if d.z>=0:continue
			enter=(upper-a.z)/d.z
		elif a.z+d.z*enter<lower:
			if d.z<=0:continue
			enter=(lower-a.z)/d.z
		if enter<0 or enter>1:continue
		var point=a+d*enter
		if point.z<0 or Vector2(point.x,point.y).distance_to(players[i].pos)>90.001:continue
		# Fence reflection regions must not strand an otherwise reachable ball.
		var hand=Vector3(players[i].pos.x,players[i].pos.y,point.z)
		if not arena.sweep_pickup(hand,point-hand,copy_id==0).is_empty():continue
		if best.is_empty() or enter<best.t:best={"t":enter,"player":i}
	return best

func award_goal(team: int):
	if not ball_present or goal_ball_live:return
	if match_enabled and match_state!="playing":return
	StallRules.reset(self)
	KeeperRules.clear(self)
	last_goal=team
	score[team]+=1
	emit_audio("goal")
	MatchRules.record_goal(self,team)
	reset_delay=4.0 if match_enabled else 2.0 # Cheer() default, before 3 s kickoff.
	# Original score() disables further goals, not the ball movement timer.
	goal_ball_live=true
	notice=team_name(team)+"进球！"
	if last_owner>=0:
		notice+="%s %d 号%s"%[team_name(players[last_owner].team),players[last_owner].number,"乌龙球" if players[last_owner].team!=team else "得分"]
	if match_enabled:
		match_state="goal"
		pending_commands.clear()
		if mode=="score" and score[team]>=score_limit:finish_match(team)

func finish_match(team: int):
	winner=team
	match_state="ended"
	if not goal_ball_live:reset_delay=0
	pending_commands.clear()
	notice=team_name(team)+"获胜！"

func travel_ball(delta: Vector3):
	if not ball_present:return
	var result=BallFlight.travel(arena,ball,velocity,delta,Callable(self,"catch_hit"),0.0 if powershot_active else 4.0,not goal_ball_live)
	for impact in result.impacts:emit_visual("fx_ball_bump",impact.pos,1.0,impact.facing)
	ball=result.position;velocity=result.velocity
	if result.event=="catch":take(result.player)
	elif result.event=="goal":
		award_goal(result.team)
		# Finish this same physics tick beyond the scoring plane. No lost motion,
		# extra gravity step or second score when the ball rebounds out of goal.
		if goal_ball_live:travel_ball(result.remaining_delta)

func step_goal_ball():
	if not goal_ball_live or not ball_present or holder>=0 or ball_hook!=0:return
	var motion=BallFlight.integrate(ball,velocity,powershot_active,SurfaceRules.ball_friction(self))
	velocity=motion.velocity
	travel_ball(motion.delta)
	intercept=maxi(0,intercept-1)
	if powershot_active and (holder>=0 or velocity.length()<=5):powershot_active=false

func step_ball():
	previous_ball=ball
	time+=BALL_DT
	TackleVisuals.step(self)
	if match_enabled and not MatchRules.tick(self):
		if apocalypse_active():step_object_impulses()
		step_goal_ball()
		return
	if reset_delay>0:
		if apocalypse_active():step_object_impulses()
		reset_delay-=BALL_DT
		if reset_delay<=0:
			reset()
		else:step_goal_ball()
		return
	for i in range(players.size()):
		var p=players[i]
		if not unit_present(i):continue
		p.cooldown=maxf(0,p.cooldown-BALL_DT)
		p.action=maxf(0,p.action-BALL_DT)
		p.slow=maxf(0,p.slow-BALL_DT)
		p.ai_action=maxf(0,p.ai_action-BALL_DT)
		var kit=Characters.DATA[p.character]
		p.mana=clampf(p.mana+BALL_DT*(kit.regen-(kit.drain if p.sprint else 0)),0,100)
		if p.mana<1:
			if p.character=="h004":set_sprint(i,false)
			else:p.sprint=false
	Characters.step(self)
	KeeperRules.step(self)
	StallRules.visuals_step(self)
	step_object_impulses()
	step_tackles()
	if not ball_present:
		pass
	elif ball_hook!=0:
		pass # The hook controls the real ball until drop/return.
	elif holder>=0:
		var old_ball=ball
		if held_contact_owner!=holder:held_ball_contacts.clear()
		var protected_before=no_steal>0
		no_steal=maxi(0,no_steal-1)
		ball=Possession.held_position(self,holder)
		# Original protection expiry moves the ball away and back to re-arm entry.
		if protected_before and no_steal==0:held_ball_contacts.clear()
		if no_steal==0:
			var contact=Possession.entered(self,old_ball,held_ball_contacts)
			if not contact.is_empty():take(contact.player)
		held_ball_contacts=Possession.snapshot(self);held_contact_owner=holder
	else:
		# Preserve the original free-flight friction/gravity/bounce order.
		var motion=BallFlight.integrate(ball,velocity,powershot_active,SurfaceRules.ball_friction(self))
		velocity=motion.velocity
		travel_ball(motion.delta)
		intercept=maxi(0,intercept-1)
	if match_enabled and match_state!="playing":return
	if powershot_active and (holder>=0 or velocity.length()<=5):powershot_active=false
	Copies.step(self)
	pass_request=maxf(0,pass_request-BALL_DT)
	if bot_enabled:
		bot_clock+=BALL_DT
		if bot_clock>=0.3:
			bot_clock=0.0
			TeamAI.think(self)


