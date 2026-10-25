extends SceneTree
const Model=preload("res://scripts/wc3_model.gd")
var passed=0
var failures=[]
var observations={}
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func run():
	var reference=JSON.parse_string(FileAccess.get_file_as_string("res://research/apocalypse-art-reference.json"))
	var world=Node3D.new();root.add_child(world)
	for row in reference.models:
		var model=Model.new();world.add_child(model);model.load_actor(row.id,Color(.2,.4,1))
		check(row.unsupported_pe1==0,"no unsupported legacy emitter "+row.id)
		for texture in model.data.textures:
			if texture.Image!="":check(ResourceLoader.exists(model.texture_name(texture.Image)),"original texture available "+texture.Image)
		for i in range(model.mesh_nodes.size()):
			var count=0;var material=model.mesh_nodes[i].material_override
			while material!=null:
				check(material.get_meta("source_layer")==count,"layer order "+row.id+" geo "+str(i))
				count+=1;material=material.next_pass
			check(count==row.layer_counts[i],"all original layers retained "+row.id+" geo "+str(i))
		for sample in row.samples:
			# The existing baker selects one Stand variant. Other native Stand
			# variants are recorded as source evidence, not claimed as exported.
			if not model.data.clips.any(func(c):return c.name==sample.clip):continue
			model.play(sample.clip,true);model.animation_time=sample.seconds;model.advance(0)
			for i in range(model.mesh_nodes.size()):
				var material=model.mesh_nodes[i].material_override;var mid=int(model.data.meshes[i].material)
				var first=mini(int(sample.seconds*30),int(model.clip.frames)-2)
				var blend=clampf(sample.seconds*30-first,0,1)
				var geo=lerpf(model.clip.alphas[first][i],model.clip.alphas[first+1][i],blend)
				while material!=null:
					var lid=int(material.get_meta("source_layer"));var expected=geo*sample.layer_alphas[mid][lid]
					check(absf(material.get_shader_parameter("opacity")-expected)<.012,"source alpha %s %s %.2f geo %d layer %d"%[row.id,sample.clip,sample.seconds,i,lid])
					material=material.next_pass
		model.free()
	# Exercise the actual birth burst through native, dense-native and script
	# paths. No synthetic emitter substitutes for the original 1,000 burst.
	var variants=[]
	for mode in ["native","dense","script"]:
		var model=Model.new();world.add_child(model);model.load_actor("apoc_black_hole",Color.WHITE)
		model.particles.defer_geometry=true;model.particles.rng.seed=9351;model.play("Birth",true)
		if mode=="script":model.particles.use_native_simulation=false
		if mode=="dense":
			for e in model.particles.emitters:e.packed=PackedFloat64Array()
		variants.append(model)
	for tick in range(9):
		for model in variants:model.advance(1.0/60)
		check(variants[0].particles.particle_count()==variants[1].particles.particle_count() and variants[0].particles.particle_count()==variants[2].particles.particle_count(),"burst count parity tick "+str(tick))
		check(variants[0].particles.rng.state==variants[1].particles.rng.state and variants[0].particles.rng.state==variants[2].particles.rng.state,"burst RNG parity tick "+str(tick))
	check(variants[0].particles.emitters[2].particles.size()==1000,"original black-hole birth keeps all 1000 squirt particles")
	observations.black_hole_burst=variants[0].particles.emitters[2].particles.size()
	for model in variants:model.free()
	# A high rate multiplied by lifespan overstates NuclearExplosion's
	# occupancy: its emission windows are short. Compare default cap to an
	# unrestricted source run, including particles that outlive the 15s clip.
	var nuclear=[];var peaks=[]
	for capacity in [512,4096]:
		var model=Model.new();world.add_child(model);model.load_actor("apoc_nuclear",Color.WHITE)
		model.particles.defer_geometry=true;model.particles.rng.seed=11;model.one_shot=true;model.play("Birth",true)
		if capacity==4096:model.use_tail_optimization=false
		for e in model.particles.emitters:e.capacity=capacity
		nuclear.append(model)
	for e in nuclear[0].particles.emitters:peaks.append(0)
	for tick in range(1020):
		for model in nuclear:model.advance(1.0/60)
		var same=true
		for e in range(peaks.size()):
			var count=nuclear[0].particles.emitters[e].particles.size();peaks[e]=maxi(peaks[e],count)
			same=same and count==nuclear[1].particles.emitters[e].particles.size()
		check(same and nuclear[0].particles.rng.state==nuclear[1].particles.rng.state,"nuclear cap never truncates source emissions tick "+str(tick))
		if tick==900:
			check(nuclear[0].particles.particle_count()>0 and not nuclear[0].visual_tail_finished(),"smoke survives the end of the fifteen-second source clip")
	observations.nuclear_peak_particles_per_emitter=peaks
	for model in nuclear:
		check(model.particles.particle_count()==0 and model.visual_tail_finished(),"nuclear tail expires after the last original particle")
		model.free()
	world.free();await process_frame
	FileAccess.open("res://research/apocalypse-art-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"observations":observations},"\t"))
	print("APOCALYPSE ART ",passed," passed; ",failures.size()," failed; ",observations)
	quit(1 if not failures.is_empty() else 0)
