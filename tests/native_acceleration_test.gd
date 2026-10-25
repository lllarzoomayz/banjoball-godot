extends SceneTree
const Model=preload("res://scripts/wc3_model.gd")
const Search=preload("res://scripts/native_grid_search.gd")
var passed=0
var failures=[]
func check(ok: bool,label: String):
	if ok:passed+=1
	else:failures.append(label);printerr("FAIL "+label)
func _initialize():call_deferred("run")
func run():
	check(ClassDB.class_exists("BanjoAccelerator"),"native library is actually loaded")
	if not failures.is_empty():quit(1);return
	var native=ClassDB.instantiate("BanjoAccelerator")
	var sampled_bones=0
	for name in DirAccess.get_files_at("res://assets/models"):
		if not name.ends_with(".json"):continue
		var model=Model.new()
		model.data=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/"+name))
		model.frames=FileAccess.get_file_as_bytes("res://assets/models/"+name.trim_suffix(".json")+".wc3anim").to_float32_array()
		var count=model.data.bone_ids.size()
		for clip in model.data.clips:
			for fraction in [0.0,0.37,0.93]:
				var frame=fraction*(int(clip.frames)-1);var first=int(frame);var second=mini(first+1,int(clip.frames)-1)
				var poses: Array=native.sample_pose(model.frames,int(clip.offset),count,first,second,frame-first)
				var equal=poses.size()==count
				for i in range(count):
					var a=model.read_transform(int(clip.offset)+(first*count+i)*16)
					var b=model.read_transform(int(clip.offset)+(second*count+i)*16)
					if a.basis.determinant()==0 or b.basis.determinant()==0:
						# Zero-scale bones are hidden in the original Death clip.
						# They must yield finite poses, with identity at zero scale.
						equal=equal and poses[i][0].is_finite() and poses[i][1].is_finite() and poses[i][2].is_finite()
						if poses[i][2]==Vector3.ZERO:equal=equal and poses[i][1].is_equal_approx(Quaternion.IDENTITY)
						sampled_bones+=1
						continue
					var reference=a.interpolate_with(b,frame-first)
					# Compare decomposition rather than rebuilding matrices with shear.
					equal=equal and reference.origin.distance_to(poses[i][0])<0.00001 and reference.basis.get_scale().distance_to(poses[i][2])<0.00001 and absf(reference.basis.get_rotation_quaternion().dot(poses[i][1]))>0.99999
					sampled_bones+=1
				check(equal,name+" "+str(clip.name)+" "+str(fraction))
		model.free()
	var rng=RandomNumberGenerator.new();rng.seed=44591
	var particles=[]
	for i in range(200):particles.append({"age":rng.randf_range(0,0.4),"gravity":rng.randf_range(-5,20),"velocity":Vector3(rng.randf(),rng.randf(),rng.randf()),"pos":Vector3(rng.randf(),rng.randf(),rng.randf()),"angle":0.0,"scale":1.0})
	var reference=particles.duplicate(true)
	for frame in range(45):
		var delta=0.016 if frame%4!=0 else 0.033
		for p in reference:
			p.age+=delta;p.velocity.y-=p.gravity*delta;p.pos+=p.velocity*delta
		reference=reference.filter(func(p):return p.age<0.7)
		particles=native.integrate_particles(particles,delta,0.7)
		var equal=particles.size()==reference.size()
		for i in range(particles.size()):equal=equal and particles[i].pos.distance_to(reference[i].pos)<0.00001 and particles[i].velocity.distance_to(reference[i].velocity)<0.00001 and particles[i].age==reference[i].age
		check(equal,"particle integration/lifetime variable delta "+str(frame))
	check(native.find_cells(0,20,0,1,PackedByteArray()).is_empty(),"invalid grids rejected")
	check(native.sample_pose(PackedFloat32Array(),0,2,0,1,0.5).is_empty(),"invalid pose bounds rejected")
	# Unreachable targets trigger the costly full search, not just easy paths.
	var grid=AStarGrid2D.new();grid.region=Rect2i(0,0,180,140);grid.cell_size=Vector2(32,32);grid.update()
	var bits=PackedByteArray();bits.resize(180*140)
	for y in range(140):grid.set_point_solid(Vector2i(90,y),true);bits[y*180+90]=1
	var script=Search.new();script.accelerator=null;var fast=Search.new()
	var timing={"script_ms":[],"native_ms":[]}
	for i in range(5):
		var start=Vector2i(10,20+i*10);var target=Vector2i(140,30+i*10)
		var t=Time.get_ticks_usec();var old=script.find_path(grid,start,target,Vector2(8,8),bits);timing.script_ms.append((Time.get_ticks_usec()-t)/1000.0)
		t=Time.get_ticks_usec();var next=fast.find_path(grid,start,target,Vector2(8,8),bits);timing.native_ms.append((Time.get_ticks_usec()-t)/1000.0)
		check(old==next,"unreachable full-size route exact parity "+str(i))
	var result={"passed":passed,"failures":failures,"sampled_bones":sampled_bones,"unreachable_search":timing}
	FileAccess.open("res://research/native-acceleration-test.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("NATIVE ACCELERATION ",passed," passed, ",failures.size()," failed; bones ",sampled_bones,"; timings ",timing)
	quit(1 if not failures.is_empty() else 0)
