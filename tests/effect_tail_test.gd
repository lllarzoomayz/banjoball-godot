extends SceneTree
const Model=preload("res://scripts/wc3_model.gd")
var passed=0
var failures=[]
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func _initialize():call_deferred("run")
func run():
	var world=Node3D.new();root.add_child(world)
	var camera=Camera3D.new();world.add_child(camera);camera.position=Vector3(0,12,15);camera.look_at(Vector3.ZERO);camera.current=true
	for id in ["fx_sprint","fx_stealth_sprint","fx_divine","fx_shadow_trail","fx_goal_block","fx_earth_pillar","fx_hook"]:
		var reference=Model.new();var actual=Model.new();world.add_child(reference);world.add_child(actual)
		reference.load_actor(id,Color.WHITE);actual.load_actor(id,Color.WHITE);reference.use_tail_optimization=false
		for clip in actual.data.clips:
			for model in [reference,actual]:
				model.play(clip.name,true);model.one_shot=true
				if is_instance_valid(model.particles):
					model.particles.rng.seed=512
					for emitter in model.particles.emitters:emitter.particles=[];emitter.credit=0.0;emitter.key=""
				if is_instance_valid(model.ribbons):
					model.ribbons.clock=0;model.ribbons.started=false
					for emitter in model.ribbons.emitters:emitter.sections=[];emitter.previous=[];emitter.credit=0.0
			var first_finished=-1.0
			for frame in range(ceili((float(clip.duration)+1.5)*60)):
				for model in [reference,actual]:model.position.x=frame*.015;model.rotation.y=frame*.005;model.advance(1.0/60)
				var same=true
				for i in range(reference.mesh_nodes.size()):same=same and reference.mesh_nodes[i].visible==actual.mesh_nodes[i].visible
				if is_instance_valid(reference.particles):
					same=same and reference.particles.particle_count()==actual.particles.particle_count()
					for e in range(reference.particles.emitters.size()):
						var a=reference.particles.emitters[e].particles;var b=actual.particles.emitters[e].particles
						if a.size()!=b.size():same=false;continue
						for p in range(a.size()):same=same and a[p].pos.distance_to(b[p].pos)<.0001
				if is_instance_valid(reference.ribbons):same=same and reference.ribbons.section_count()==actual.ribbons.section_count()
				check(same,"pruning keeps visible meshes and complete trails %s %s frame %d"%[id,clip.name,frame])
				if actual.visual_tail_finished():
					if first_finished<0:first_finished=frame/60.0
					check(not reference.mesh_nodes.any(func(node):return node.visible) and (not is_instance_valid(reference.particles) or reference.particles.particle_count()==0) and (not is_instance_valid(reference.ribbons) or reference.ribbons.section_count()<2),"finished effect has no visible reference remainder "+id)
			if id=="fx_sprint" and clip.name=="Death":check(first_finished>0 and first_finished<float(clip.duration),"empty sprint death finishes before blank animation frames")
		# Reusing a model after a tail-only period must restore its mesh visibility.
		for model in [reference,actual]:model.one_shot=false;model.play("Stand",true);model.advance(.2)
		check(reference.mesh_nodes.map(func(n):return n.visible)==actual.mesh_nodes.map(func(n):return n.visible),"playing Stand restores pruned material state "+id)
		reference.free();actual.free()
	world.free()
	FileAccess.open("res://research/effect-tail-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("EFFECT TAIL CHECKS ",passed," passed; ",failures.size()," failed")
	quit(1 if not failures.is_empty() else 0)
