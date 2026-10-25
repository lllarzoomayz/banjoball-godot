extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
const Driver=preload("res://scripts/benchmark_driver.gd")
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func run_case(step: float):
	var s=Sim.new();s.random.seed=Driver.SEED;s.mixed_roster=true;s.start_match(3)
	s.countdown=0;s.match_state="playing";s.benchmark_driver=Driver.new()
	var left=8.0
	while left>.00000001:
		var dt=minf(step,left);s.advance(dt);left-=dt
	return s
func run():
	var a=run_case(1.0/60);var b=run_case(1.0/32);var c=run_case(.077)
	for s in [b,c]:
		check(s.random.state==a.random.state,"fixed-tick commands preserve seeded RNG across render rates")
		check(s.ball.is_equal_approx(a.ball) and s.velocity.is_equal_approx(a.velocity),"same ball state after equal simulation duration")
		check(s.score==a.score and s.holder==a.holder,"same score and possession")
		check(s.input_sequence==a.input_sequence and s.benchmark_driver.last_step==a.benchmark_driver.last_step,"same command count and scripted stage")
		for i in range(a.players.size()):check(s.players[i].pos.is_equal_approx(a.players[i].pos),"same route result for player "+str(i))
	check(a.benchmark_driver.last_step==3,"orders occur on movement ticks before eight seconds")
	check(Sim.new().benchmark_driver==null,"ordinary games have no automatic benchmark controller")
	FileAccess.open("res://research/benchmark-replay-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("BENCHMARK REPLAY ",passed," passed; ",failures.size()," failed")
	quit(1 if not failures.is_empty() else 0)
