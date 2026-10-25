extends Node3D
## One original BizTree per loaded map, surviving field changes and match resets.
## Native zero-radius ANCIENT unit: selectable and enumerable, without an
## invented navigation footprint. Apocalypse binds its actual physics record.
const Model=preload("res://scripts/wc3_model.gd")
const Scenery=preload("res://scripts/field_scenery.gd")
var game
var catalog={}
var chosen={}
var removed=false
var pending=-1.0
var text_age=-1.0
var bound_field
var model
var replacement
var label
var origin=Vector3.ZERO
var bounds=AABB()
var apocalypse
var bridge
var before_apocalypse={}
var replacement_death_at=-1.0

func setup(owner_game,seed_value=-1):
	game=owner_game
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/scenery/biz_trees.json"))
	var random=RandomNumberGenerator.new()
	if seed_value<0:random.randomize()
	else:random.seed=seed_value
	# Source retries non-trees in RandomDestructableInRectBJ, then repeats three
	# successful tree draws and retains only the last. Sample that eligible set.
	for i in range(int(catalog.draws)):chosen=catalog.candidates[random.randi_range(0,catalog.candidates.size()-1)]
	game.sim.apocalypse_prepared.connect(bind_apocalypse)
	bind_field()
	if game.sim.apocalypse!=null:bind_apocalypse(game.sim.apocalypse)

func bind_apocalypse(adapter):
	if apocalypse!=null:leave_apocalypse()
	before_apocalypse={"removed":removed,"pending":pending,"text_age":text_age}
	apocalypse=adapter;bridge=adapter.bind_biz_tree(chosen,removed,pending,text_age)
	replacement_death_at=-1
	bind_field()

func leave_apocalypse():
	# A new match reloads Apocalypse world state. Preserve the Easter egg's
	# pre-event map state, just as it survives ordinary match/field changes.
	removed=before_apocalypse.get("removed",removed)
	pending=before_apocalypse.get("pending",-1.0);text_age=before_apocalypse.get("text_age",-1.0)
	apocalypse=null;bridge=null;before_apocalypse.clear();replacement_death_at=-1
	bound_field=null

func native_point(p: Vector3) -> Vector3:
	return Vector3(p.x,p.z,-p.y)/100.0

func sync_apocalypse():
	if bridge==null:return
	var unit=bridge.object
	if not unit.removed:
		# A unit starting outside the render crop can be pulled into view.
		if not is_instance_valid(model):make_unit()
		origin=native_point(unit.pos);model.position=origin
		return
	if is_instance_valid(model):model.free();model=null
	removed=not bridge.replacement.is_empty()
	if not bridge.replacement_present():
		if is_instance_valid(replacement):replacement.free();replacement=null
		if is_instance_valid(label):label.free();label=null
		return
	var row=bridge.replacement;var p=row.position
	origin=native_point(apocalypse.local(Vector3(p[0],p[1],p[2])))
	text_age=apocalypse.rules.clock-bridge.text_at
	if row.alive:
		if not is_instance_valid(replacement):make_replacement()
		replacement.position=origin
	else:
		if is_instance_valid(replacement):replacement.free();replacement=null
		if replacement_death_at<0:replacement_death_at=apocalypse.rules.started+51.5
		var c=apocalypse.rules.world.field.center
		bound_field.destruction_state().add_world_death(row,Vector2(c[0],c[1]),maxf(0,apocalypse.rules.clock-replacement_death_at))
	update_text()
	if is_instance_valid(label):
		# The source TextTag uses the airborne unit's Z; CreateDestructable is
		# independently grounded. Do not move the label down to the tree base.
		label.position=native_point(apocalypse.local(bridge.text_position))+Vector3(-.4,2+text_age*.5,0)

func bind_field():
	for child in get_children():child.free()
	model=null;replacement=null;label=null;bound_field=game.field_scenery
	if bridge!=null:
		bound_field.set_placement_visible(int(chosen.editor_id),false)
		sync_apocalypse();return
	if not bound_field.placement_slots.has(int(chosen.editor_id)):return
	var slot=bound_field.placement_slots[int(chosen.editor_id)]
	var p=slot.placement.position
	origin=Vector3(p[0],bound_field.height_at(Vector2(p[0],p[1])),-p[1])/100.0
	bound_field.set_placement_visible(int(chosen.editor_id),false)
	if removed:make_replacement();return
	make_unit()

func make_unit():
	model=Model.new();add_child(model);model.load_actor(chosen.model,Color.WHITE)
	model.position=origin;model.rotation.y=deg_to_rad(float(catalog.replacement_angle));model.play("Stand",true)
	var first=true
	for mesh in model.mesh_nodes:
		var box=mesh.mesh.get_aabb()
		bounds=box if first else bounds.merge(box);first=false

func make_replacement():
	if is_instance_valid(model):model.queue_free();model=null
	if is_instance_valid(replacement):return
	replacement=Node3D.new();add_child(replacement);replacement.position=origin
	replacement.rotation.y=deg_to_rad(float(catalog.replacement_angle));replacement.scale=Vector3.ONE*float(catalog.replacement_scale)
	for mesh in Scenery.model_meshes(chosen.replacement):
		var node=MeshInstance3D.new();node.mesh=mesh;replacement.add_child(node)
	update_text()

func update_text():
	if text_age<0 or text_age>=float(catalog.text_lifetime):
		if is_instance_valid(label):label.queue_free();label=null
		return
	if not is_instance_valid(label):
		label=Label3D.new();label.text="Hue";label.font=game.font;label.font_size=40;label.pixel_size=.01
		label.outline_size=8;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.no_depth_test=true;add_child(label)
	# Source TextTag uses x-40, terrain-relative z+200, .022 size, 1.5s life
	# and final .5s fade. As with existing text cues, screen ascent is local.
	label.position=origin+Vector3(-.4,2+text_age*.5,0)
	label.modulate=Color(1,1,1,clampf((float(catalog.text_lifetime)-text_age)/.5,0,1))

func frame(delta: float):
	if apocalypse!=null and not is_same(apocalypse,game.sim.apocalypse):leave_apocalypse()
	if not is_instance_valid(bound_field) or bound_field!=game.field_scenery:bind_field()
	if game.paused:delta=0
	if bridge!=null:
		sync_apocalypse()
		if is_instance_valid(model):model.advance(delta)
		return
	if pending>=0:
		pending-=delta
		if pending<=0:
			removed=true;text_age=maxf(0,-pending);pending=-1
			if is_instance_valid(model):make_replacement()
	elif removed and text_age>=0:text_age+=delta
	if is_instance_valid(model):model.advance(delta)
	if is_instance_valid(replacement):update_text()

func try_select(screen: Vector2) -> bool:
	if not is_instance_valid(bound_field) or bound_field!=game.field_scenery:bind_field()
	if game.paused or game.aim!="" or removed or not is_instance_valid(model):return false
	var camera=game.camera
	if camera.is_position_behind(model.global_position):return false
	var inverse=model.global_transform.affine_inverse()
	var ray_from=inverse*camera.project_ray_origin(screen)
	var ray_dir=(inverse.basis*camera.project_ray_normal(screen)).normalized()
	# Selection uses the original model's full bounds. It is not an invisible
	# movement obstacle. Exact Warcraft pixel/occlusion selection is uncalibrated.
	if bounds.intersects_ray(ray_from,ray_dir)==null:return false
	if bridge!=null:return bridge.select()
	if pending<0:pending=float(catalog.delay)
	return true
