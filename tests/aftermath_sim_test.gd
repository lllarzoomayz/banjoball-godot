extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var passed=0
var failures=[]
var sim
var army
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func reset():
	sim=Sim.new();sim.start_practice();sim.random.seed=24102026
	army=sim.prepare_apocalypse().aftermath
func spawn(raw,owner,team,pos):
	var data=army.catalog.units[raw]
	var row={"rawcode":raw,"model":data.model,"owner":owner,"team":team,"position":sim.apocalypse.absolute(Vector3(pos.x,pos.y,0)),"facing":0.0,"time":0.0}
	army.spawn(row);return army.units[row.unit_id]
func ticks(count):
	for i in range(count):army.tick(army.clock+.03)
func run():
	reset()
	var warrior=spawn("nske",0,0,Vector2(-400,0));var enemy=spawn("nske",1,1,Vector2(-320,0))
	check(warrior.hp==180 and army.spec(warrior).armor==1,"native warrior health and armor loaded")
	check(not army.choose(enemy.id) and army.selected==warrior.id,"enemy cannot be selected as local unit")
	check(not army.command("attack",Vector2.ZERO,warrior.id),"friendly fire order rejected")
	army.command("attack",Vector2.ZERO,enemy.id);ticks(1)
	check(warrior.hit_at<INF and warrior.attack_serial==1,"attack begins with real windup")
	ticks(18);check(enemy.hp==180,"melee has no damage before source .56 second attack point")
	ticks(1);check(enemy.hp<180 and enemy.hp>=180-15/1.06-.001,"melee impact applies native damage roll and armor")
	army.command("move_direction",Vector2.LEFT)
	check(warrior.hit_at==INF and warrior.attack_at==-INF,"move interrupts attack presentation as well as pending hit")
	var before=warrior.pos;ticks(20);check(warrior.pos.distance_to(before)>20,"direction command turns then walks")
	var second=spawn("nske",0,0,Vector2(-700,0));army.choose(second.id)
	check(warrior.order=="idle" and warrior.axis==Vector2.ZERO,"switching units releases former joystick order")
	reset();var archer=spawn("nska",0,0,Vector2(-400,0));enemy=spawn("nske",1,1,Vector2(50,0))
	enemy.order="direct";enemy.axis=Vector2.ZERO
	army.command("attack",Vector2.ZERO,enemy.id);ticks(24)
	check(army.arrows.is_empty() and enemy.hp==180,"archer waits for .7 second attack point")
	ticks(1)
	check(army.arrows.size()==1 and enemy.hp==180,"arrow is launched without instant ranged damage")
	if not army.arrows.is_empty():
		var arrow=army.arrows[0];ticks(5)
		check(arrow.pos.z>arrow.start.z and arrow.travel>0,"arrow follows an elevated flight arc")
	ticks(15)
	check(enemy.hp<180 and army.arrows.is_empty(),"ranged damage is applied when arrow reaches target")
	archer.hp=100;enemy.hp=100;archer.order="direct";archer.axis=Vector2.ZERO;ticks(10)
	check(is_equal_approx(archer.hp,100.15) and enemy.hp==100,"archer regenerates .5 per second; warrior requires absent blight")
	army.damage(archer.id,1000)
	check(archer.hp==0 and archer.dead_at==army.clock and not army.command("move",Vector2.ZERO),"death removes local command eligibility")
	# Integration: the real Apocalypse scheduler must generate gameplay units,
	# not only decorative model records, independent of render frame partition.
	var results=[]
	for dt in [.1,.037]:
		reset();sim.bot_enabled=false;sim.advance(40);var state=sim.apocalypse
		check(state.vote(0),"real gate accepts vote")
		var end=sim.timeline+62.3
		while sim.timeline<end-.000001:sim.advance(minf(dt,end-sim.timeline))
		check(state.aftermath.units.size()==20,"native post-apocalypse spawn creates ten units per owner")
		var rows=[]
		for u in state.aftermath.units:rows.append([u.rawcode,u.owner,u.team,u.pos,u.hp,u.attack_serial])
		results.append(rows)
	check(results[0]==results[1],"unit simulation is independent of render step partition")
	FileAccess.open("res://research/aftermath-sim-verification.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("AFTERMATH SIM CHECKS ",passed," passed; ",failures.size()," failed")
	quit(0 if failures.is_empty() else 1)
