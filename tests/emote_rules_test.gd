extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func notices(s):return s.native_visuals.filter(func(e):return e.get("message","")=="Lolz acquired")
func run():
	var s=Sim.new();s.start_practice();s.bot_enabled=false
	check(not s.Emotes.cast(s,0,"taunt") and not s.Emotes.cast(s,0,"sadface"),"both source emotes require the pick unlock")
	s.advance(39.99);check(notices(s).is_empty(),"no acquisition text before forty seconds")
	s.advance(.01);check(notices(s).size()==2,"one acquisition notice for each newly picked unit")
	check(notices(s).all(func(e):return e.time==40.0 and e.text_lifetime==2 and e.model==""),"acquisition keeps source timer and two-second text-only lifetime")
	var rng=s.random.state;s.command(0,Vector2(700,0));var target=s.players[0].destination
	check(s.Emotes.cast(s,0,"taunt"),"taunt unlocks exactly at forty seconds")
	check(not s.Emotes.cast(s,0,"taunt"),"taunt has a five-second cooldown")
	check(s.Emotes.cast(s,0,"sadface"),"sadface cooldown is independent of taunt")
	check(s.shout.available(s,0),"emotes do not consume Shout cooldown")
	check(s.players[0].want_move and s.players[0].destination==target,"visual emotes leave locomotion orders intact")
	check(s.random.state==rng,"visual choices never consume simulation randomness")
	check(s.native_visuals[-2].message in s.Emotes.TAUNTS and s.native_visuals[-1].message in s.Emotes.SADFACES,"messages selected from original lists")
	check(s.native_visuals[-1].text_lifetime==3,"emotes have source three-second lifespan")
	s.advance(4.99);check(not s.Emotes.cast(s,0,"sadface"),"cooldown cannot finish early")
	s.advance(.01);check(s.Emotes.cast(s,0,"sadface"),"cooldown finishes at exactly five seconds")
	var ready=s.shout.states[0].sadface_ready_at;s.reset()
	check(s.shout.states[0].sadface_ready_at==ready and s.Emotes.remaining(s,0,"taunt")==0,"kickoff reset preserves unlock and independent cooldowns")
	check(notices(s).is_empty(),"kickoff does not replay acquisition")
	for key in ["stun","silence","disabled","possess_time"]:
		s.players[0][key]=1;check(not s.Emotes.cast(s,0,"taunt"),"emote unavailable during "+key);s.players[0][key]=0
	s.submit_command("taunt",0);s.consume_commands();check(s.native_visuals[-1].message in s.Emotes.TAUNTS,"queued emote input reaches source text")
	check(not s.Emotes.cast(s,-1,"taunt") and not s.Emotes.cast(s,0,"invalid"),"invalid actor and emote are rejected")
	# Re-pick before the old timer expires: stale timers must never unlock new units.
	s.start_practice();s.advance(20);s.Characters.configure(s.players[0],"h026");s.shout.bind_players(s)
	s.advance(20);check(notices(s).all(func(e):return e.owner!=0),"replaced unit ignores obsolete acquisition timer")
	check(not s.Emotes.cast(s,0,"taunt"),"replacement has its own full forty-second wait")
	s.advance(20);check(notices(s).any(func(e):return e.owner==0 and is_equal_approx(e.time,s.timeline)),"replacement receives acquisition at its own deadline")
	# One large advance should preserve the timer's timestamp rather than stamping frame end.
	s.start_practice();var start=s.timeline;s.advance(45)
	check(notices(s).all(func(e):return is_equal_approx(e.time,start+40)),"catch-up records fixed timer timestamp, not frame-end time")
	# Verify exact source lists (including escaped slash expressions).
	var source=FileAccess.get_file_as_string("res://research/war3map.j")
	for pair in [["taunts",s.Emotes.TAUNTS],["sadfaces",s.Emotes.SADFACES]]:
		for i in range(pair[1].size()):
			var value=pair[1][i].replace("\\","\\\\")
			check(source.contains('set Emotes___%s[%d]="%s"'%[pair[0],i,value]),"exact source expression "+pair[0]+str(i))
	FileAccess.open("res://research/emote-rules-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("EMOTE RULES ",passed," passed; ",failures.size()," failed");quit(1 if not failures.is_empty() else 0)
