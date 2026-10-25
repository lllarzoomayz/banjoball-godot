extends RefCounted
## Pick__acquireLolz, Shout___cast/together/rage and A00S/A00X/B00B.
const UNLOCK_DELAY=40.0
const COOLDOWN=60.0
const TEAM_WINDOW=4.5
const DURATION=8.0
const VOICE_GROUP={"h003":0,"h004":1,"h005":1,"h00F":0,"h00P":1,"h00R":1,"h00Y":0,"h010":2,"h001":0,"h012":2,"h01I":1,"h01N":1,"h01R":1,"h026":1,"h028":0,"h029":1,"h02C":0,"h027":0}
var states=[]
var counts=[0,0]
var deadlines=[INF,INF]
var events=[]
var next_time=INF
var sequence=0
var random=RandomNumberGenerator.new()

func _init():clear()

func clear():
	states.clear();counts=[0,0];deadlines=[INF,INF];events.clear();next_time=INF;sequence=0
	# Emote text and voice choices do not perturb ball/AI random numbers.
	random.seed=270149

func bind_players(sim):
	while states.size()>sim.players.size():states.pop_back()
	for i in range(sim.players.size()):
		var p=sim.players[i]
		if i>=states.size():states.append({})
		if states[i].get("character","")!=p.character:
			states[i]={"character":p.character,"unlock_at":sim.clock_now()+UNLOCK_DELAY,"ready_at":0.0,"adrenaline_until":0.0,"taunt_ready_at":0.0,"sadface_ready_at":0.0}
			var unlock=schedule("unlock",states[i].unlock_at,int(p.team))
			unlock.player=i;unlock.state=states[i]
		p.shout_state=states[i]

func remaining(sim,index: int) -> float:
	if index<0 or index>=states.size():return INF
	return maxf(0,maxf(states[index].unlock_at,states[index].ready_at)-sim.clock_now())

func available(sim,index: int) -> bool:
	if index<0 or index>=sim.players.size() or remaining(sim,index)>0:return false
	return can_act(sim,index)

func can_act(sim,index: int) -> bool:
	if index<0 or index>=sim.players.size():return false
	if sim.match_enabled and sim.match_state!="playing":return false
	if sim.reset_delay>0:return false
	var p=sim.players[index]
	return p.stun<=0 and p.silence<=0 and p.disabled<=0 and p.hooked==0 and p.tackle<=0 and p.ability_delay<=0 and not sim.Characters.absent(p)

func schedule(kind: String,due: float,team: int):
	sequence+=1
	var event={"kind":kind,"due":due,"team":team,"sequence":sequence}
	events.append(event)
	events.sort_custom(func(a,b):return a.due<b.due if a.due!=b.due else a.sequence<b.sequence)
	next_time=events[0].due
	return event

func step(sim,now: float):
	while not events.is_empty() and events[0].due<=now+.00000001:
		var event=events.pop_front()
		if event.kind=="unlock":
			var index=int(event.player)
			if index<states.size() and sim.unit_present(index) and is_same(states[index],event.state):
				sim.emit_text(index,"Lolz acquired",2.0)
		elif event.kind=="chorus":sim.emit_audio("shout4")
		elif deadlines[event.team]==event.due:counts[event.team]=0;deadlines[event.team]=INF
	next_time=INF if events.is_empty() else events[0].due

func effect(sim,index: int):
	var event=sim.emit_visual("fx_shout",sim.Characters.world_position(sim.players[index]))
	event.owner=index;event.attachment="origin"
	return event

func cast(sim,index: int) -> bool:
	step(sim,sim.clock_now())
	if not available(sim,index):return false
	var p=sim.players[index];var now=sim.clock_now();var team=int(p.team)
	states[index].ready_at=now+COOLDOWN
	var letters="DEATH";var lower=[2,6,6,2,2];var upper=[4,10,10,4,4];var message=""
	for i in range(5):message+=letters[i].repeat(random.randi_range(lower[i],upper[i]))
	var visual=effect(sim,index);visual.message=message+"!";visual.text_offset=Vector3(-180,0,150)
	var group=int(VOICE_GROUP.get(p.character,2))
	var voice=5 if group==0 else [1,2,3,5][random.randi_range(0,2 if group==1 else 3)]
	sim.emit_audio("shout"+str(voice))
	counts[team]+=1
	var team_size=sim.players.filter(func(other):return other.team==team).size()
	if counts[team]==team_size:
		counts[team]=0;deadlines[team]=INF
		schedule("chorus",now+2.0,team)
		for i in range(sim.players.size()):
			if sim.players[i].team==team:
				states[i].adrenaline_until=now+DURATION;effect(sim,i)
		sim.notice="全队响应！肾上腺素持续 8 秒。"
	else:
		deadlines[team]=now+TEAM_WINDOW;schedule("expire",deadlines[team],team)
		sim.notice="队伍呐喊 %d/%d · 4.5 秒内接着响应"%[counts[team],team_size]
	return true
