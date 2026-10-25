extends Node3D
## Original scenery models/placements with their full Stand animation clocks.
const Model=preload("res://scripts/wc3_model.gd")
const Geometry=preload("res://scripts/particle_geometry.gd")
static var catalog={}
var models=[]
var batches={}
var use_batches=true
var use_packed=true
var profile={}

func _init():
	if catalog.is_empty():catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/scenery/dynamic_models.json"))

func supports(key: String) -> bool:return catalog.has(key)

func place(placed: Dictionary):
	var row=catalog[placed.key];var model=Model.new();add_child(model);model.load_actor(row.model,Color.WHITE)
	var p=placed.position;var s=placed.scale
	model.transform=Transform3D(Basis(Vector3.UP,float(placed.angle)).scaled_local(Vector3(s[0],s[2],s[1])),Vector3(p[0],p[2],-p[1])/100.0)
	model.tint=Color(row.tint[0],row.tint[1],row.tint[2]);model.play("Stand",true)
	model.set_meta("editor_id",int(placed.editor_id));model.set_meta("scenery_key",placed.key)
	if is_instance_valid(model.particles):
		model.particles.defer_geometry=true
		model.particles.rng.seed=hash(row.model+":"+str(placed.editor_id))
		for emitter in model.particles.emitters:
			# Scenery particles follow transparent scenery surfaces, retaining depth
			# testing against opaque geometry. Stable for separate/batched drawing.
			emitter.mesh.material_override.render_priority=1
			if use_packed and model.particles.accelerator!=null and model.particles.accelerator.has_method("draw_packed_particles"):
				emitter.packed=PackedFloat64Array()
	models.append(model)

func advance(delta: float):
	var start=Time.get_ticks_usec()
	for model in models:model.advance(delta)
	var simulation_end=Time.get_ticks_usec()
	flush_particles()
	profile={"models":models.size(),"simulation_ms":(simulation_end-start)/1000.0,"geometry_ms":(Time.get_ticks_usec()-simulation_end)/1000.0}

func flush_particles():
	for batch in batches.values():batch.geometry.begin()
	for model in models:
		if not model.is_visible_in_tree() or not is_instance_valid(model.particles):continue
		for index in range(model.particles.emitters.size()):
			var emitter=model.particles.emitters[index]
			if use_batches and int(emitter.source.FilterMode)==1:
				var key=str(model.data.actor.id)+":"+str(index)
				if not batches.has(key):
					var node=MeshInstance3D.new();node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					node.material_override=emitter.mesh.material_override;add_child(node)
					var geometry=Geometry.new();geometry.begin();batches[key]={"node":node,"geometry":geometry}
				emitter.batch_geometry=batches[key].geometry
			else:emitter.erase("batch_geometry")
			model.particles.draw_emitter(emitter)
	for batch in batches.values():batch.geometry.commit(batch.node)

func particle_count() -> int:
	var total=0
	for model in models:
		if is_instance_valid(model.particles):total+=model.particles.particle_count()
	return total
