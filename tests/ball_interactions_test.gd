extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var results=[]
var failed=false
func check(ok: bool,label: String,detail=""):
	results.append({"test":label,"passed":ok,"detail":str(detail)})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+label+" "+str(detail))
func _initialize():call_deferred("run")
func scene(id="h005"):
	var s=Sim.new();s.selected_character=id;s.start_practice()
	s.players[0].pos=Vector2(-1400,-900);s.players[1].pos=Vector2(1400,900)
	s.ball=Vector3(1200,-900,0);s.holder=-1;s.last_owner=1
	return s
func fake(s,position: Vector3,velocity=Vector3.ZERO):
	s.next_fake_id+=1
	var c={"id":s.next_fake_id,"creator":1,"team":1,"position":position,"previous":position,"velocity":velocity,"holder":-1,"last_owner":1,"intercept":0,"life":10.0}
	s.fake_balls.append(c)
	return c
func run():
	var s=scene("h00P");s.players[0].pos=Vector2.ZERO;s.ball=Vector3(300,0,0)
	var c=fake(s,s.ball);var held=fake(s,Vector3(310,0,0));held.holder=1
	var far=fake(s,Vector3(900,0,0));var high=fake(s,Vector3(300,0,700))
	s.Characters.slam(s,0)
	check(c.velocity.distance_to(s.velocity)<0.00001 and c.velocity.z>0 and absf(c.velocity.length()-39.453739)<0.0001,"slam gives every free ball the original distance-scaled upward impulse",c.velocity)
	check(c.last_owner==0 and c.creator==1 and c.team==1,"slam changes last toucher without changing fake identity or team tint")
	check(held.velocity==Vector3.ZERO and far.velocity==Vector3.ZERO and high.velocity==Vector3.ZERO,"slam excludes held balls and respects full three-dimensional range")
	s.players[0].z=601;c.position=Vector3(300,0,601);c.velocity=Vector3(2,3,4);c.last_owner=1;s.Characters.slam(s,0)
	check(c.velocity==Vector3(2,3,4) and c.last_owner==0,"high caster applies zero impulse but still assigns in-range ball ownership")
	s=scene("h02C");s.players[0].ability_target=Vector2.ZERO;s.ball=Vector3.ZERO;c=fake(s,s.ball)
	s.Characters.create_pillar(s,0)
	check(s.velocity.z==17.5 and c.velocity==Vector3.ZERO,"pillar birth launches the real ball but does not launch a copy")
	s=scene();s.arena.add_pillar(Vector2.ZERO,0);s.ball=Vector3(-130,0,50);s.velocity=Vector3(80,0,0);c=fake(s,s.ball,s.velocity)
	s.step_ball()
	check(s.velocity.x<0 and c.velocity.x>0 and c.position.x> -90,"real ball reflects from totem while fake traverses the same contact")
	s=scene();s.arena.add_pillar(Vector2.ZERO,0);s.players[0].pos=Vector2(-150,0)
	c=fake(s,Vector3(-80,0,0))
	check(s.catch_hit(c.position,Vector3.ZERO,-1,0).is_empty() and s.catch_hit(c.position,Vector3.ZERO,-1,0,c.id).get("player",-1)==0,"totem blocks real reach but permits reaching a fake")
	s.Copies.take(s,c,0)
	check(c.position==Vector3(-50,0,0) and s.Copies.held_position(s,0).x< -90,"held fake offset passes through totem while real held offset is clipped")
	s.players[1].pos=Vector2(-100,0);s.Copies.step(s)
	check(c.holder==1,"fake can be intercepted through a totem using the same fake-only contact policy")
	s=scene();s.arena.add_box(Rect2(-5,-100,10,200),240);c=fake(s,Vector3(-50,0,50),Vector3(100,0,0));s.Copies.step(s)
	check(c.velocity.x<0 and c.position.x< -30,"excluding totems does not let a fake cross a practice wall")
	s=scene();c=fake(s,Vector3(1960,700,50),Vector3(200,0,0));s.Copies.step(s)
	check(c.velocity.x<0,"fake still bounces from authored field boundary")
	s=scene();s.powershot_active=true;c=fake(s,Vector3.ZERO,Vector3(30,0,0));s.Copies.step(s)
	check(absf(c.velocity.x-29.98)<0.00001,"active powershot applies global ground friction to copies",c.velocity)
	c.position=Vector3(0,0,300);c.velocity=Vector3(20,0,10);s.Copies.step(s)
	var air=Vector3(20,0,8.5)
	check(c.velocity.distance_to(air.normalized()*(air.length()-0.02))<0.00001,"global powershot air friction includes a fake after gravity")
	c.position=Vector3(0,0,2);c.velocity=Vector3(0,0,-8);s.Copies.step(s)
	check(absf(c.velocity.z-8.73)<0.0001 and c.position.z==0,"fake ground rebound uses global powershot loss")
	s=scene();s.arena.add_box(Rect2(-5,-100,10,200),240);s.powershot_active=true
	c=fake(s,Vector3(-50,0,50),Vector3(100,0,0));s.Copies.step(s)
	check(absf(c.velocity.x+99.980002)<0.0001,"powershot removes the usual fixed wall speed loss for copies",c.velocity)
	s=scene();s.powershot_active=true;s.velocity=Vector3(51,0,0);c=fake(s,Vector3.ZERO,Vector3(30,0,7));s.Copies.take(s,c,0)
	check(not s.powershot_active and s.holder==-1 and s.velocity==Vector3(51,0,0),"fake take ends the global powershot state without taking the scoring ball")
	check(s.players[0].knock==Vector2.ZERO and s.players[0].vz==0,"fake catcher does not receive the real power ball impact")
	s=scene();s.powershot_active=true;s.velocity=Vector3(51,0,8);s.take(0)
	check(s.players[0].knock.distance_to(Vector2(43.35,0))<0.00001 and absf(s.players[0].vz-6.8)<0.00001 and s.velocity==Vector3.ZERO,"real power-ball take blasts its actual receiver before clearing velocity")
	s=scene();s.players[0].pos=Vector2.ZERO;s.powershot_active=true
	c=fake(s,Vector3(50,0,0));var later=fake(s,Vector3(700,-700,0),Vector3(30,0,0));s.Copies.step(s)
	check(c.holder==0 and absf(later.velocity.x-29.55)<0.00001,"fake catch restores ordinary friction before the next ball slot advances")
	s=scene("h00F");s.take(0);s.Characters.use(s,0,Vector2(1800,0));c=fake(s,Vector3.ZERO);s.Copies.take(s,c,1)
	check(s.players[0].ability_delay>0 and s.holder==0,"catching a fake does not interrupt charging while the caster still owns the real ball")
	s.holder=-1;s.last_owner=1;s.on_ball_taken()
	check(s.players[0].ability_delay==0 and s.players[0].disabled==0,"global ball event cancels charge when main ball owner differs from caster")
	s=scene("h00Y");s.Characters.use(s,0,Vector2.ZERO);c=fake(s,Vector3.ZERO);s.Copies.take(s,c,0)
	check(s.players[0].pull_time>0,"catching a fake does not stop a pull toward another owner's real ball")
	s=scene("h00Y");s.last_owner=0;s.Characters.use(s,0,Vector2.ZERO);c=fake(s,Vector3.ZERO);s.Copies.take(s,c,1)
	check(s.players[0].pull_time==0 and s.players[0].cooldown==10,"fake take triggers pull cancellation for the real ball's last owner")
	s=scene("h012");s.curve={"owner":0};s.players[0].mana=8;s.players[1].mana=9;c=fake(s,Vector3.ZERO);s.Copies.take(s,c,0)
	check(s.curve.is_empty() and s.players[0].mana==8 and s.players[1].mana==9,"fake catch ends a free real-ball curve without granting fake receiver mana")
	s=scene("h012");s.take(0);s.players[0].mana=8;s.players[1].mana=17;s.curve={"owner":0};c=fake(s,Vector3.ZERO);s.Copies.take(s,c,1)
	check(s.players[0].mana==100 and s.players[1].mana==17 and s.curve.is_empty(),"global curve callback rewards held real ball's ally, independent of fake catcher")
	for keep in [true,false]:
		s=scene("h01N");s.players[0].pos=Vector2.ZERO;s.take(0);s.step_ball();s.players[0].mana=8;s.curve={"owner":0}
		check(s.Characters.use(s,0,Vector2(1500,0),not keep),"trickster cast succeeds with keep="+str(keep))
		c=s.fake_balls[0]
		check(s.curve.is_empty() and s.players[0].mana==8 and (s.holder==0)==keep and (c.holder==0)!=keep,"trickster creation dispatches take events in source order, keep="+str(keep))
		check(s.last_owner==0 and s.players[0].cooldown==14 and s.no_steal==0,"trickster preserves scoring owner and fourteen-second cooldown")
	s=scene("h01N");s.players[0].pos=Vector2.ZERO;s.take(0);s.step_ball();s.Copies.create(s,0,true,Vector2(1500,0));c=s.fake_balls[0]
	c.life=2.25;s.Copies.take(s,c,1);var identity=c.id
	s.Copies.create(s,0,true,Vector2(0,1500))
	check(s.fake_balls.size()==1 and c.id==identity and c.life==2.25 and c.holder==-1 and s.holder==0,"repeated trickster cast reclaims its own slot without resetting fake lifetime")
	check(c.velocity.distance_to((Vector3(0,1500,0)-c.position).normalized()*30+Vector3(0,0,7))<0.0001,"reused fake is kicked from the new held position")
	s=scene("h003");s.players[0].pos=Vector2(-600,0);s.ball=Vector3(300,0,50);c=fake(s,s.ball)
	s.Characters.use(s,0,Vector2.ZERO);s.Characters.step(s);s.Characters.step(s)
	check(s.velocity.x<0 and c.velocity==Vector3.ZERO,"black hole changes free real ball motion but does not attract fake")
	s=scene("h026");s.players[0].pos=Vector2.ZERO;s.ball=Vector3(200,0,0);c=fake(s,s.ball);s.Characters.smash(s,0)
	check(s.velocity==Vector3(45,0,0) and c.velocity==Vector3.ZERO,"ogre smash hits true ball only")
	s=scene("h01R");c=fake(s,Vector3.ZERO)
	var hit=s.Characters.Complex.hook_candidate(s,{"owner":0,"friendly":false},Vector3(-200,0,0),Vector3(400,0,0))
	check(hit.is_empty(),"hook proximity scan does not attach to free fake")
	s.ball=Vector3.ZERO;hit=s.Characters.Complex.hook_candidate(s,{"owner":0,"friendly":false},Vector3(-200,0,0),Vector3(400,0,0))
	check(hit.get("player",-1)==-2,"same hook scan attaches to true ball")
	s=scene("h027");c=fake(s,Vector3.ZERO);s.ball=Vector3.ZERO
	var r={"owner":0,"a":Vector3.ZERO,"b":Vector3(700,0,0),"life":3.0,"age":0.0,"unlock":0.0,"projectile":0,"traveled":{}}
	s.rifts.append(r);s.Characters.Complex.step(s)
	check(s.ball.x==700 and c.position==Vector3.ZERO,"rift teleports free true ball while free fake stays at entrance")
	s.players[1].pos=Vector2.ZERO;s.Copies.take(s,c,1);s.Characters.Complex.step(s)
	check(s.players[1].pos.x>650 and c.position.distance_to(s.Copies.held_position(s,1,false))<0.001,"held fake follows its player through a rift")
	for id in ["h00F","h010","h012","h01N"]:
		s=scene(id);c=fake(s,Vector3.ZERO);s.Copies.take(s,c,0)
		check(not s.Characters.use(s,0,Vector2(800,0)) and s.players[0].cooldown==0,"fake possession cannot activate true-ball-only kit "+id)
	var slow=scene("h00P");var fast=scene("h00P")
	for world in [slow,fast]:
		world.players[0].pos=Vector2(-700,0);world.ball=Vector3(-300,0,0);world.velocity=Vector3(25,0,0)
		fake(world,Vector3(-300,200,0),Vector3(25,0,0));world.arena.add_pillar(Vector2(100,0),1)
		world.powershot_active=true;world.Characters.use(world,0,Vector2.ZERO)
	for i in range(90):slow.advance(1.0/30)
	for i in range(432):fast.advance(1.0/144)
	check(slow.ball.distance_to(fast.ball)<0.001 and slow.velocity.distance_to(fast.velocity)<0.001 and slow.fake_balls[0].position.distance_to(fast.fake_balls[0].position)<0.001 and slow.fake_balls[0].velocity.distance_to(fast.fake_balls[0].velocity)<0.001,"combined slam totem and global friction are independent of rendering frame rate")
	FileAccess.open("res://research/ball-interactions-tests.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":results},"\t"))
	quit(1 if failed else 0)
