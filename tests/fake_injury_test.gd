extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var checks=[]
var failed=false

func check(ok: bool,name: String):
	checks.append({"test":name,"passed":ok});failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name)

func fresh(id="h005"):
	var s=Sim.new();s.selected_character=id;s.reset()
	s.players[0].pos=Vector2(-700,0);s.players[1].pos=Vector2(1700,1100)
	s.ball=Vector3(800,-900,0);s.previous_ball=s.ball
	return s

func double_stop(s):
	s.stop(0);s.advance(0.12);s.stop(0)

func state(s) -> Array:
	var p=s.players[0]
	return [p.pos,p.z,p.knock,p.vz,p.mana,p.cooldown,p.tackle,p.slow,p.stun,p.sprint,p.want_move,s.ball,s.velocity,s.holder]

func framed(rate: int):
	var s=fresh("h00P")
	s.submit_command("stop",0)
	while s.timeline<0.12-0.0000001:s.advance(minf(1.0/rate,0.12-s.timeline))
	s.submit_command("stop",0)
	while s.timeline<2.4-0.0000001:s.advance(minf(1.0/rate,2.4-s.timeline))
	return s

func _initialize():call_deferred("run")

func run():
	var s=fresh();s.command(0,Vector2(700,0));s.stop(0)
	check(not s.players[0].injury_pose and s.players[0].injury_window and not s.players[0].want_move,"single S stops and opens 0.25-second window")
	s.advance(0.24);s.stop(0)
	check(s.players[0].injury_pose and s.players[0].injury_count==1,"second S inside window starts fake injury")
	s=fresh();s.stop(0);s.advance(0.25);s.stop(0)
	check(not s.players[0].injury_pose,"window is expired at its exact deadline")
	s=fresh();s.stop(0);s.advance(0.2);s.stop(0);s.advance(0.1);s.stop(0)
	check(s.players[0].injury_count==1 and not s.players[0].injury_pose,"each stop has an independent expiry; rapid chain does not extend first window")
	s.advance(0.01);s.stop(0)
	check(s.players[0].injury_pose and s.players[0].injury_count==2,"newly armed window can trigger after earlier timer has expired")
	s=fresh();double_stop(s);s.advance(5)
	check(s.players[0].injury_pose and not s.players[0].injury_window,"ordinary character has no invented automatic get-up timer")
	for id in ["h00P","h003","h010"]:
		s=fresh(id);double_stop(s)
		var delay=2.0 if id=="h00P" else 1.0
		s.advance(delay-0.001)
		check(s.players[0].injury_pose,id+" remains in death animation before source reset time")
		s.advance(0.002)
		check(not s.players[0].injury_pose,id+" uses source-specific animation reset")
	s=fresh("h003");double_stop(s);s.advance(0.78);s.stop(0);s.advance(0.10);s.stop(0);s.advance(0.13)
	check(s.players[0].injury_pose,"auto reset does nothing when a recent stop window is still set")
	s.advance(0.2)
	check(s.players[0].injury_pose,"skipped stand callback is not retried when multipress later clears")
	s.advance(0.7)
	check(not s.players[0].injury_pose,"later independently scheduled stand callback still executes")
	s=fresh("h003");double_stop(s);s.advance(0.38);s.stop(0);s.advance(0.1);s.stop(0);s.advance(0.53)
	check(not s.players[0].injury_pose,"old stand callback can finish a newer fake injury after its press window clears")
	s=fresh();s.take(0);double_stop(s)
	check(not s.players[0].injury_pose and s.players[0].injury_window,"real-ball holder cannot fake injury but still arms window")
	s.holder=-1;s.ball=Vector3(800,-900,0);s.stop(0)
	check(s.players[0].injury_pose,"losing real ball allows next stop within existing window")
	s=fresh("h01N");s.take(0);s.ball=s.Copies.held_position(s,0)
	s.Copies.create(s,0,false,Vector2(1800,0));double_stop(s)
	check(s.players[0].injury_pose and s.holder!=0 and s.Copies.held(s,0).size()>0,"fake-ball holder can fake injury without dropping the fake")
	s=fresh();double_stop(s);s.take(0)
	check(s.players[0].injury_pose and s.holder==0 and s.Characters.catchable(s.players[0]),"lying animation does not prevent catching or automatically recover on catch")
	check(not s.free_point(s.players[0].pos,1) and not s.Characters.phased(s.players[0]),"lying character keeps ordinary collision footprint")
	s.kick(0,Vector2(1400,100))
	check(not s.players[0].injury_pose and s.holder==-1,"successful real-ball kick resumes action animation")
	s=fresh();double_stop(s)
	check(not s.kick(0,Vector2(1400,100)) and s.players[0].injury_pose,"unavailable kick does not cancel pose")
	s.command(0,Vector2(100,0));s.advance(0.3)
	check(not s.players[0].injury_pose and s.players[0].pos.x>-700,"right-click recovers and moves immediately without a new delay")
	s=fresh();s.stop(0);s.advance(0.06);s.command(0,Vector2(600,0));s.advance(0.06);s.stop(0)
	check(s.players[0].injury_pose,"intervening move does not cancel original multipress timer")
	s=fresh();s.KeeperRules.hold(s,0);s.advance(0.06);s.KeeperRules.hold(s,0);s.advance(0.06);s.stop(0)
	check(not s.players[0].injury_pose and s.players[0].injury_count==0,"H/internal movement cleanup does not count as S")
	s=fresh();s.stop(0,false);s.stop(0,false);s.stop(0)
	check(not s.players[0].injury_pose,"internal stop helper cannot accidentally trigger fake injury")
	s=fresh("h00P");s.stop(0);s.advance(0.05);s.Characters.use(s,0,Vector2.ZERO)
	check(not s.players[0].injury_pose and s.players[0].injury_count==0,"successful skill's internal stop does not act as a second S")
	s=fresh();double_stop(s);s.toggle_sprint(0)
	check(not s.players[0].injury_pose and s.players[0].sprint,"changing sprint resumes animation")
	s=fresh();double_stop(s);s.fake_injury_enabled=false
	check(s.players[0].injury_pose,"disabling future injuries does not cancel already playing animation")
	s.advance(0.3);double_stop(s)
	check(not s.players[0].injury_pose and s.players[0].injury_window,"disabled option preserves normal stop and multipress timer")
	s.fake_injury_enabled=true;s.stop(0)
	check(s.players[0].injury_pose,"re-enabling can use existing press window as in original toggle")
	for scenario in ["ice","tackle","air"]:
		var a=fresh();var b=fresh();b.fake_injury_enabled=false
		for item in [a,b]:
			if scenario=="ice":item.arena.set_field(2);item.players[0].knock=Vector2(18,3)
			elif scenario=="tackle":item.tackle(0,Vector2(900,0))
			else:item.players[0].z=160;item.apply_impulse(0,Vector3(10,5,9))
			double_stop(item);item.advance(0.75)
		check(state(a)==state(b),scenario+": fake injury changes neither motion nor game state relative to same stop inputs")
	s=fresh("h003");double_stop(s);s.reset();s.advance(2)
	check(not s.players[0].injury_pose and not s.players[0].injury_window and s.injury_events.is_empty(),"reset discards previous unit timers and press state")
	s=fresh("h003");double_stop(s);s.advance(0.35);s.Characters.configure(s.players[0],"h005");double_stop(s);s.advance(1)
	check(s.players[0].injury_pose,"character replacement invalidates callbacks from the old unit")
	s=fresh();s.fake_injury_enabled=false;s.start_match(3)
	check(not s.fake_injury_enabled,"option is preserved when starting a new match")
	s.submit_command("stop",0);s.submit_command("stop",0);s.advance(0.1)
	check(s.players[0].injury_count==0,"countdown rejects playing inputs")
	var a=framed(30);var b=framed(144)
	check(a.players[0].injury_start==b.players[0].injury_start and a.players[0].injury_count==1 and b.players[0].injury_count==1 and not a.players[0].injury_pose and not b.players[0].injury_pose,"queued press and exact one-shot deadlines agree at 30/144 render fps")
	check(state(a)==state(b),"added presentation timer dispatch does not disturb physics frame independence")
	s=fresh("h003");s.stop(0);s.stop(0);s.advance(0.75);s.stop(0);s.advance(0.12);s.stop(0);s.advance(0.14)
	check(s.players[0].injury_pose and not s.players[0].injury_window,"equal deadlines use stable creation order; original tie order remains unmeasured")
	var file=FileAccess.open("res://research/fake-injury-tests.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"basis":"Original JASS handler and independent timer lifetimes; no new native sampling","checks":checks},"\t"))
	quit(1 if failed else 0)
