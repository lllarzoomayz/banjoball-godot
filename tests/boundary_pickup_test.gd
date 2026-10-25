extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var checks=[]
var cases=[]
var failed=false
func _initialize():call_deferred("run")
func check(ok: bool,label: String):
	checks.append({"test":label,"passed":ok})
	failed=failed or not ok
	if not ok:printerr("FAIL "+label)
func scene(field: int=0):
	var s=Sim.new();s.selected_field=field;s.start_practice();s.bot_enabled=false
	for i in range(s.players.size()):
		var p=s.players[i];s.Characters.configure(p,"h005");p.cooldown=999
		p.pos=Vector2(-800+i*800,-900);p.previous=p.pos
	s.holder=-1;s.last_owner=-1;s.intercept=0;s.velocity=Vector3.ZERO
	return s
func stranded(field: int,sx: float,sy: float):
	var s=scene(field)
	# Reproduce the reported route, not merely teleport a ball into the fence:
	# leave the open goal corridor tangentially and come to rest in its side bound.
	s.ball=Vector3(sx*(s.arena.half_size.x+8),sy*180,0);s.previous_ball=s.ball
	s.velocity=Vector3(0,sy*24,0)
	for tick in range(192):s.advance(1.0/32)
	return s
func recovery(field: int,sx: float,sy: float,ai: bool):
	var s=stranded(field,sx,sy);var point=s.ball
	var label="field %d edge %s/%s %s"%[field,sx,sy,"AI" if ai else "joystick"]
	check(s.holder==-1 and s.velocity.length()<0.001 and absf(point.y)>288,label+" ball actually rests after tangential entry")
	var index=1 if ai else 0;var p=s.players[index]
	p.pos=Vector2(point.x-sx*300,point.y);p.previous=p.pos;p.angle=0 if sx>0 else PI;p.body=p.angle
	p.role="chaser"
	if ai:s.bot_enabled=true
	else:s.DirectionalMotion.order(s,index,Vector2(sx,0))
	var valid=true;var caught=false;var seconds=0.0
	for tick in range(192):
		s.advance(1.0/32);seconds+=1.0/32
		valid=valid and s.arena.point_free(p.pos,p.radius)
		if s.holder==index:caught=true;break
	check(caught,label+" recovers ball without referee or rescue teleport")
	check(valid,label+" player respects walking blockers")
	if caught:
		check(absf(s.ball.x)<=s.arena.half_size.x,label+" caught ball stays on inner side of fence")
		if ai:s.bot_enabled=false
		s.DirectionalMotion.order(s,index,Vector2(-sx,0))
		for tick in range(32):s.advance(1.0/32)
		check(s.holder==index and absf(s.ball.x)<s.arena.half_size.x-50,label+" can carry recovered ball back into play")
	cases.append({"case":label,"stranded_ball":str(point),"caught":caught,"seconds":seconds})
func fake(s,point: Vector3):
	s.next_fake_id+=1
	var copy={"id":s.next_fake_id,"creator":1,"team":1,"position":point,"previous":point,"velocity":Vector3.ZERO,"holder":-1,"last_owner":1,"intercept":0,"life":10.0}
	s.fake_balls.append(copy)
	return copy
func run():
	for field in range(4):
		for sx in [-1.0,1.0]:
			for sy in [-1.0,1.0]:
				recovery(field,sx,sy,false)
				recovery(field,sx,sy,true)
	var s=scene();var edge=s.arena.half_size.x
	s.ball=Vector3(edge+8,800,0)
	for distance in [7.0,44.0,74.0,90.0]:
		s.players[0].pos=Vector2(s.ball.x-distance,s.ball.y)
		check(s.catch_hit(s.ball,Vector3.ZERO).get("player",-1)==0,"free ball within original range is reachable: "+str(distance))
	s.players[0].pos.x=s.ball.x-90.01
	check(s.catch_hit(s.ball,Vector3.ZERO).is_empty(),"catch range has not increased")
	s.players[0].pos.x=s.ball.x-44
	check(s.catch_hit(s.ball+Vector3(0,0,s.players[0].catch_height+1),Vector3.ZERO).is_empty(),"catch height is unchanged")
	check(s.catch_hit(s.ball,Vector3.ZERO,0,1).is_empty(),"kicker recatch protection is unchanged")
	s.players[0].eject_time=1
	check(s.catch_hit(s.ball,Vector3.ZERO).is_empty(),"uncatchable player remains excluded")
	s.players[0].eject_time=0
	var copy=fake(s,s.ball);s.ball=Vector3.ZERO;s.Copies.step(s)
	check(copy.holder==0,"free fake ball has the same fence pickup policy")
	for fake_ball in [false,true]:
		s=scene();s.players[1].pos=Vector2(edge+1,800);s.players[1].body=0
		s.players[0].pos=Vector2(edge-190,800)
		if fake_ball:
			copy=fake(s,Vector3.ZERO);s.Copies.take(s,copy,1)
		else:s.take(1)
		s.step_ball();s.players[0].pos=Vector2(edge-60,800);s.step_ball()
		check((copy.holder if fake_ball else s.holder)==0,"near-fence held ball can be stolen, fake="+str(fake_ball))
		# Only the scoring ball uses range-entry snapshots; this scoped change
		# does not replace the existing fake-ball proximity/reacquisition policy.
		if not fake_ball:
			s.step_ball()
			check(s.holder==0,"scoring-ball pickup does not ping-pong")
	s=scene();s.players[0].pos=Vector2(edge-26,800);s.players[0].body=0;s.take(0)
	check(absf(s.ball.x-(edge-0.2))<0.001,"held-ball clipping retains original inside-edge position")
	s=scene();s.players[0].pos=Vector2(-40,0);s.ball=Vector3(40,0,0)
	s.arena.add_box(Rect2(-5,-100,10,200),240)
	check(s.catch_hit(s.ball,Vector3.ZERO).is_empty(),"practice wall still occludes pickup")
	s=scene();s.players[0].pos=Vector2(-150,0);s.ball=Vector3(-80,0,0);s.arena.add_pillar(Vector2.ZERO,1)
	check(s.catch_hit(s.ball,Vector3.ZERO).is_empty(),"totem still occludes real-ball pickup")
	check(s.catch_hit(s.ball,Vector3.ZERO,-1,0,1).get("player",-1)==0,"existing fake-ball totem exception is preserved")
	s=scene();var goal=s.arena.goals[1];s.players[0].pos=Vector2(goal.position.x-40,0);s.players[0].z=320
	check(s.catch_hit(Vector3(goal.position.x+20,0,320),Vector3.ZERO).is_empty(),"goal overhead blocker remains in pickup query")
	FileAccess.open("res://research/boundary-pickup-test.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"cases":cases},"\t"))
	print("BOUNDARY PICKUP ",checks.size()," checks; failed=",failed)
	quit(1 if failed else 0)
