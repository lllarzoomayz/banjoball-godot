extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
const Motion=preload("res://scripts/object_motion.gd")
var checks=[]
var failed=false
func check(ok: bool,label: String,detail=""):
	checks.append({"test":label,"passed":ok,"detail":str(detail)})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+label+" "+str(detail))
func _initialize():call_deferred("run")
func scene(field=0):
	var s=Sim.new();s.selected_field=field;s.start_practice()
	s.players[1].pos=Vector2(1000,-900);s.ball=Vector3(-1000,-900,0)
	return s
func frames(s,seconds: float,fps: int):
	var left=seconds
	while left>0.00000001:
		var dt=minf(left,1.0/fps);s.advance(dt);left-=dt
func run():
	check(Motion.boundary_reflect(Vector3(40,12,6),Vector3(-1,0,0))==Vector3(-25,12,6),"boundary response loses fifteen from normal impact and preserves tangent and vertical motion")
	check(Motion.boundary_reflect(Vector3(15,0,0),Vector3(-1,0,0))==Vector3(-15,0,0),"player impact of exactly fifteen fully rebounds")
	check(absf(Motion.boundary_reflect(Vector3(15.01,0,0),Vector3(-1,0,0)).x+0.01)<0.00001,"player impact above fifteen uses strict source threshold")
	check(Motion.boundary_reflect(Vector3(5,7,0),Vector3(-1,0,0))==Vector3(-5,7,0),"small player impact rebounds instead of being clamped to zero")
	check(Motion.boundary_reflect(Vector3(-5,7,0),Vector3(-1,0,0))==Vector3(-5,7,0),"already separating motion is unchanged")
	var normal=Vector3(-1,-1,0).normalized();var v=Vector3(40,20,5);var out=Motion.boundary_reflect(v,normal)
	check(absf(out.dot(normal)-(-v.dot(normal)-15))<0.00001 and absf(out.dot(Vector3(-normal.y,normal.x,0))-v.dot(Vector3(-normal.y,normal.x,0)))<0.00001 and out.z==5,"diagonal boundary uses authored normal rather than rectangle face")
	var s=scene();var p=s.players[0]
	p.pos=Vector2(2020,700);s.apply_impulse(0,Vector3(30,40,0))
	check(Vector3(p.knock.x,p.knock.y,p.vz)==Vector3(-30,25,0),"adding force while already in boundary follows distinct BoundaryCheck tangent rule")
	p.knock=Vector2.ZERO;s.apply_impulse(0,Vector3(30,12,0))
	check(p.knock==Vector2(0,12),"BoundaryCheck removes normal when remaining tangent is not above fifteen")
	p.knock=Vector2.ZERO;s.apply_impulse(0,Vector3(30,0,20))
	check(p.knock.distance_to(Vector2(-30,0))<0.00001 and absf(p.vz-5)<0.00001,"BoundaryCheck remaining length includes vertical motion",[p.knock,p.vz])
	s=scene();p=s.players[0];p.pos=Vector2(2020,700);s.apply_impulse(0,Vector3(-30,12,0))
	check(p.knock==Vector2(-30,12),"new force away from existing boundary is not reflected again")
	s=scene();s.players[1].pos=Vector2(2020,700);s.players[1].knock=Vector2(40,0)
	s.skill_effects.append({"kind":"black_hole","pos":Vector3(1900,700,0),"life":2.0,"age":1.5,"power":36000.0,"owner":0});s.Characters.step(s)
	check(s.players[1].knock.length()<0.00001,"black-hole force dispatches BoundaryCheck before its sixty-speed cap")
	for field in range(4):
		s=scene(field);p=s.players[0];p.pos=Vector2(0,s.arena.half_size.y-12);p.knock=Vector2(10,40)
		var raw=Vector2(10,40);var speed=raw.length();var drag=0.40 if field>=2 else 0.65
		var x=10*(speed-drag)/speed;var y=40*(speed-drag)/speed
		s.step_object_impulses()
		check(absf(p.knock.x-x)<0.00001 and absf(p.knock.y+y-15)<0.00001,"field "+str(field)+" integrates friction before native boundary reflection",p.knock)
		var expected=s.arena.half_size.y-0.01-(y-15)*(1.0-12.0/y)
		check(absf(p.pos.y-expected)<0.001 and absf(p.pos.x-x)<0.001,"field "+str(field)+" moves to center boundary and uses remaining tick after rebound",p.pos)
		s=scene(field);p=s.players[0];p.pos=Vector2(s.arena.half_size.x-5,800);p.knock=Vector2(10,0);s.step_object_impulses()
		check(p.knock.x< -9 and p.pos.x<s.arena.half_size.x,"field "+str(field)+" small side impact bounces inward")
	s=scene();p=s.players[0];p.pos=Vector2(0,1200);p.knock=Vector2(0,6000);s.step_object_impulses()
	check(p.pos.is_finite() and absf(p.pos.y)<=s.arena.half_size.y and p.knock.is_finite(),"large impulse can rebound from multiple native boundaries in one update",p.pos)
	s=scene();p=s.players[0];p.pos=Vector2(0,1300);p.knock=Vector2(0,80);p.ogre_slow=1;s.step_object_impulses()
	check(p.knock==Vector2.ZERO and p.vz==0 and p.ogre_slow==0 and p.stun==1.5,"ogre-smashed player stops and is stunned at native field boundary")
	s=scene();p=s.players[0];p.pos=Vector2(-2500,0);p.knock=Vector2(-80,0);p.ogre_slow=1;s.step_object_impulses()
	check(p.knock==Vector2.ZERO and p.ogre_slow==0 and p.stun==0,"ogre boundary hit inside own goal stops without stun")
	s=scene();p=s.players[0];p.pos=Vector2(1595,0);p.knock=Vector2(40,0);p.ogre_slow=1;s.step_object_impulses()
	check(absf(p.knock.x+19.675)<0.00001 and p.ogre_slow==1 and p.stun==0,"forbidden goal uses half-speed rebound, not ogre boundary stun")
	check(p.pos.x<1590 and p.pos.x>1550,"right goal repairs to ten units before front edge then moves inward",p.pos)
	s=scene();p=s.players[0];p.team=1;p.pos=Vector2(-1595,0);p.knock=Vector2(-40,0);s.step_object_impulses()
	check(absf(p.knock.x-19.675)<0.00001 and p.pos.x> -1560,"left goal preserves original asymmetric forty-unit exit offset",p.pos)
	s=scene();p=s.players[0];p.pos=Vector2(1800,453);p.knock=Vector2(0,-20);s.step_object_impulses()
	check(p.pos.y>488 and p.knock.y>9,"top goal entrance repairs to forty units beyond upper edge",p.pos)
	s=scene();p=s.players[0];p.pos=Vector2(1800,-453);p.knock=Vector2(0,20);s.step_object_impulses()
	check(p.pos.y< -458 and p.knock.y< -9,"bottom goal entrance repairs ten units past lower edge",p.pos)
	s=scene();var repaired=Motion.goal_exit(s.arena,Vector2(2400,100),1)
	check(repaired.position==Vector2(2016,488) and repaired.normal==Vector2(0,1),"deep goal intrusion first clamps X then chooses nearest original exit")
	p=s.players[0];p.pos=Vector2(1800,100);p.z=250;p.knock=Vector2(20,0);s.step_object_impulses()
	check(p.pos.x<1600 and p.z>248 and p.knock.x<0,"goal repair also handles already-inside airborne object without discarding height")
	s=scene();p=s.players[0];p.pos=Vector2(-1595,0);p.knock=Vector2(-40,0);s.step_object_impulses()
	check(p.pos.x< -1600 and p.knock.x<0,"first own defender may enter protected goal under impulse")
	s.players.append(s.make_player(Vector2(-1595,0),0));s.players[2].knock=Vector2(-40,0);s.step_object_impulses()
	check(s.players[2].pos.x> -1600 and s.players[2].knock.x>0,"second own defender rebounds from occupied goal")
	for swapped in [false,true]:
		s=scene(3)
		if swapped:s.arena.swap_ends()
		p=s.players[0];var direction=s.arena.attack_direction(0);var front: Rect2=s.arena.guards[1][0]
		var edge=front.position.x if direction>0 else front.end.x
		p.pos=Vector2(edge-direction*5,0);p.knock=Vector2(direction*40,0);s.step_object_impulses()
		check(p.knock.x*direction<0 and not s.arena.in_guard(p.pos,1),"large-field goal restriction follows current side assignment swapped="+str(swapped))
	for height in [299.0,300.0,500.0]:
		s=scene();p=s.players[0];p.pos=Vector2(-2220,0);p.z=height;p.knock=Vector2(-50,0);s.step_object_impulses()
		check((p.knock.x<0 and p.pos.x< -2240) if height<300 else (p.knock.x>0 and p.pos.x> -2240),"goal high boundary gates object at source height "+str(height),p.pos)
	s=scene();p=s.players[0];p.pos=Vector2(-150,0);p.knock=Vector2(80,0);s.arena.add_box(Rect2(-5,-100,10,200),240);s.step_object_impulses();s.step_object_impulses()
	check(p.pos.x<=-35 and p.knock.x==0,"added practice wall retains its explicit solid stop instead of using field reflection")
	s=scene();p=s.players[0];p.pos=Vector2(-100,0);p.knock=Vector2(40,0);p.vz=10;s.arena.add_pillar(Vector2.ZERO,1);s.step_object_impulses()
	check(p.knock.x<0 and p.vz>0 and p.pos.x< -90,"totem retains ninety-percent full-vector rebound")
	var a=scene(2);var b=scene(2)
	for world in [a,b]:world.players[0].pos=Vector2(0,1250);world.players[0].knock=Vector2(17,60);world.players[0].z=80;world.players[0].vz=20
	frames(a,2,30);frames(b,2,144)
	check(a.players[0].pos.distance_to(b.players[0].pos)<0.001 and a.players[0].knock.distance_to(b.players[0].knock)<0.001 and absf(a.players[0].z-b.players[0].z)<0.001,"airborne ice boundary motion remains independent of rendering frame rate")
	var escaped=[]
	for field in range(4):
		for degrees in range(0,360,15):
			s=scene(field);p=s.players[0];p.pos=Vector2.ZERO;p.knock=Vector2.from_angle(deg_to_rad(degrees))*300;p.z=350
			for tick in range(50):
				s.step_object_impulses()
				if not p.pos.is_finite() or absf(p.pos.x)>s.arena.bounds.end.x+32 or absf(p.pos.y)>s.arena.half_size.y+32:escaped.append([field,degrees,tick,str(p.pos)]);break
	check(escaped.is_empty(),"ninety-six high-speed object trajectories remain inside authored stadium extents",escaped.slice(0,4))
	FileAccess.open("res://research/object-boundary-tests.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks},"\t"))
	quit(1 if failed else 0)
