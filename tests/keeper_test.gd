extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
const Model=preload("res://scripts/wc3_model.gd")
var results=[]
var failed=false
func check(ok: bool,name: String,detail=""):
	results.append({"test":name,"passed":ok,"detail":str(detail)})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))
func _initialize():call_deferred("run")
func scene(id="h005",field=0):
	var s=Sim.new();s.selected_character=id;s.selected_field=field;s.start_practice()
	s.players[0].pos=s.arena.keeper_position(0);s.players[0].previous=s.players[0].pos
	s.players[1].pos=Vector2(1200,900);s.ball=Vector3(1300,-900,0)
	return s
func shot(s,index=0):
	var p=s.players[index]
	var direction=s.arena.attack_direction(p.team)
	s.ball=Vector3(p.pos.x+direction*360,p.pos.y,220)
	s.velocity=Vector3(-direction*35,0,10)
func run():
	var s=scene();var p=s.players[0]
	var start: Vector2=p.pos
	s.command(0,Vector2(0,0));s.submit_command("hold",0);s.advance(0.03)
	check(not p.want_move and p.path.is_empty() and p.keeper_cooldown==2 and p.z==0,"H order stops walking and starts jump on ordered movement tick")
	check(absf(p.knock.x-5.0357971523)<0.00001 and absf(p.vz-28.5594248374)<0.00001 and p.knock.y==0,"jump adds original 29 impulse at eighty degrees")
	check(p.mana==100 and p.cooldown==0,"shared jump does not consume mana or role ability cooldown")
	s.advance(0.00125)
	check(p.z>27 and p.pos.x>start.x+4,"jump moves through the shared object physics instead of visual-only motion")
	var momentum=Vector3(p.knock.x,p.knock.y,p.vz)
	check(not Sim.KeeperRules.hold(s,0) and Vector3(p.knock.x,p.knock.y,p.vz)==momentum,"repeated H during cooldown adds no extra impulse")
	s.advance(2.2)
	check(p.keeper_cooldown==0 and p.z<1 and p.vz==0,"jump returns to ground and expires cooldown")
	s=scene();p=s.players[0];p.body=PI/2;p.knock=Vector2(3,-2);p.vz=4
	Sim.KeeperRules.hold(s,0)
	check(p.knock.distance_to(Vector2(3,3.035797))<0.0001 and absf(p.vz-32.559425)<0.0001,"jump follows display facing and adds to existing horizontal and vertical impulse")
	s=scene();p=s.players[0];p.role="field"
	check(Sim.KeeperRules.hold(s,0),"field player inside own protected goal can jump without designated keeper role")
	s=scene();p=s.players[0];p.pos=Vector2.ZERO;p.role="keeper";s.command(0,Vector2(500,0))
	check(not Sim.KeeperRules.hold(s,0) and not p.want_move and p.keeper_cooldown==0,"H outside own goal holds position without granting jump to a named goalkeeper")
	s=scene();s.players[0].pos=s.arena.keeper_position(1)
	check(not Sim.KeeperRules.hold(s,0),"opposing goal does not grant jump")
	s=scene();s.take(0)
	check(not Sim.KeeperRules.hold(s,0) and s.players[0].keeper_cooldown==0,"holding real scoring ball prevents jump without consuming cooldown")
	Sim.Copies.create(s,0,false,Vector2(0,0))
	check(s.has_ball(0) and s.holder<0 and Sim.KeeperRules.hold(s,0),"held decoy does not block the original real-ball-only jump condition")
	s=scene();p=s.players[0];p.z=50;p.silence=1
	check(Sim.KeeperRules.hold(s,0),"H is an order not a spell and has no invented grounded-only gate")
	for state in ["stun","disabled","hooked","possess_time"]:
		s=scene();s.players[0][state]=1
		check(not Sim.KeeperRules.hold(s,0),"cannot issue jump while "+state)
	s=scene();p=s.players[0];p.tackle=500
	check(Sim.KeeperRules.hold(s,0) and p.tackle==500,"hold position does not cancel existing scripted tackle travel")
	s=scene();s.players[1].team=0
	var regions=s.arena.guards[0];var center=(regions[0].get_center()+regions[1].get_center())/2
	s.players[0].pos=center+Vector2(60,0);s.players[1].pos=center
	check(not Sim.KeeperRules.hold(s,0) and Sim.KeeperRules.hold(s,1),"during transient overlap only nearest unit to combined goal center may jump")
	s=scene();Sim.KeeperRules.hold(s,0);s.command(0,Vector2(0,0))
	check(s.players[0].keeper_pose==0 and s.players[0].keeper_cooldown==2,"move cancels jump pose but cannot bypass cooldown")
	s=scene();shot(s);s.advance(0.8)
	check(s.score==[0,1],"high incoming shot beats a grounded keeper through actual goal detection")
	s=scene();shot(s);s.submit_command("hold",0)
	var caught_air=false
	for i in range(28):
		s.advance(s.BALL_DT)
		if s.holder==0 and s.players[0].z>100:caught_air=true
	check(caught_air and s.score==[0,0] and s.holder==0,"same shot can be caught above ground by the jumping keeper")
	check(s.ball.z>0 and s.kick(0,Vector2(1000,0)),"jumping keeper can pass the caught ball from current height")
	s=scene();s.players[0].pos=s.arena.keeper_position(0);s.players[0].body=PI
	Sim.KeeperRules.hold(s,0);s.advance(1.3)
	check(s.arena.point_free(s.players[0].pos,s.players[0].radius),"jumping toward back wall remains within legal pitch geometry")
	# Real AI decision and physical catch, both physical ends and all field sizes.
	for field in range(4):
		for swapped in [false,true]:
			s=Sim.new();s.selected_field=field;s.start_match(3);s.match_state="playing";s.bot_enabled=false
			if swapped:s.arena.swap_ends();s.reset()
			for i in range(s.players.size()):
				if i!=2:s.players[i].pos=Vector2(-900+i*250,1000)
			shot(s,2)
			Sim.TeamAI.think(s)
			var took_off=s.players[2].keeper_cooldown>0
			var caught=false
			for i in range(28):
				s.advance(s.BALL_DT)
				if s.holder==2 and s.players[2].z>100:caught=true
			check(took_off and caught and s.score==[0,0],"AI keeper intercepts high shot field %d swapped %s"%[field,swapped])
			Sim.KeeperRules.clear(s);s.holder=-1;s.players[2].z=0;s.players[2].vz=0;s.players[2].knock=Vector2.ZERO
			shot(s,2);s.ball.z=0;s.velocity.z=0
			check(not Sim.KeeperRules.should_jump(s,2,Sim.TeamAI.observation(s,0)),"AI saves jump for high ball field %d swapped %s"%[field,swapped])
	s=Sim.new();s.start_match(3);s.match_state="playing";s.bot_enabled=false
	for i in range(s.players.size()):
		if i!=2:s.players[i].pos=Vector2(-500+i*100,1000)
	s.ball=Vector3(1000,500,0);s.velocity=Vector3.ZERO
	s.fake_balls.append({"id":9,"team":1,"position":Vector3(-1730,0,220),"velocity":Vector3(-35,0,10),"holder":-1,"life":3.0})
	Sim.TeamAI.think(s)
	check(s.players[2].keeper_cooldown>0,"enemy high decoy can provoke normal keeper jump without revealing true ball")
	s.award_goal(1)
	check(s.players[2].keeper_cooldown==0 and s.players[2].keeper_pose==0,"goal event clears jump cooldown and visual state immediately")
	s.start_match(3)
	check(not Sim.KeeperRules.hold(s,2),"pregame countdown blocks jump")
	s.match_state="halftime"
	check(not Sim.KeeperRules.hold(s,2),"halftime blocks jump")
	s=scene();var t=scene()
	for sample in [s,t]:shot(sample);sample.submit_command("hold",0)
	for i in range(45):s.advance(1.0/30)
	for i in range(216):t.advance(1.0/144)
	check(s.players[0].pos==t.players[0].pos and s.players[0].z==t.players[0].z and s.ball==t.ball and s.holder==t.holder,"jump and aerial catch remain identical across render frame rates")
	# Existing MDX clips, including newly baked slam variants and cow exception.
	var animations=true;var airborne=true
	for id in Sim.Characters.IDS:
		s=scene(id);Sim.KeeperRules.hold(s,0);s.advance(0.25)
		airborne=airborne and s.players[0].z>100
		var model=Model.new();root.add_child(model);model.load_actor(id,Color.WHITE);model.play_keeper_jump();model.advance(0.2)
		animations=animations and "attack" in model.active_clip.to_lower()
		if id in ["h00R","h026","h028","h01I"]:animations=animations and "slam" in model.active_clip.to_lower()
		if id=="h02C":animations=animations and not "slam" in model.active_clip.to_lower()
		for bone in range(model.skeleton.get_bone_count()):animations=animations and model.skeleton.get_bone_pose_position(bone).is_finite()
		model.free()
	check(airborne,"all eighteen base characters share the same defensive jump")
	check(animations,"original jump attack clips render for all characters including slam and tauren exception")
	var f=FileAccess.open("res://research/keeper-tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":results},"\t"));quit(1 if failed else 0)
