extends SceneTree
const UVTracks=preload("res://scripts/wc3_uv.gd")
const Model=preload("res://scripts/wc3_model.gd")
var checks=[]
var failed=false
func check(ok: bool,label: String,detail=""):
	checks.append({"test":label,"passed":ok,"detail":str(detail)});failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+label+" "+str(detail))
func _initialize():call_deferred("run")
func run():
	var data=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/h012.json"))
	var reference=JSON.parse_string(FileAccess.get_file_as_string("res://research/uv-reference.json"))
	var error=0.0
	for row in reference.rows:
		var actual=UVTracks.transform(data.texture_animations[int(row.animation)],row.frame,row.interval,row.seconds,data.global_sequences)
		for pair in [[actual.x.x,0],[actual.x.y,1],[actual.y.x,3],[actual.y.y,4],[actual.z.x,6],[actual.z.y,7]]:error=maxf(error,absf(pair[0]-row.matrix[int(pair[1])]))
	check(error<0.00001,"original four texture tracks match 144 independent upstream matrices",error)
	var actor=Model.new();root.add_child(actor);actor.load_actor("h012",Color.WHITE)
	var animated=[]
	for i in range(actor.mesh_nodes.size()):
		var material=actor.mesh_nodes[i].material_override
		var layer=actor.data.materials[int(actor.data.meshes[i].material)].Layers[int(material.get_meta("source_layer"))]
		if layer.get("TVertexAnimId")!=null:animated.append(material)
	check(animated.size()>0,"real sorceress mesh materials receive original UV animation")
	var initial=animated.map(func(m):return m.get_shader_parameter("uv_transform"))
	actor.advance(0.251)
	var moved=animated.map(func(m):return m.get_shader_parameter("uv_transform"))
	check(initial!=moved,"global texture atlas advances while model is standing")
	actor.advance(0)
	check(animated.map(func(m):return m.get_shader_parameter("uv_transform"))==moved,"pause holds actual material texture frames")
	actor.play("Walk");actor.advance(0)
	check(animated.map(func(m):return m.get_shader_parameter("uv_transform"))==moved,"changing unit animation does not reset global texture clock")
	var plain=Model.new();root.add_child(plain);plain.load_actor("h005",Color.WHITE);plain.advance(0.5)
	check(plain.data.texture_animations.is_empty() and plain.mesh_nodes[0].material_override.get_shader_parameter("uv_transform")==null,"models without animated UV retain identity shader default")
	actor.free();plain.free()
	FileAccess.open("res://research/uv-animation-tests.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks},"\t"))
	quit(1 if failed else 0)
