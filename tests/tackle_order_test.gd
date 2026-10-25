extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var checks=[]
var failed=false

func check(ok: bool,name: String,detail=""):
	checks.append({"test":name,"passed":ok,"detail":str(detail)})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))

func pair(reverse_indices=false):
	var s=Sim.new()
	s.players=[]
	for x in ([180.0,0.0] if reverse_indices else [0.0,180.0]):
		var p=s.make_player(Vector2(x,0),s.players.size());p.angle=0;p.body=0;p.previous_body=0
		s.players.append(p)
	s.ball=Vector3(-1300,700,0)
	return s

func cast(s,order: Array):
	for index in order:s.submit_command("ability",index,s.players[index].pos+Vector2(1000,0))
	s.advance(1.0/32)

func shadow_owners(s) -> Array:
	return s.tackle_shadows.map(func(shadow):return shadow.owner)

func _initialize():call_deferred("run")

func run():
	for reverse_indices in [false,true]:
		var front=0 if reverse_indices else 1;var rear=1-front
		var s=pair(reverse_indices);cast(s,[front,rear])
		check(shadow_owners(s)==[front,rear],"front-first shadows follow activation order, swapped="+str(reverse_indices),shadow_owners(s))
		check(s.players[front].tackle>0 and s.players[rear].tackle>0,"front moves away before following tackle contact, swapped="+str(reverse_indices))
		check(s.players[front].knock==Vector2.ZERO and s.players[rear].knock==Vector2.ZERO,"front-first 180 separation causes no premature impulse, swapped="+str(reverse_indices))
		check(s.players[front].slow==1.5 and s.players[rear].slow==0,"front first sees 224.6 separation; rear then slows front at 180")
		s=pair(reverse_indices);cast(s,[rear,front])
		check(shadow_owners(s)==[rear,front],"rear-first keeps source activation order, swapped="+str(reverse_indices),shadow_owners(s))
		check(s.players[rear].tackle==0 and s.players[front].tackle>0,"rear-first enters 140 contact before front advances")
		check(s.players[rear].knock.is_equal_approx(Vector2(5,0)) and s.players[front].knock.is_equal_approx(Vector2(10,0)),"rear-first applies source 5/10 impulses without same-tick extra travel")
		check(s.players[rear].pos.is_equal_approx(Vector2(44.6,0)) and s.players[front].pos.is_equal_approx(Vector2(224.6,0)),"both active instances still advance once when first one ends")
	# Expected hit set is calculated independently from sequential source moves:
	# 44.6 displacement, 140 forward contact, and immediate end after all contacts.
	for order in [[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]]:
		var s=pair();s.players=[]
		var expected_positions=[0.0,180.0,360.0];var expected_ended=[false,false,false]
		for x in expected_positions:
			var p=s.make_player(Vector2(x,0),0);s.players.append(p)
		for i in order:
			expected_positions[i]+=44.6
			for j in range(3):
				if i!=j and expected_positions[j]>=expected_positions[i] and expected_positions[j]-expected_positions[i]<=140:expected_ended[i]=true
		cast(s,order)
		check(shadow_owners(s)==order,"three-caster shadow sequence "+str(order),shadow_owners(s))
		var correct=true
		for i in range(3):
			if (s.players[i].tackle<=0)!=expected_ended[i] or absf(s.players[i].pos.x-expected_positions[i])>0.001:correct=false
		check(correct,"three-caster source movement/contact sequence "+str(order),expected_ended)
	var s=pair()
	s.players[0].pos=Vector2(-700,-400);s.players[0].angle=PI;s.players[0].body=PI
	s.players[1].pos=Vector2(-700,400)
	s.submit_command("ability",0,Vector2(700,-400));s.submit_command("ability",1,Vector2(700,400))
	s.advance(0.04)
	check(s.players[0].cast_pending and s.players[0].tackle==0 and s.players[1].tackle>0,"first requested spell still prepares turn while second activates")
	s.advance(0.20)
	check(s.players[0].tackle>0 and shadow_owners(s).slice(-2)==[1,0],"actual activation order survives delayed reverse-facing preparation",shadow_owners(s))
	s=pair();s.players[0].pos=Vector2(-700,-400);s.players[1].pos=Vector2(-700,400)
	cast(s,[1,0]);s.command(1,Vector2(700,800));s.stop(0,false);s.KeeperRules.hold(s,1);s.step_ball()
	check(shadow_owners(s).slice(-2)==[1,0] and s.players[0].tackle>0 and s.players[1].tackle>0,"move stop and hold do not cancel or reorder active scripted tackle")
	s.players[1].tackle=10;s.step_ball()
	check(s.players[1].tackle==0 and s.players[0].tackle>0,"oldest instance expiring does not skip younger instance")
	s.players[1].cooldown=0;s.tackle(1,Vector2(700,400));s.step_ball()
	check(shadow_owners(s).slice(-2)==[0,1],"recast after cooldown refresh joins behind still-active instance")
	s=pair();s.players[0].angle=PI;s.players[0].body=PI
	s.submit_command("ability",0,Vector2(1200,0));s.submit_command("stop",0)
	s.submit_command("ability",1,Vector2(1200,0));s.advance(0.04)
	check(shadow_owners(s)==[1] and not s.players[0].cast_pending,"canceled turn preparation leaves no active iterator entry")
	s.reset();s.players[0].pos=Vector2.ZERO;s.players[1].pos=Vector2(180,0)
	s.players[1].angle=0;s.players[1].body=0;s.players[1].previous_body=0;s.ball=Vector3(-1300,700,0)
	s.tackle(1,Vector2(1200,0));s.tackle(0,Vector2(1200,0));s.step_ball()
	check(shadow_owners(s)==[1,0] and s.players[0].tackle>0 and s.players[1].tackle>0,"new round has no stale instances or former order")
	s=pair();s.players=[]
	for i in range(12):s.players.append(s.make_player(Vector2(-700,-825+150*i),i%2))
	var twelve_order=[11,3,8,0,6,2,10,4,1,9,5,7]
	for i in twelve_order:
		s.players[i].angle=0;s.players[i].body=0;s.tackle(i,Vector2(1200,s.players[i].pos.y))
	for tick in range(15):s.step_ball()
	var expected=[]
	for tick in range(15):expected.append_array(twelve_order)
	check(shadow_owners(s)==expected and s.players.all(func(p):return p.tackle==0),"twelve active tackles retain cast order for all 180 updates")
	var a=pair();var b=pair()
	for sim in [a,b]:
		sim.submit_command("ability",1,Vector2(1200,0));sim.submit_command("ability",0,Vector2(1200,0))
	for frame in range(30):a.advance(1.0/30)
	for frame in range(144):b.advance(1.0/144)
	check(a.players[0].pos.is_equal_approx(b.players[0].pos) and a.players[1].pos.is_equal_approx(b.players[1].pos) and a.tackle_shadows==b.tackle_shadows,"activation-order outcome and ghosts agree at 30/144 FPS")
	var f=FileAccess.open("res://research/tackle-order-tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"basis":"JASS List_addElement appends; Tackle_II32 iterates from head.next. Not a native cross-system scheduling verification.","checks":checks},"\t"))
	quit(1 if failed else 0)
