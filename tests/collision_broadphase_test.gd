extends SceneTree
const Fast=preload("res://scripts/arena_collision.gd")
const Reference=preload("res://tests/arena_collision_reference.gd")
func _initialize():call_deferred("run")
func run():
	var rng=RandomNumberGenerator.new();rng.seed=38173
	var failures=[]
	for i in range(10000):
		var start=Vector2(rng.randf_range(-200,200),rng.randf_range(-200,200))
		var move=Vector2(rng.randf_range(-500,500),rng.randf_range(-500,500)) if i%11 else Vector2.ZERO
		var rect=Rect2(Vector2(rng.randf_range(-100,100),rng.randf_range(-100,100)),Vector2(rng.randf_range(0,200),rng.randf_range(0,200)))
		var radius=rng.randf_range(0,60)
		var a=Fast.disk_rect_hit(start,move,rect,radius);var b=Reference.disk_rect_hit(start,move,rect,radius)
		if a!=b:failures.append(i)
	FileAccess.open("res://research/collision-broadphase-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":10000-failures.size(),"failures":failures},"\t"))
	print("BROADPHASE CHECKS ",10000-failures.size()," passed; ",failures.size()," failed")
	quit(0 if failures.is_empty() else 1)
