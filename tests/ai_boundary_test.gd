extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var passed=0
var failures=[]
var cases=[]
func _initialize():call_deferred("run")
func check(ok: bool,label: String):
	if ok:passed+=1
	else:failures.append(label);printerr("FAIL "+label)
func scene(field: int):
	var sim=Sim.new();sim.selected_field=field;sim.start_match(1)
	sim.match_state="playing";sim.countdown=0;sim.controlled=0
	for p in sim.players:sim.Characters.configure(p,"h005");p.cooldown=999
	sim.players[0].pos=Vector2(-900,0);sim.players[0].previous=sim.players[0].pos
	sim.holder=-1;sim.last_owner=-1;sim.intercept=0;sim.velocity=Vector3.ZERO
	return sim
func pickup(field: int,label: String,point: Vector2,approach: Vector2,keeper_team: int=-1):
	var sim=scene(field);var p=sim.players[1]
	if keeper_team>=0:
		p.team=keeper_team;p.role="keeper";sim.players[0].team=1-keeper_team
		sim.players[0].pos=Vector2(sim.arena.attack_direction(keeper_team)*900,0)
	p.pos=point+approach.normalized()*440;p.previous=p.pos
	p.angle=(-approach).angle();p.body=p.angle
	sim.ball=Vector3(point.x,point.y,0);sim.previous_ball=sim.ball
	var found=false;var seconds=0.0;var valid=true
	var routes=0
	for tick in range(160):
		sim.advance(0.03);seconds+=0.03
		routes+=sim.profile.get("route_calls",0)
		valid=valid and p.pos.is_finite() and sim.arena.point_free(p.pos,p.radius,sim.goal_restrictions(1))
		if sim.holder==1:found=true;break
	var name="field %d %s"%[field,label]
	check(found,name+" AI catches the edge ball without referee help")
	check(valid,name+" respects collision geometry")
	cases.append({"name":name,"caught":found,"seconds":seconds,"distance":p.pos.distance_to(Vector2(sim.ball.x,sim.ball.y)),"position":str(p.pos),"target":str(p.target),"route_status":p.route_status,"routes":routes})
	if found:
		var caught_at: Vector2=p.pos
		sim.advance(1.2)
		check(p.pos.distance_to(caught_at)>40 or sim.holder!=1,name+" continues moving or passes after pickup")
func match_recovery(field: int,size: int,side: Vector2,moving: bool):
	var sim=Sim.new();sim.selected_field=field;sim.start_match(size)
	sim.match_state="playing";sim.countdown=0;sim.controlled=0
	# Isolate chase/navigation from black holes, hooks and other rescue skills.
	for p in sim.players:sim.Characters.configure(p,"h005");p.cooldown=999
	var half=sim.arena.half_size
	var point=side*(half-Vector2.ONE*(60 if moving else 1))
	sim.ball=Vector3(point.x,point.y,0);sim.previous_ball=sim.ball;sim.holder=-1
	sim.velocity=Vector3(side.x*6,side.y*6,0) if moving else Vector3.ZERO
	sim.last_owner=-1;sim.intercept=0
	var caught=false;var valid=true;var seconds=0.0
	for tick in range(400):
		sim.advance(.03);seconds+=.03
		for p in sim.players:valid=valid and p.pos.is_finite() and sim.arena.bounds.grow(1).has_point(p.pos)
		if sim.holder>=0 and sim.holder!=sim.controlled:caught=true;break
	var name="%dv%d field %d %s %s"%[size,size,field,str(side),"rebound" if moving else "corner"]
	check(caught,name+" team AI recovers edge ball")
	check(valid,name+" all players remain finite and in bounds")
	cases.append({"name":name,"caught":caught,"seconds":seconds,"holder":sim.holder})
func run():
	for field in range(4):
		var sample=scene(field);var half=sample.arena.half_size
		for sign_y in [-1,1]:
			pickup(field,"sideline "+str(sign_y),Vector2(0,sign_y*(half.y-1)),Vector2(0,-sign_y))
		for sign_x in [-1,1]:
			pickup(field,"endline "+str(sign_x),Vector2(sign_x*(half.x-1),700),Vector2(-sign_x,0))
			for sign_y in [-1,1]:
				pickup(field,"corner %s %s"%[sign_x,sign_y],Vector2(sign_x*(half.x-1),sign_y*(half.y-1)),Vector2(-sign_x,-sign_y))
		for team in [0,1]:
			var direction=sample.arena.attack_direction(team)
			pickup(field,"keeper goal corridor "+str(team),Vector2(-direction*(half.x+210),0),Vector2(direction,0),team)
		for size in [3,6]:
			for side in [Vector2(-1,-1),Vector2(-1,1),Vector2(1,-1),Vector2(1,1)]:match_recovery(field,size,side,false)
			for side in [Vector2.UP,Vector2.DOWN,Vector2(-1,0.6),Vector2(1,0.6)]:match_recovery(field,size,side,true)
	FileAccess.open("res://research/ai-boundary-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"cases":cases},"\t"))
	print("AI BOUNDARY ",passed," passed; ",failures.size()," failed")
	quit(0 if failures.is_empty() else 1)
