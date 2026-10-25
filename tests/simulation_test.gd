extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
const WCModel=preload("res://scripts/wc3_model.gd")
var results=[]
var failed=false
func check(ok: bool,name: String,detail=""):
	results.append({"test":name,"passed":ok,"detail":detail})
	if not ok:failed=true
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))

func _initialize():
	call_deferred("run")

func run():
	var s=Sim.new()
	check(not s.kick(0,Vector2(1000,0)),"shot requires possession")
	s.take(0)
	s.step_ball()
	check(absf(s.ball.x-(-400))<0.001 and s.ball.y==0,"ball held 100 units along display facing")
	check(s.kick(0,Vector2(1000,0)),"possessed ball can be kicked")
	check(s.velocity.distance_to(Vector3(30,0,7))<0.001 and s.intercept==5,"original kick vector and five-tick exclusion")
	s.step_ball()
	# First tick uses ground friction on the full 3D vector, BEFORE displacement.
	var expected=Vector3(30,0,7).normalized()*(Vector3(30,0,7).length()-0.45)
	check(s.velocity.distance_to(expected)<0.001 and absf(s.ball.z-expected.z)<0.001,"ground-friction order matches JASS")
	s.step_ball()
	var airborne=expected-Vector3(0,0,1.5)
	airborne=airborne.normalized()*(airborne.length()-0.07)
	check(s.velocity.distance_to(airborne)<0.001,"gravity before full-vector air friction")
	s.reset()
	s.players[0].pos=Vector2(-1500,1000)
	s.ball=Vector3(0,0,1.0)
	s.velocity=Vector3(1,0,-10)
	s.step_ball()
	check(s.ball.z==0 and s.velocity.z>0,"ground impact bounces without penetration")
	s.reset()
	s.ball=Vector3(2230,0,80)
	s.velocity=Vector3(30,0,0)
	s.step_ball()
	check(s.score[0]==1 and s.reset_delay>0,"right goal scores once")
	for i in range(10):s.step_ball()
	check(s.score[0]==1,"goal cannot score repeatedly during reset")
	s.reset()
	# Original high-goal trigger starts at x=2240, not the field edge x=2016.
	s.ball=Vector3(2230,0,350)
	s.velocity=Vector3(30,0,0)
	s.step_ball()
	check(s.velocity.x<0 and s.score[0]==1,"shot above 300-unit goal is blocked")
	s.reset()
	s.toggle_sprint(0)
	for i in range(32):s.step_ball()
	check(absf(s.players[0].mana-80)<0.001,"sprint net mana drain 20 per second")
	s.players[0].mana=0
	s.step_ball()
	check(not s.players[0].sprint,"sprint stops when mana is empty")
	s.reset()
	s.command(0,Vector2(1500,0))
	for i in range(500):s.step_movement()
	check(s.players[0].pos.distance_to(Vector2(1500,0))<=Sim.Native.MIN_POINT_STOP+0.001,"move command reaches native stopping range")
	s.reset()
	s.players[1].pos=Vector2(0,0)
	s.command(0,Vector2(500,0))
	var safe=true
	for i in range(500):
		s.step_movement()
		if s.players[0].pos.distance_to(s.players[1].pos)<59.99:safe=false
	# Detour changes may select a different final heading; the native bound is
	# 0.49*32, independently checked against original instructions in arrival_test.
	check(safe and s.players[0].pos.distance_to(Vector2(500,0))<=Sim.Native.MIN_POINT_STOP+0.001,"route around stationary unit reaches native stopping range",str(s.players[0].pos)+" "+str(s.players[0].path))
	var native=JSON.parse_string(FileAccess.get_file_as_string("res://research/native-movement-traces.json"))
	for trial in range(4):
		s.reset()
		s.players[0].pos=Vector2(-600,0)
		s.players[0].turn=[0.1,0.6,0.6,1.0][trial]
		s.players[1].pos=Vector2(1500,1000)
		s.command(0,Vector2(native[trial].goal[0],native[trial].goal[1]))
		var max_position=0.0
		var max_body=0.0
		for step in range(1,31):
			s.step_movement()
			var row=native[trial].rows[step+9]
			max_position=maxf(max_position,s.players[0].pos.distance_to(Vector2(row.x,row.y)))
			max_body=maxf(max_body,absf(rad_to_deg(Sim.signed_turn_to(deg_to_rad(row.facing),s.players[0].body))))
		check(max_position<1 and max_body<2,"original-engine turn trace "+str(trial),"max position="+str(max_position)+" body degrees="+str(max_body))
	var at30=Sim.new()
	var at144=Sim.new()
	for sim in [at30,at144]:sim.command(0,Vector2(800,100));sim.take(0)
	for i in range(90):at30.advance(1.0/30)
	for i in range(432):at144.advance(1.0/144)
	check(at30.players[0].pos.distance_to(at144.players[0].pos)<0.001 and at30.ball.distance_to(at144.ball)<0.001,"30 and 144 FPS produce identical gameplay states")
	var catalog=JSON.parse_string(FileAccess.get_file_as_string("res://research/actors.json"))
	var valid=true
	for actor in catalog:
		var model=WCModel.new()
		root.add_child(model)
		model.load_actor(actor.id,Color.WHITE)
		for clip in model.data.clips:
			model.play(str(clip.name),true)
			model.advance(minf(0.35,float(clip.duration)/2))
			for i in range(model.skeleton.get_bone_count()):
				if not model.skeleton.get_bone_pose_position(i).is_finite():valid=false
		model.free()
	check(valid,"19 original models load and animate with finite bone poses")
	var f=FileAccess.open("res://research/test-results.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"passed":not failed,"tests":results},"\t"))
	quit(1 if failed else 0)
