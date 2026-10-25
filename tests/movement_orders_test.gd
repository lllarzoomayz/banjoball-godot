extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var checks=[]
var failed=false
func check(ok: bool,label: String,detail=""):
	checks.append({"test":label,"passed":ok,"detail":str(detail)});failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+label+" "+str(detail))
func _initialize():call_deferred("run")
func scene(field=2,id="h005"):
	var s=Sim.new();s.selected_field=field;s.selected_character=id;s.start_practice()
	s.players[0].pos=Vector2(-600,0);s.players[0].angle=0;s.players[0].body=0
	s.players[1].pos=Vector2(1400,900);s.ball=Vector3(1000,-900,0)
	return s
func run():
	for field in range(4):
		var s=scene(field);var p=s.players[0]
		s.submit_command("move_order",0,Vector2(900,0));s.step_movement()
		check(p.pos.x> -600 and p.want_move and not p.slide_order and not p.object_active,"field %d explicit move walks without starting smart-order Object callback"%field)
		s.step_object_impulses()
		check(p.knock==Vector2.ZERO and p.pathing_enabled,"field %d explicit move keeps ordinary collision and adds no ice thrust"%field)
		s.command(0,Vector2(900,0));s.step_object_impulses()
		check(p.slide_order and (p.knock.x>0 if field>=2 else p.knock==Vector2.ZERO),"field %d right click retains original surface-specific behavior"%field)
	for id in ["h003","h02C","h027"]:
		var s=scene(2,id);var p=s.players[0]
		var accepted=s.Characters.use(s,0,Vector2(900,0))
		check(accepted and not p.ability_order.is_empty() and p.want_move and not p.object_active and not p.slide_order,"spell approach does not synthesize a smart order for "+id)
		# A delayed final Object callback can otherwise overwrite another skill's
		# collision state. No motion/height is injected in this focused case.
		s.set_unit_pathing(0,false);s.step_object_impulses()
		check(not p.pathing_enabled,"queued approach cannot accidentally restore phased collision for "+id)
		s.set_unit_pathing(0,true)
		for i in range(210):s.advance(0.03)
		var fired=p.cooldown>0 if id!="h027" else (not p.rift.is_empty() and p.rift.count==1)
		check(p.ability_order.is_empty() and fired and p.knock==Vector2.ZERO,"spell reaches range and fires once without fake ice momentum for "+id)
	var s=scene();var p=s.players[0]
	s.command(0,Vector2(900,0));s.advance(0.25);var velocity=p.knock.x
	s.command(0,Vector2(900,0),false);s.step_object_impulses()
	check(not p.slide_order and p.object_active and p.knock.x>0 and p.knock.x<velocity,"explicit move cancels new ice thrust but preserves existing inertia")
	s=scene();p=s.players[0];s.tackle(0,Vector2(900,0));s.command(0,Vector2(-600,900),false)
	s.advance(0.2)
	check(p.tackle>0 and p.body>0 and p.knock==Vector2.ZERO and not p.pathing_enabled and not p.object_active,"explicit move steers active tackle without inventing an Object collision callback")
	s=scene();p=s.players[0];s.tackle(0,Vector2(900,0));s.command(0,Vector2(-600,900));s.advance(0.2)
	check(p.tackle>0 and p.body>0 and p.knock.length()>0 and p.object_active,"right-click tackle steering still invokes original ice push")
	s=scene(0);p=s.players[0];s.arena.add_box(Rect2(-100,-350,100,700),240);s.command(0,Vector2(600,0),false)
	var safe=true;var detour=0.0
	for i in range(500):
		s.advance(0.03);safe=safe and s.arena.point_free(p.pos,p.radius);detour=maxf(detour,absf(p.pos.y))
	check(safe and detour>350 and p.pos.distance_to(Vector2(600,0))<16,"explicit move uses the same obstacle route and real player footprint",p.pos)
	for order in ["move","move_order","stop"]:
		s=scene(0,"h003");p=s.players[0];s.Characters.use(s,0,Vector2(900,0));s.submit_command(order,0,Vector2(-1000,0));s.advance(6)
		check(p.ability_order.is_empty() and s.skill_effects.is_empty() and p.cooldown==0,"new "+order+" cancels a queued distant cast")
	for smart in [false,true]:
		s=scene(2,"h010");p=s.players[0];p.possess_time=4;s.holder=-1;s.last_owner=0;s.ball=Vector3(p.pos.x,p.pos.y,100)
		s.command(0,Vector2(1000,0),smart)
		check(p.jump_due and p.jump_target==Vector2(1000,0),"possessed ball explicitly accepts both move and smart orders smart="+str(smart))
	for smart in [false,true]:
		s=scene(2,"h00F");p=s.players[0];s.take(0);s.step_ball();s.Characters.use(s,0,Vector2(1200,0))
		s.command(0,Vector2(500,500),smart);s.step_object_impulses()
		check(p.ability_delay>0 and p.want_move!=smart and not p.slide_order and p.knock==Vector2.ZERO,"powershot smart uses nested stop; move retains follow-up destination smart="+str(smart))
		s.advance(0.6)
		check(s.holder==-1 and s.powershot_active and p.want_move!=smart,"both orders preserve scheduled charged shot smart="+str(smart))
	var a=framed(30);var b=framed(144)
	check(a.players[0].pos.distance_to(b.players[0].pos)<0.001 and a.players[0].knock.distance_to(b.players[0].knock)<0.001,"mixed smart/move steering remains render-frame independent")
	FileAccess.open("res://research/movement-orders-tests.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks},"\t"))
	quit(1 if failed else 0)
func framed(rate: int):
	var s=scene();s.submit_command("tackle",0,Vector2(1000,0))
	var time=0.0;var issued=false
	while time<1.0-0.000001:
		var end=minf(1.0,time+1.0/rate)
		if not issued and end>=0.18:
			s.advance(0.18-time);time=0.18;s.submit_command("move_order",0,Vector2(-600,900));issued=true
		s.advance(end-time);time=end
	return s
