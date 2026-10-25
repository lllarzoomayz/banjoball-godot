extends SceneTree
const Arena=preload("res://scripts/arena_collision.gd")
const Goals=preload("res://scripts/original_goals.gd")
const Scenery=preload("res://scripts/field_scenery.gd")
var checks=[]
var failed=false
func check(ok: bool,label: String,detail=""):
	checks.append({"test":label,"passed":ok,"detail":str(detail)});failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+label+" "+str(detail))
func _initialize():call_deferred("run")
func run():
	var world=Node3D.new();root.add_child(world)
	var camera=Camera3D.new();world.add_child(camera);camera.position=Vector3(-15,15,25);camera.look_at(Vector3(-20,1,0));camera.current=true
	for field in range(4):
		var arena=Arena.new();arena.set_field(field)
		var scenery=Scenery.new();world.add_child(scenery);scenery.load_field(arena.data.id)
		var goals=Goals.new();world.add_child(goals);goals.load_field(arena,scenery)
		check(goals.parts.size()==68,"field %d has all 68 original h00H placements"%field)
		var visual_ok=true;var locations={};var position_snapshot=[];var counts={}
		for part in goals.parts:
			var source: Vector3=part.get_meta("source_position")
			locations[str(source)]=true;position_snapshot.append(part.position)
			counts[source.x]=int(counts.get(source.x,0))+1
			visual_ok=visual_ok and part.data.actor.id=="h00H" and is_equal_approx(part.scale.x,0.6) and part.rotation==Vector3.ZERO and part.particles.particle_count()>0 and goals.batch_mesh.visible and part.particles.batch_geometry==goals.geometry
			visual_ok=visual_ok and absf(part.position.y*100-source.z-scenery.height_at(Vector2(source.x,source.y)))<0.001
		check(visual_ok,"field %d uses original scale, facing, ground elevation and live particle resource"%field)
		check(locations.size()==68 and counts.size()==2 and counts.values().all(func(n):return n==34),"field %d has no duplicate corners or missing side pieces"%field)
		# Independent known original base placement, shifted by the field's width.
		var shift=(float(arena.data.block_width)-32)*64
		check(counts.has(-2167.0-shift) and counts.has(2247.0+shift),"field %d preserves asymmetric original X offsets +73 / +7"%field)
		var time=goals.parts[0].visual_time;var particle_count=goals.parts[0].particles.particle_count()
		goals.advance(0)
		check(goals.parts[0].visual_time==time and goals.parts[0].particles.particle_count()==particle_count,"field %d pause freezes ambient frame"%field)
		arena.swap_ends();goals.advance(0)
		check(goals.parts.map(func(p):return p.position)==position_snapshot,"field %d halftime swaps teams without moving the neutral frame"%field)
		arena.swap_ends()
		for side in [-1.0,1.0]:
			var x=side*(2240+shift)
			var start=Vector3(x-side*120,0,299)
			var motion=Vector3(side*180,0,0)
			check(arena.sweep_ball(start,motion).is_empty() and not arena.goal_hit(start,motion).is_empty(),"field %d side %d low ball enters open mouth and scores"%[field,int(side)])
			for height in [300,450]:
				start.z=height
				var hit=arena.sweep_ball(start,motion)
				check(not hit.is_empty() and hit.name.begins_with("Goal_") and hit.normal.is_equal_approx(Vector3(-side,0,0)) and arena.goal_hit(start,motion).is_empty(),"field %d side %d height %d uses original overhead blocker"%[field,int(side),height])
			var inside_x=side*(2400+shift)
			for edge in [-1.0,1.0]:
				var hit=arena.sweep_ball(Vector3(inside_x,edge*200,80),Vector3(0,edge*60,0))
				check(not hit.is_empty() and absf(hit.t-0.4)<0.0001 and hit.normal.is_equal_approx(Vector3(0,-edge,0)),"field %d side %d goal side %d blocks at source corridor edge 224"%[field,int(side),int(edge)])
			var back=arena.sweep_ball(Vector3(side*(2500+shift),0,80),Vector3(side*80,0,0))
			check(not back.is_empty() and absf(back.t-0.35)<0.0001,"field %d side %d rear boundary remains at 2528"%[field,int(side)])
		goals.free();scenery.free()
	check(world.get_child_count()==1,"field switches release all goal emitters and scenery")
	world.free()
	FileAccess.open("res://research/original-goals-tests.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks},"\t"))
	quit(1 if failed else 0)
