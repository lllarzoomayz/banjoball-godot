extends SceneTree
const Fast=preload("res://scripts/native_grid_search.gd")
const Reference=preload("res://tests/native_grid_search_reference.gd")
const Sim=preload("res://scripts/match_sim.gd")
var passed=0
var failures=[]
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func _initialize():call_deferred("run")
func run():
	var rng=RandomNumberGenerator.new();rng.seed=271827
	var grid=AStarGrid2D.new();grid.region=Rect2i(-4,-3,35,27);grid.cell_size=Vector2(32,32);grid.offset=Vector2(16,16);grid.update()
	var fast=Fast.new();var reference=Reference.new()
	for fixture in range(100):
		for y in range(-3,24):
			for x in range(-4,31):grid.set_point_solid(Vector2i(x,y),rng.randf()<0.28)
		var start=Vector2i(rng.randi_range(-4,30),rng.randi_range(-3,23));var goal=Vector2i(rng.randi_range(-4,30),rng.randi_range(-3,23))
		grid.set_point_solid(start,false)
		check(fast.find_path(grid,start,goal,Vector2(8,8))==reference.find_path(grid,start,goal,Vector2(8,8)),"original ordered route and partial endpoint "+str(fixture))
	var sim=Sim.new()
	for field in range(4):
		for course in range(5):
			sim.arena.set_field(field);sim.arena.set_course(course)
			var dimensions=Vector2i(sim.arena.bounds.size/32)+Vector2i(2,2)
			sim.grid.region=Rect2i(Vector2i.ZERO,dimensions);sim.grid.cell_size=Vector2(32,32)
			sim.grid.offset=Sim.Native.fine_grid_point(Vector2i.ZERO,sim.arena.bounds.position-Vector2(32,32));sim.grid.update()
			if course==4:sim.arena.pillars.append({"center":Vector2(0,0),"radius":82.0})
			var radius=34.0 if course%2==0 else 52.0
			var base=sim.make_navigation_base(dimensions,radius);var equal=true
			for y in range(dimensions.y):
				for x in range(dimensions.x):
					if (base[y*dimensions.x+x]==0)!=sim.arena.point_free(sim.grid.get_point_position(Vector2i(x,y)),radius):equal=false
			check(equal,"every occupancy cell matches original geometry field %d course %d"%[field,course])
	FileAccess.open("res://research/performance-navigation-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("NAVIGATION CHECKS ",passed," passed; ",failures.size()," failed")
	quit(1 if not failures.is_empty() else 0)
