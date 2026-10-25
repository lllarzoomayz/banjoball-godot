extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var checks=[]
var failed=false

func check(ok: bool,name: String,detail=""):
	checks.append({"test":name,"passed":ok,"detail":str(detail)});failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))

func scene(xs: Array):
	var s=Sim.new();s.players=[]
	for x in xs:s.players.append(s.make_player(Vector2(x,0),0))
	s.ball=Vector3(1200,800,0)
	return s

func close(a: float,b: float) -> bool:return absf(a-b)<0.0002

func _initialize():call_deferred("run")

func run():
	# Direct scalar expectations from JASS: friction .65, then displacement,
	# then exchange; the newly appended receiver gets its own .65 this pass.
	for reversed in [false,true]:
		var s=scene([70.0,0.0] if reversed else [0.0,70.0])
		var source=1 if reversed else 0;var victim=1-source
		s.apply_impulse(source,Vector3(20,0,0));s.step_object_impulses()
		check(close(s.players[source].pos.x,19.35) and close(s.players[victim].pos.x,88.7),"sleeping victim joins same pass regardless of player index "+str(reversed),[s.players[source].pos,s.players[victim].pos])
		check(close(s.players[source].knock.x,0) and close(s.players[victim].knock.x,18.7),"each newly moving object pays its own friction "+str(reversed))
		check(s.players[source].object_active and s.players[victim].object_active,"zero source retains final enabling callback "+str(reversed))
		s.set_unit_pathing(source,false);s.step_object_impulses()
		check(not s.players[source].object_active and s.navigation_solid(s.players[source]),"final zero callback restores pathing then sleeps "+str(reversed))
	# Both were active before this pass: exact relative motion depends on
	# activation order, not array index. An existing receiver isn't appended.
	for first in [0,1]:
		var s=scene([0.0,70.0])
		for index in [first,1-first]:s.apply_impulse(index,Vector3(20 if index==0 else -10,0,0))
		s.step_object_impulses()
		var expected=[19.35,88.7] if first==0 else [-8.7,60.65]
		var velocities=[-10.0,18.7] if first==0 else [-8.7,20.0]
		check(close(s.players[0].pos.x,expected[0]) and close(s.players[1].pos.x,expected[1]),"preexisting movers retain activation order "+str(first),s.players.map(func(p):return p.pos))
		check(close(s.players[0].knock.x,velocities[0]) and close(s.players[1].knock.x,velocities[1]),"already visited receiver does not move twice "+str(first))
	# A three-body transfer has only one new forward contact at each step;
	# all permutations must have the same world-space outcome.
	for layout in [[0.0,70.0,140.0],[0.0,140.0,70.0],[70.0,0.0,140.0],[70.0,140.0,0.0],[140.0,0.0,70.0],[140.0,70.0,0.0]]:
		var s=scene(layout);s.apply_impulse(layout.find(0.0),Vector3(30,0,0));s.step_object_impulses()
		var right=true
		for role in range(3):
			var p=s.players[layout.find(role*70.0)]
			if not close(p.pos.x,[29.35,98.7,168.05][role]) or not close(p.knock.x,28.05 if role==2 else 0):right=false
		check(right,"live tail visits chain of newly awakened victims "+str(layout),s.players.map(func(p):return p.pos))
	var s=scene([0.0,70.0]);s.apply_impulse(1,Vector3.ZERO);s.apply_impulse(0,Vector3(20,0,0));s.step_object_impulses()
	check(close(s.players[1].pos.x,88.7) and s.players[1].object_active,"stopped earlier member can rejoin tail on later impact")
	s=scene([0.0,70.0]);s.apply_impulse(0,Vector3(20,0,0));s.apply_impulse(1,Vector3(-10,0,0));s.apply_impulse(0,Vector3.ZERO);s.step_object_impulses()
	check(close(s.players[0].pos.x,19.35) and close(s.players[1].pos.x,88.7),"additional impulse keeps an already active member in place")
	s=scene([0.0,70.0]);s.command(1,Vector2(1000,0));s.apply_impulse(0,Vector3(20,0,0));s.step_object_impulses()
	check(close(s.players[1].pos.x,88.7) and s.players[1].want_move,"smart-order zero callback can sleep and be hit in same pass")
	s=scene([0.0,70.0]);s.apply_impulse(0,Vector3(-20,0,0));s.step_object_impulses()
	check(s.players[1].pos==Vector2(70,0) and not s.players[1].object_active,"separating bodies do not wake a stationary neighbor")
	s=scene([0.0,70.0]);s.players[1].z=102;s.apply_impulse(0,Vector3(20,0,0));s.step_object_impulses()
	check(s.players[1].pos==Vector2(70,0) and s.players[1].knock==Vector2.ZERO,"100-height contact filter still applies before later airborne step")
	s=scene([0.0,70.0]);s.players[1].possess_time=8;s.apply_impulse(0,Vector3(20,0,0));s.step_object_impulses()
	check(not s.players[1].object_active and s.players[1].pos==Vector2(70,0),"absent player is not woken by contact")
	s=scene([0.0,70.0]);s.set_unit_pathing(1,false);s.apply_impulse(0,Vector3(20,0,0));s.step_object_impulses()
	check(not s.navigation_solid(s.players[1]) and close(s.players[1].pos.x,88.7),"newly awakened ground motion ends with absolute-height collision disable")
	s=scene([0.0,70.0]);s.apply_impulse(0,Vector3(20,0,0));s.stop_object(0);s.players[0].knock=Vector2.ZERO;s.step_object_impulses()
	check(s.players[0].pos==Vector2.ZERO and s.players[1].pos==Vector2(70,0),"stale stopped entry does not run")
	s=scene([0.0,70.0]);s.apply_impulse(0,Vector3(20,0,0));s.reset();var before=s.players.map(func(p):return p.pos);s.step_object_impulses()
	check(s.players.map(func(p):return p.pos)==before and s.players.all(func(p):return not p.object_active),"new round discards old active registrations")
	s=scene([0.0,70.0]);s.apply_impulse(0,Vector3(20,0,0))
	for tick in range(200):s.step_object_impulses()
	check(s.object_members.is_empty() and s.players.all(func(p):return not p.object_active),"all resting members and tombstones eventually leave iterator")
	for layout in [[0.0,160.0,230.0],[230.0,160.0,0.0],[160.0,0.0,230.0]]:
		s=scene(layout);var caster=layout.find(0.0);var victim=layout.find(160.0);var next=layout.find(230.0)
		s.begin_tackle(caster);s.step_tackle(caster);s.step_object_impulses()
		check(close(s.players[caster].pos.x,48.95) and close(s.players[victim].pos.x,169.35) and close(s.players[next].pos.x,238.7),"real tackle hit chains through source activation order "+str(layout),s.players.map(func(p):return p.pos))
	s=scene([0.0,400.0]);s.apply_impulse(0,Vector3.ZERO);s.set_unit_pathing(1,false);s.Characters.exchange_players(s,0,1)
	check(s.players[0].object_active and s.players[1].object_active,"swap forwards an enabled zero-vector Object callback")
	s.step_object_impulses()
	check(s.navigation_solid(s.players[1]) and not s.players[1].object_active,"swapped zero-vector receiver restores pathing before sleeping")
	s=scene([0.0,400.0]);s.set_unit_pathing(0,false);s.set_unit_pathing(1,false);s.Characters.exchange_players(s,0,1);s.step_object_impulses()
	check(not s.players[0].object_active and not s.players[1].object_active and not s.navigation_solid(s.players[0]),"swapping two sleeping players does not invent callbacks")
	s=scene([0.0,70.0]);s.apply_impulse(0,Vector3(20,0,0));s.apply_impulse(1,Vector3(-10,0,0));s.Characters.exchange_players(s,0,1);s.step_object_impulses()
	check(close(s.players[0].pos.x,60.65) and close(s.players[1].pos.x,-8.7),"swap exchanges motion but preserves prior active-list positions")
	var a=scene([70.0,0.0]);var b=scene([70.0,0.0])
	for sim in [a,b]:sim.apply_impulse(1,Vector3(20,0,0))
	for frame in range(90):a.advance(1.0/30)
	for frame in range(432):b.advance(1.0/144)
	check(a.players[0].pos.is_equal_approx(b.players[0].pos) and a.players[1].pos.is_equal_approx(b.players[1].pos),"activation-driven contact agrees at 30/144 render FPS")
	var f=FileAccess.open("res://research/object-order-tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"basis":"Original JASS Object_start32, Object_II32 iteration and collision applyVector. Player-object list only; global family ordering/native group enumeration remain separate.","checks":checks},"\t"))
	quit(1 if failed else 0)
