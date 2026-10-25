extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func match_scene(size=3):
	var s=Sim.new();s.start_match(size);s.countdown=0;s.match_state="playing";s.bot_enabled=false
	return s
func audio_count(s,kind: String):return s.audio_events.filter(func(e):return e.kind==kind).size()
func run():
	var s=match_scene()
	check(not s.shout.cast(s,0),"source Pick timer prevents shouting immediately after picking")
	s.advance(39.99);check(not s.shout.cast(s,0),"unlock does not happen before forty seconds")
	s.advance(.01);var rng=s.random.state
	check(s.shout.cast(s,0),"A00S unlocks at forty seconds")
	check(s.random.state==rng,"emote text/voice RNG does not alter ball or AI randomness")
	check(not s.shout.cast(s,0) and is_equal_approx(s.shout.remaining(s,0),60),"native sixty-second cooldown blocks repeated casts")
	var text=s.native_visuals.filter(func(e):return e.model=="fx_shout")[0].message
	var pattern=RegEx.new();pattern.compile("^D{2,4}E{6,10}A{6,10}T{2,4}H{2,4}!$")
	check(pattern.search(text)!=null,"source DEATH text length ranges preserved")
	check(s.audio_events[-1].kind in ["shout1","shout2","shout3"],"source point-value-one voice group excludes death5")
	s.advance(4.4);check(s.shout.cast(s,1),"second teammate can respond")
	s.advance(4.4);check(s.shout.cast(s,2),"rolling window extends from each response, not first shout")
	var until=s.timeline+8.0
	check(s.players.slice(0,3).all(func(p):return p.shout_state.adrenaline_until==until),"A00X gives all three allies an eight-second status")
	check(s.players.slice(3,6).all(func(p):return p.shout_state.adrenaline_until==0),"enemy team does not inherit ally status")
	check(s.shout.counts[0]==0 and s.shout.deadlines[0]==INF,"complete response clears team counter")
	check(is_equal_approx(s.walking_speed(0),315.0),"base movement receives source five-percent modifier")
	check(audio_count(s,"shout4")==0,"chorus is not played immediately")
	s.advance(1.99);check(audio_count(s,"shout4")==0,"chorus waits its full two seconds")
	s.advance(.01);check(audio_count(s,"shout4")==1,"chorus fires at source timer deadline")
	var ready=s.players[0].shout_state.ready_at
	s.reset();check(s.players[0].shout_state.ready_at==ready and s.players[0].shout_state.adrenaline_until==until,"kickoff reset retains native cooldown and timed status")
	s.advance(6.0);check(is_equal_approx(s.walking_speed(0),300.0),"status expires without changing permanent move speed")
	check(audio_count(s,"shout4")==1,"chorus never repeats")
	s=match_scene(2);s.advance(40);s.shout.cast(s,0);s.advance(4.51)
	check(s.shout.counts[0]==0,"incomplete response expires after 4.5 seconds")
	s.shout.cast(s,1);check(s.players[0].shout_state.adrenaline_until==0,"late response starts a new count")
	s.shout.cast(s,2);check(s.shout.counts==[1,1],"team counts are independent")
	s.shout.cast(s,3);check(s.players[2].shout_state.adrenaline_until>s.timeline and s.players[0].shout_state.adrenaline_until==0,"opposing team may complete its own response")
	s.start_match(2);s.bot_enabled=false;s.countdown=0;s.match_state="playing";var old=audio_count(s,"shout4")
	s.advance(3);check(audio_count(s,"shout4")==old and not s.shout.events.any(func(e):return e.kind=="chorus"),"new match clears delayed chorus from previous match")
	check(s.shout.remaining(s,0)>36,"new picks must unlock again")
	s.advance(37)
	for key in ["stun","silence","disabled","possess_time","tackle"]:
		s.players[0][key]=1;check(not s.shout.cast(s,0),"unavailable during "+key);s.players[0][key]=0
	s.match_state="halftime";check(not s.shout.cast(s,0),"cannot shout during halftime selection")
	s.match_state="playing";s.submit_command("shout",0);s.consume_commands()
	check(s.shout.counts[0]==1,"queued gameplay command reaches shout rules")
	s.start_practice();s.PracticeRules.refresh(s,0)
	check(not s.shout.available(s,0),"practice cooldown refresh does not bypass source unlock delay")
	var units=JSON.parse_string(FileAccess.get_file_as_string("res://research/map-units.json"))
	for unit in units:
		if s.Characters.IDS.has(unit.id):check(int(unit.fields.upoi)==int(s.shout.VOICE_GROUP[unit.id]),"original voice group "+unit.id)
	FileAccess.open("res://research/shout-rules-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("SHOUT RULES ",passed," passed; ",failures.size()," failed")
	quit(1 if not failures.is_empty() else 0)
