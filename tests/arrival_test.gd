extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
const Native=preload("res://scripts/native_rules.gd")
var results=[]
var failed=false
func check(ok: bool,name: String,detail=""):
	results.append({"test":name,"passed":ok,"detail":detail})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))
func _initialize():call_deferred("run")
func run():
	var oracle=JSON.parse_string(FileAccess.get_file_as_string("res://research/native-stop-vectors.json"))
	var mismatches=0
	for v in oracle.vectors:
		# Isolate the branch predicate, using native-produced sqrt/angle inputs.
		# This does not claim our atan2/sqrt reproduce the engine's software math.
		var state=Native.arrival_state(v.native_distance,v.engine_error,v.radius,v.forced!=0)
		if state!=Vector2i(v.engine_force_stop,v.engine_done):mismatches+=1
	check(mismatches==0 and oracle.vectors.size()==400,"400 original x86 arrival predicate vectors",str(mismatches)+" mismatches")
	var traces=JSON.parse_string(FileAccess.get_file_as_string("res://research/native-movement-traces.json"))
	for t in traces.slice(0,7):
		var last=t.rows[-1]
		var target=Vector2(t.goal[0],t.goal[1])
		var final_pos=Vector2(last.x,last.y)
		var previous=final_pos
		for j in range(t.rows.size()-2,-1,-1):
			var row=t.rows[j]
			var p=Vector2(row.x,row.y)
			if p.distance_to(final_pos)>0.1:previous=p;break
		var final_distance=final_pos.distance_to(target)
		var preceding_distance=previous.distance_to(target)
		check(final_distance<=Native.MIN_POINT_STOP+0.002 and preceding_distance>Native.MIN_POINT_STOP-0.002,"native final/preceding position bracket stop radius: "+t.name,str([preceding_distance,final_distance]))
	var s=Sim.new()
	s.command(0,s.players[0].pos+Vector2(10,0))
	var origin: Vector2=s.players[0].pos
	for i in range(20):s.step_movement()
	check(s.players[0].pos==origin and not s.players[0].want_move,"10-unit click completes without a forward step")
	s=Sim.new()
	origin=s.players[0].pos
	s.command(0,origin+Vector2(-10,0))
	s.step_movement()
	check(s.players[0].pos==origin and s.players[0].want_move,"nearby reverse click stops translation while turning")
	for i in range(20):s.step_movement()
	check(s.players[0].pos==origin and not s.players[0].want_move and absf(Sim.signed_turn_to(PI,s.players[0].angle))<=Native.ARRIVAL_ANGLE,"arrival waits for heading tolerance")
	s=Sim.new()
	origin=s.players[0].pos
	s.command(0,origin+Vector2(16,0))
	s.step_movement()
	var after_step: Vector2=s.players[0].pos
	# Original software angle may be slightly off-axis; test step length and
	# forward travel, not an idealized exact horizontal endpoint.
	check(absf(after_step.distance_to(origin)-9)<0.0001 and after_step.x>origin.x+8.99,"16-unit click takes one normal movement step",str(after_step-origin))
	s.step_movement()
	check(s.players[0].pos==after_step and not s.players[0].want_move,"next tick completes at native minimum stop radius")
	var f=FileAccess.open("res://research/arrival-tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"scope":"Native stop predicate plus observed stopping boundaries. Full native pathfinding and software heading math remain separate.","checks":results},"\t"))
	quit(1 if failed else 0)
