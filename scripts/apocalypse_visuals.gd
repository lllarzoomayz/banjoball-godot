extends Node3D
## Presentation for the live MatchSim Apocalypse adapter. No preview timer,
## input entry, gameplay RNG calls or fabricated skeleton combat lives here.
const Effects=preload("res://scripts/spell_visuals.gd")
const Model=preload("res://scripts/wc3_model.gd")
var game
var state
var field
var effects
var mask_layer: CanvasLayer
var mask: ColorRect
var hole
var hole_entry={}
var events=[]
var transients=[]
var trees={}
var fires=[]
var skeletons=[]
var rubble=[]
var last_absorption=0
var absorbed_count=0
var explosion_count=0
var cleaned=false
var last_clock=0.0
var tree_history=[]
var shake_offset=Vector2.ZERO
var noise=FastNoiseLite.new()
var model_sequence=0
var arrow_models={}
var last_arrow_end=0

func setup(owner_game):
	game=owner_game
	noise.seed=42017;noise.frequency=1.0
	effects=Effects.new();add_child(effects)
	mask_layer=CanvasLayer.new();mask_layer.layer=3;add_child(mask_layer)
	mask=ColorRect.new();mask.mouse_filter=Control.MOUSE_FILTER_IGNORE
	mask_layer.add_child(mask);mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mask.hide()
	game.sim.apocalypse_prepared.connect(bind)
	if game.sim.apocalypse!=null:bind(game.sim.apocalypse)

func clear():
	var was_active=state!=null and state.active
	if state!=null and state.rules.event.is_connected(on_event):state.rules.event.disconnect(on_event)
	state=null;field=null;events.clear();transients.clear();trees.clear();fires.clear();skeletons.clear();rubble.clear();tree_history.clear();arrow_models.clear();last_arrow_end=0
	effects.clear();hole=null;hole_entry.clear();last_absorption=0;absorbed_count=0;explosion_count=0;cleaned=false;last_clock=0;model_sequence=0
	mask.hide();shake_offset=Vector2.ZERO
	if is_instance_valid(game.camera):game.camera.h_offset=0;game.camera.v_offset=0
	if is_instance_valid(game.original_goals):game.original_goals.show()
	# End-of-event cleanup preserves scorch. Starting a new match is a
	# different lifecycle boundary, including when reusing the same field ID.
	if was_active:
		if is_instance_valid(game.event_decals):game.event_decals.clear()
		if is_instance_valid(game.event_spawns):game.event_spawns.clear()

func bind(adapter):
	clear();state=adapter;field=game.field_scenery;last_clock=state.rules.clock
	state.rules.event.connect(on_event)

func on_event(kind: String,row: Dictionary):
	# Signals are connected at prepare(), before vote() can emit begin. Queue
	# only render events; never allocate Godot models inside a simulation tick.
	if kind in ["begin","tree","explosion","cleanup","decorations","skeleton"]:
		events.append({"kind":kind,"row":row.duplicate(true)})

func create_model(id: String,pos: Vector3,facing: float,size: float=-1,color: Color=Color.WHITE):
	var model=Model.new();effects.add_child(model)
	model.load_actor(id,color)
	model.position=Effects.point(pos);model.rotation.y=facing
	if size>=0:model.scale=Vector3.ONE*size
	model_sequence+=1
	if is_instance_valid(model.particles):
		model.particles.defer_geometry=true
		model.particles.rng.seed=hash("apocalypse:"+id+":"+str(model_sequence))
	model.play("Stand",true)
	return model

func burst(row: Dictionary,absolute=false):
	var p=state.local(row.position) if absolute else row.pos
	var model=create_model(row.model,p,row.get("facing",0.0),row.get("scale",1.0))
	model.one_shot=true
	if row.model=="apoc_absorb":model.play("Death",true)
	elif not model.play("Birth",true):model.play(model.data.clips[0].name,true)
	model.rotate_object_local(Vector3.FORWARD,deg_to_rad(90-float(row.get("pitch",90))))
	transients.append({"model":model,"at":float(row.time),"advanced":0.0})
	return model

func advance_to(entry: Dictionary,now: float):
	var age=maxf(0,now-entry.at)
	# Particle integration has bounded steps. Paused rendering cannot advance
	# effects, and late-rendered events catch up from their simulation timestamp.
	while entry.advanced+0.000001<age:
		var step=minf(1.0/60,age-entry.advanced)
		entry.model.advance(step);entry.advanced+=step
		if entry.model.one_shot and entry.model.visual_tail_finished():break

func consume(event: Dictionary):
	var row=event.row
	match event.kind:
		"begin":
			hole=create_model("apoc_black_hole",state.local(state.rules.center(1224)),row.facing,1)
			hole_entry={"model":hole,"at":float(row.time),"advanced":0.0}
			hole.fade_alpha=0;hole.advance(0)
		"tree":
			if row.has("tree"):
				tree_history.append(row)
				apply_tree(row)
		"explosion":
			burst(row,true);explosion_count+=1
		"cleanup":
			cleaned=true
			if is_instance_valid(hole):hole.free();hole=null;hole_entry.clear()
			for entry in trees.values():entry.model.free()
			trees.clear()
			game.original_goals.hide() # Neutral-owned h00H units are removed too.
			field.destruction_state().kill_destructables()
			# Detached model effects and terrain splats retain their own lifetime.
			# In particular the nuclear UberSplat must survive this cleanup.
		"decorations":build_decorations(row.objects,float(row.time))
		"skeleton":
			var color=game.sim.team_color(row.team)
			var model=create_model(row.model,state.local(row.position),row.facing,-1,color)
			var health=Label3D.new();health.font=game.font;health.font_size=28;health.pixel_size=.008;health.position.y=1.6
			health.billboard=BaseMaterial3D.BILLBOARD_ENABLED;model.add_child(health)
			skeletons.append({"model":model,"at":float(row.time),"advanced":0.0,"source":state.aftermath.units[row.unit_id],"health":health,"attack_serial":0,"pose":"","last_clock":float(row.time)})
			burst({"model":"apoc_animate_dead","position":row.position,"time":row.time},true)

func apply_tree(row: Dictionary):
	field.destruction_state().apply_tree_replacement(row,Vector2(state.rules.world.field.center[0],state.rules.world.field.center[1]))

func sync_trees():
	for row in state.trees:
		if row.removed:
			if trees.has(row.id):trees[row.id].model.free();trees.erase(row.id)
			continue
		if not trees.has(row.id):
			var model=create_model(row.model,row.pos,row.facing)
			trees[row.id]={"model":model,"at":float(row.time),"advanced":0.0}
		trees[row.id].model.position=Effects.point(row.pos)

static func baked_mesh(model,index: int) -> ArrayMesh:
	# Preserve the original skinned Stand pose when batching static rubble.
	# Raw MDX vertices are not guaranteed to be in the displayed bind pose.
	var arrays=model.mesh_nodes[index].mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var bones=arrays[Mesh.ARRAY_BONES];var weights=arrays[Mesh.ARRAY_WEIGHTS]
	var influences=weights.size()/vertices.size()
	for i in range(vertices.size()):
		var p=Vector3.ZERO;var n=Vector3.ZERO
		for j in range(influences):
			var weight=float(weights[i*influences+j])
			if weight==0:continue
			var pose=model.skeleton.get_bone_global_pose(int(bones[i*influences+j]))
			p+=(pose*vertices[i])*weight;n+=(pose.basis*normals[i])*weight
		vertices[i]=p;normals[i]=n.normalized()
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_BONES]=null;arrays[Mesh.ARRAY_WEIGHTS]=null
	var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func build_decorations(rows: Array,at: float):
	var groups={}
	for row in rows:
		if row.kind!=3:
			fires.append({"model":create_model(row.model,state.local(row.position),row.facing,row.scale),"at":at,"advanced":0.0})
		else:
			if not groups.has(row.model):groups[row.model]=[]
			groups[row.model].append(row)
	for id in groups:
		var reference=create_model(id,Vector3.ZERO,0,1);reference.advance(0)
		for i in range(reference.mesh_nodes.size()):
			var multi=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D
			multi.mesh=baked_mesh(reference,i);multi.instance_count=groups[id].size()
			var node=MultiMeshInstance3D.new();effects.add_child(node);node.multimesh=multi
			node.material_override=reference.mesh_nodes[i].material_override
			for n in range(groups[id].size()):
				var row=groups[id][n]
				multi.set_instance_transform(n,Transform3D(Basis(Vector3.UP,row.facing).scaled_local(Vector3.ONE*row.scale),Effects.point(state.local(row.position))))
			rubble.append(node)
		reference.free()

func arrow_birth(arrow):
	var direction=arrow.pos-arrow.start
	var model=create_model("apoc_arrow",arrow.start,atan2(direction.y,direction.x),1)
	model.one_shot=true;model.play("Birth",true)
	return model

func advance_arrow(model,arrow,now):
	var age=maxf(0,now-float(arrow.time));var advanced=float(model.get_meta("arrow_age",0.0))
	var delta=maxf(0,age-advanced)
	if model.active_clip=="Birth":
		var step=minf(delta,maxf(0,float(model.clip.duration)-model.animation_time))
		model.advance(step);delta-=step
		if model.animation_time>=float(model.clip.duration)-.000001:model.one_shot=false;model.play("Stand",true)
	model.position=Effects.point(arrow.pos);model.advance(delta);model.set_meta("arrow_age",age)

func sync_army(now: float):
	for entry in skeletons:
		var u=entry.source;var data=state.aftermath.spec(u);var model=entry.model
		model.position=Effects.point(u.pos);model.rotation.y=u.angle
		var pose="Death" if u.hp<=0 else ("Attack" if u.hit_at!=INF or now-u.attack_at<float(data.attack_point)+float(data.backswing) else ("Walk" if u.moving else "Stand"))
		var elapsed=maxf(0,now-entry.last_clock)
		if u.attack_serial!=entry.attack_serial or pose!=entry.pose:
			model.one_shot=pose in ["Death","Attack"];model.play(pose,true)
			entry.pose=pose;entry.attack_serial=u.attack_serial
			if pose=="Attack":elapsed=maxf(0,now-u.attack_at)
			elif pose=="Death":elapsed=maxf(0,now-u.dead_at)
		model.rate=float(data.speed)/float(data.walk_animation_speed) if pose=="Walk" else 1.0
		model.advance(elapsed);entry.last_clock=now
		model.visible=u.hp>0 or now-u.dead_at<float(data.death)
		entry.health.text="%d / %d"%[ceili(u.hp),int(data.hp)]
		entry.health.modulate=Color("8ec8ff") if u.team==0 else Color("ffa295")
		entry.health.visible=u.hp>0 and (u.id==state.aftermath.selected or u.hp<data.hp)
	var alive={}
	for arrow in state.aftermath.arrows:
		alive[arrow.id]=true
		if not arrow_models.has(arrow.id):arrow_models[arrow.id]=arrow_birth(arrow)
		var model=arrow_models[arrow.id];var direction=arrow.pos-arrow.previous
		if direction.length_squared()>0:
			model.rotation=Vector3.ZERO;model.rotation.y=atan2(direction.y,direction.x)
			model.rotate_object_local(Vector3.BACK,atan2(direction.z,Vector2(direction.x,direction.y).length()))
		advance_arrow(model,arrow,now)
	for ended in state.aftermath.arrow_ends:
		if ended.event_id<=last_arrow_end:continue
		var model=arrow_models.get(ended.id)
		if model==null:model=arrow_birth(ended)
		advance_arrow(model,ended,float(ended.ended))
		model.position=Effects.point(ended.pos);model.one_shot=true;model.play("Death",true)
		transients.append({"model":model,"at":float(ended.ended),"advanced":0.0})
		arrow_models.erase(ended.id);last_arrow_end=ended.event_id
	for id in arrow_models.keys():
		if not alive.has(id):arrow_models[id].free();arrow_models.erase(id)
	if state.aftermath.active():
		var selected=state.aftermath.selected
		game.selection.visible=state.aftermath.local_owner(selected)
		if game.selection.visible:game.selection.position=Effects.point(state.aftermath.units[selected].pos)+Vector3.UP*.04

func update_shake():
	var rules=state.rules;var amount=rules.shake_magnitude/100.0
	# Native CameraSetTargetNoiseEx's undocumented waveform is not calibrated.
	# Use deterministic continuous noise with the original growing envelope;
	# its clock is simulation time and it never consumes the gameplay RNG.
	var t=maxf(0,rules.clock-rules.started-22.0)
	var phase=t*sqrt(maxf(rules.shake_velocity,0.0))*.02
	shake_offset=Vector2(noise.get_noise_1d(phase),noise.get_noise_1d(phase+71.3))*amount
	game.camera.h_offset=shake_offset.x;game.camera.v_offset=shake_offset.y

func frame():
	if state==null:return
	if not is_same(state,game.sim.apocalypse):clear();return
	if field!=game.field_scenery:
		field=game.field_scenery
		for row in tree_history:apply_tree(row)
		if cleaned:field.destruction_state().kill_destructables();game.original_goals.hide()
	var now=float(state.rules.clock)
	for event in events:consume(event)
	events.clear()
	for row in state.visuals:
		if row.id>last_absorption:
			last_absorption=row.id
			if row.model=="apoc_absorb":absorbed_count+=1
			burst(row)
	if is_instance_valid(hole):
		hole.fade_alpha=state.rules.alpha/255.0;hole.scale=Vector3.ONE*state.rules.size
		advance_to(hole_entry,now);hole.advance(0)
	sync_trees()
	for entry in trees.values():advance_to(entry,now)
	for entry in fires:advance_to(entry,now)
	sync_army(now)
	for entry in transients:advance_to(entry,now)
	for entry in transients.duplicate():
		if entry.model.visual_tail_finished():entry.model.free();transients.erase(entry)
	effects.flush_particles()
	mask.color=state.rules.MASK_COLOR;mask.color.a=state.rules.mask_opacity();mask.visible=mask.color.a>0
	update_shake()
	last_clock=now
