extends SceneTree
const Scenery=preload("res://scripts/field_scenery.gd")
const Destruction=preload("res://scripts/scenery_destruction.gd")
const ApocalypseWorld=preload("res://scripts/apocalypse_world.gd")
var passed=0
var failures=[]
var observations={}
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func run():
	var catalog=Destruction.source_catalog()
	check(catalog.native_placements.size()==2223,"original 2223 destructables include invisible blockers")
	check(not catalog.types.has("LRrk") and catalog.types.has("LTlt"),"rocks are decorative doodads; original tree walls are destructables")
	check(catalog.models.size()==28 and catalog.models.B000_0.status=="no_death_sequence","water has no authored death; not silently hidden with decorative scenery")
	for key in catalog.models:
		var row=catalog.models[key]
		if row.status!="death":continue
		for i in range(row.meshes.size()):
			var geo=row.meshes[i];var positions=FileAccess.get_file_as_bytes(geo.positions).to_float32_array();var normals=FileAccess.get_file_as_bytes(geo.normal_frames).to_float32_array()
			check(positions.size()==int(row.frames)*int(geo.vertex_count)*4 and normals.size()==positions.size(),"complete float animation textures "+key+" geo "+str(i))
			var low=Vector3(geo.bounds[0][0],geo.bounds[0][1],geo.bounds[0][2]);var high=Vector3(geo.bounds[1][0],geo.bounds[1][1],geo.bounds[1][2]);var box=AABB(low,high-low).grow(.0001)
			var bounded=true;var normalized=true
			for j in range(0,positions.size(),4):
				bounded=bounded and box.has_point(Vector3(positions[j],positions[j+1],positions[j+2]))
				normalized=normalized and absf(Vector3(normals[j],normals[j+1],normals[j+2]).length()-1)<.001
			check(bounded and normalized,"all animated positions bounded and source normals normalized "+key+" geo "+str(i))
			check(ResourceLoader.exists(Scenery.texture_name(geo.texture)),"SLK replacement texture exists "+key)
	for id in ["Sunny_Hills","Waterfall","Frozen","Frozen_Coast"]:
		var field=Scenery.new();root.add_child(field);field.load_field(id)
		check(not is_instance_valid(field.destruction),"no death renderer allocated during normal field load "+id)
		var state=field.destruction_state();var scene=Scenery.scene_cache[id];var eligible=[];var decoration_slots=[]
		for placed in scene.placements:
			if catalog.models.has(placed.key) and catalog.models[placed.key].status=="death":eligible.append(placed)
			if not catalog.types.has(str(placed.key).get_slice("_",0)) and field.placement_slots.has(int(placed.editor_id)):decoration_slots.append(field.placement_slots[int(placed.editor_id)])
		var result=state.kill_destructables()
		check(result.animated_destructables==eligible.size(),"kill only original destructable placements "+id)
		for key in state.batches:
			if field.batch_nodes.has(key):check(field.batch_nodes[key].all(func(n):return not n.visible),"fully replaced static batches stop drawing "+id+" "+key)
		check(state.kill_destructables().animated_destructables==0,"repeated cleanup does not restart deaths "+id)
		for placed in eligible:
			var eid=int(placed.editor_id)
			if field.placement_slots.has(eid):
				var slot=field.placement_slots[eid]
				check(field.batch_nodes[slot.key][0].multimesh.get_instance_transform(slot.index).basis.determinant()==0,"old static tree hidden "+id+" "+str(eid))
			else:
				check(field.dynamic.models.filter(func(m):return int(m.get_meta("editor_id",-1))==eid).all(func(m):return not m.visible),"original animated team flag hidden during its Death replacement")
		var unchanged=true
		for slot in decoration_slots:unchanged=unchanged and field.batch_nodes[slot.key][0].multimesh.get_instance_transform(slot.index).basis.determinant()!=0
		check(unchanged,"rocks, fences, birds and non-destructable doodads remain "+id)
		var calls=0
		for batch in state.batches.values():calls+=batch.nodes.size()
		observations[id]={"deaths":eligible.size(),"geometry_batches":calls,"retained_no_death":result.retained_without_death}
		check(calls<=54,"death draw batches bounded by source variants rather than tree count "+id)
		state.advance(.4);var clock=state.clock;state.advance(0)
		check(state.clock==clock,"zero simulation delta freezes death clock "+id)
		state.advance(3)
		for batch in state.batches.values():
			for i in range(batch.nodes.size()):check(batch.nodes[i].visible==(float(catalog.models[batch.key].meshes[i].alphas[-1])>.01),"settled zero-alpha geosets stop drawing "+id)
			var last=batch.last_clock;state.advance(.1)
			check(batch.last_clock==last,"settled dead poses need no repeated material updates "+id)
		state.clear()
		check(state.batches.is_empty() and state.handled.is_empty(),"clear releases instances and placement state "+id)
		var candidate=eligible.filter(func(p):return str(p.key).begins_with("LTlt_") or str(p.key).begins_with("WTst_"))
		if not candidate.is_empty():
			var placed=candidate[0];var tree_id=int(placed.editor_id)
			field.set_placement_visible(tree_id,false);state.kill_destructables()
			check(not state.handled.has(tree_id),"already replaced hidden originals are not resurrected by death art "+id)
			state.clear();check(not field.is_placement_visible(tree_id),"clear preserves another scene owner's hidden original "+id)
			field.set_placement_visible(tree_id,true);var lifted=state.replace_tree(tree_id,9)
			check(not lifted.is_empty() and lifted.model in ["h01K","h01L"],"tree conversion returns original lifted-unit art "+id)
			check(state.replace_tree(int(placed.editor_id),9).is_empty(),"same tree cannot be lifted twice "+id)
			var batch=state.batches.values()[0];var transform=batch.entries[0].transform
			check(transform.basis.get_scale().is_equal_approx(Vector3.ONE*1.2),"dead replacement uses original 1.2 scale "+id)
			check(batch.entries[0].start<0 and batch.end==0,"pre-existing dead replacement starts at final pose "+id)
			state.clear()
			var native_world=ApocalypseWorld.new();var random=RandomNumberGenerator.new();random.seed=123
			var index=["Sunny_Hills","Waterfall","Frozen","Frozen_Coast"].find(id)
			native_world.setup(index,random)
			var native_tree=native_world.find_editor(tree_id)
			var center=Vector2(native_world.field.center[0],native_world.field.center[1])
			var first=native_world.lift(native_tree.uid,0)
			check(state.apply_tree_replacement(first,center),"native world tree removal drives field renderer "+id)
			check(not field.is_placement_visible(tree_id),"original tree removed by native replacement "+id)
			var first_slot=state.native_dead[first.replacement.uid]
			var second=native_world.lift(first.replacement.uid,7)
			check(state.apply_tree_replacement(second,center),"already dead replacement can be pulled again "+id)
			check(state.batches[first_slot.key].nodes[0].multimesh.get_instance_transform(first_slot.index).basis.determinant()==0,"previous stump instance removed, not duplicated "+id)
			var second_slot=state.native_dead[second.replacement.uid]
			var stump=state.batches[second_slot.key].nodes[0].multimesh.get_instance_transform(second_slot.index)
			check(stump.basis.get_scale().is_equal_approx(Vector3.ONE*1.2),"repeated native stump uses original size "+id)
			check(absf(stump.origin.y-(second.replacement.position[2]-1024)/100)<.0001,"absolute world ground matches rendered field ground "+id)
			var third=native_world.lift(second.replacement.uid,7)
			check(state.apply_tree_replacement(third,center),"same-variant third replacement "+id)
			check(not state.apply_tree_replacement(second,center) and not state.apply_tree_replacement(first,center),"old event replays cannot resurrect obsolete stumps "+id)
			check(state.native_dead.size()==1,"one visible stump identity after repeated replacement "+id)
			state.clear()
			check(field.is_placement_visible(tree_id) and state.native_seen.is_empty(),"new field restores originals and clears native event identities "+id)
		field.free()
	await process_frame
	FileAccess.open("res://research/scenery-destruction-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"observations":observations},"\t"))
	print("SCENERY DESTRUCTION ",passed," passed; ",failures.size()," failed; ",observations);quit(1 if not failures.is_empty() else 0)
