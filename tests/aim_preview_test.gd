extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
const Preview=preload("res://scripts/aim_preview.gd")
var passed=0
var failures=[]
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func _initialize():call_deferred("run")
func fresh(id: String):
	var s=Sim.new();s.selected_character=id;s.reset();s.bot_enabled=false
	s.players[0].pos=Vector2(-800,0);s.players[0].body=0
	s.players[1].pos=Vector2(-1500,1000);s.take(0);s.ball=s.Copies.held_position(s,0)
	return s
func run():
	for id in Sim.Characters.IDS:
		var s=fresh(id);var p=s.players[0];var info=Preview.spec(p,"ability")
		var target=Preview.target(p,info,Vector2(1,1),1)
		var before=var_to_bytes([s.players,s.ball,s.velocity,s.holder,s.projectiles,s.fake_balls,s.pending_commands,s.random.state])
		var result=Preview.build(s,0,"ability",target)
		check(not result.is_empty(),"indicator exists for "+id)
		check(var_to_bytes([s.players,s.ball,s.velocity,s.holder,s.projectiles,s.fake_balls,s.pending_commands,s.random.state])==before,"preview cannot mutate simulation or RNG "+id)
		if info.kind=="pillar":
			check(absf(target.x-p.pos.x)+absf(target.y-p.pos.y)<=700.01,"pillar uses original diamond placement range")
			check(Preview.target(p,info,Vector2.RIGHT,0)==p.pos,"pillar zero drag targets exact feet")
			check(info.radius==125,"pillar indicator includes native ball hit radius")
		if info.mode=="point":check(p.pos.distance_to(target)<=info.range+0.01,"point skill clamps rather than auto-walking "+id)
	for kind in ["kick","angel","curve"]:
		for side in [false,true]:
			var s=fresh("h012" if kind=="curve" else "h028");var point=Vector2(1100,180)
			var predicted=Preview.ball_path(s,0,kind,point,side)
			if kind=="curve":s.Characters.cast_curve(s,0,point,side)
			else:s.kick(0,point,35.0 if kind=="angel" else 30.0,7)
			var max_error=0.0
			for i in range(4):s.step_ball()
			max_error=s.ball.distance_to(predicted[1])
			check(max_error<0.05,"initial airborne segment agrees with actual launch "+kind+str(side)+" error="+str(max_error))
			check(predicted.size()<=17,"bounded guide geometry "+kind+str(side))
			var landed=false;var valid=true
			for v in predicted.slice(1):
				if v.z<0 or not v.is_finite() or (landed and v.z>0):valid=false
				if v.z==0:landed=true
			check(valid,"guide is finite and stays flat after landing "+kind+str(side))
	var s=fresh("h005");s.arena.add_box(Rect2(-400,-400,60,800),300)
	var predicted=Preview.ball_path(s,0,"kick",Vector2(1200,0))
	var open_field=fresh("h005")
	check(predicted==Preview.ball_path(open_field,0,"kick",Vector2(1200,0)),"guide ignores obstacle geometry and reflection")
	s.kick(0,Vector2(1200,0))
	s.players[0].pos=Vector2(1500,1000) # Indicators explicitly exclude future catches.
	var reflected=false
	for i in range(64):
		s.step_ball()
		if s.velocity.x<0:reflected=true
	check(reflected,"real ball still reflects from the wall despite simplified guide")
	s=fresh("h005");s.holder=1;s.ball=Vector3(1500,700,80);s.velocity=Vector3(-80,50,30)
	var before=var_to_bytes([s.players,s.ball,s.velocity,s.holder,s.pending_commands,s.random.state])
	var preaim=Preview.build(s,0,"kick",Vector2(1200,100));var from=s.players[0].pos+Vector2.from_angle(s.players[0].body)*100
	check(preaim.trajectory[0].is_equal_approx(Vector3(from.x,from.y,s.players[0].z)) and preaim.note.contains("预瞄"),"unheld preview starts at local hypothetical ball rather than another player")
	check(var_to_bytes([s.players,s.ball,s.velocity,s.holder,s.pending_commands,s.random.state])==before,"preaim does not take a ball or mutate simulation")
	s.ball=Vector3(-1400,-800,300);s.velocity=Vector3(90,-70,-10)
	check(Preview.build(s,0,"kick",Vector2(1200,100)).trajectory==preaim.trajectory,"distant ball movement and velocity cannot move the preaim guide")
	s.take(0);s.ball=s.Copies.held_position(s,0)
	var caught=Preview.build(s,0,"kick",Vector2(1200,100))
	check(caught.trajectory==preaim.trajectory and not caught.note.contains("预瞄"),"catch uses the same prepared shot arc in open space")
	s=fresh("h026");s.Characters.use(s,0,Vector2(1000,0))
	check(s.players[0].action_clip=="Attack 2" and is_equal_approx(s.players[0].action,0.15),"Ogre uses JASS sequence 6 until the 0.15 second strike")
	var model=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/h026.json"))
	check(model.clips.any(func(c):return c.name=="Attack 2"),"original Ogre Attack 2 was exported")
	FileAccess.open("res://research/aim-preview-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("AIM PREVIEW CHECKS ",passed," passed; ",failures.size()," failed")
	quit(0 if failures.is_empty() else 1)
