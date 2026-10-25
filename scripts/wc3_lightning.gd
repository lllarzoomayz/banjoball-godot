extends Node3D
## Original LightningData textures/width/color. Segment motion is presentation
## approximation; the original engine's lightning noise/UV timer is not ported.
var data=JSON.parse_string(FileAccess.get_file_as_string("res://research/lightning-assets.json"))
var nodes={}

func material_for(code: String) -> Material:
	var source=data[code]
	var mat=StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo=true
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED
	# ROPE's original BLP is opaque even in its black background (alpha=255).
	# Alpha blending therefore draws a solid black ribbon. Lightning's additive
	# composition makes black contribute nothing while retaining the rope weave.
	mat.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
	var regex=RegEx.new();regex.compile("[^a-z0-9._-]+")
	var filename="res://assets/textures/"+regex.sub(source.texture.to_lower(),"_",true)+".png"
	mat.albedo_texture=load(filename)
	return mat

func update_links(links: Array,time: float):
	var camera=get_viewport().get_camera_3d()
	if camera==null:return
	var groups={}
	for link in links:
		if link.a.distance_to(link.b)<0.1:continue
		if not groups.has(link.code):groups[link.code]=[]
		groups[link.code].append(link)
	for code in nodes:nodes[code].visible=groups.has(code)
	for code in groups:
		if not nodes.has(code):
			var node=MeshInstance3D.new();add_child(node)
			node.material_override=material_for(code)
			node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			nodes[code]=node
		var mesh=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var source=data[code]
		for link in groups[code]:
			var a=Vector3(link.a.x,link.a.z,-link.a.y)/100.0
			var b=Vector3(link.b.x,link.b.z,-link.b.y)/100.0
			var distance=a.distance_to(b)
			if distance<0.001:continue
			var side=(b-a).cross(camera.global_position-(a+b)/2).normalized()
			var count=maxi(1,ceili(distance*100/float(source.AvgSegLen)))
			var width=float(source.Width)/200.0
			var color=Color(source.R/255.0,source.G/255.0,source.B/255.0,source.A/255.0)*link.get("color",Color.WHITE)
			for i in range(count):
				var f0=float(i)/count;var f1=float(i+1)/count
				var p=a.lerp(b,f0)+side*sin(i*2.7+time*13)*float(source.NoiseScale)*sin(f0*PI)
				var q=a.lerp(b,f1)+side*sin((i+1)*2.7+time*13)*float(source.NoiseScale)*sin(f1*PI)
				var shift=time*float(source.TexCoordScale)
				var uv=[Vector2(f0*distance+shift,0),Vector2(f0*distance+shift,1),Vector2(f1*distance+shift,0),Vector2(f1*distance+shift,1)]
				var vertices=[p+side*width,p-side*width,q+side*width,q-side*width]
				for j in [0,1,2,2,1,3]:
					mesh.surface_set_color(color);mesh.surface_set_uv(uv[j]);mesh.surface_add_vertex(vertices[j])
		mesh.surface_end();nodes[code].mesh=mesh;nodes[code].visible=true
