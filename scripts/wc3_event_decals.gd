extends Node3D
## Batched original FPT / SPL / UBR on the rendered W3E ground.
const Rules=preload("res://scripts/wc3_decal_rules.gd")
const Model=preload("res://scripts/wc3_model.gd")
const MAX_PER_BATCH=4096
var game
var definitions={}
var definition_keys=[]
var definition_indices={}
var data_texture: ImageTexture
var height_texture: ImageTexture
var field_id=""
var bounds=Vector4()
var clock=0.0
var batches={}
var mesh: ArrayMesh
var total_emitted=0
var overflow_drops=0

const SHADER="""shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, world_vertex_coords, BLEND;
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D definitions : filter_nearest, repeat_disable;
uniform sampler2D heights : filter_nearest, repeat_disable;
uniform vec4 terrain_bounds;
uniform float clock_now;
varying vec4 tint;
varying vec4 tile;
varying vec2 native_xy;
float ground(vec2 xy){
 ivec2 size=textureSize(heights,0);
 vec2 p=clamp((xy-terrain_bounds.xy)/128.0,vec2(0.0),vec2(size)-vec2(1.00001));
 ivec2 i=ivec2(floor(p));vec2 f=fract(p);
 float a=texelFetch(heights,i,0).r;float b=texelFetch(heights,i+ivec2(1,0),0).r;
 float c=texelFetch(heights,i+ivec2(0,1),0).r;float d=texelFetch(heights,i+ivec2(1,1),0).r;
 return (f.x+f.y<=1.0 ? a+(b-a)*f.x+(c-a)*f.y : d+(c-d)*(1.0-f.x)+(b-d)*(1.0-f.y))/100.0;
}
void vertex(){
 int row=int(INSTANCE_CUSTOM.y);float age=max(0.0,clock_now-INSTANCE_CUSTOM.x);
 vec4 times=texelFetch(definitions,ivec2(0,row),0);
 vec4 start=texelFetch(definitions,ivec2(1,row),0);
 vec4 middle=texelFetch(definitions,ivec2(2,row),0);
 vec4 end=texelFetch(definitions,ivec2(3,row),0);
 vec4 life_uv=texelFetch(definitions,ivec2(4,row),0);
 vec4 decay_uv=texelFetch(definitions,ivec2(5,row),0);
 float cell=0.0;float cols=life_uv.w;float rows=decay_uv.w;
 if(times.w>0.5){
  if(age<times.x){tint=mix(start,middle,age/max(times.x,0.000001));}
  else if(age<times.x+times.y){tint=middle;}
  else{tint=mix(middle,end,clamp((age-times.x-times.y)/max(times.z,0.000001),0.0,1.0));}
 }else{
  bool birth=age<times.x;
  float f=clamp(birth ? age/max(times.x,0.000001) : (age-times.x)/max(times.z,0.000001),0.0,1.0);
  vec4 interval=birth ? life_uv : decay_uv;float count=interval.y-interval.x;
  cell=count>0.0 ? interval.x+mod(floor(count*interval.z*f),count) : interval.x;
  cell=min(cell,cols*rows-1.0);tint=birth ? mix(start,middle,f) : mix(middle,end,f);
 }
 if(age>=times.x+times.y+times.z){tint.a=0.0;}
 tint.a*=INSTANCE_CUSTOM.z;
 tile=vec4(mod(cell,cols),floor(cell/cols),cols,rows);
 native_xy=vec2(VERTEX.x,-VERTEX.z)*100.0;
 VERTEX.y=ground(native_xy)+0.014;
}
void fragment(){
 if(native_xy.x<terrain_bounds.x||native_xy.y<terrain_bounds.y||native_xy.x>terrain_bounds.z||native_xy.y>terrain_bounds.w){discard;}
 vec2 size=vec2(textureSize(atlas,0));vec2 begin=tile.xy/tile.zw;vec2 end=(tile.xy+vec2(1.0))/tile.zw;
 vec2 uv=clamp((tile.xy+UV)/tile.zw,begin+0.5/size,end-0.5/size);
 vec4 color=texture(atlas,uv)*tint;
 if(color.a<0.001){discard;}
 ALBEDO=color.rgb;ALPHA=color.a;
}
"""

func setup(owner_game):
	game=owner_game
	var data=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/events/decals.json"))
	definitions=data.definitions
	# Current map uses decorative WaterPlane models, not W3E water. A future
	# water map needs native surface sampling and the exported Water substitutes.
	assert(int(data.terrain_native_water_vertices)==0,"Native water decals need surface sampling")
	definition_keys=definitions.keys();definition_keys.sort()
	var image=Image.create(6,definition_keys.size(),false,Image.FORMAT_RGBAF)
	for i in range(definition_keys.size()):
		definition_indices[definition_keys[i]]=i
		var row=definitions[definition_keys[i]];var s=row.source
		var uber=row.kind=="UBR"
		image.set_pixel(0,i,Color(float(s.BirthTime) if uber else float(s.Lifespan),float(s.PauseTime) if uber else 0,float(s.Decay),1 if uber else 0))
		for j in range(3):image.set_pixel(j+1,i,Rules.color(s,["Start","Middle","End"][j]))
		image.set_pixel(4,i,Color(float(s.get("UVLifespanStart",0)),float(s.get("UVLifespanEnd",0)),float(s.get("LifespanRepeat",1)),float(s.get("Columns",1))))
		image.set_pixel(5,i,Color(float(s.get("UVDecayStart",0)),float(s.get("UVDecayEnd",0)),float(s.get("DecayRepeat",1)),float(s.get("Rows",1))))
	data_texture=ImageTexture.create_from_image(image);mesh=make_mesh()
	add_to_group("wc3_model_events");sync_field()

func make_mesh() -> ArrayMesh:
	var points=PackedVector3Array();var uv=PackedVector2Array();var indices=PackedInt32Array()
	# Nine vertices conform small decals to terrain, without per-frame CPU mesh work.
	for y in range(3):
		for x in range(3):
			var u=float(x)/2;var v=float(y)/2
			points.append(Vector3(1-2*v,0,2*u-1));uv.append(Vector2(u,v))
	for y in range(2):
		for x in range(2):
			var i=y*3+x;indices.append_array([i,i+1,i+3,i+1,i+4,i+3])
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_INDEX]=indices
	var result=ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);return result

func clear():
	for batch in batches.values():batch.node.queue_free()
	batches.clear();clock=0

func sync_field():
	if not is_instance_valid(game.field_scenery) or field_id==game.field_scenery.field_id:return
	clear();field_id=game.field_scenery.field_id
	var source=game.field_scenery.scene_cache[field_id];var size=source.grid
	bounds=Vector4(source.bounds[0],source.bounds[1],source.bounds[2],source.bounds[3])
	var pixels=PackedFloat32Array(source.heights)
	height_texture=ImageTexture.create_from_image(Image.create_from_data(int(size[0]),int(size[1]),false,Image.FORMAT_RF,pixels.to_byte_array()))

func make_batch(row: Dictionary) -> Dictionary:
	var shader=Shader.new();shader.code=SHADER.replace("BLEND","blend_add" if int(row.source.BlendMode)==1 else "blend_mix")
	var material=ShaderMaterial.new();material.shader=shader
	material.render_priority=-2
	material.set_shader_parameter("atlas",load(row.texture));material.set_shader_parameter("definitions",data_texture)
	material.set_shader_parameter("heights",height_texture);material.set_shader_parameter("terrain_bounds",bounds);material.set_shader_parameter("clock_now",clock)
	var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_custom_data=true;mm.mesh=mesh
	mm.instance_count=32;mm.visible_instance_count=0
	var node=MultiMeshInstance3D.new();node.multimesh=mm;node.material_override=material;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader projects height after instancing, so give it the ground bounds.
	node.custom_aabb=AABB(Vector3(bounds.x/100,-100,-bounds.w/100),Vector3((bounds.z-bounds.x)/100,200,(bounds.w-bounds.y)/100))
	add_child(node)
	return {"node":node,"mesh":mm,"material":material,"entries":[],"capacity":32}

func write_slot(batch: Dictionary,index: int):
	var entry=batch.entries[index]
	batch.mesh.set_instance_transform(index,entry.transform)
	batch.mesh.set_instance_custom_data(index,Color(entry.born,entry.definition,entry.alpha,0))

func remove_slot(batch: Dictionary,index: int):
	var last=batch.entries.size()-1
	if index!=last:batch.entries[index]=batch.entries[last]
	batch.entries.pop_back()
	if index<batch.entries.size():write_slot(batch,index)
	batch.mesh.visible_instance_count=batch.entries.size()

func advance(delta: float):
	sync_field()
	if delta<=0 or game.paused:return
	clock+=delta
	for batch in batches.values():
		batch.material.set_shader_parameter("clock_now",clock)
		for i in range(batch.entries.size()-1,-1,-1):
			if clock>=batch.entries[i].expires:remove_slot(batch,i)

func model_event(model,event: Dictionary,position: Vector3):
	if event.type not in ["FPT","SPL","UBR"] or not game.is_ancestor_of(model):return
	if game.paused or not model.is_visible_in_tree() or model.visibility_amount<=.01 or model.fade_alpha<=.01:return
	sync_field()
	var key=str(event.type)+":"+str(event.code)
	if not definitions.has(key):return
	var row=definitions[key]
	if row.texture=="" or Rules.lifetime(row)<=0:return
	var point=Vector2(position.x,-position.z)*100
	if not game.field_scenery.source_bounds.has_point(point):return
	var batch_key=str(row.texture)+":"+str(int(row.source.BlendMode))
	if not batches.has(batch_key):batches[batch_key]=make_batch(row)
	var batch=batches[batch_key]
	if batch.entries.size()>=MAX_PER_BATCH:
		overflow_drops+=1;return # Explicit exceptional budget; never shorten ordinary lifetimes.
	if batch.entries.size()==batch.capacity:
		batch.capacity=mini(MAX_PER_BATCH,batch.capacity*2);batch.mesh.instance_count=batch.capacity
		for i in range(batch.entries.size()):write_slot(batch,i)
	var r=event.get("rotation",[0,0,0,1]);var q=Quaternion(r[0],r[1],r[2],r[3])
	var source_rotation=model.global_basis.orthonormalized()*Model.CONVERSION*Basis(q)*Model.CONVERSION.inverse()
	# A ground splat keeps heading but cannot inherit the dummy's vertical
	# attachment tilt: that would collapse the pillar's circular stamp to a line.
	var forward=source_rotation.x;forward.y=0
	var heading=atan2(-forward.z,forward.x) if forward.length_squared()>.000001 else atan2(source_rotation.z.x,source_rotation.z.z)
	var rotation=Basis(Vector3.UP,heading)
	# SLK Scale is a half extent, independent of the actor's mesh scale.
	var transform=Transform3D(rotation.scaled(Vector3.ONE*float(row.source.Scale)/100.0),position)
	batch.entries.append({"key":key,"born":clock,"expires":clock+Rules.lifetime(row),"definition":definition_indices[key],"alpha":model.visibility_amount*model.fade_alpha,"transform":transform})
	write_slot(batch,batch.entries.size()-1);batch.mesh.visible_instance_count=batch.entries.size();total_emitted+=1

func live_count() -> int:
	var count=0
	for batch in batches.values():count+=batch.entries.size()
	return count
