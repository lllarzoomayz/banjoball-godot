extends RefCounted
## Native destructable lifecycle, independent of the renderer's field crop.
## Absolute Warcraft coordinates. Dead objects remain enumerable; removed
## objects do not. The caller supplies one gameplay RNG, never a visual RNG.
static var source={}
var objects={}
var next_id=0
var field={}
var initial_bounds=[]

static func data() -> Dictionary:
	if source.is_empty():source=JSON.parse_string(FileAccess.get_file_as_string("res://assets/scenery/apocalypse-world.json"))
	return source

static func contains(bounds: Array,p: Vector2) -> bool:
	# RectContainsCoords includes the upper edges, unlike Rect2.has_point.
	return p.x>=bounds[0] and p.y>=bounds[1] and p.x<=bounds[2] and p.y<=bounds[3]

static func generate_ice(rng) -> Array:
	var rows=[]
	for center in data().generated_ice_centers:
		var kind="B00"+str(rng.randi_range(1,5))
		var x=center[0]+rng.randf_range(-400,400);var y=center[1]+rng.randf_range(-400,400)
		var angle=rng.randf_range(0,TAU);var size=rng.randf_range(.9,1.2)
		rows.append({"id":kind,"position":[x,y,900],"angle":angle,"scale":[size,size,size],"variation":0,"life":100,"editor_id":-1,"generated":"FrozenIce","generated_index":rows.size()})
	return rows

func setup(field_index: int,rng,ice_rows=null):
	objects.clear();next_id=0
	var input=data();field=input.fields[field_index];initial_bounds=input.initial_playable_bounds
	for row in input.placed:add(row)
	var frozen=field.id in ["Frozen","Frozen_Coast"]
	for row in input.generated_water:
		if (row.generated=="Frozen")==frozen:add(row)
	if frozen:
		for row in (generate_ice(rng) if ice_rows==null else ice_rows):add(row)

func add(row: Dictionary) -> Dictionary:
	next_id+=1
	var copy=row.duplicate(true);copy.uid=next_id
	copy.alive=float(copy.get("life",100))>0
	objects[next_id]=copy
	return copy

func remove(uid: int) -> bool:
	return objects.erase(uid)

func find_editor(editor_id: int) -> Dictionary:
	if editor_id<0:return {}
	for row in objects.values():
		if int(row.get("editor_id",-1))==editor_id:return row
	return {}

func remove_blockers() -> Array:
	var removed=[]
	for row in objects.values():
		if row.id=="YTpb" and contains(initial_bounds,Vector2(row.position[0],row.position[1])):
			removed.append(row);objects.erase(row.uid)
	return removed

func candidates() -> Array:
	var result=[]
	for row in objects.values():
		if contains(field.zone,Vector2(row.position[0],row.position[1])):result.append(row)
	return result

func random_tree_pull(rng) -> Dictionary:
	var pool=candidates()
	if pool.is_empty():return {"empty":true}
	# Uniform choice matches RandomDestructableInRectBJ's distribution. Native
	# handle enumeration/RNG sequence is not claimed to be bit-identical.
	var chosen=pool[rng.randi_range(0,pool.size()-1)]
	if chosen.id not in ["LTlt","WTst"]:return {"empty":false,"selected":chosen.uid}
	return lift(chosen.uid,rng.randi_range(0,9))

func lift(uid: int,variation: int) -> Dictionary:
	if not objects.has(uid) or variation<0 or variation>9:return {}
	var original=objects[uid]
	if original.id not in ["LTlt","WTst"]:return {}
	var p=original.position;var height=ground_height(Vector2(p[0],p[1]))
	var dead=add({"id":original.id,"position":[p[0],p[1],height],"angle":deg_to_rad(270),"scale":[1.2,1.2,1.2],
		"variation":variation,"life":0,"editor_id":-1,"original_editor":original.get("original_editor",original.get("editor_id",-1))})
	remove(uid)
	return {"empty":false,"selected":uid,"removed":original,"replacement":dead,
		"tree":{"rawcode":"h00V" if original.id=="LTlt" else "h00W","model":"h01K" if original.id=="LTlt" else "h01L",
			"position":Vector3(p[0],p[1],height),"facing":deg_to_rad(270),"radius":0.0}}

func kill_all() -> Array:
	var killed=[]
	for row in objects.values():
		if row.alive and contains(initial_bounds,Vector2(row.position[0],row.position[1])):
			row.alive=false;row.life=0;killed.append(row)
	return killed

func ground_height(point: Vector2) -> float:
	var terrain=data().terrain;var nx=int(terrain.size[0]);var ny=int(terrain.size[1])
	var p=(point-Vector2(terrain.origin[0],terrain.origin[1]))/128.0
	p=Vector2(clampf(p.x,0,nx-1.00001),clampf(p.y,0,ny-1.00001))
	var x=int(p.x);var y=int(p.y);var u=p.x-x;var v=p.y-y;var h=terrain.heights
	var a=float(h[y*nx+x]);var b=float(h[y*nx+x+1]);var c=float(h[(y+1)*nx+x]);var d=float(h[(y+1)*nx+x+1])
	# Same source triangles as FieldScenery, not a claim about native cliff
	# recovery / GetTerrainZ rounding at discontinuities.
	return a+(b-a)*u+(c-a)*v if u+v<=1 else d+(c-d)*(1-u)+(b-d)*(1-v)
