extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var checks=[]
var failed=false

func check(ok: bool,name: String):
	checks.append({"test":name,"passed":ok});failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name)

func _initialize():call_deferred("run")

func run():
	var s=Sim.new();s.set_course(1);s.score=[2,1]
	var p=s.players[0];p.mana=8;p.cooldown=30;p.secondary_cooldown=20;p.sprint_cooldown=6;p.keeper_cooldown=1
	var before=p.pos;var obstacles=s.arena.obstacles.duplicate(true)
	s.submit_command("practice_refresh",0)
	check(p.mana==8 and p.cooldown==30,"refresh waits for simulation command boundary")
	s.step_movement()
	check(p.mana==100 and p.cooldown==0 and p.secondary_cooldown==0 and p.sprint_cooldown==0 and p.keeper_cooldown==0,"refresh replenishes resources and independent cooldowns")
	check(p.pos==before and s.score==[2,1] and s.arena.obstacles==obstacles,"refresh retains positions course and score")
	for id in s.Characters.IDS:
		s.selected_character=id;s.reset();p=s.players[0];p.cooldown=12;p.mana=10
		check(s.PracticeRules.refresh(s,0) and p.cooldown==0 and p.mana==100,"idle refresh supports "+id)
	s=Sim.new();p=s.players[0];s.tackle(0,p.pos+Vector2(900,0));var length=p.tackle
	check(not s.PracticeRules.refresh(s,0) and p.tackle==length and p.cooldown>0,"refresh does not reset an active tackle")
	s.finish_tackle(0)
	check(s.PracticeRules.refresh(s,0) and p.cooldown==0,"finished tackle can be tried again immediately")
	s.selected_character="h027";s.reset();p=s.players[0];s.Characters.use(s,0,p.pos+Vector2(300,0))
	var r=p.rift;var unlock=r.unlock
	check(not s.PracticeRules.refresh(s,0) and p.rift==r and r.unlock==unlock,"refresh preserves two-stage portal timing")
	s.selected_character="h029";s.reset();p=s.players[0];p.morph_kit="h005";p.morph_casts=1;p.cooldown=10
	check(s.PracticeRules.refresh(s,0) and p.morph_casts==1 and p.morph_kit=="h005","refresh keeps borrowed skill and use budget")
	s=Sim.new();p=s.players[0];s.ball=Vector3(1300,500,200);s.velocity=Vector3(100,0,50);s.powershot_active=true
	s.submit_command("practice_ball",0);s.step_movement()
	check(s.holder==0 and s.ball==s.Copies.held_position(s,0) and s.previous_ball==s.ball,"recall gives the actual ball to the controlled player")
	check(s.velocity==Vector3.ZERO and p.knock==Vector2.ZERO and not s.powershot_active,"recall cancels old flight without powershot recoil")
	s.Characters.configure(s.players[1],"h00F");s.take(1);s.ball=s.Copies.held_position(s,1);s.Characters.use(s,1,Vector2(-1200,0))
	check(s.PracticeRules.recall_ball(s,0) and s.players[1].ability_delay==0 and s.holder==0,"recall cancels the former holder's pending charged shot")
	s.selected_character="h01N";s.reset();s.take(0);s.ball=s.Copies.held_position(s,0);s.Characters.use(s,0,Vector2(1300,0),true)
	check(s.has_ball(0) and s.holder==-1,"fixture holds a fake ball before recall")
	s.PracticeRules.recall_ball(s,0)
	check(s.holder==0 and s.Copies.held(s,0).is_empty() and s.fake_balls.size()==1,"recall releases held fake without deleting it")
	s=Sim.new();s.ball_hook=88;before=Vector2(s.ball.x,s.ball.y)
	check(not s.PracticeRules.recall_ball(s,0) and s.ball_hook==88 and Vector2(s.ball.x,s.ball.y)==before,"recall cannot tear ball out of active hook")
	s.ball_hook=0;s.players[1].possess_time=5
	check(not s.PracticeRules.recall_ball(s,0) and s.players[1].possess_time==5,"recall respects another player's possession")
	s=Sim.new();s.players[0].stun=1
	check(not s.PracticeRules.recall_ball(s,0) and s.holder==-1,"stunned player cannot use recall to bypass state")
	s=Sim.new();s.start_match(3);s.match_state="playing";s.players[0].mana=8;s.players[0].cooldown=12;s.holder=-1
	s.submit_command("practice_refresh",0);s.submit_command("practice_ball",0);s.step_movement()
	check(s.players[0].mana==8 and s.players[0].cooldown==12 and s.holder==-1,"practice inputs cannot alter a live match")
	check(not s.PracticeRules.refresh(s,-1) and not s.PracticeRules.recall_ball(s,99),"invalid practice targets are rejected")
	s.start_practice();s.reset_delay=3
	check(not s.PracticeRules.refresh(s,0) and not s.PracticeRules.recall_ball(s,0),"goal restart cannot be interrupted by practice tools")
	var f=FileAccess.open("res://research/practice-tools-tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks},"\t"));quit(1 if failed else 0)
