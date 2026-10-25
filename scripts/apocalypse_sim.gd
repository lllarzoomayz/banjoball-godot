extends RefCounted
## MatchSim adapter. Local roster slots stand for original player owners.
## Rendering consumes rules.event / visuals; no networking or UI is enabled.
const Rules=preload("res://scripts/apocalypse_rules.gd")
var host: WeakRef
var rules=Rules.new()
var next_objects=INF
var next_time: float:
	get:return minf(minf(minf(rules.next_time,next_objects),biz_tree.next_time if biz_tree!=null else INF),aftermath.next_time)
var active: bool:
	get:return rules.active
var removed_players={}
var ball_removed=false
var cleaned=false
var trees=[]
var external_objects=[]
var next_tree_id=0
var visuals=[]
var visual_sequence=0
var terrain_repair_requests=0
var properties={}
var biz_tree
var aftermath=preload("res://scripts/aftermath_sim.gd").new()

func bind_biz_tree(chosen: Dictionary,replaced: bool,pending: float,text_age: float=-1):
	if biz_tree==null:
		biz_tree=preload("res://scripts/apocalypse_biz_tree.gd").new()
		biz_tree.setup(self,chosen,replaced,pending,text_age)
	return biz_tree

func setup(sim):
	host=weakref(sim)
	aftermath.setup(self)
	properties=JSON.parse_string(FileAccess.get_file_as_string("res://assets/scenery/apocalypse-objects.json")).objects
	var teams=[[],[]]
	for i in range(sim.players.size()):teams[sim.players[i].team].append(i)
	rules.setup(sim.selected_field,sim.random,[0],teams,sim.field_started,sim.generated_ice)
	rules.advance_to(sim.clock_now())
	rules.event.connect(on_event)

func vote(owner: int) -> bool:
	return rules.vote(owner,host.get_ref().clock_now())

func absolute(position: Vector3) -> Vector3:
	var sim=host.get_ref()
	return position+Vector3(rules.world.field.center[0],rules.world.field.center[1],sim.arena.world_height_offset)

func local(position: Vector3) -> Vector3:
	return position-absolute(Vector3.ZERO)

func visual(model: String,position: Vector3,size: float,pitch: float,facing: float=NAN):
	visual_sequence+=1
	visuals.append({"id":visual_sequence,"time":rules.clock,"model":model,"pos":position,"scale":size,"pitch":pitch,"facing":rules.rng.randf_range(0,TAU) if is_nan(facing) else facing})
	# Presentation consumes sequence IDs; long absorbed-unit streams are bounded.
	if visuals.size()>256:visuals.pop_front()

func step(now: float):
	rules.advance_to(now)
	if biz_tree!=null:biz_tree.step(now)
	aftermath.step(now)
	if next_objects<=now+1e-8:
		step_objects();next_objects=INF if cleaned else next_objects+Rules.DT

func nonplayer_objects() -> Array:
	var sim=host.get_ref();var result=[]
	for tree in trees:
		if not tree.get("removed",false):result.append(tree)
	for projectile in sim.projectiles:
		if projectile.life>0:
			projectile.apoc_rawcode={"swap":"h011","hook":"h01S","rift":"h02A"}.get(projectile.kind,"")
			if properties.has(projectile.apoc_rawcode):result.append(projectile)
	if not sim.referee.is_empty():
		sim.referee.apoc_rawcode="h00T";result.append(sim.referee)
	for shadow in sim.tackle_shadows:
		if not shadow.get("removed",false):shadow.apoc_rawcode="h00E";result.append(shadow)
	for row in external_objects:
		if not row.get("removed",false):result.append(row)
	return result

func register_external(rawcode: String,object: Dictionary) -> bool:
	if not properties.has(rawcode) or properties[rawcode].player or not object.has("pos") or external_objects.any(func(row):return is_same(row,object)):return false
	object.apoc_rawcode=rawcode;external_objects.append(object)
	return true

func on_event(kind: String,row: Dictionary):
	var sim=host.get_ref()
	match kind:
		"skeleton":aftermath.spawn(row)
		"begin":
			sim.arena.remove_authored_blockers()
			sim.nav_cache.clear();sim.nav_dirty.clear();sim.nav_grid_key=""
			next_objects=row.time+Rules.DT
		"pull":
			for i in range(sim.players.size()):
				if not sim.unit_present(i):continue
				var response=rules.unit_pull(absolute(sim.Characters.world_position(sim.players[i])))
				if response.remove:
					visual("apoc_absorb",local(rules.center(1234)),3,0);remove_player(i)
				else:sim.apply_impulse(i,response.force)
			for object in nonplayer_objects():
				var response=rules.unit_pull(absolute(object.pos))
				if response.remove:
					visual("apoc_absorb",local(rules.center(1234)),3,0);remove_nonplayer(object)
				else:apply_nonplayer(object,response.force)
			if sim.ball_present:
				var response=rules.ball_pull(absolute(sim.ball))
				if response.remove:visual("apoc_absorb",sim.ball,1,90);remove_ball()
				else:
					# s__Ball_applyVector drops a held real ball before adding force.
					if sim.holder>=0:sim.last_owner=sim.holder
					sim.holder=-1;sim.no_steal=0
					sim.velocity=sim.ObjectMotion.check_force(sim.arena,sim.ball,sim.velocity+response.force,4.0)
		"tree":
			if row.has("tree"):
				next_tree_id+=1
				var tree=row.tree.duplicate();tree.id=next_tree_id;tree.time=row.time;tree.pos=local(tree.position);tree.previous=tree.pos
				tree.apoc_velocity=Vector3.ZERO;tree.removed=false;trees.append(tree)
		"explosion":
			for i in range(sim.players.size()):
				if sim.unit_present(i):sim.apply_impulse(i,rules.blast(absolute(sim.Characters.world_position(sim.players[i]))))
			for object in nonplayer_objects():apply_nonplayer(object,rules.blast(absolute(object.pos)))
			# Unlike the pull, original explosionBlast does not target ball[0].
		"cleanup":
			for i in range(sim.players.size()):remove_player(i)
			remove_ball()
			for object in nonplayer_objects():remove_nonplayer(object)
			sim.fake_balls.clear();sim.projectiles.clear();sim.rifts.clear();sim.skill_effects.clear()
			sim.curve.clear();sim.tackle_shadows.clear();sim.arena.clear_pillars()
			sim.pending_commands.clear();sim.InjuryRules.reset(sim);sim.shout.clear();sim.StallRules.reset(sim)
			sim.reset_delay=0;cleaned=true;next_objects=INF

func remove_player(index: int):
	var sim=host.get_ref()
	if not sim.unit_present(index):return
	removed_players[index]=true
	var p=sim.players[index]
	# Remove the native unit, not the roster slot. HUD/old references remain
	# valid, while commands, collision, abilities and later resets see a tombstone.
	p.removed=true;p.moving=false;p.want_move=false;p.path.clear();p.direct_axis=Vector2.ZERO
	p.cast_pending=false;p.shot_order.clear();p.ability_order.clear();p.ability_delay=0;p.tackle=0;p.tackle_order=0
	p.action=0;p.disabled=0;p.sprint=false;p.pull_time=0;p.shadow_return=0
	p.flight_steps=0;p.possess_time=0;p.jump_due=false;p.flip_time=0;p.keeper_pose=0
	p.morph_roll=0;p.morph_ghost=0;p.knock=Vector2.ZERO;p.vz=0
	sim.stop_object(index);sim.InjuryRules.configure(p)
	if sim.holder==index:sim.holder=-1;sim.no_steal=0
	sim.Copies.release_held(sim,index)
	for projectile in sim.projectiles:
		if projectile.kind=="hook" and projectile.caught==index:
			projectile.caught=-1;projectile.returning=true
	p.hooked=0
	sim.pending_commands=sim.pending_commands.filter(func(c):return c.player!=index)

func remove_ball():
	var sim=host.get_ref()
	if not sim.ball_present:return
	ball_removed=true;sim.ball_present=false;sim.holder=-1;sim.no_steal=0
	sim.velocity=Vector3.ZERO;sim.curve.clear();sim.powershot_active=false;sim.ball_hook=0
	for projectile in sim.projectiles:
		if projectile.kind=="hook" and projectile.caught==-2:projectile.caught=-1;projectile.returning=true
	for p in sim.players:
		if p.possess_time>0 or p.flight_steps>0:
			p.possess_time=0;p.flight_steps=0;p.jump_due=false;p.eject_time=.5
		if p.pull_time>0:sim.Characters.finish_pull(p)
	sim.stall_counter=0;sim.stall_warned=false;sim.next_referee=INF

func restore_removed_flags():
	var sim=host.get_ref()
	for index in removed_players:
		if index<sim.players.size():sim.players[index].removed=true
	if ball_removed:sim.ball_present=false;sim.holder=-1

func remove_nonplayer(object: Dictionary):
	var sim=host.get_ref();object.removed=true;object.apoc_velocity=Vector3.ZERO
	if object.has("kind") and object.kind=="hook":sim.Characters.Complex.hook_drop(sim,object);sim.players[object.owner].hook={}
	if object.has("life"):object.life=0
	if object.get("apoc_rawcode","")=="h00E":object.age=sim.TackleVisuals.LIFETIME
	if is_same(object,sim.referee):sim.referee={};sim.next_referee=INF

func apply_nonplayer(object: Dictionary,force: Vector3):
	var sim=host.get_ref()
	object.apoc_velocity=sim.ObjectMotion.check_force(sim.arena,object.pos,object.get("apoc_velocity",Vector3.ZERO)+force,0)

func step_objects():
	var sim=host.get_ref()
	for object in nonplayer_objects():
		if not object.has("apoc_velocity"):continue
		var position: Vector3=object.pos;var velocity: Vector3=object.apoc_velocity
		var old_world=absolute(position);var old_ground=rules.world.ground_height(Vector2(old_world.x,old_world.y))
		var rawcode=str(object.get("apoc_rawcode",object.get("rawcode","")))
		var radius=float(properties[rawcode].radius)
		if radius>0:
			velocity=sim.Skills.object_velocity(old_world.z-old_ground,velocity,sim.SurfaceRules.player_friction(sim))
		var candidate=old_world+Vector3(velocity.x,velocity.y,0)
		if Rules.World.contains(rules.world.initial_bounds,Vector2(candidate.x,candidate.y)):
			position.x+=velocity.x;position.y+=velocity.y
		var current_world=absolute(position)
		var ground=rules.world.ground_height(Vector2(current_world.x,current_world.y))-sim.arena.world_height_offset
		# Zero-radius native objects have NO friction or gravity. Moving XY
		# preserves fly height above terrain before adding the Z velocity.
		position.z+=ground-(old_ground-sim.arena.world_height_offset)+velocity.z
		if position.z<ground and velocity.z<0:
			position.z=ground;velocity.z=maxf(0,-velocity.z-(15 if radius>0 else 0))
		for boundary in sim.arena.boundaries:
			var a=Vector2(object.pos.x,object.pos.y);var b=Vector2(position.x,position.y)
			if not boundary.rect.has_point(a) and boundary.rect.has_point(b) and position.z>=boundary.low and position.z<=boundary.high and velocity.dot(boundary.normal)<0:
				velocity=velocity.bounce(boundary.normal)
		# Native SetUnitPosition recovery on nonwalkable terrain is still not
		# calibrated; record encounters, do not invent a player-radius collider.
		var xy=Vector2(position.x,position.y)
		if not sim.arena.in_playable_region(xy) or not sim.arena.terrain_walkable(xy):terrain_repair_requests+=1
		object.previous=object.pos;object.pos=position;object.apoc_velocity=velocity
		if radius>0 and velocity.length_squared()>0:collide_players(object)

func collide_players(object: Dictionary):
	var sim=host.get_ref()
	for i in range(sim.players.size()):
		var p=sim.players[i]
		if sim.Characters.absent(p) or absf(p.z-object.pos.z)>100 or p.pos.distance_to(Vector2(object.pos.x,object.pos.y))>80:continue
		var offset=sim.Characters.world_position(p)-object.pos
		var other=Vector3(p.knock.x,p.knock.y,p.vz)
		if not sim.Skills.contact_allowed_3d(object.apoc_velocity,other,offset):continue
		var flash=sim.ObjectMotion.contact_flash(object.apoc_velocity,other,object.pos,offset)
		if not flash.is_empty():
			visual("fx_player_bump",flash.pos,flash.scale,flash.pitch,flash.facing)
			visuals[-1].time=sim.clock_now()
		var exchanged=sim.Skills.contact_exchange_3d(object.apoc_velocity,other,offset)
		object.apoc_velocity=sim.ObjectMotion.check_force(sim.arena,object.pos,exchanged[0],0)
		other=sim.checked_player_velocity(sim.Characters.world_position(p),exchanged[1])
		p.knock=Vector2(other.x,other.y);p.vz=other.z;sim.start_object(i)

func collide_external_from_player(index: int):
	# Native radius queries enumerate non-Locust ANCIENT units, including a
	# zero-radius BizTree. It receives momentum but is not a pathfinding wall.
	var sim=host.get_ref();var p=sim.players[index]
	var origin=sim.Characters.world_position(p)
	for object in external_objects:
		if object.get("removed",false) or properties[object.apoc_rawcode].locust:continue
		var offset: Vector3=object.pos-origin
		if absf(offset.z)>100 or Vector2(offset.x,offset.y).length()>80:continue
		var source=Vector3(p.knock.x,p.knock.y,p.vz);var other=object.get("apoc_velocity",Vector3.ZERO)
		if not sim.Skills.contact_allowed_3d(source,other,offset):continue
		var flash=sim.ObjectMotion.contact_flash(source,other,origin,offset)
		if not flash.is_empty():
			visual("fx_player_bump",flash.pos,flash.scale,flash.pitch,flash.facing)
			visuals[-1].time=sim.clock_now()
		var exchanged=sim.Skills.contact_exchange_3d(source,other,offset)
		var result=sim.checked_player_velocity(origin,exchanged[0])
		p.knock=Vector2(result.x,result.y);p.vz=result.z
		object.apoc_velocity=sim.ObjectMotion.check_force(sim.arena,object.pos,exchanged[1],0)
