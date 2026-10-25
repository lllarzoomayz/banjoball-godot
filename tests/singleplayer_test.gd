extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var results=[]
var failed=false
func check(ok: bool,name: String,detail=""):
	results.append({"test":name,"passed":ok,"detail":detail})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))
func _initialize():call_deferred("run")
func run():
	var s=Sim.new()
	s.start_match(3,10,300)
	check(s.players.size()==6 and s.match_state=="countdown" and s.score==[0,0],"3v3 starts with countdown and fresh score")
	var start: Vector2=s.players[0].pos
	s.submit_command("move",0,Vector2(900,0))
	s.advance(1)
	check(s.players[0].pos==start and s.time_left==300,"countdown locks movement and match clock")
	s.advance(2.1)
	check(s.match_state=="playing" and s.time_left<300,"countdown opens play")
	s.switch_player()
	check(s.controlled!=0 and s.players[s.controlled].team==0,"control switches only to blue teammate")
	# Run all players through the real action pipeline for a short match segment.
	s.controlled=-1
	var catches=0;var shots=0;var previous_holder=-1
	var started=Time.get_ticks_msec()
	for i in range(600):
		s.advance(0.05)
		if s.holder>=0 and previous_holder!=s.holder:catches+=1
		if previous_holder>=0 and s.holder<0 and s.velocity.length()>1:shots+=1
		previous_holder=s.holder
	var finite=true
	for p in s.players:finite=finite and p.pos.is_finite()
	check(finite and catches>0 and shots>0,"AI acquires and releases ball through normal gameplay",{"catches":catches,"shots_or_passes":shots,"score":s.score,"ms":Time.get_ticks_msec()-started})
	s.controlled=0
	s.mode="score";s.score_limit=10;s.score=[9,0]
	s.award_goal(0)
	var frozen=s.players[0].pos
	s.advance(1)
	check(s.match_state=="ended" and s.winner==0 and s.score==[10,0] and s.players[0].pos==frozen,"winning goal ends and freezes match")
	s.start_match(6,10,300)
	check(s.players.size()==12 and s.score==[0,0] and s.winner==-1,"6v6 restart rebuilds twelve players and clears result")
	s.advance(13)
	finite=true
	for p in s.players:finite=finite and p.pos.is_finite() and absf(p.pos.x)<2530 and absf(p.pos.y)<1320
	check(finite and s.match_state=="playing" and s.time_left<291,"twelve-player match advances within pitch bounds")
	# An open scoring opportunity exercises AI decision, flight and actual goal detection.
	s.start_match(3)
	s.match_state="playing"
	s.bot_enabled=false
	for i in range(s.players.size()):s.players[i].pos=Vector2(-1600+i*150,-1000)
	s.players[1].pos=Vector2(1500,100)
	s.players[1].previous=s.players[1].pos
	s.take(1)
	s.step_ball()
	Sim.TeamAI.think(s)
	check(s.holder==-1 and s.velocity.x>0,"AI shoots toward an open opponent goal")
	for i in range(s.players.size()):s.stop(i)
	s.advance(1.5)
	check(s.score[0]==1 and s.match_state=="goal","AI shot crosses goal and enters goal pause")
	s.advance(7.3)
	check(s.score==[1,0] and s.match_state=="playing" and s.holder==-1 and s.ball.length()>0,"scoring resets formation then restarts with a random kickoff impulse")
	# A requested pass must follow the ordinary kick and interception path.
	s.start_match(3)
	s.match_state="playing"
	s.bot_enabled=false
	for i in range(s.players.size()):s.players[i].pos=Vector2(-1600+i*150,-1000)
	s.players[1].pos=Vector2(-500,0)
	s.players[0].pos=Vector2(100,0)
	s.take(1)
	s.step_ball()
	s.call_for_pass()
	Sim.TeamAI.think(s)
	for i in range(s.players.size()):s.stop(i)
	s.advance(0.9)
	check(s.holder==0 and s.pass_request==0,"called pass can be caught by controlled teammate")
	s.start_match(6,10,300)
	s.countdown=0
	s.step_ball()
	s.time_left=0.01
	s.step_ball()
	check(s.overtime and s.match_state=="playing" and s.time_left==120,"tied timer enters two-minute extension")
	s.award_goal(1)
	check(s.match_state=="goal" and s.winner==-1,"overtime goal does not end the two-minute period early")
	s.start_practice()
	check(not s.match_enabled and s.players.size()==2 and s.controlled==0,"practice restores two-player sandbox")
	s=Sim.new()
	s.players[0].pos=Vector2(-600,0)
	s.tackle(0,Vector2(-1200,0))
	for i in range(5):s.step_movement()
	check(s.players[0].cast_pending and s.players[0].tackle==0 and s.players[0].pos==Vector2(-600,0),"reverse tackle turns before activating")
	s.step_movement()
	check(not s.players[0].cast_pending and s.players[0].tackle>0 and not s.players[0].want_move,"tackle cast does not create an automatic walk order")
	var f=FileAccess.open("res://research/singleplayer-tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":results},"\t"))
	quit(1 if failed else 0)
