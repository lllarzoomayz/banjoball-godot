extends Node3D
## Classic MDX ParticleEmitter2 presentation. Source tracks are sampled at 30 Hz;
## particle integration is local to rendering and never changes match RNG/state.
const CONVERSION=Basis(Vector3.RIGHT,Vector3(0,0,-1),Vector3.UP)
const MAX_PARTICLES=512
var actor
var emitters=[]
var rng=RandomNumberGenerator.new()
var emitting=true
var batch_geometry
var use_native_geometry=true
var use_native_emission=true
var defer_geometry=false
var use_native_simulation=true
static var accelerator=preload("res://scripts/acceleration.gd").create()
static var constant_track_cache={}
var track_clip=""
var constant_tracks=[]

func configure(model):
	actor=model
	rng.seed=hash(str(model.data.actor.id))
	top_level=true
	global_transform=Transform3D.IDENTITY
	for source in model.data.get("emitters",[]):
		var mesh=MeshInstance3D.new()
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.material_override=make_material(source)
		add_child(mesh)
		emitters.append({"source":source,"mesh":mesh,"particles":[],"credit":0.0,"key":"","capacity":clampi(int(actor.data.actor.get("particle_capacity",MAX_PARTICLES)),1,4096)})

func make_material(source: Dictionary) -> Material:
	var mat=StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo=true
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED
	var filter_mode=int(source.FilterMode)
	if filter_mode==1:mat.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
	elif filter_mode in [2,3]:mat.blend_mode=BaseMaterial3D.BLEND_MODE_MUL
	elif filter_mode==4:
		mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold=0.75
	var tex=actor.data.textures[int(source.TextureID)]
	var name=str(tex.Image)
	if int(tex.ReplaceableId)==2:name="ReplaceableTextures\\TeamGlow\\TeamGlow00.blp"
	if name!="" and ResourceLoader.exists(actor.texture_name(name)):mat.albedo_texture=load(actor.texture_name(name))
	if int(tex.ReplaceableId) in [1,2]:mat.albedo_color=actor.team_color
	if filter_mode in [2,3,4]:
		var shader=Shader.new()
		shader.code="""shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, BLENDING;
uniform sampler2D source_texture : source_color, filter_linear_mipmap;
void fragment(){
 vec4 t=texture(source_texture,UV)*COLOR;
 if(t.a<CUTOFF)discard;
 ALBEDO=t.rgb*GAIN;
 ALPHA=t.a;
}
""".replace("BLENDING","blend_add" if filter_mode==4 else "blend_mul").replace("CUTOFF","0.75" if filter_mode==4 else "0.01").replace("GAIN","2.0" if filter_mode==3 else "1.0")
		var special=ShaderMaterial.new();special.shader=shader
		special.set_shader_parameter("source_texture",mat.albedo_texture)
		return special
	return mat

func values_for(index: int,frame: float) -> Array:
	var rows=actor.clip.get("emitters",[])
	if rows.is_empty():return []
	if track_clip!=actor.active_clip:
		track_clip=actor.active_clip
		var key=str(actor.data.actor.id)+":"+track_clip
		if not constant_track_cache.has(key):
			var tracks=[]
			for e in range(rows[0].size()):
				var same=true
				for row in rows:
					if row[e]!=rows[0][e]:same=false;break
				tracks.append(rows[0][e] if same else [])
			constant_track_cache[key]=tracks
		constant_tracks=constant_track_cache[key]
	if not constant_tracks[index].is_empty():return constant_tracks[index]
	var a=mini(int(frame),rows.size()-1)
	var b=mini(a+1,rows.size()-1)
	var result=[]
	for column in range(10):
		result.append(lerpf(rows[a][index][column],rows[b][index][column],frame-a) if column in [1,2,3,4,5,6,7] else rows[a][index][column])
	return result

func advance(delta: float,frame: float):
	visible=actor.visible
	if use_native_simulation and accelerator!=null and accelerator.has_method("advance_emitters"):
		var active=emitting and ((actor.clip.loop and not actor.one_shot) or actor.animation_time<float(actor.clip.duration))
		accelerator.advance_emitters(emitters,actor.clip.get("emitters",[]),frame,delta,actor.skeleton,actor.global_transform,actor.active_clip,actor.animation_cycle,active,actor.visible,rng)
		if not defer_geometry:
			for emitter in emitters:draw_emitter(emitter)
		return
	for index in range(emitters.size()):
		var emitter=emitters[index]
		var source=emitter.source
		var values=values_for(index,frame)
		if values.is_empty():continue
		# Hidden/stealthed enemies must not leave revealing particles behind.
		if not actor.visible:
			emitter.particles.clear();emitter.credit=0;continue
		if delta>0:
			if accelerator!=null:
				emitter.particles=accelerator.integrate_particles(emitter.particles,delta,float(source.LifeSpan))
			else:
				for particle in emitter.particles:
					particle.age+=delta
					particle.velocity.y-=particle.gravity*delta
					particle.pos+=particle.velocity*delta
				emitter.particles=emitter.particles.filter(func(p):return p.age<float(source.LifeSpan))
			if emitting and values[0]>0 and ((actor.clip.loop and not actor.one_shot) or actor.animation_time<float(actor.clip.duration)):
				if source.Squirt and values[8]>=0:
					var key=actor.active_clip+":"+str(actor.animation_cycle)+":"+str(values[8])
					if key!=emitter.key:emitter.key=key;emitter.credit+=maxf(0,values[9])
				else:emitter.credit+=maxf(0,values[5])*delta
				var count=maxi(0,mini(int(emitter.credit),int(emitter.get("capacity",MAX_PARTICLES))-emitter.particles.size()))
				emitter.credit-=floor(emitter.credit)
				emit_particles(emitter,values,count)
		if not defer_geometry:draw_emitter(emitter)

func emit_particles(emitter: Dictionary,values: Array,count: int):
	if count<=0:return
	if use_native_emission and accelerator!=null and accelerator.has_method("spawn_particles"):
		accelerator.spawn_particles(emitter.particles,emitter.source,values,actor.skeleton.get_bone_pose(int(emitter.source.bone_index)),actor.global_transform,rng,count)
	else:
		for n in range(count):spawn(emitter,values)

func spawn(emitter: Dictionary,values: Array):
	var source=emitter.source
	if float(source.LifeSpan)<=0:return
	var pivot=source.PivotPoint
	var local=Vector3(pivot[0]+rng.randf_range(-values[6],values[6]),pivot[1]+rng.randf_range(-values[7],values[7]),pivot[2])
	var speed=float(values[1])*(1+rng.randf_range(-values[2],values[2]))
	var angle=rng.randf_range(0,TAU)
	var velocity=Vector3(0,0,speed).rotated(Vector3.UP,rng.randf_range(0,deg_to_rad(values[3]))).rotated(Vector3.BACK,angle)
	if int(source.Flags)&131072:velocity.x=0
	var pose=actor.skeleton.get_bone_pose(int(source.bone_index))
	var point=pose*(CONVERSION*local/100.0)
	velocity=pose.basis*(CONVERSION*velocity/100.0)
	var model_space=bool(int(source.Flags)&524288)
	var size_scale=1.0 if model_space else actor.global_basis.get_scale().x
	if not model_space:
		point=actor.global_transform*point
		velocity=actor.global_basis*velocity
	emitter.particles.append({"pos":point,"velocity":velocity,"age":0.0,"angle":angle,"scale":size_scale,"gravity":float(values[4])/100.0*size_scale})

func color_at(source: Dictionary,segment: int,blend: float) -> Color:
	var a=source.SegmentColor[segment];var b=source.SegmentColor[segment+1]
	return Color(a[0],a[1],a[2],source.Alpha[segment]/255.0).lerp(Color(b[0],b[1],b[2],source.Alpha[segment+1]/255.0),blend)

func tile(source: Dictionary,track: Array,blend: float) -> Rect2:
	var columns=maxi(1,int(source.Columns));var rows=maxi(1,int(source.Rows))
	var count=maxi(1,int(track[1])-int(track[0]))
	var repeats=maxi(1,int(track[2]))
	var frame=int(track[0])+mini(count-1,int(blend*count*repeats)%count)
	frame=clampi(frame,0,columns*rows-1)
	return Rect2(float(frame%columns)/columns,float(floori(float(frame)/columns))/rows,1.0/columns,1.0/rows)

func quad(mesh: ImmediateMesh,vertices: Array,uv: Rect2,color: Color):
	var coords=[uv.position,uv.position+Vector2(0,uv.size.y),uv.position+Vector2(uv.size.x,0),uv.end]
	for i in [0,1,2,2,1,3]:
		mesh.surface_set_color(color)
		mesh.surface_set_uv(coords[i])
		mesh.surface_add_vertex(vertices[i])

func draw_emitter(emitter: Dictionary):
	var node=emitter.mesh
	if emitter_count(emitter)==0:node.visible=false;return
	var camera=get_viewport().get_camera_3d()
	if camera==null:return
	var shared_geometry=emitter.get("batch_geometry",batch_geometry)
	if shared_geometry!=null:
		node.visible=false
		draw_batched(emitter,camera,shared_geometry)
		return
	# Keep separate materials/buff transforms, but submit each emitter's vertices
	# in one native call instead of rebuilding ImmediateMesh vertex by vertex.
	if use_native_geometry and accelerator!=null:
		if not emitter.has("geometry"):
			emitter.geometry=preload("res://scripts/particle_geometry.gd").new()
		var geometry=emitter.geometry
		geometry.begin()
		draw_batched(emitter,camera,geometry)
		geometry.commit(node)
		return
	node.visible=true
	var mesh=ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var source=emitter.source
	for particle in emitter.particles:
		var t=clampf(particle.age/float(source.LifeSpan),0,1)
		var midpoint=clampf(float(source.Time),0.0001,0.9999)
		var segment=0 if t<midpoint else 1
		var blend=t/midpoint if segment==0 else (t-midpoint)/(1-midpoint)
		var color=color_at(source,segment,blend)*actor.tint
		color.a*=actor.fade_alpha*actor.visibility_amount
		var size=lerpf(source.ParticleScaling[segment],source.ParticleScaling[segment+1],blend)/100.0*particle.scale
		var pos: Vector3=particle.pos
		var velocity: Vector3=particle.velocity
		if int(source.Flags)&524288:
			pos=actor.global_transform*pos;velocity=actor.global_basis*velocity;size*=actor.global_basis.get_scale().x
		if int(source.FrameFlags)&1:
			var right=camera.global_basis.x*size;var up=camera.global_basis.y*size
			if int(source.Flags)&1048576:
				right=Vector3.RIGHT.rotated(Vector3.UP,particle.angle)*size
				up=Vector3.FORWARD.rotated(Vector3.UP,particle.angle)*size
			quad(mesh,[pos-right+up,pos-right-up,pos+right+up,pos+right-up],tile(source,source.LifeSpanUVAnim if segment==0 else source.DecayUVAnim,blend),color)
		if int(source.FrameFlags)&2:
			var end=pos-velocity*float(source.TailLength)
			var side=velocity.cross(camera.global_position-pos).normalized()*size
			quad(mesh,[pos+side,pos-side,end+side,end-side],tile(source,source.TailUVAnim if segment==0 else source.TailDecayUVAnim,blend),color)
	mesh.surface_end()
	node.mesh=mesh

func draw_batched(emitter: Dictionary,camera: Camera3D,geometry):
	var source=emitter.source
	if geometry.accelerator!=null:
		if emitter.has("packed"):
			geometry.accelerator.draw_packed_particles(emitter.packed,source,actor.global_transform,actor.tint,actor.fade_alpha*actor.visibility_amount,camera.global_basis.x,camera.global_basis.y,camera.global_position)
		else:geometry.accelerator.draw_particles(emitter.particles,source,actor.global_transform,actor.tint,actor.fade_alpha*actor.visibility_amount,camera.global_basis.x,camera.global_basis.y,camera.global_position)
		return
	var life: float=source.LifeSpan;var midpoint=clampf(float(source.Time),0.0001,0.9999)
	var transform: Transform3D=actor.global_transform;var scale: float=transform.basis.get_scale().x
	var model_space: bool=(int(source.Flags)&524288)!=0
	var head: bool=(int(source.FrameFlags)&1)!=0;var tail: bool=(int(source.FrameFlags)&2)!=0
	var xy_quad: bool=(int(source.Flags)&1048576)!=0
	var right: Vector3=camera.global_basis.x;var up: Vector3=camera.global_basis.y;var eye: Vector3=camera.global_position
	var alpha: float=actor.fade_alpha*actor.visibility_amount
	for particle in emitter.particles:
		var t=clampf(particle.age/life,0,1);var segment=0 if t<midpoint else 1
		var blend=t/midpoint if segment==0 else (t-midpoint)/(1-midpoint)
		var color=color_at(source,segment,blend)*actor.tint;color.a*=alpha
		var size=lerpf(source.ParticleScaling[segment],source.ParticleScaling[segment+1],blend)/100.0*particle.scale
		var pos: Vector3=particle.pos;var velocity: Vector3=particle.velocity
		if model_space:pos=transform*pos;velocity=transform.basis*velocity;size*=scale
		if head:
			var r=right*size;var u=up*size
			if xy_quad:r=Vector3.RIGHT.rotated(Vector3.UP,particle.angle)*size;u=Vector3.FORWARD.rotated(Vector3.UP,particle.angle)*size
			geometry.quad(pos-r+u,pos-r-u,pos+r+u,pos+r-u,tile(source,source.LifeSpanUVAnim if segment==0 else source.DecayUVAnim,blend),color)
		if tail:
			var end=pos-velocity*float(source.TailLength);var side=velocity.cross(eye-pos).normalized()*size
			geometry.quad(pos+side,pos-side,end+side,end-side,tile(source,source.TailUVAnim if segment==0 else source.TailDecayUVAnim,blend),color)

static func emitter_count(emitter: Dictionary) -> int:
	return int(emitter.packed.size()/10) if emitter.has("packed") else emitter.particles.size()

func particle_count() -> int:
	var count=0
	for emitter in emitters:count+=emitter_count(emitter)
	return count
