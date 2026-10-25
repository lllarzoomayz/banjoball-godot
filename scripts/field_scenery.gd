extends Node3D
## Original placed map scenery is visual only. Simulation owns all collision.
static var mesh_cache={}
static var terrain_cache={}
static var scene_cache={}
var field_id=""
var placement_count=0
var batch_count=0
var source_bounds=Rect2()
var placement_slots={}
var placement_visibility={}
var hidden_slots={}
var batch_nodes={}
var dynamic
var material_animation
var destruction

func height_at(point: Vector2) -> float:
	# Match the two triangles actually rendered in each original W3E cell.
	var data: Dictionary=scene_cache[field_id]
	var nx=int(data.grid[0]);var ny=int(data.grid[1])
	var p=(point-Vector2(data.bounds[0],data.bounds[1]))/128.0
	p=Vector2(clampf(p.x,0,nx-1.00001),clampf(p.y,0,ny-1.00001))
	var x=int(p.x);var y=int(p.y);var u=p.x-x;var v=p.y-y
	var h=data.heights;var a=float(h[y*nx+x]);var b=float(h[y*nx+x+1])
	var c=float(h[(y+1)*nx+x]);var d=float(h[(y+1)*nx+x+1])
	return a+(b-a)*u+(c-a)*v if u+v<=1 else d+(c-d)*(1-u)+(b-d)*(1-v)

static func texture_name(source: String) -> String:
	var regex=RegEx.new();regex.compile("[^a-z0-9._-]+")
	return "res://assets/textures/"+regex.sub(source.to_lower(),"_",true)+".png"

static func model_meshes(key: String) -> Array:
	if mesh_cache.has(key):return mesh_cache[key]
	var data=JSON.parse_string(FileAccess.get_file_as_string("res://assets/scenery/"+key+".json"))
	var meshes=[]
	for geo in data.meshes:
		var vertices=PackedVector3Array();var normals=PackedVector3Array();var uv=PackedVector2Array()
		for i in range(geo.vertices.size()/3):
			vertices.append(Vector3(geo.vertices[i*3],geo.vertices[i*3+1],geo.vertices[i*3+2]))
			normals.append(Vector3(geo.normals[i*3],geo.normals[i*3+1],geo.normals[i*3+2]))
			uv.append(Vector2(geo.uv[i*2],geo.uv[i*2+1]))
		var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
		arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_INDEX]=PackedInt32Array(geo.indices)
		var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var mat=StandardMaterial3D.new()
		mat.cull_mode=BaseMaterial3D.CULL_DISABLED
		mat.roughness=1;mat.specular_mode=BaseMaterial3D.SPECULAR_DISABLED
		mat.albedo_color=Color(geo.tint[0],geo.tint[1],geo.tint[2],geo.opacity)
		mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if geo.texture!="":mat.albedo_texture=load(texture_name(geo.texture))
		if int(geo.filter)==1:
			mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR;mat.alpha_scissor_threshold=0.5
		elif int(geo.filter)>=2:
			mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
			if int(geo.filter) in [3,4]:mat.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
		if int(geo.shading)&1:mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.surface_set_material(0,mat)
		meshes.append(mesh)
	mesh_cache[key]=meshes
	return meshes

static func terrain_mesh(data: Dictionary) -> ArrayMesh:
	if terrain_cache.has(data.id):return terrain_cache[data.id]
	var nx=int(data.grid[0]);var ny=int(data.grid[1]);var b=data.bounds
	var vertices=PackedVector3Array();var normals=PackedVector3Array();var uv=PackedVector2Array();var indices=PackedInt32Array()
	for y in range(ny):
		for x in range(nx):
			vertices.append(Vector3((b[0]+x*128)/100.0,data.heights[y*nx+x]/100.0,(b[1]+y*128)/-100.0))
			var dx=(data.heights[y*nx+mini(x+1,nx-1)]-data.heights[y*nx+maxi(x-1,0)])/float(128*(mini(x+1,nx-1)-maxi(x-1,0)))
			var dy=(data.heights[mini(y+1,ny-1)*nx+x]-data.heights[maxi(y-1,0)*nx+x])/float(128*(mini(y+1,ny-1)-maxi(y-1,0)))
			normals.append(Vector3(-dx,1,dy).normalized())
			uv.append(Vector2(float(x)/(nx-1),1-float(y)/(ny-1)))
			if x<nx-1 and y<ny-1:
				if data.has("skip_bounds"):
					var skip=data.skip_bounds;var px=b[0]+x*128;var py=b[1]+y*128
					if px>=skip[0] and py>=skip[1] and px+128<=skip[2] and py+128<=skip[3]:continue
				var i=y*nx+x
				indices.append_array([i,i+nx,i+1,i+1,i+nx,i+nx+1])
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var mat=StandardMaterial3D.new()
	mat.albedo_texture=load(data.texture);mat.roughness=1;mat.specular_mode=BaseMaterial3D.SPECULAR_DISABLED
	mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mesh.surface_set_material(0,mat);terrain_cache[data.id]=mesh
	return mesh

func load_field(id: String):
	field_id=id;name="OriginalFieldScenery"
	if not scene_cache.has(id):scene_cache[id]=JSON.parse_string(FileAccess.get_file_as_string("res://assets/scenery/"+id+".json"))
	var data: Dictionary=scene_cache[id]
	# Scripted floating ice can sit outside the cropped terrain backdrop.
	# Restore the same complete source water grid, using the existing two
	# geometry batches/material clock; never replace its ocean with blank void.
	if id in ["Frozen","Frozen_Coast"] and not data.get("complete_frozen_water",false):
		var definition=JSON.parse_string(FileAccess.get_file_as_string("res://research/fields.json")).fields.filter(func(f):return f.id==id)[0]
		var present={}
		for placed in data.placements:
			if placed.key=="B000_0":present[Vector2(placed.position[0],placed.position[1])]=true
		for water in load("res://scripts/apocalypse_world.gd").data().generated_water:
			if water.generated!="Frozen":continue
			var p=water.position;var xy=Vector2(p[0]-definition.center[0],p[1]-definition.center[1])
			if present.has(xy):continue
			data.placements.append({"key":"B000_0","editor_id":-1,"position":[xy.x,xy.y,p[2]-definition.world_height_offset],"angle":water.angle,"scale":water.scale,"life":water.life})
			present[xy]=true
		data.complete_frozen_water=true
	source_bounds=Rect2(Vector2(data.bounds[0],data.bounds[1]),Vector2(data.bounds[2]-data.bounds[0],data.bounds[3]-data.bounds[1]))
	var ground=MeshInstance3D.new();ground.name="OriginalTerrain";ground.mesh=terrain_mesh(data);add_child(ground)
	ground.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if id in ["Frozen","Frozen_Coast"]:
		var backdrop=JSON.parse_string(FileAccess.get_file_as_string("res://assets/scenery/"+id+"_seabed.json"))
		var seabed=MeshInstance3D.new();seabed.name="OriginalSeabedBackdrop";seabed.mesh=terrain_mesh(backdrop);seabed.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(seabed)
	material_animation=preload("res://scripts/scenery_materials.gd").new()
	dynamic=preload("res://scripts/dynamic_scenery.gd").new();add_child(dynamic)
	var groups={}
	for placed in data.placements:
		placement_count+=1
		if dynamic.supports(placed.key):dynamic.place(placed);continue
		if not groups.has(placed.key):groups[placed.key]=[]
		var p=placed.position;var s=placed.scale
		var basis=Basis(Vector3.UP,float(placed.angle)).scaled_local(Vector3(s[0],s[2],s[1]))
		placement_slots[int(placed.editor_id)]={"key":placed.key,"index":groups[placed.key].size(),"placement":placed}
		groups[placed.key].append(Transform3D(basis,Vector3(p[0],p[2],-p[1])/100.0))
	for key in groups:
		batch_nodes[key]=[]
		var transforms: Array=groups[key]
		var mesh_index=0
		for mesh in model_meshes(key):
			var batch=MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D;batch.mesh=mesh
			batch.instance_count=transforms.size()
			for i in range(transforms.size()):batch.set_instance_transform(i,transforms[i])
			var node=MultiMeshInstance3D.new();node.name=key;node.multimesh=batch;add_child(node)
			material_animation.bind(key,mesh_index,node,mesh.surface_get_material(0));mesh_index+=1
			batch_nodes[key].append(node)
			batch_count+=1

func advance(delta: float):
	if is_instance_valid(dynamic):dynamic.advance(delta)
	if material_animation!=null:material_animation.advance(delta)
	if is_instance_valid(destruction):destruction.advance(delta)

func destruction_state():
	if not is_instance_valid(destruction):
		destruction=load("res://scripts/scenery_destruction.gd").new();add_child(destruction);destruction.setup(self)
	return destruction

func set_placement_visible(editor_id: int,show: bool):
	placement_visibility[editor_id]=show
	if not placement_slots.has(editor_id):
		if is_instance_valid(dynamic):
			for model in dynamic.models:
				if int(model.get_meta("editor_id",-1))==editor_id:model.visible=show
		return
	var slot=placement_slots[editor_id];var p=slot.placement.position;var s=slot.placement.scale
	if not hidden_slots.has(slot.key):hidden_slots[slot.key]={}
	if show:hidden_slots[slot.key].erase(slot.index)
	else:hidden_slots[slot.key][slot.index]=true
	var basis=Basis(Vector3.UP,float(slot.placement.angle)).scaled_local(Vector3(s[0],s[2],s[1]) if show else Vector3.ZERO)
	for node in batch_nodes.get(slot.key,[]):
		node.multimesh.set_instance_transform(slot.index,Transform3D(basis,Vector3(p[0],p[2],-p[1])/100.0))
		node.visible=hidden_slots[slot.key].size()<node.multimesh.instance_count

func is_placement_visible(editor_id: int) -> bool:
	if not bool(placement_visibility.get(editor_id,true)):return false
	if not placement_slots.has(editor_id) and is_instance_valid(dynamic):
		for model in dynamic.models:
			if int(model.get_meta("editor_id",-1))==editor_id:return model.visible
	return true
