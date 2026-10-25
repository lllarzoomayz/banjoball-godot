extends SceneTree
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func run():
	var game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	game.start_game(3);game.sim.countdown=0;game.sim.match_state="playing";game.sim.advance(2)
	game.sim.submit_command("kick",0,Vector2(900,100));game.sim.random.randf()
	var old=game.sim;game.original_effects.last_event=999;game.experience.last_sound=999
	game.experience.follow_camera=false;var perf=game.perf
	perf.start_benchmark()
	check(not is_same(old,game.sim) and game.sim.timeline==0 and game.sim.time==0,"benchmark replaces prior clocks and simulation")
	check(game.sim.pending_commands.is_empty() and game.sim.benchmark_driver!=null,"no previous commands survive; fixed-tick driver installed")
	check(game.experience.last_sound==0,"new simulation audio starts with a fresh event cursor")
	game.sim.emit_visual("fx_jump",Vector3.ZERO);game.update_visuals(.01)
	check(game.original_effects.bursts.any(func(e):return e.model.data.actor.id=="fx_jump"),"new simulation visual IDs are not hidden by the old cursor")
	var state=game.sim.random.state;game.sim.advance(.04)
	check(game.sim.benchmark_driver.last_step==0,"benchmark input is issued by the movement clock")
	perf.next_phase()
	check(game.sim.random.state==state and game.sim.timeline==0,"half-resolution phase restarts identical initial random and clock state")
	check(is_equal_approx(game.get_viewport().scaling_3d_scale,.425),"half-resolution phase still applies requested render scale")
	perf.finish_benchmark(true)
	check(game.sim.benchmark_driver==null,"cancel removes automatic commands before manual play")
	check(perf.last_report.protocol=="seeded-fixed-orders-v2" and perf.last_report.seed==270127,"report identifies reproducibility protocol and seed")
	check(not game.experience.follow_camera,"benchmark restores the user's follow-camera preference")
	game.free()
	FileAccess.open("res://research/benchmark-phase-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("BENCHMARK PHASE ",passed," passed; ",failures.size()," failed")
	quit(1 if not failures.is_empty() else 0)
