extends SceneTree
const F=preload("res://scripts/native_float.gd")
func _initialize():
	var fixture=JSON.parse_string(FileAccess.get_file_as_string("res://research/native-float-checks.json"))
	var failed=[];var counts={}
	for v in fixture.checks:
		var out: int
		match v.operation:
			"sqrt":out=F.square_root(int(v.a))
			"multiply":out=F.multiply(int(v.a),int(v.b))
			"add":out=F.add(int(v.a),int(v.b))
			"subtract":out=F.subtract(int(v.a),int(v.b))
			"divide":out=F.divide(int(v.a),int(v.b))
			"acos":out=F.arc_cos(int(v.a))
			"angle_error":out=F.angle_error(int(v.a),int(v.b),int(v.facing))
		counts[v.operation]=counts.get(v.operation,0)+1
		if out!=int(v.original):failed.append({"operation":v.operation,"input":v,"godot":out})
	var file=FileAccess.open("res://research/native-float-tests.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"total":fixture.checks.size(),"counts":counts,"failures":failed,"scope":fixture.scope},"\t"))
	print("Native float vectors: ",fixture.checks.size(),"; mismatches: ",failed.size())
	if not failed.is_empty():print(failed.slice(0,3))
	quit(0 if failed.is_empty() else 1)
