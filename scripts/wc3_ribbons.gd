extends Node3D
## Original MDX RibbonEmitter data, independent of match state and wall clock.
## Cross-sections are in native local Y, transformed by the original bone pose.
## Captured sections remain in world space when the actor moves or turns.
const CONVERSION=Basis(Vector3.RIGHT,Vector3(0,0,-1),Vector3.UP)
const MAX_SECTIONS=256
static var shaders={}
var actor
var emitters=[]
var clock=0.0
var emitting=true
var started=false
var use_packed_geometry=true
var use_native_geometry=true
static var accelerator=preload("res://scripts/acceleration.gd").create()

func configure(model):
	actor=model
	top_level=true;global_transform=Transform3D.IDENTITY
	for source in model.data.get("ribbons",[]):
		var nodes=[]
		for layer in model.data.materials[int(source.MaterialID)].Layers:
			var node=MeshInstance3D.new();add_child(node)
			node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.material_override=make_material(layer)
			node.visible=false;nodes.append(node)
		emitters.append({"source":source,"nodes":nodes,"sections":[],"credit":0.0,"previous":[],"last_texture":[]})

func make_material(layer: Dictionary) -> ShaderMaterial:
	var mode=int(layer.FilterMode)
	var blending="blend_mul" if mode in [5,6] else ("blend_add" if mode in [3,4] else "blend_mix")
	var shader_code="""shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, BLENDING;
uniform sampler2D source_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 ribbon_color : source_color = vec4(1.0);
uniform vec4 team_color : source_color = vec4(1.0);
uniform int replaceable = 0;
uniform float layer_alpha = 1.0;
void fragment(){
 vec4 t=texture(source_texture,UV);
 if(replaceable==1){t=team_color;}
 else if(replaceable==2){float glow=max(t.r,max(t.g,t.b));t=vec4(team_color.rgb*glow,glow);}
 t*=ribbon_color;
 t.a*=layer_alpha;
 if(t.a<CUTOFF)discard;
 ALBEDO=t.rgb*GAIN;
 ALPHA=t.a;
}
""".replace("BLENDING",blending).replace("CUTOFF","0.75" if mode==1 else "0.01").replace("GAIN","2.0" if mode==6 else "1.0")
	if not shaders.has(shader_code):
		var shader=Shader.new();shader.code=shader_code;shaders[shader_code]=shader
	var material=ShaderMaterial.new();material.shader=shaders[shader_code]
	material.set_shader_parameter("team_color",actor.team_color)
	return material

func sample(index: int,frame: float) -> Array:
	var tracks=actor.clip.get("ribbons",[])
	if tracks.is_empty():return []
	var a=mini(int(frame),tracks.size()-1);var b=mini(a+1,tracks.size()-1)
	var values=[]
	for column in range(5):
		values.append(lerpf(tracks[a][index][column],tracks[b][index][column],frame-a) if column in [1,2,3] else tracks[a][index][column])
	return values

func endpoints(source: Dictionary,values: Array) -> Array:
	var pivot=source.PivotPoint
	var native=Vector3(pivot[0],pivot[1],pivot[2])
	var pose=actor.global_transform*actor.skeleton.get_bone_pose(int(source.bone_index))
	return [pose*(CONVERSION*(native+Vector3(0,values[1],0))/100.0),pose*(CONVERSION*(native-Vector3(0,values[2],0))/100.0)]

func advance(delta: float,frame: float):
	clock+=delta
	visible=actor.visible
	for index in range(emitters.size()):
		var emitter=emitters[index];var source=emitter.source
		var values=sample(index,frame)
		if values.is_empty():continue
		var current=endpoints(source,values)
		if not actor.visible:
			emitter.sections.clear();emitter.credit=0;emitter.previous=current
			for node in emitter.nodes:node.visible=false
			continue
		if emitter.previous.is_empty() or not started:emitter.previous=current
		if delta>0:
			var lifespan=float(source.LifeSpan)
			emitter.sections=emitter.sections.filter(func(section):return clock-section.birth<lifespan)
			var active=emitting and values[0]>0 and lifespan>0 and ((actor.clip.loop and not actor.one_shot) or actor.animation_time<float(actor.clip.duration))
			if active:
				var rate=maxf(0,float(source.EmissionRate))
				var accumulated=emitter.credit+rate*delta
				var count=mini(floori(accumulated+0.00000001),MAX_SECTIONS)
				for i in range(count):
					var offset=(1-emitter.credit+i)/rate
					var fraction=clampf(offset/delta,0,1)
					var birth=clock-delta+offset
					if clock-birth>=lifespan:continue
					emitter.sections.append({"above":emitter.previous[0].lerp(current[0],fraction),"below":emitter.previous[1].lerp(current[1],fraction),"birth":birth,"gravity":float(source.Gravity)*actor.global_basis.get_scale().x/100.0})
				emitter.credit=accumulated-floor(accumulated+0.00000001)
				emitter.credit=maxf(0,emitter.credit)
				while emitter.sections.size()>MAX_SECTIONS:emitter.sections.pop_front()
			else:emitter.credit=0.0
		emitter.previous=current
		draw_emitter(emitter,values,frame)
	if delta>0:started=true

func section_point(section: Dictionary,key: String) -> Vector3:
	# Gravity is integrated from birth time, so frame rate does not change sag.
	# This is a visual integration, not a claim about Warcraft's timer cadence.
	var age=maxf(0,clock-float(section.birth))
	return section[key]-Vector3.UP*(0.5*float(section.gravity)*age*age)

func coordinates(source: Dictionary,slot: int,age: float) -> Vector2:
	var columns=maxi(1,int(source.Columns));var rows=maxi(1,int(source.Rows))
	slot=clampi(slot,0,columns*rows-1)
	return Vector2((float(slot%columns)+clampf(age/float(source.LifeSpan),0,1))/columns,float(floori(float(slot)/columns))/rows)

func draw_emitter(emitter: Dictionary,values: Array,frame: float):
	if emitter.sections.size()<2:
		for node in emitter.nodes:node.visible=false
		return
	var source=emitter.source
	var mesh
	if use_packed_geometry and use_native_geometry and accelerator!=null and accelerator.has_method("draw_ribbons"):
		mesh=native_mesh(emitter,values)
	elif use_packed_geometry:mesh=packed_mesh(emitter,values)
	else:mesh=legacy_mesh(emitter,values)
	var rgb=source.Color
	var color=Color(rgb[0],rgb[1],rgb[2],values[3])*actor.tint
	color.a*=actor.visibility_amount*actor.fade_alpha
	var row=mini(int(frame),actor.clip.frames-1)
	var next=mini(row+1,actor.clip.frames-1)
	for index in range(emitter.nodes.size()):
		var node=emitter.nodes[index]
		if node.mesh!=mesh:node.mesh=mesh
		node.visible=color.a>0.001
		var material=node.material_override
		var material_id=int(source.MaterialID)
		var alpha=lerpf(actor.clip.layer_alphas[row][material_id][index],actor.clip.layer_alphas[next][material_id][index],frame-row)
		var state=[color,alpha]
		if node.get_meta("ribbon_state",[])!=state:
			node.set_meta("ribbon_state",state)
			material.set_shader_parameter("ribbon_color",color)
			material.set_shader_parameter("layer_alpha",alpha)
		var texture_id=int(actor.clip.layer_textures[row][material_id][index])
		if emitter.last_texture.size()<=index:emitter.last_texture.append(-1)
		if emitter.last_texture[index]!=texture_id:
			emitter.last_texture[index]=texture_id
			var texture=actor.data.textures[texture_id]
			var filename=str(texture.Image)
			if int(texture.ReplaceableId)==2:filename="ReplaceableTextures\\TeamGlow\\TeamGlow00.blp"
			material.set_shader_parameter("replaceable",int(texture.ReplaceableId))
			if filename!="":material.set_shader_parameter("source_texture",load(actor.texture_name(filename)))

func native_mesh(emitter: Dictionary,values: Array) -> ArrayMesh:
	accelerator.begin_geometry()
	accelerator.draw_ribbons(emitter.sections,emitter.source,clock,int(values[4]))
	if not emitter.has("geometry"):emitter.geometry=ArrayMesh.new()
	var mesh: ArrayMesh=emitter.geometry;mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,accelerator.geometry_arrays())
	return mesh

func packed_mesh(emitter: Dictionary,values: Array) -> ArrayMesh:
	var source=emitter.source
	var count=emitter.sections.size()
	var vertices=PackedVector3Array();vertices.resize(count*2)
	var uvs=PackedVector2Array();uvs.resize(count*2)
	var indices=PackedInt32Array();indices.resize((count-1)*6)
	var columns=maxi(1,int(source.Columns));var rows=maxi(1,int(source.Rows))
	var slot=clampi(int(values[4]),0,columns*rows-1)
	var height=1.0/rows;var tile_y=float(floori(float(slot)/columns))/rows
	var life=float(source.LifeSpan)
	for i in range(count):
		var section=emitter.sections[i];var age=maxf(0,clock-float(section.birth))
		var sag=Vector3.UP*(0.5*float(section.gravity)*age*age)
		vertices[i*2]=section.above-sag;vertices[i*2+1]=section.below-sag
		var uv=Vector2((float(slot%columns)+clampf(age/life,0,1))/columns,tile_y)
		uvs[i*2]=uv;uvs[i*2+1]=uv+Vector2(0,height)
		if i==count-1:continue
		var v=i*2;var offset=i*6
		indices[offset]=v;indices[offset+1]=v+1;indices[offset+2]=v+2
		indices[offset+3]=v+2;indices[offset+4]=v+1;indices[offset+5]=v+3
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_INDEX]=indices
	if not emitter.has("geometry"):emitter.geometry=ArrayMesh.new()
	var mesh: ArrayMesh=emitter.geometry;mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func legacy_mesh(emitter: Dictionary,values: Array) -> ImmediateMesh:
	var source=emitter.source
	var mesh=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var height=1.0/maxi(1,int(source.Rows))
	for i in range(emitter.sections.size()-1):
		var a=emitter.sections[i];var b=emitter.sections[i+1]
		var first=coordinates(source,int(values[4]),clock-a.birth);var second=coordinates(source,int(values[4]),clock-b.birth)
		var vertices=[section_point(a,"above"),section_point(a,"below"),section_point(b,"above"),section_point(b,"below")]
		var uv=[first,first+Vector2(0,height),second,second+Vector2(0,height)]
		for j in [0,1,2,2,1,3]:mesh.surface_set_uv(uv[j]);mesh.surface_add_vertex(vertices[j])
	mesh.surface_end()
	return mesh

func section_count() -> int:
	var count=0
	for emitter in emitters:count+=emitter.sections.size()
	return count
