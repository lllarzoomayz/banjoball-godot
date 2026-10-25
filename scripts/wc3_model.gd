extends Node3D
## Original MDX meshes, bones, ParticleEmitter2 and RibbonEmitter tracks.
## Legacy ParticleEmitter remains unsupported.
const WCParticles=preload("res://scripts/wc3_particles.gd")
const WCRibbons=preload("res://scripts/wc3_ribbons.gd")
const UVTracks=preload("res://scripts/wc3_uv.gd")
const EventTrack=preload("res://scripts/wc3_event_track.gd")
const WCLights=preload("res://scripts/wc3_lights.gd")
const LivePose=preload("res://scripts/wc3_live_pose.gd")
signal native_event(event: Dictionary,world_position: Vector3)
const CONVERSION=Basis(Vector3.RIGHT,Vector3(0,0,-1),Vector3.UP)
static var model_cache={}
static var shader_cache={}
static var pose_cache={}
static var pose_cache_frame=-1
static var accelerator=preload("res://scripts/acceleration.gd").create()
var data: Dictionary
var skeleton: Skeleton3D
var mesh_nodes: Array[MeshInstance3D]=[]
var material_states=[]
var frames=PackedFloat32Array()
var clip: Dictionary
var animation_time=0.0
var active_clip=""
var rate=1.0
var visibility_amount=1.0
var tint=Color.WHITE
var fade_alpha=1.0
var last_visual=[]
var particles
var ribbons
var lights
var team_color=Color.WHITE
var animation_cycle=0
var one_shot=false
var visual_time=0.0
var attachment_points={}
var use_native_billboards=true
var use_tail_optimization=true
var tail_only=false
var events_enabled=true
var event_start_pending=false

func vec(values: Array, index: int=0) -> Vector3:
	return Vector3(values[index],values[index+1],values[index+2])

func load_actor(id: String, color: Color, translucent: bool=false):
	team_color=color
	events_enabled=not translucent
	# Shared source data and immutable geometry; each actor keeps independent
	# bones and materials. Tackle produces up to 15 animated copies per caster.
	if not model_cache.has(id):
		model_cache[id]={"data":JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/"+id+".json")),
			"frames":FileAccess.get_file_as_bytes("res://assets/models/"+id+".wc3anim").to_float32_array(),"meshes":[]}
	var cached=model_cache[id]
	data=cached.data
	frames=cached.frames
	attachment_points.clear()
	for attachment in data.get("attachments",[]):
		var key=str(attachment.name).to_lower().replace("ref","").replace(" ","").replace("-","")
		if not attachment_points.has(key):attachment_points[key]=attachment
	skeleton=Skeleton3D.new()
	skeleton.name="OriginalSkeleton"
	add_child(skeleton)
	var skin=Skin.new()
	for i in range(data.bone_ids.size()):
		skeleton.add_bone("bone_"+str(int(data.bone_ids[i])))
		skeleton.set_bone_rest(i,Transform3D.IDENTITY)
		skin.add_bind(i,Transform3D.IDENTITY)
	if cached.meshes.is_empty():
		for geo in data.meshes:cached.meshes.append(build_mesh(geo))
	for i in range(data.meshes.size()):
		var geo=data.meshes[i]
		var instance=MeshInstance3D.new()
		instance.mesh=cached.meshes[i]
		instance.skin=skin
		skeleton.add_child(instance)
		instance.skeleton=NodePath("..")
		instance.material_override=make_material(data.materials[int(geo.material)],color,translucent)
		instance.custom_aabb=AABB(Vector3(-6,-6,-6),Vector3(12,16,12))
		if data.actor.get("scenery",false) or data.actor.get("source_bounds",false):
			var minimum=CONVERSION*vec(data.bounds.min)/100.0;var maximum=CONVERSION*vec(data.bounds.max)/100.0
			var source_box=AABB(minimum.min(maximum),(maximum-minimum).abs()).grow(.1)
			instance.custom_aabb=instance.custom_aabb.merge(source_box)
		if translucent:instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_nodes.append(instance)
		material_states.append([])
	scale=Vector3.ONE*float(data.actor.scale)
	if not data.get("emitters",[]).is_empty() and not translucent:
		particles=WCParticles.new();add_child(particles);particles.configure(self)
	if not data.get("ribbons",[]).is_empty() and not translucent:
		ribbons=WCRibbons.new();add_child(ribbons);ribbons.configure(self)
	if not data.get("lights",[]).is_empty() and not translucent:
		lights=WCLights.new();add_child(lights);lights.configure(self)
	if not play("Stand") and not data.clips.is_empty():play(data.clips[0].name)
	advance(0)

func set_team_color(color: Color):
	if team_color==color:return
	team_color=color
	for mesh in mesh_nodes:
		var material=mesh.material_override
		while material!=null:
			material.set_shader_parameter("team_color",color);material=material.next_pass
	if is_instance_valid(particles):
		for emitter in particles.emitters:
			var tex=data.textures[int(emitter.source.TextureID)]
			if int(tex.ReplaceableId) in [1,2] and emitter.mesh.material_override is StandardMaterial3D:emitter.mesh.material_override.albedo_color=color
	if is_instance_valid(ribbons):
		for emitter in ribbons.emitters:
			for node in emitter.nodes:node.material_override.set_shader_parameter("team_color",color)

func attachment_transform(name: String) -> Transform3D:
	var key=name.to_lower().replace(",","").replace(" ","")
	if not attachment_points.has(key):key="origin"
	if not attachment_points.has(key):return global_transform
	var attachment=attachment_points[key]
	# Baked bones are skin matrices. The attachment pivot must be transformed
	# too; using only matrix.origin leaves a resting foot at the unit's origin.
	var pose=skeleton.get_bone_pose(int(attachment.bone_index))
	pose.origin=pose*(CONVERSION*vec(attachment.pivot)/100.0)
	return global_transform*pose

func build_mesh(geo: Dictionary) -> ArrayMesh:
	var arrays=[]
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices=PackedVector3Array()
	var normals=PackedVector3Array()
	var uv=PackedVector2Array()
	var bones=PackedInt32Array()
	var weights=PackedFloat32Array()
	for i in range(geo.vertices.size()/3):
		vertices.append(CONVERSION*vec(geo.vertices,i*3)/100.0)
		normals.append(CONVERSION*vec(geo.normals,i*3))
		uv.append(Vector2(geo.uv[i*2],geo.uv[i*2+1]))
		var group=geo.groups[int(geo.vertex_group[i])]
		# Classic MDX averages every matrix in a group; retain up to 8.
		for j in range(8):
			bones.append(int(group[j]) if j<group.size() else 0)
			weights.append(1.0/group.size() if j<group.size() else 0.0)
	var indices=PackedInt32Array()
	for i in range(0,geo.faces.size(),3):
		# Godot uses clockwise front faces.
		indices.append_array([int(geo.faces[i]),int(geo.faces[i+2]),int(geo.faces[i+1])])
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uv
	arrays[Mesh.ARRAY_INDEX]=indices
	arrays[Mesh.ARRAY_BONES]=bones
	arrays[Mesh.ARRAY_WEIGHTS]=weights
	var mesh=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	return mesh

func texture_name(source: String) -> String:
	var regex=RegEx.new()
	regex.compile("[^a-z0-9._-]+")
	return "res://assets/textures/"+regex.sub(source.to_lower(),"_",true)+".png"

func make_material(material: Dictionary, color: Color, translucent: bool=false, explicit_layer: int=-1) -> Material:
	# Original layered art needs every pass, including duplicate glow passes.
	# Keep the established character compositing policy until those models are
	# individually checked; new source-faithful effects explicitly opt in.
	if explicit_layer<0 and data.actor.get("material_layer_passes",false):
		var first: Material
		var previous: Material
		for index in range(material.Layers.size()):
			var pass_material=make_material(material,color,translucent,index)
			if first==null:first=pass_material
			else:previous.next_pass=pass_material
			previous=pass_material
		return first
	var layer=material.Layers[0]
	var layer_index=0
	var team=false
	for candidate in material.Layers:
		var index=int(candidate.TextureID) if typeof(candidate.TextureID) in [TYPE_INT,TYPE_FLOAT] else 0
		if int(data.textures[index].ReplaceableId)==1: team=true
		if data.textures[index].Image!="": layer=candidate;layer_index=material.Layers.find(candidate)
	if explicit_layer>=0:
		layer_index=explicit_layer;layer=material.Layers[layer_index]
		team=false
	var tid=int(layer.TextureID) if typeof(layer.TextureID) in [TYPE_INT,TYPE_FLOAT] else 0
	var tex=data.textures[tid]
	var native_flags=int(layer.Shading)
	var filter_mode=int(layer.FilterMode)
	var shader_code="""shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform sampler2D skin_tex : source_color, filter_linear_mipmap;
uniform mat3 uv_transform = mat3(1.0);
uniform vec4 team_color : source_color = vec4(0.2,0.5,1.0,1.0);
uniform bool has_texture = true;
uniform bool team_under = false;
uniform bool alpha_cut = false;
uniform bool unlit = false;
uniform bool replaceable_glow = false;
uniform float opacity = 1.0;
uniform float model_alpha = 1.0;
uniform float visibility_amount = 1.0;
uniform vec4 display_tint : source_color = vec4(1.0);
uniform vec4 geoset_tint : source_color = vec4(1.0);
void fragment(){
 float stipple=mod(floor(FRAGCOORD.x),4.0)+4.0*mod(floor(FRAGCOORD.y),4.0);
 if(stipple/16.0>=visibility_amount) discard;
 vec4 t=has_texture ? texture(skin_tex,(uv_transform*vec3(UV,1.0)).xy) : team_color;
 if(replaceable_glow){float mask=max(t.r,max(t.g,t.b))*t.a;t=vec4(team_color.rgb*mask,mask);}
 if(alpha_cut && t.a<0.5) discard;
 vec3 rgb=team_under ? mix(team_color.rgb,t.rgb,t.a) : t.rgb;
 ALBEDO=rgb*display_tint.rgb*geoset_tint.rgb;
 ROUGHNESS=1.0;
 if(unlit){ EMISSION=rgb*display_tint.rgb*geoset_tint.rgb*0.4; }
}
"""
	if translucent:
		shader_code=shader_code.replace("specular_disabled;","specular_disabled, blend_mix, depth_draw_never;")
		shader_code=shader_code.replace("ROUGHNESS=1.0;","ROUGHNESS=1.0; ALPHA=(team_under ? 1.0 : t.a)*opacity*model_alpha;")
	elif filter_mode>=2 and not team:
		var blend_mode="blend_mul" if filter_mode in [5,6] else ("blend_add" if filter_mode in [3,4] else "blend_mix")
		shader_code=shader_code.replace("specular_disabled;","specular_disabled, depth_draw_never, "+blend_mode+";")
		shader_code=shader_code.replace("ROUGHNESS=1.0;","ROUGHNESS=1.0; ALPHA=t.a*opacity*model_alpha;")
		if filter_mode in [5,6]:
			shader_code=shader_code.replace("ALBEDO=rgb*display_tint.rgb*geoset_tint.rgb;","if(t.a*opacity*model_alpha<0.01)discard; ALBEDO=rgb*display_tint.rgb*geoset_tint.rgb"+("*2.0;" if filter_mode==6 else ";"))
	if native_flags&1:
		shader_code=shader_code.replace("cull_disabled,","unshaded, cull_disabled,")
		shader_code=shader_code.replace("if(unlit){ EMISSION=rgb*display_tint.rgb*geoset_tint.rgb*0.4; }","")
	if not shader_cache.has(shader_code):
		var shader=Shader.new();shader.code=shader_code;shader_cache[shader_code]=shader
	var mat=ShaderMaterial.new()
	mat.shader=shader_cache[shader_code]
	mat.set_shader_parameter("team_color",color)
	mat.set_shader_parameter("team_under",team)
	mat.set_shader_parameter("unlit",bool(native_flags&1))
	var source: String=tex.Image
	if int(tex.ReplaceableId)==2:source="ReplaceableTextures\\TeamGlow\\TeamGlow00.blp"
	mat.set_shader_parameter("replaceable_glow",int(tex.ReplaceableId)==2)
	var has_texture=source!="" and ResourceLoader.exists(texture_name(source))
	mat.set_shader_parameter("has_texture",has_texture)
	if has_texture: mat.set_shader_parameter("skin_tex",load(texture_name(source)))
	mat.set_shader_parameter("alpha_cut",filter_mode==1 and not team)
	mat.set_meta("source_layer",layer_index)
	return mat

func play(prefix: String, restart: bool=false) -> bool:
	for candidate in data.clips:
		if str(candidate.name).to_lower().begins_with(prefix.to_lower()):
			if active_clip!=candidate.name or restart:
				clip=candidate
				active_clip=candidate.name
				animation_time=0.0
				animation_cycle+=1
				event_start_pending=true
			return true
	return false

func play_keeper_jump():
	if data.actor.id!="h02C" and play("Attack Slam"):return
	if play("Attack"):return
	play("Spell Attack")

func advance(delta: float, wrap_clip: bool=true):
	if clip.is_empty(): return
	visual_time+=delta
	var old_time=animation_time
	animation_time+=delta*rate
	var duration=float(clip.duration)
	if delta*rate>0:
		if events_enabled:
			for event in EventTrack.crossed(clip.get("events",[]),old_time,delta*rate,maxf(duration,0.01),wrap_clip and clip.loop and not one_shot,event_start_pending):
				var world_position=global_transform*(CONVERSION*vec(event.position)/100.0)
				native_event.emit(event,world_position)
				get_tree().call_group("wc3_model_events","model_event",self,event,world_position)
		event_start_pending=false
	if wrap_clip and clip.loop and not one_shot:
		animation_cycle+=floori(animation_time/maxf(duration,0.01))
		animation_time=fmod(animation_time,maxf(duration,0.01))
	else: animation_time=minf(animation_time,duration)
	if is_instance_valid(lights):lights.advance()
	var frame=minf(animation_time*30,float(clip.frames)-1.001)
	var first=int(frame)
	var second=mini(first+1,int(clip.frames)-1)
	var blend=frame-first
	var count=data.bone_ids.size()
	if use_tail_optimization and one_shot and animation_time>=float(clip.get("visual_end",duration)):
		if not tail_only:
			for i in range(mesh_nodes.size()):mesh_nodes[i].hide();material_states[i]=[]
			last_visual=[];tail_only=true
		# No future mesh or emission is possible. Existing particles/ribbon
		# sections still integrate and render for their full original lifetime.
		if is_instance_valid(particles):particles.advance(delta,frame)
		if is_instance_valid(ribbons):ribbons.advance(delta,frame)
		return
	tail_only=false
	var visual=[active_clip,frame,visibility_amount,tint,fade_alpha]
	if not data.get("texture_animations",[]).is_empty():visual.append(visual_time)
	if not data.get("live_pose_nodes",[]).is_empty():visual.append(visual_time)
	if not data.get("billboards",[]).is_empty() or data.get("live_pose_camera",false):
		var camera=get_viewport().get_camera_3d()
		if camera:visual.append(camera.global_transform);visual.append(global_transform)
	if visual==last_visual:
		if is_instance_valid(particles):particles.advance(delta,frame)
		if is_instance_valid(ribbons):ribbons.advance(delta,frame)
		return
	var pose_changed=last_visual.is_empty() or last_visual[0]!=active_clip or last_visual[1]!=frame or not data.get("billboards",[]).is_empty()
	pose_changed=pose_changed or not data.get("live_pose_nodes",[]).is_empty()
	last_visual=visual
	if pose_changed:
		# Copies at identical animation times can share evaluation, but never a
		# Skeleton3D. Discard per-frame evaluations to keep the cache bounded.
		var render_frame=Engine.get_process_frames()
		if render_frame!=pose_cache_frame:
			pose_cache.clear();pose_cache_frame=render_frame
		var key=str(data.actor.id)+":"+active_clip
		if not pose_cache.has(key):pose_cache[key]={}
		var cached=pose_cache[key]
		if not cached.has(frame):
			if cached.size()>=64:cached.clear()
			var poses=[]
			if accelerator!=null:
				poses=accelerator.sample_pose(frames,int(clip.offset),count,first,second,blend)
			else:
				for i in range(count):
					var a=read_transform(int(clip.offset)+(first*count+i)*16)
					var b=read_transform(int(clip.offset)+(second*count+i)*16)
					var t=a.interpolate_with(b,blend)
					poses.append([t.origin,t.basis.get_rotation_quaternion(),t.basis.get_scale()])
			cached[frame]=poses
		var poses=cached[frame]
		if accelerator!=null:accelerator.apply_pose(skeleton,poses)
		else:
			for i in range(count):
				skeleton.set_bone_pose_position(i,poses[i][0])
				skeleton.set_bone_pose_rotation(i,poses[i][1])
				skeleton.set_bone_pose_scale(i,poses[i][2])
		apply_billboards()
		if not data.get("live_pose_nodes",[]).is_empty():LivePose.apply(self)
	for i in range(mesh_nodes.size()):
		var geo_opacity=lerpf(float(clip.alphas[first][i]),float(clip.alphas[second][i]),blend)
		var mat: Material=mesh_nodes[i].material_override
		var material_id=int(data.meshes[i].material)
		var geoset_color=Color.WHITE
		if clip.has("colors"):
			var a=clip.colors[first][i];var b=clip.colors[second][i]
			geoset_color=Color(a[0],a[1],a[2]).lerp(Color(b[0],b[1],b[2]),blend)
		var states=[];var any_visible=false;var pass_index=0
		while mat!=null:
			var layer_id=int(mat.get_meta("source_layer",0));var opacity=geo_opacity
			if clip.has("layer_alphas"):
				opacity*=lerpf(float(clip.layer_alphas[first][material_id][layer_id]),float(clip.layer_alphas[second][material_id][layer_id]),blend)
			var state=[opacity,fade_alpha,visibility_amount,tint,geoset_color]
			states.append(state);any_visible=any_visible or opacity>0.01
			if pass_index>=material_states[i].size() or state!=material_states[i][pass_index]:
				mat.set_shader_parameter("opacity",opacity)
				mat.set_shader_parameter("model_alpha",fade_alpha)
				mat.set_shader_parameter("visibility_amount",visibility_amount)
				mat.set_shader_parameter("display_tint",tint)
				mat.set_shader_parameter("geoset_tint",geoset_color)
			var layer=data.materials[material_id].Layers[layer_id]
			if layer.get("TVertexAnimId")!=null:
				var transform=UVTracks.transform(data.texture_animations[int(layer.TVertexAnimId)],float(clip.interval[0])+animation_time*1000,clip.interval,visual_time,data.global_sequences)
				mat.set_shader_parameter("uv_transform",transform)
			mat=mat.next_pass;pass_index+=1
		material_states[i]=states;mesh_nodes[i].visible=any_visible
	if is_instance_valid(particles):particles.advance(delta,frame)
	if is_instance_valid(ribbons):ribbons.advance(delta,frame)

func read_transform(i: int) -> Transform3D:
	var basis=Basis(Vector3(frames[i],frames[i+1],frames[i+2]),Vector3(frames[i+4],frames[i+5],frames[i+6]),Vector3(frames[i+8],frames[i+9],frames[i+10]))
	return Transform3D(CONVERSION*basis*CONVERSION.inverse(),CONVERSION*Vector3(frames[i+12],frames[i+13],frames[i+14])/100.0)

func visual_tail_finished() -> bool:
	var events=clip.get("events",[])
	if events_enabled and not events.is_empty() and (event_start_pending or animation_time<float(events[-1].time)):return false
	return one_shot and animation_time>=float(clip.get("visual_end",clip.duration)) and (not is_instance_valid(particles) or particles.particle_count()==0) and (not is_instance_valid(ribbons) or ribbons.section_count()<2)

func apply_billboards():
	if data.get("billboards",[]).is_empty():return
	var camera=get_viewport().get_camera_3d()
	if camera==null:return
	if use_native_billboards and accelerator!=null and accelerator.has_method("apply_billboards"):
		accelerator.apply_billboards(skeleton,data.billboards,global_transform,camera.global_basis)
		return
	for entry in data.get("billboards",[]):
		var pose=skeleton.get_bone_pose(int(entry.bone_index))
		var pivot=pose*(CONVERSION*vec(entry.pivot)/100.0)
		# MDX billboard planes face native +X. Godot camera looks down -Z.
		var rotation=global_basis.orthonormalized().inverse()*Basis(camera.global_basis.z,camera.global_basis.y,-camera.global_basis.x)
		var transform=Transform3D(rotation,pivot-rotation*pivot)
		for index in entry.affected:
			var result=transform*skeleton.get_bone_pose(int(index))
			skeleton.set_bone_pose_position(int(index),result.origin)
			skeleton.set_bone_pose_rotation(int(index),result.basis.get_rotation_quaternion())
			skeleton.set_bone_pose_scale(int(index),result.basis.get_scale())
