extends RefCounted
## Batch identical additive emitters into one indexed mesh, retaining every
## original particle position, color, UV and lifetime. No gameplay changes.
var vertices=PackedVector3Array()
var colors=PackedColorArray()
var uvs=PackedVector2Array()
var indices=PackedInt32Array()
var mesh=ArrayMesh.new()
var accelerator=preload("res://scripts/acceleration.gd").create()

func begin():
	vertices.resize(0);colors.resize(0);uvs.resize(0)
	if accelerator!=null:accelerator.begin_geometry()

func quad(a: Vector3,b: Vector3,c: Vector3,d: Vector3,uv: Rect2,color: Color):
	vertices.append(a);vertices.append(b);vertices.append(c);vertices.append(d)
	colors.append(color);colors.append(color);colors.append(color);colors.append(color)
	uvs.append(uv.position);uvs.append(uv.position+Vector2(0,uv.size.y));uvs.append(uv.position+Vector2(uv.size.x,0));uvs.append(uv.end)

func commit(node: MeshInstance3D):
	if accelerator!=null:
		var accelerated: Array=accelerator.geometry_arrays()
		vertices=accelerated[Mesh.ARRAY_VERTEX];colors=accelerated[Mesh.ARRAY_COLOR]
		uvs=accelerated[Mesh.ARRAY_TEX_UV];indices=accelerated[Mesh.ARRAY_INDEX]
	mesh.clear_surfaces()
	node.visible=not vertices.is_empty()
	if vertices.is_empty():return
	var count: int=vertices.size()/4
	while indices.size()<count*6:
		var i: int=indices.size()/6*4
		indices.append(i);indices.append(i+1);indices.append(i+2);indices.append(i+2);indices.append(i+1);indices.append(i+3)
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_INDEX]=indices.slice(0,count*6)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	if node.mesh!=mesh:node.mesh=mesh
