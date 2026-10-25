extends SceneTree
const Rules=preload("res://scripts/apocalypse_rules.gd")
const World=preload("res://scripts/apocalypse_world.gd")
var passed=0
var failures=[]
var observations={}
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func make_rules(field=0,teams=[[0],[1]],humans=[0]):
	var result=Rules.new();var random=RandomNumberGenerator.new();random.seed=42102
	result.setup(field,random,humans,teams)
	return result
func count_kind(world,kind: String) -> int:
	return world.objects.values().filter(func(row):return row.id==kind).size()
func run():
	var source=World.data()
	check(source.placed.size()==2223,"all source DOO destructables, not only rendered crop")
	check(source.generated_water.size()==952,"both source-created water grids exported")
	for f in range(4):
		var rules=make_rules(f);var world=rules.world
		var expected=549 if f>=2 else 408
		check(world.objects.size()==2223+expected,"chosen field removes the other water family %d"%f)
		check(count_kind(world,"B000")==4+(544 if f>=2 else 408),"placed plus generated water %d"%f)
		var initial=world.objects.size();var removed=world.remove_blockers()
		check(removed.size()==1056,"remove all original YTpb %d"%f)
		check(world.objects.size()==initial-1056,"native blocker removal is actual object removal %d"%f)
		check(world.remove_blockers().is_empty(),"repeated blocker cleanup idempotent %d"%f)
		var alive_before=world.objects.values().filter(func(row):return row.alive).size()
		var killed=world.kill_all()
		check(world.objects.size()==initial-1056,"Kill preserves enumeration handles %d"%f)
		check(world.kill_all().is_empty(),"second Kill produces no new deaths %d"%f)
		check(world.objects.values().filter(func(row):return row.alive).size()==alive_before-killed.size(),"only initial playable rectangle is killed %d"%f)
		observations[world.field.id]={"objects_after_blockers":world.objects.size(),"killed":killed.size(),"zone_candidates":world.candidates().size()}
	var rules=make_rules();var world=rules.world
	world.remove_blockers()
	var tree=world.candidates().filter(func(row):return row.id=="LTlt")[0]
	var original_id=tree.uid;var editor=int(tree.editor_id);var count=world.objects.size()
	var first=world.lift(original_id,2)
	check(not world.objects.has(original_id),"lift removes selected native tree")
	check(world.objects.size()==count,"dead replacement preserves pool population")
	check(first.replacement.alive==false and first.replacement.variation==2,"replacement is dead chosen variation")
	check(first.tree.rawcode=="h00V" and first.tree.radius==0,"lifted native tree has object class but zero collision radius")
	check(world.candidates().any(func(row):return row.uid==first.replacement.uid),"dead replacement remains a candidate")
	var second=world.lift(first.replacement.uid,9)
	check(not second.is_empty() and not world.objects.has(first.replacement.uid),"already dead tree can be lifted again")
	check(second.replacement.original_editor==editor,"repeat replacement retains original visual identity")
	check(second.tree.position.is_equal_approx(first.tree.position),"repeat lift has source terrain height")
	world.objects.clear()
	world.add({"id":"B000","position":[world.field.center[0],world.field.center[1],1016],"editor_id":-1})
	var water=world.random_tree_pull(rules.rng)
	check(not water.empty and not water.has("tree") and world.objects.size()==1,"non-tree choice consumes attempt without creating a tree")
	world.objects.clear();check(world.random_tree_pull(rules.rng).empty,"empty enumeration stops tree timer")
	check(World.contains([0,0,1,1],Vector2.ONE),"native rect upper edges are inclusive")
	# Source threshold R2I(humans*.75+.5), observer/computer cannot vote.
	rules=make_rules(0,[[0,1],[2,3]],[0,1,2,3])
	check(not rules.vote(0,39.999),"40-second field-choice gate")
	check(not rules.vote(9,40),"non-human cannot vote")
	check(rules.vote(0,40) and not rules.active,"first of four votes")
	check(not rules.vote(0,40),"one vote per human")
	check(rules.vote(1,40) and not rules.active,"second vote below 75 percent rounded threshold")
	check(rules.vote(2,40) and rules.active,"third vote triggers")
	check(not rules.vote(3,40),"cannot restart active sequence")
	var start=rules.started
	rules.advance_to(start+1)
	# Independent arithmetic sum for 32 updates, not replay of implementation.
	check(rules.alpha==32 and absf(rules.size-1.32)<1e-9,"32Hz appearance after one second")
	check(absf(rules.pull_force-(32+.00625*32*31/2))<1e-9,"linearly growing delta produces quadratic pull accumulation")
	var center=rules.center()
	var unit=rules.unit_pull(center+Vector3(100,0,0))
	check(not unit.remove and absf(unit.force.x+rules.pull_force/100)<.00001,"source inverse-distance pull")
	check(rules.unit_pull(center).remove and rules.unit_pull(center).force.is_finite(),"exact-center absorption avoids divide by zero")
	check(rules.unit_pull(center+Vector3(9*rules.size*.999,0,0)).remove,"just inside unit absorption surface")
	check(not rules.unit_pull(center+Vector3(9*rules.size*1.001,0,0)).remove,"just outside unit absorption surface")
	check(rules.ball_pull(center).remove,"ball exact center absorption")
	check(rules.ball_pull(center+Vector3(sqrt(rules.pull_force)*.99,0,0)).remove,"ball absorption is force/distance threshold")
	check(not rules.ball_pull(center+Vector3(sqrt(rules.pull_force)*1.01,0,0)).remove,"ball beyond force threshold survives")
	check(rules.blast(center).is_equal_approx(Vector3(0,0,75)),"central explosion pushes upward")
	var blast=rules.blast(center+Vector3(1000,0,-200))
	check(absf(blast.length()-75)<.0001 and blast.z>blast.x,"explosion uses absolute z+100 not fly height")
	# A live timer/event sequence, stepped with irregular render deltas.
	for f in range(4):
		var a=make_rules(f,[[0,1],[2]], [0]);var b=make_rules(f,[[0,1],[2]],[0])
		var events=[];var pull_times=[]
		a.event.connect(func(kind,row):
			if kind=="pull":pull_times.append(row.time)
			else:events.append({"kind":kind,"time":row.time}))
		a.vote(0,40);b.vote(0,40)
		a.advance_to(62);check(a.phase=="shaking" and a.shake_magnitude==0,"shake starts timer at 22s, not first increment")
		a.advance_to(62.1);check(absf(a.shake_magnitude-.55)<1e-8,"first camera shake at 22.1s")
		a.advance_to(87);check(a.phase=="exploded" and a.next_pull==INF and a.next_tree==INF,"47s explosion cancels pulls and new trees")
		check(a.alpha==255,"black-hole alpha saturates")
		check(a.mask_opacity()==0,"no mask before explosion+.5")
		a.advance_to(88.5);check(absf(a.mask_opacity()-.5)<1e-8,"2s original brown mask fade midpoint")
		a.advance_to(91.5);check(a.decorations.size()==230 and a.shake_magnitude==0,"cleanup resets shake and creates exactly 230 decorations")
		check(a.mask_opacity()==1,"cleanup remains fully covered")
		a.advance_to(96.5);check(absf(a.mask_opacity()-.5)<1e-8,"5s reveal midpoint")
		a.advance_to(99);check(a.skeletons.is_empty(),"first skeleton waits an additional .15s")
		a.advance_to(99.15);check(a.skeletons.size()==1,"first skeleton 59.15s after activation")
		a.advance_to(105)
		while b.clock<105:b.advance_to(minf(105,b.clock+.073))
		check(a.skeletons.size()==30 and a.phase=="aftermath" and a.next_time==INF,"10 skeletons per roster owner then stops %d"%f)
		check(a.decorations==b.decorations and a.skeletons==b.skeletons and a.rng.state==b.rng.state,"render chunk size does not change random world result %d"%f)
		check(pull_times.size()==1503,"explicit phase-first tie policy cancels pull at exactly 47s")
		var spacing_ok=true
		for row in a.decorations:
			check(Vector2(row.position.x-a.world.field.center[0],row.position.y-a.world.field.center[1]).length()<=2048.001,"decoration source radius")
			check(row.position.z==1024,"decoration fixed original absolute elevation")
			for other in a.decorations:
				if is_same(row,other) or row.kind!=other.kind:continue
				if row.position.distance_to(other.position)<=[0,150,100,50][row.kind]:spacing_ok=false
		check(spacing_ok,"all decoration pairs obey same-category exclusion radii %d"%f)
		for i in range(a.skeletons.size()):
			var row=a.skeletons[i];var p=Vector2(row.position.x-a.world.field.center[0],row.position.y-a.world.field.center[1])
			check(World.contains(a.world.field.pitch,p),"spawn in relocated chosen pitch %d"%f)
			check(row.team==i%2 and row.owner==([0,1][int(i/2)%2] if i%2==0 else 2),"alternating teams and round-robin owners")
		observations[a.world.field.id].events=events.filter(func(row):return row.kind!="tree" and row.kind!="skeleton")
	var single=make_rules(0,[[],[4,5]],[4]);single.vote(4,40);single.advance_to(104)
	check(single.skeletons.size()==20 and single.skeletons.all(func(row):return row.team==1),"empty team skipped without dropping spawns")
	check(single.skeletons[0].owner==4 and single.skeletons[1].owner==5,"one-team owner round robin")
	single.setup(1,single.rng,[0],[[0],[]],200)
	check(not single.active and single.next_time==INF and single.decorations.is_empty() and single.skeletons.is_empty(),"new game clears all event state")
	check(not single.vote(0,239.9) and single.vote(0,240),"new game arms a fresh 40s gate")
	var report={"passed":passed,"failures":failures,"fields":observations,"native_timer_tie_calibrated":false,"game_adapter_connected":false}
	FileAccess.open("res://research/apocalypse-rules-verification.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("APOCALYPSE RULES ",passed," passed; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
