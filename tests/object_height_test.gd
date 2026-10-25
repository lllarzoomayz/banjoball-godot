extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var checks=[]
var failed=false

func check(ok: bool,name: String,detail=""):
	checks.append({"test":name,"passed":ok,"detail":str(detail)});failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))

func _initialize():call_deferred("run")

func run():
	var native=JSON.parse_string(FileAccess.get_file_as_string("res://research/fidelity-probe/run-v4/traces.json"))
	for trial in native.trials:
		if int(trial.trial) not in [5,6,7,10,11]:continue
		var s=Sim.new();s.players[0].pos=Vector2(-600,0);s.players[1].pos=Vector2(1200,900);s.ball=Vector3(0,-1100,0)
		if int(trial.trial) in [5,7]:s.players[1].pos=Vector2(-450,0)
		if int(trial.trial) in [6,11]:s.players[1].pos=Vector2(-540,0)
		if int(trial.trial)==7:s.players[1].team=0
		if int(trial.trial)<10:s.begin_tackle(0)
		else:s.apply_impulse(0,Vector3(10,0,0))
		var mismatches=[];var max_error=0.0
		for row_index in range(9,trial.rows.size()):
			if row_index>9:s.step_ball()
			var row=trial.rows[row_index];var p=s.players[0];var other=s.players[1]
			if int(not p.pathing_enabled)!=int(row.phased):mismatches.append(int(row.tick))
			max_error=maxf(max_error,p.pos.distance_to(Vector2(row.x,row.y)))
			max_error=maxf(max_error,other.pos.distance_to(Vector2(row.other_x,row.other_y)))
			max_error=maxf(max_error,p.knock.distance_to(Vector2(row.vx,row.vy)))
			max_error=maxf(max_error,other.knock.distance_to(Vector2(row.other_vx,row.other_vy)))
		check(mismatches.is_empty(),"saved original collision flags "+trial.name,mismatches)
		check(max_error<0.02,"saved original positions and push velocities "+trial.name,max_error)
	for field in range(4):
		var s=Sim.new();s.selected_field=field;s.start_practice();s.players[1].pos=Vector2(1200,900)
		check(s.arena.world_height_offset==1024 and s.arena.data.terrain_height_range[0]>1,"original W3E elevation retains positive-height branch across field "+str(field))
		s.apply_impulse(0,Vector3(10,0,0));s.step_object_impulses()
		check(s.players[0].z==0 and not s.navigation_solid(s.players[0]),"ground movement uses original absolute elevation on field "+str(field))
		for tick in range(80):s.step_object_impulses()
		check(s.navigation_solid(s.players[0]) and not s.players[0].object_active,"last ground callback restores collision on field "+str(field))
	var s=Sim.new();s.command(0,Vector2(700,0));s.step_object_impulses()
	check(s.navigation_solid(s.players[0]) and not s.players[0].object_active,"zero-speed smart callback returns before absolute-height disable")
	s=Sim.new();s.set_unit_pathing(0,false);s.step_object_impulses()
	check(not s.navigation_solid(s.players[0]),"idle player does not invent an absolute-height callback")
	s=Sim.new();s.arena.world_height_offset=0;s.apply_impulse(0,Vector3(10,0,0));s.step_object_impulses()
	check(s.navigation_solid(s.players[0]),"synthetic zero-elevation ground retains enabled pathing")
	s=Sim.new();s.arena.world_height_offset=-200;s.players[0].z=50;s.step_object_impulses()
	check(s.navigation_solid(s.players[0]) and s.players[0].z>1,"synthetic below-zero world altitude does not confuse fly height with absolute height")
	s=Sim.new();s.players[0].pos=Vector2(-400,0);s.players[1].pos=Vector2.ZERO;s.ball=Vector3(1300,900,0)
	s.arena.add_box(Rect2(-1000,64,2000,1500),200);s.arena.add_box(Rect2(-1000,-1564,2000,1500),200)
	s.apply_impulse(1,Vector3(10,0,0));s.step_object_impulses();s.command(0,Vector2(400,0))
	check(s.players[0].path==[Vector2(400,0)] and not s.navigation_solid(s.players[1]),"ground push opens a route through the moving blocker")
	s.advance(3.0)
	check(s.navigation_solid(s.players[1]) and s.players[0].pos.x<s.players[1].pos.x-59.99 and s.players[0].want_move,"settled blocker closes route again before the follower overlaps")
	s.set_unit_pathing(1,false);s.advance(3.0)
	check(s.players[0].pos.distance_to(Vector2(400,0))<=16,"later skill disable still reopens the waiting route")
	var f=FileAccess.open("res://research/object-height-tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"basis":"Unchanged local JASS GetUnitZ + Object_iterate32, original W3E elevation, and five preserved native v4 trials. No new Warcraft sampling.","checks":checks},"\t"))
	quit(1 if failed else 0)
