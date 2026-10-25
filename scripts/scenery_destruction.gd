extends Node3D
## Original destructable Death poses, instanced by variant on a shared clock.
## Doodads are not destructables. Death art does not invent physics blockers.
const Scenery=preload("res://scripts/field_scenery.gd")
static var catalog={}
static var geometry_cache={}
static var shader_cache={}
var field
var clock=0.0
var batches={}
var handled={}
var dead_slots={}
var retained_no_death=[]
var native_dead={}
var native_seen={}

const SHADER="""shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled MODES;
uniform sampler2D positions : filter_nearest, repeat_disable;
uniform sampler2D normals : filter_nearest, repeat_disable;
uniform sampler2D pose_colors : filter_nearest, repeat_disable;
uniform sampler2D skin : source_color, filter_linear_mipmap;
uniform float clock_now=0.0;
uniform float last_frame=0.0;
varying vec4 pose_color;
void vertex(){
 float frame=clamp((clock_now-INSTANCE_CUSTOM.x)*30.0,0.0,last_frame);
 int a=int(floor(frame));int b=min(a+1,int(last_frame));float weight=fract(frame);
 VERTEX=mix(texelFetch(positions,ivec2(VERTEX_ID,a),0).xyz,texelFetch(positions,ivec2(VERTEX_ID,b),0).xyz,weight);
 NORMAL=normalize(mix(texelFetch(normals,ivec2(VERTEX_ID,a),0).xyz,texelFetch(normals,ivec2(VERTEX_ID,b),0).xyz,weight));
 pose_color=mix(texelFetch(pose_colors,ivec2(a,0),0),texelFetch(pose_colors,ivec2(b,0),0),weight);
}
void fragment(){
 vec4 t=texture(skin,UV);
 if(pose_color.a<0.01)discard;
 ALBEDO=t.rgb*pose_color.rgb;ROUGHNESS=1.0;
 ALPHA_CODE
}
"""

static func source_catalog() -> Dictionary:
	if catalog.is_empty():catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/scenery/deaths/catalog.json"))
	return catalog

func setup(owner_field):
	field=owner_field;source_catalog()

static func create_geometry(key: String,index: int) -> Dictionary:
	var cache_key=key+":"+str(index)
	if geometry_cache.has(cache_key):return geometry_cache[cache_key]
	var row=source_catalog().models[key];var geo=row.meshes[index]
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
	var vertices=PackedVector3Array();var normals=PackedVector3Array();var uv=PackedVector2Array()
	for i in range(int(geo.vertex_count)):
		vertices.append(Vector3(geo.vertices[i*3],geo.vertices[i*3+1],geo.vertices[i*3+2]))
		normals.append(Vector3(geo.normals[i*3],geo.normals[i*3+1],geo.normals[i*3+2]))
		uv.append(Vector2(geo.uv[i*2],geo.uv[i*2+1]))
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_INDEX]=PackedInt32Array(geo.indices)
	var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var poses=ImageTexture.create_from_image(Image.create_from_data(int(geo.vertex_count),int(row.frames),false,Image.FORMAT_RGBAF,FileAccess.get_file_as_bytes(geo.positions)))
	var normal_frames=ImageTexture.create_from_image(Image.create_from_data(int(geo.vertex_count),int(row.frames),false,Image.FORMAT_RGBAF,FileAccess.get_file_as_bytes(geo.normal_frames)))
	var colors=PackedFloat32Array()
	for i in range(int(row.frames)):colors.append_array([geo.colors[i][0],geo.colors[i][1],geo.colors[i][2],geo.alphas[i]])
	var color_texture=ImageTexture.create_from_image(Image.create_from_data(int(row.frames),1,false,Image.FORMAT_RGBAF,colors.to_byte_array()))
	var low=Vector3(geo.bounds[0][0],geo.bounds[0][1],geo.bounds[0][2]);var high=Vector3(geo.bounds[1][0],geo.bounds[1][1],geo.bounds[1][2])
	var modes="";var alpha=""
	if int(geo.filter)==1:alpha="if(t.a*pose_color.a<0.5)discard;"
	elif int(geo.filter)>=2:
		modes=", depth_draw_never, "+("blend_add" if int(geo.filter) in [3,4] else ("blend_mul" if int(geo.filter) in [5,6] else "blend_mix"))
		alpha="ALPHA=t.a*pose_color.a;"
	if int(geo.shading)&1:modes+=", unshaded"
	var code=SHADER.replace(" MODES",modes).replace("ALPHA_CODE",alpha)
	if not shader_cache.has(code):
		var shader=Shader.new();shader.code=code;shader_cache[code]=shader
	geometry_cache[cache_key]={"mesh":mesh,"positions":poses,"normals":normal_frames,"colors":color_texture,"shader":shader_cache[code],"bounds":AABB(low,high-low).grow(.02)}
	return geometry_cache[cache_key]

func make_batch(key: String) -> Dictionary:
	var row=catalog.models[key];var batch={"key":key,"entries":[],"nodes":[],"materials":[],"capacity":0,"end":clock,"last_clock":-INF}
	for i in range(row.meshes.size()):
		var geometry=create_geometry(key,i);var geo=row.meshes[i]
		var material=ShaderMaterial.new();material.shader=geometry.shader
		material.set_shader_parameter("positions",geometry.positions);material.set_shader_parameter("normals",geometry.normals)
		material.set_shader_parameter("pose_colors",geometry.colors);material.set_shader_parameter("skin",load(Scenery.texture_name(geo.texture)))
		material.set_shader_parameter("last_frame",float(row.frames)-1);material.set_shader_parameter("clock_now",clock)
		var multi=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.use_custom_data=true;multi.mesh=geometry.mesh
		var node=MultiMeshInstance3D.new();node.name=key+"_death_"+str(i);node.multimesh=multi;node.material_override=material;add_child(node)
		batch.nodes.append(node);batch.materials.append(material)
	return batch

func write_entry(batch: Dictionary,index: int):
	var entry=batch.entries[index]
	for node in batch.nodes:
		node.multimesh.set_instance_transform(index,entry.transform)
		node.multimesh.set_instance_custom_data(index,Color(entry.start,0,0,0))

func add_death(key: String,transform: Transform3D,already_dead=false,age: float=0):
	if not catalog.models.has(key) or catalog.models[key].status!="death":return false
	if not batches.has(key):batches[key]=make_batch(key)
	var batch=batches[key];var row=catalog.models[key]
	# A pre-existing dead tree starts at the exact final sampled pose. The
	# runtime Death instances in the same batch retain their independent start.
	var length=(float(row.frames)-1)/30.0
	batch.entries.append({"transform":transform,"start":clock-length if already_dead else clock-maxf(0,age)})
	if batch.entries.size()>batch.capacity:
		batch.capacity=maxi(8,batch.capacity*2)
		for node in batch.nodes:node.multimesh.instance_count=batch.capacity
		for i in range(batch.entries.size()):write_entry(batch,i)
	else:write_entry(batch,batch.entries.size()-1)
	for i in range(batch.nodes.size()):
		var node=batch.nodes[i];var box=transform*create_geometry(key,i).bounds
		node.multimesh.custom_aabb=box if batch.entries.size()==1 else node.multimesh.custom_aabb.merge(box)
		node.multimesh.visible_instance_count=batch.entries.size()
	batch.end=maxf(batch.end,clock+(0 if already_dead else maxf(0,length-age)));batch.last_clock=-INF
	advance(0);return true

func placed_transform(placed: Dictionary) -> Transform3D:
	var p=placed.position;var s=placed.scale
	return Transform3D(Basis(Vector3.UP,float(placed.angle)).scaled_local(Vector3(s[0],s[2],s[1])),Vector3(p[0],p[2],-p[1])/100.0)

func kill_destructables() -> Dictionary:
	var killed=0;var kept=0
	var placements=Scenery.scene_cache[field.field_id].placements
	for slot in range(placements.size()):
		var placed=placements[slot]
		var kind=str(placed.key).get_slice("_",0)
		if not catalog.types.has(kind) or dead_slots.has(slot):continue
		var id=int(placed.editor_id)
		if handled.has(id):continue
		dead_slots[slot]=true
		# Another scene owner may have removed/replaced this original (BizTree).
		# Do not resurrect its hidden geometry or sound during destruction.
		if not field.is_placement_visible(id):continue
		if float(placed.get("life",100))>0:
			get_tree().call_group("wc3_destructable_events","destructable_death",field,kind,field.global_transform*placed_transform(placed).origin)
		if not catalog.models.has(placed.key) or catalog.models[placed.key].status!="death":
			kept+=1
			if placed.key not in retained_no_death:retained_no_death.append(placed.key)
			continue
		if add_death(placed.key,placed_transform(placed),float(placed.get("life",100))<=0):
			field.set_placement_visible(id,false);handled[id]=true;killed+=1
	return {"animated_destructables":killed,"retained_without_death":kept}

func replace_tree(editor_id: int,variation: int) -> Dictionary:
	if handled.has(editor_id) or not field.placement_slots.has(editor_id) or not field.is_placement_visible(editor_id):return {}
	var placed=field.placement_slots[editor_id].placement;var kind=str(placed.key).get_slice("_",0)
	if kind not in ["LTlt","WTst"] or variation<0 or variation>9:return {}
	var p=placed.position;var ground=field.height_at(Vector2(p[0],p[1]))
	var transform=Transform3D(Basis(Vector3.UP,deg_to_rad(270)).scaled_local(Vector3.ONE*1.2),Vector3(p[0],ground,-p[1])/100.0)
	if not add_death(kind+"_"+str(variation),transform,true):return {}
	field.set_placement_visible(editor_id,false);handled[editor_id]=true
	return {"editor_id":editor_id,"type":kind,"model":catalog.tree_unit_art[kind],"position":Vector3(p[0],p[1],ground),"facing":270.0}

func add_world_death(row: Dictionary,world_center: Vector2,age: float=0) -> bool:
	# Runtime-created destructables (e.g. clicked BizTree) have no authored
	# scene slot. Track their real UID so a later treePull can replace the stump.
	var uid=int(row.uid)
	if native_seen.has(uid):return false
	var p=Vector2(row.position[0],row.position[1])-world_center
	if not field.source_bounds.has_point(p):return false
	var key=str(row.id)+"_"+str(row.variation)
	var s=row.scale
	var transform=Transform3D(Basis(Vector3.UP,float(row.angle)).scaled_local(Vector3(s[0],s[2],s[1])),Vector3(p.x,field.height_at(p),-p.y)/100.0)
	if not add_death(key,transform,false,age):return false
	native_dead[uid]={"key":key,"index":batches[key].entries.size()-1};native_seen[uid]=true
	get_tree().call_group("wc3_destructable_events","destructable_death",field,row.id,field.global_transform*transform.origin)
	return true

func apply_tree_replacement(result: Dictionary,world_center: Vector2) -> bool:
	# Consume ApocalypseWorld's real remove/create identities. A previously
	# created DEAD tree can be selected again; replace that instance instead
	# of accumulating overlapping stumps or rejecting the second selection.
	if not result.has("replacement"):return false
	var original=result.removed;var dead=result.replacement
	var uid=int(dead.uid)
	if native_seen.has(uid):return false # Includes already replaced instances.
	var position=Vector2(dead.position[0],dead.position[1])-world_center
	if not field.source_bounds.has_point(position):return false
	var previous=native_dead.get(int(original.uid),{})
	var editor_id=int(original.get("editor_id",-1))
	if previous.is_empty() and editor_id>=0:
		if not field.placement_slots.has(editor_id) or not field.is_placement_visible(editor_id):return false
	var ground=field.height_at(position)
	var transform=Transform3D(Basis(Vector3.UP,deg_to_rad(270)).scaled_local(Vector3.ONE*1.2),Vector3(position.x,ground,-position.y)/100)
	var key=str(dead.id)+"_"+str(dead.variation)
	if not add_death(key,transform,true):return false
	if not previous.is_empty():
		var old_batch=batches[previous.key];var index=int(previous.index)
		old_batch.entries[index].transform.basis=Basis.from_scale(Vector3.ZERO)
		write_entry(old_batch,index);native_dead.erase(int(original.uid))
	elif editor_id>=0:
		field.set_placement_visible(editor_id,false);handled[editor_id]=true
	native_dead[uid]={"key":key,"index":batches[key].entries.size()-1}
	native_seen[uid]=true
	return true

func advance(delta: float):
	clock+=maxf(0,delta)
	for batch in batches.values():
		if batch.last_clock>=batch.end:continue
		for i in range(batch.materials.size()):
			batch.materials[i].set_shader_parameter("clock_now",clock)
			batch.nodes[i].visible=clock<batch.end or float(catalog.models[batch.key].meshes[i].alphas[-1])>.01
		batch.last_clock=clock

func clear():
	for editor_id in handled:field.set_placement_visible(editor_id,true)
	for child in get_children():child.free()
	batches.clear();handled.clear();dead_slots.clear();retained_no_death.clear();native_dead.clear();native_seen.clear();clock=0
