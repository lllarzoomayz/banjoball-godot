extends SceneTree
const Visibility=preload("res://scripts/native_visibility.gd")
var checks=[]
var failed=false

func check(ok: bool,name: String,detail=""):
	checks.append({"test":name,"passed":ok,"detail":str(detail)})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))

func _initialize():call_deferred("run")

func inspect(row: Dictionary,ray: bool) -> bool:
	var queries=[]
	var blocked=[]
	for xy in row.blocked:blocked.append(Vector2i(xy[0],xy[1]))
	var walkable=func(cell):
		queries.append([cell.x,cell.y])
		return cell.x>=0 and cell.y>=0 and cell.x<32 and cell.y<32 and cell not in blocked
	var clear=false
	if ray:clear=Visibility.ray_clear(Vector2(row.origin[0],row.origin[1]),Vector2(row.step[0],row.step[1]),row.length,int(row.mode),walkable)
	else:clear=Visibility.transition_clear(Vector2i(12,12),int(row.mask),int(row.mode),walkable)
	if clear!=row.native_clear or queries.size()!=row.native_queries.size():return false
	for i in range(queries.size()):
		if queries[i][0]!=int(row.native_queries[i][0]) or queries[i][1]!=int(row.native_queries[i][1]):return false
	return true

func run():
	var fixture=JSON.parse_string(FileAccess.get_file_as_string("res://research/native-visibility-ray.json"))
	var ray_mismatches=[];var footprint_mismatches=[]
	for i in range(fixture.checks.size()):
		if not inspect(fixture.checks[i],true):ray_mismatches.append(i)
	for i in range(fixture.footprints.size()):
		if not inspect(fixture.footprints[i],false):footprint_mismatches.append(i)
	check(fixture.checks.size()==756 and ray_mismatches.is_empty(),"756 original fine-ray results and complete cell query orders match",ray_mismatches)
	check(fixture.footprints.size()==116 and footprint_mismatches.is_empty(),"116 original directional footprints and early stops match",footprint_mismatches)
	var calls=[]
	var all_clear=func(cell):calls.append(cell);return true
	check(Visibility.ray_clear(Vector2(8.25,8.75),Vector2.RIGHT,1.0,1,all_clear) and calls.is_empty(),"one-cell ray does not inspect its start or endpoint")
	Visibility.ray_clear(Vector2(8.25,8.75),Vector2.RIGHT,2.0,1,all_clear)
	check(calls==[Vector2i(7,8),Vector2i(8,8),Vector2i(9,8),Vector2i(9,6),Vector2i(9,7)],"first changed cell retains original zero-origin direction-mask behavior",calls)
	calls.clear()
	var blocked_side=func(cell):calls.append(cell);return cell!=Vector2i(10,11)
	check(not Visibility.transition_clear(Vector2i(12,12),3,1,blocked_side) and calls==[Vector2i(10,11)],"diagonal footprint rejects its first side cell without testing later cells")
	check(not Visibility.ray_clear(Vector2(INF,0),Vector2.RIGHT,10,0,all_clear) and not Visibility.ray_clear(Vector2.ZERO,Vector2.RIGHT,INF,0,all_clear),"diagnostic adapter rejects non-finite input")
	check(not Visibility.transition_clear(Vector2i.ZERO,0,2,all_clear),"unported radius class is explicit rather than silently using a smaller footprint")
	FileAccess.open("res://research/native-visibility-tests.json",FileAccess.WRITE).store_string(JSON.stringify({"scope":fixture.scope,"checks":checks},"\t"))
	quit(1 if failed else 0)
