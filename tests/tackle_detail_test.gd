extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
const Skills=preload("res://scripts/original_skill_rules.gd")
const Visuals=preload("res://scripts/tackle_visuals.gd")
var checks=[]
var failed=false

func check(ok: bool,name: String):
	checks.append({"test":name,"passed":ok});failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name)

func fresh():
	var s=Sim.new()
	s.players[0].pos=Vector2(-600,0);s.players[0].body=0
	s.players[1].pos=Vector2(1600,1000);s.ball=Vector3(1400,-900,0)
	return s

func contact(offset: Vector3,height: float=0,ally: bool=false):
	var s=fresh()
	s.players[0].z=height;s.players[0].tackle=640
	s.players[1].pos=s.players[0].pos+Vector2(44.6,0)+Vector2(offset.x,offset.y)
	s.players[1].z=height+offset.z
	if ally:s.players[1].team=s.players[0].team
	s.step_tackle(0)
	return s

func framed(rate: int):
	var s=fresh();s.tackle(0,Vector2(1200,0))
	while s.timeline<0.7-0.0000001:s.advance(minf(1.0/rate,0.7-s.timeline))
	return s

func _initialize():call_deferred("run")

func run():
	# 120/160/200 and 84/112/140 are independent Pythagorean boundaries.
	check(Skills.tackle_contact_3d(Vector3(120,0,160),0,true,false).slow,"slow includes exact 200-unit spherical boundary")
	check(not Skills.tackle_contact_3d(Vector3(120,0,160.1),0,true,false).slow,"vertical separation can exclude a horizontally nearby enemy")
	check(Skills.tackle_contact_3d(Vector3(84,0,112),0,true,false).hit,"push includes exact 140-unit spherical boundary")
	check(not Skills.tackle_contact_3d(Vector3(84,0,112.1),0,true,false).hit,"push excludes just beyond spherical radius")
	check(Skills.tackle_contact_3d(Vector3(20,0,130),0,true,false).hit,"cone is horizontal yaw, not a 3D forward cone")
	check(not Skills.tackle_contact_3d(Vector3(-20,0,130),0,true,false).hit,"near vertical target behind caster fails yaw cone")
	check(Skills.tackle_contact_3d(Vector3(100*cos(deg_to_rad(31)),100*sin(deg_to_rad(31)),80),0,true,false).hit,"airborne target inside 32-degree horizontal cone is hit")
	check(not Skills.tackle_contact_3d(Vector3(100*cos(deg_to_rad(33)),100*sin(deg_to_rad(33)),80),0,true,false).hit,"airborne target outside 32-degree horizontal cone is not hit")
	check(Skills.tackle_contact_3d(Vector3(0,0,100),0,true,false).hit and not Skills.tackle_contact_3d(Vector3(0,0,100),PI,true,false).hit,"directly overhead target keeps source Atan2 zero convention")
	var s=contact(Vector3(60,0,80))
	check(s.players[0].tackle==0 and s.players[1].slow==1.5,"air hit ends tackle and applies enemy slow")
	check(s.players[1].knock.is_equal_approx(Vector2(6,0)) and is_equal_approx(s.players[1].vz,8.0),"upward target receives 6 horizontal / 8 vertical impulse")
	check(s.players[0].knock.is_equal_approx(Vector2(5,0)) and s.players[0].vz==0,"caster receives horizontal five with no invented lift")
	s=contact(Vector3(60,0,-80),100)
	check(s.players[1].knock.is_equal_approx(Vector2(6,0)) and is_equal_approx(s.players[1].vz,-8.0),"high caster can push lower target downwards")
	s=contact(Vector3(100,0,0),400)
	check(s.players[1].knock.is_equal_approx(Vector2(10,0)) and s.players[1].vz==0,"equal-height airborne units retain full horizontal push")
	s=contact(Vector3(10,0,201))
	check(s.players[0].tackle>0 and s.players[1].slow==0 and s.players[1].knock==Vector2.ZERO,"ground tackle does not hit or slow target over 200 units above")
	s=contact(Vector3(100,0,120))
	check(s.players[0].tackle>0 and s.players[1].slow==1.5 and s.players[1].knock==Vector2.ZERO,"between 140 and 200 in 3D gets slow only")
	s=contact(Vector3(60,0,80),0,true)
	check(s.players[1].slow==0 and is_equal_approx(s.players[1].vz,8.0),"ally still receives 3D push without slow")
	s=contact(Vector3.ZERO)
	check(s.players[0].knock==Vector2(5,0) and s.players[1].knock==Vector2.ZERO and s.players[1].vz==0,"zero offset stays zero; caster still receives five")
	s=fresh();s.players[0].tackle=640;s.players[1].slow=0.3
	s.players[1].pos=Vector2(-460,100);s.players[1].z=80;s.step_tackle(0)
	check(is_equal_approx(s.players[1].slow,0.3),"airborne existing slow is not refreshed")
	s=fresh();s.players.append(s.players[1].duplicate(true));s.players[0].tackle=640
	s.players[1].pos=Vector2(-455.4,20);s.players[2].pos=Vector2(-455.4,-20)
	s.players[1].z=40;s.players[2].z=40;s.step_tackle(0)
	check(s.players[1].vz>0 and s.players[2].vz>0 and s.players[0].knock==Vector2(10,0),"all front contacts apply before tackle ends")
	s=fresh();s.arena.add_box(Rect2(-570,-300,10,600),200)
	s.players[0].tackle=640;s.players[1].pos=Vector2(-500,0);s.players[1].z=80;s.step_tackle(0)
	check(s.players[0].pos==Vector2(-600,0) and s.players[1].vz>0,"blocked step can hit across wall; source has no line-of-sight gate")
	check(s.tackle_shadows.size()==1 and s.tackle_shadows[0].pos==Vector3(-600,0,0),"rejected contact step still creates its old-position shadow")
	s=fresh();s.players[0].tackle=640
	for i in range(15):s.step_ball()
	check(s.tackle_shadows.size()==15 and s.players[0].tackle==0,"full tackle creates exactly fifteen shadows")
	check(is_equal_approx(s.players[0].pos.x,69.0),"unblocked full travel remains 669 units")
	check(s.tackle_shadows[0].pos.is_equal_approx(Vector3(-600,0,0)) and s.tackle_shadows[-1].pos.is_equal_approx(Vector3(24.4,0,0)),"shadows are left at pre-move positions including last step")
	check(is_equal_approx(s.tackle_shadows[0].age,14.0/32) and s.tackle_shadows[-1].age==0,"new shadow starts age zero after earlier shadows tick")
	var original_shadow=s.tackle_shadows[0].duplicate()
	s.command(0,Vector2(900,500));s.advance(0.1)
	check(s.tackle_shadows[0].pos==original_shadow.pos and s.tackle_shadows[0].angle==original_shadow.angle,"existing shadows do not follow new position or direction")
	s=fresh();s.arena.add_box(Rect2(-570,-300,32,600),200);s.players[0].tackle=640
	for i in range(15):s.step_ball()
	check(s.tackle_shadows.size()==15 and s.tackle_shadows.all(func(v):return v.pos==Vector3(-600,0,0)),"fifteen rejected wall steps retain all fifteen source shadows")
	s=fresh();s.Characters.configure(s.players[0],"h029");s.players[0].body=PI/2;s.players[0].z=125;s.players[0].tackle=640
	s.step_tackle(0)
	check(s.tackle_shadows[0].model=="h00E" and s.tackle_shadows[0].pos.z==125 and s.tackle_shadows[0].angle==PI/2,"morph tackle still uses Shaman shadow at caster altitude and facing")
	check(s.players.size()==2 and s.arena.pillars.is_empty(),"shadows add no player or collision body")
	s=fresh();Visuals.create(s,0);s.players[0].pos=Vector2(-1200,800)
	check(s.catch_hit(Vector3(-700,0,0),Vector3(200,0,0)).is_empty(),"abandoned shadow cannot catch a passing ball")
	check(s.free_point(Vector2(-600,0),1),"abandoned shadow cannot block another player's route")
	check(is_equal_approx(Visuals.alpha(0),127.0/255) and is_equal_approx(Visuals.alpha(0.03),127.0/255),"initial alpha127 remains until first 32Hz alpha tick")
	check(is_equal_approx(Visuals.alpha(1.0/32),124.0/255) and is_equal_approx(Visuals.alpha(42.0/32),1.0/255),"each alpha tick subtracts three")
	check(Visuals.alpha(43.0/32)==0 and Visuals.alpha(1.4)==0,"alpha clamps at zero before removal")
	check(is_equal_approx(Visuals.animation_time(0.05),0.2) and is_equal_approx(Visuals.animation_time(0.10),0.4),"shadow attack advances at four times speed for first tenth second")
	check(is_equal_approx(Visuals.animation_time(0.60),0.55),"remaining attack animation advances at 0.30 speed")
	s=fresh();Visuals.create(s,0)
	for i in range(44):s.step_ball()
	check(s.tackle_shadows.size()==1,"shadow state survives last 32Hz tick before 1.4 seconds")
	s.step_ball();check(s.tackle_shadows.is_empty(),"expired shadow state is removed on next simulation tick")
	s=fresh();Visuals.create(s,0);s.match_enabled=true;s.match_state="goal";s.reset_delay=4
	for i in range(45):s.step_ball()
	check(s.tackle_shadows.is_empty(),"goal celebration does not freeze and accumulate old shadows")
	s=fresh();Visuals.create(s,0);var old_id=s.tackle_shadows[0].id;s.reset()
	check(s.tackle_shadows.is_empty(),"reset clears old shadows")
	Visuals.create(s,0);check(s.tackle_shadows[0].id>old_id,"new match shadows cannot reuse an old render instance id")
	var a=framed(30);var b=framed(144)
	check(a.players[0].pos.is_equal_approx(b.players[0].pos) and a.tackle_shadows.size()==15 and b.tackle_shadows.size()==15,"30 and 144 fps produce same completed tackle and shadow count")
	var equal=true
	for i in range(a.tackle_shadows.size()):
		equal=equal and a.tackle_shadows[i].pos.is_equal_approx(b.tackle_shadows[i].pos) and is_equal_approx(a.tackle_shadows[i].age,b.tackle_shadows[i].age)
	check(equal,"shadow poses and lifetimes are independent of rendering frame rate")
	var f=FileAccess.open("res://research/tackle-detail-tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"basis":"Preserved Tackle/Alpha JASS; not a new Warcraft runtime calibration","checks":checks},"\t"))
	quit(1 if failed else 0)
