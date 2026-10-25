extends Node3D
## Initialization__setup: neutral h00H (BarkSkinTarget), scale 0.6, facing 0.
## The visual has zero unit collision. Ball boundaries and keeper restrictions
## come from the map's regions, not from a bounding box around these particles.
const Model=preload("res://scripts/wc3_model.gd")
const HEIGHT=300.0
var parts=[]
var field_id=""
var geometry=preload("res://scripts/particle_geometry.gd").new()
var batch_mesh: MeshInstance3D

func load_field(arena,scenery):
	name="OriginalGoals";field_id=arena.data.id
	batch_mesh=MeshInstance3D.new();add_child(batch_mesh)
	batch_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var left: Rect2=arena.rect(arena.data.regions.Goal_1)
	var right: Rect2=arena.rect(arena.data.regions.Goal_2)
	var spacing=left.size.y/12.0
	for i in range(13):
		for pair in [[left.end.x+73.0,left.end.y],[right.position.x+7.0,right.end.y]]:
			for height in [0.0,HEIGHT]:add_part(Vector2(pair[0],pair[1]-spacing*i),height,scenery)
	for i in range(1,5):
		for pair in [[left.end.x+73.0,left.end.y],[left.end.x+73.0,left.position.y],[right.position.x+7.0,right.end.y],[right.position.x+7.0,right.position.y]]:
			add_part(Vector2(pair[0],pair[1]),HEIGHT-HEIGHT/5.0*i,scenery)
	# These ambient emitters have already been running during map setup.
	# Warm only their visual clock; never advance gameplay or its random state.
	for i in range(30):advance(1.0/60)

func add_part(point: Vector2,height: float,scenery):
	var model=Model.new();add_child(model)
	model.position=Vector3(point.x,(scenery.height_at(point) if scenery!=null else 0.0)+height,-point.y)/100.0
	model.set_meta("source_position",Vector3(point.x,point.y,height))
	model.load_actor("h00H",Color.WHITE)
	model.particles.rng.seed=hash("goal:"+str(parts.size()))
	model.particles.batch_geometry=geometry
	if batch_mesh.material_override==null:batch_mesh.material_override=model.particles.emitters[0].mesh.material_override
	parts.append(model)

func advance(delta: float):
	geometry.begin()
	for model in parts:model.advance(delta)
	geometry.commit(batch_mesh)
