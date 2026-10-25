extends RefCounted
## Apocalypse__* timer/state port. Effects use authoritative simulation time.
## The game adapter must synchronously consume pull/blast/remove events and
## supply its actual object registry. No UI entry until that adapter is ready.
signal event(kind: String,row: Dictionary)
const World=preload("res://scripts/apocalypse_world.gd")
const DT=0.03125
const MASK_COLOR=Color(.3,.1,0,1)
var world=World.new()
var rng=RandomNumberGenerator.new()
var clock=0.0
var unlock_at=40.0
var active=false
var started=0.0
var phase="waiting"
var votes={}
var humans=[0]
var teams=[[0],[1]]
var next_time=INF
var next_pull=INF
var next_tree=INF
var next_shake=INF
var next_phase=INF
var next_spawn=INF
var alpha=0
var size=1.0
var pull_force=0.0
var pull_delta=1.0
var tree_period=3.5
var shake_magnitude=0.0
var shake_velocity=0.0
var decorations=[]
var skeletons=[]
var skeleton_team=0
var skeleton_counters=[0,0]
var remaining=0

func setup(field_index: int,game_rng,human_ids: Array,team_owners: Array,now=0.0,ice_rows=null):
	rng=game_rng;clock=now;unlock_at=now+40;active=false;started=0;phase="waiting"
	votes.clear();humans=human_ids.duplicate();teams=team_owners.duplicate(true)
	next_time=INF;next_pull=INF;next_tree=INF;next_shake=INF;next_phase=INF;next_spawn=INF
	alpha=0;size=1;pull_force=0;pull_delta=1;tree_period=3.5;shake_magnitude=0;shake_velocity=0
	decorations.clear();skeletons.clear();skeleton_team=0;skeleton_counters=[0,0];remaining=0
	world.setup(field_index,rng,ice_rows)

func vote(owner: int,now: float) -> bool:
	advance_to(now)
	if active or now<unlock_at or owner not in humans or votes.has(owner):return false
	votes[owner]=true
	if votes.size()>=int(humans.size()*.75+.5):begin()
	return true

func begin():
	active=true;started=clock;phase="pulling"
	var facing=rng.randf_range(0,TAU)
	var removed=world.remove_blockers()
	next_pull=clock+DT;next_tree=clock+6;next_phase=clock+22
	refresh_next()
	event.emit("begin",{"time":clock,"facing":facing,"removed_blockers":removed})

func refresh_next():
	next_time=minf(minf(next_pull,next_tree),minf(minf(next_shake,next_phase),next_spawn))

func advance_to(now: float):
	if now<clock:return
	while next_time<=now+1e-8:
		clock=next_time
		# Equal-time ordering is explicit and stable; native inter-timer ties
		# have not been sampled. Phase changes cancel due timers first.
		if next_phase<=clock+1e-8:transition()
		elif next_pull<=clock+1e-8:
			alpha=mini(255,alpha+1);size+=.01;pull_force+=pull_delta;pull_delta+=.00625
			next_pull+=DT;event.emit("pull",{"time":clock})
		elif next_tree<=clock+1e-8:
			var result=world.random_tree_pull(rng);result.time=clock
			if result.empty:next_tree=INF
			else:
				tree_period=tree_period-.03125 if tree_period>.13125 else .1
				next_tree=clock+tree_period
				event.emit("tree",result)
		elif next_shake<=clock+1e-8:
			shake_magnitude+=.55;shake_velocity+=1300;next_shake+=.1
		else:spawn_skeleton()
		refresh_next()
	clock=now

func transition():
	match phase:
		"pulling":
			phase="shaking";tree_period-=2.6;next_shake=clock+.1;next_phase=started+47
			event.emit("shake_start",{"time":clock})
		"shaking":
			phase="exploded";next_pull=INF;next_tree=INF;next_shake=INF;next_phase=started+47.5
			event.emit("explosion",{"time":clock,"position":center(0),"model":"apoc_nuclear","scale":3.5,"pitch":90.0,"facing":rng.randf_range(0,TAU)})
		"exploded":phase="fade_out";next_phase=started+51.5;event.emit("fade_out",{"time":clock})
		"fade_out":
			phase="covered";shake_magnitude=0;shake_velocity=0;next_phase=started+54
			event.emit("cleanup",{"time":clock,"killed":world.kill_all()})
			for i in range(230):decorate()
			event.emit("decorations",{"time":clock,"objects":decorations})
		"covered":
			phase="reveal";remaining=(teams[0].size()+teams[1].size())*10;next_phase=started+59
			event.emit("reveal",{"time":clock})
		"reveal":
			phase="spawning" if remaining>0 else "aftermath"
			next_phase=INF;next_spawn=clock+.15 if remaining>0 else INF

func center(z: float=1224) -> Vector3:
	return Vector3(world.field.center[0],world.field.center[1],z)

func unit_pull(position: Vector3) -> Dictionary:
	var offset=center()-position;var distance=offset.length()
	return {"remove":distance<=9*size,"force":offset*(pull_force/(distance*distance)) if distance>0 else Vector3.ZERO}

func ball_pull(position: Vector3) -> Dictionary:
	var offset=center()-position;var distance=offset.length()
	return {"remove":distance*distance<=pull_force,"force":offset*(pull_force/(distance*distance)) if distance>0 else Vector3.ZERO}

func blast(position: Vector3) -> Vector3:
	# The source uses absolute GetUnitZ + 100, not relative flying height.
	return Vector3(position.x-world.field.center[0],position.y-world.field.center[1],position.z+100).normalized()*75

func mask_opacity() -> float:
	if not active:return 0
	var age=clock-started
	if age<47.5:return 0
	if age<49.5:return (age-47.5)/2
	if age<54:return 1
	return clampf(1-(age-54)/5,0,1)

func decorate():
	var choice=rng.randi_range(0,10)
	var kind=1 if choice==0 else (2 if choice<=2 else 3)
	var radius=[0,150,100,50][kind];var p=Vector3.ZERO
	var accepted=false
	while not accepted:
		var angle=rng.randf_range(0,TAU);var distance=rng.randf_range(0,2048)
		p=center(1024)+Vector3(cos(angle)*distance,sin(angle)*distance,0)
		accepted=true
		for row in decorations:
			if row.kind==kind and row.position.distance_to(p)<=radius:accepted=false;break
	var model="apoc_fire_large" if kind==1 else ("apoc_fire_small" if kind==2 else "apoc_rubble_"+str(rng.randi_range(0,3)))
	decorations.append({"kind":kind,"position":p,"model":model,"scale":.6 if kind==3 else 1.0,"facing":rng.randf_range(0,TAU)})

func spawn_skeleton():
	var rect=world.field.pitch;var origin=world.field.center
	var x=origin[0]+rng.randf_range(rect[0],rect[2]);var y=origin[1]+rng.randf_range(rect[1],rect[3])
	if teams[skeleton_team].is_empty():skeleton_team=1-skeleton_team
	var members=teams[skeleton_team]
	if members.is_empty():remaining=0;next_spawn=INF;phase="aftermath";return
	var slot=int(skeleton_counters[skeleton_team])%members.size()
	skeleton_counters[skeleton_team]=slot+1
	var melee=rng.randi_range(0,1)==0
	var row={"time":clock,"owner":members[slot],"team":skeleton_team,"position":Vector3(x,y,world.ground_height(Vector2(x,y))),
		"rawcode":"nske" if melee else "nska","model":"apoc_skeleton" if melee else "apoc_skeleton_archer","facing":rng.randf_range(0,TAU)}
	skeletons.append(row);remaining-=1;skeleton_team=1-skeleton_team
	next_spawn=clock+.15 if remaining>0 else INF
	if remaining==0:phase="aftermath"
	event.emit("skeleton",row)
