extends SceneTree
## Diagnostic comparison: all errors are retained, with no broad pass assertion.
## Only the relative phase of the 30 ms engine clock is fitted across trials.
const Sim=preload("res://scripts/match_sim.gd")
var traces=[]
func _initialize():call_deferred("run")
func compare_trial(t: Dictionary,phase: float,original_order: bool=true) -> Dictionary:
	var s=Sim.new()
	s.players[0].pos=Vector2(-600,0)
	s.players[1].pos=Vector2(1200,900)
	# Keep ball simulation away from the controlled no-ball native experiment.
	s.ball=Vector3(0,-1100,0)
	var trial=int(t.trial)
	if trial in [5,7]:s.players[1].pos=Vector2(-450,0)
	if trial in [6,11]:s.players[1].pos=Vector2(-540,0)
	if trial==7:s.players[1].team=0
	if trial==8:s.players[1].pos=Vector2(-500,150)
	if trial==9:s.arena.add_box(Rect2(-448,-640,32,1312),200)
	var start=roundf(float(t.rows[9].time)*32.0)/32.0
	s.timeline=start
	s.next_move=(floorf((start-phase)/Sim.MOVE_DT+0.00001)+1)*Sim.MOVE_DT+phase
	s.next_ball=start+Sim.BALL_DT
	if trial<10:s.tackle(0,Vector2(t.meta[3],t.meta[4]))
	else:s.players[0].knock=Vector2(10,0)
	var rows=[]
	var max_position=0.0;var max_body=0.0;var max_other=0.0;var active=[]
	var pathing_mismatches=[]
	for j in range(9,t.rows.size()):
		if j>9:s.advance(Sim.BALL_DT)
		# The recorded probe issued "move", not the player's smart/right click.
		if j==16 and trial==3:s.command(0,Vector2(-600,900),not original_order)
		if j==16 and trial==4:s.stop(0)
		var r=t.rows[j]
		var position_error=s.players[0].pos.distance_to(Vector2(r.x,r.y))
		var body_error=absf(rad_to_deg(Sim.signed_turn_to(deg_to_rad(r.facing),s.players[0].body)))
		var other_error=s.players[1].pos.distance_to(Vector2(r.other_x,r.other_y))
		max_position=maxf(max_position,position_error)
		max_body=maxf(max_body,body_error)
		max_other=maxf(max_other,other_error)
		if s.players[0].tackle>0:active.append(j+1)
		var phased=not s.players[0].pathing_enabled
		if phased!=(r.phased!=0):pathing_mismatches.append(j+1)
		rows.append({"tick":j+1,"x":s.players[0].pos.x,"y":s.players[0].pos.y,"facing":rad_to_deg(s.players[0].body),"active":s.players[0].tackle>0,"position_error":position_error,"body_error":body_error,"other_error":other_error,"phased":phased,"original_phased":r.phased!=0})
	return {"name":t.name,"phase":phase,"max_position":max_position,"max_body":max_body,"max_other":max_other,"pathing_mismatch_ticks":pathing_mismatches,"first_active":active[0] if not active.is_empty() else -1,"final":[s.players[0].pos.x,s.players[0].pos.y],"rows":rows}
func run():
	var fixture=JSON.parse_string(FileAccess.get_file_as_string("res://research/fidelity-probe/run-v4/traces.json"))
	if not fixture.complete:push_error("Original full probe is incomplete");quit(1);return
	traces=fixture.trials.slice(0,12)
	var best_phase=0.0;var best_score=INF;var phases=[]
	for i in range(24):
		var phase=i*0.00125
		var score=0.0
		for t in traces.slice(0,3):
			var result=compare_trial(t,phase)
			score+=result.max_position
		phases.append({"phase":phase,"score":score})
		if score<best_score:best_score=score;best_phase=phase
	var results=[]
	for t in traces:
		var result=compare_trial(t,best_phase)
		results.append(result)
		print(t.name," first active ",result.first_active," max position ",result.max_position," body ",result.max_body," other ",result.max_other," final ",result.final)
	var out=FileAccess.open("res://research/native-tackle-comparison.json",FileAccess.WRITE)
	var control=compare_trial(traces[3],best_phase,false)
	var order_check={"original_command":"move","old_smart_pathing_mismatch_ticks":control.pathing_mismatch_ticks,"corrected_move_pathing_mismatch_ticks":results[3].pathing_mismatch_ticks}
	print("Recorded move order collision comparison: ",order_check)
	out.store_string(JSON.stringify({"scope":"Whole 240-sample original trials. One global engine-clock phase fitted on forward/reverse/right-angle; errors for all scenarios retained. Not a declaration of full fidelity.","best_phase":best_phase,"phase_search":phases,"trials":results,"order_control":order_check},"\t"))
	quit()
