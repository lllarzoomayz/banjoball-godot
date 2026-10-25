extends RefCounted
const Sim=preload("res://scripts/match_sim.gd")
const Wire=preload("res://scripts/net_wire.gd")
var id=Wire.uuid()
var host=""
var state="lobby"
var config={"size":3,"field":0,"mode":0,"limit":10,"minutes":10,"formation":"row"}
var seats=[]
var sim
var match_id=""
var loading_since=0.0
var offline_since=-1.0
var finished_since=0.0
var result_saved=false
var result_pending=false
var settlement={}
var error=""

func _init(owner="",nickname=""):
	host=owner
	resize_seats()
	if owner!="":seats[0]=human(owner,nickname)

func empty() -> Dictionary:
	return {"uid":"","nickname":"空位 / Empty","ai":false,"ready":false,"hero":"h005","hat":12,"connected":false,"loaded":false,"lost_at":-1.0,"seq":-1,"last_input":0.0}

func human(uid,nickname) -> Dictionary:
	var s=empty();s.uid=uid;s.nickname=nickname;s.connected=true;return s

func resize_seats():
	seats=[]
	for i in range(config.size*2):seats.append(empty())

func find_user(uid: String) -> int:
	for i in range(seats.size()):
		if seats[i].uid==uid:return i
	return -1

func clear_ready():
	for seat in seats:seat.ready=seat.ai;seat.loaded=false

func view() -> Dictionary:
	var rows=[]
	for s in seats:rows.append({"uid":s.uid,"nickname":s.nickname,"ai":s.ai,"ready":s.ready,"hero":s.hero,"hat":s.hat,"connected":s.connected})
	return {"id":id,"host":host,"state":state,"config":config.duplicate(),"seats":rows,"match_id":match_id,"result_saved":result_saved}

func configure(uid: String,next: Dictionary) -> bool:
	if uid!=host or state!="lobby":return fail("只有房主可修改 / Host only")
	var size=int(next.get("size",config.size))
	if size<1 or size>6:return fail("每队人数 1–6 / Team size 1–6")
	var field=int(next.get("field",config.field));var mode=int(next.get("mode",config.mode))
	var formation=str(next.get("formation",config.formation))
	if field<0 or field>3 or mode<0 or mode>2 or formation not in ["row","tactical"]:return fail("规则无效 / Invalid rules")
	if size!=config.size:
		var people=seats.filter(func(s):return s.uid!="")
		if people.size()>size*2:return fail("先让多余玩家离房 / Too many players")
		config.size=size;resize_seats()
		for i in range(people.size()):seats[i]=people[i]
	config.field=field;config.mode=mode;config.formation=formation
	config.limit=clampi(int(next.get("limit",config.limit)),1,50)
	config.minutes=clampi(int(next.get("minutes",config.minutes)),1,60)
	clear_ready();return true

func join(uid,nickname) -> bool:
	var existing=find_user(uid)
	if existing>=0:
		var s=seats[existing];s.connected=true;s.lost_at=-1.0;s.loaded=false;s.seq=-1;s.nickname=nickname
		if sim!=null:
			# Wait for snapshot/load acknowledgement before replacing the AI.
			sim.human_slots.erase(existing)
		return true
	if state!="lobby":return fail("比赛中只允许原玩家重连 / Reconnect only")
	for i in range(seats.size()):
		if seats[i].uid=="" and not seats[i].ai:
			seats[i]=human(uid,nickname)
			var host_index=find_user(host)
			if host_index<0 or not seats[host_index].connected:host=uid
			clear_ready();return true
	return fail("房间已满 / Room full")

func select(uid,slot: int,hero: String,hat: int) -> bool:
	var previous=find_user(uid)
	if state!="lobby" or previous<0 or slot<0 or slot>=seats.size():return fail("不能更换位置 / Cannot change seat")
	if not Sim.Characters.DATA.has(hero) or hat<0 or hat>=38 or hat==25:return fail("角色或装扮无效 / Invalid character")
	if previous!=slot and (seats[slot].uid!="" or seats[slot].ai):return fail("位置已占用 / Seat occupied")
	var s=seats[previous];seats[previous]=empty();seats[slot]=s;s.hero=hero;s.hat=hat
	clear_ready();return true

func set_ai(uid,slot: int,hero: String,hat: int=12) -> bool:
	if uid!=host or state!="lobby" or slot<0 or slot>=seats.size() or seats[slot].uid!="":return fail("只能编辑空位或 AI / Empty or AI seat only")
	if hero!="" and (not Sim.Characters.DATA.has(hero) or hat<0 or hat>=38 or hat==25):return fail("角色或装扮无效 / Invalid character")
	seats[slot]=empty()
	if hero!="":
		seats[slot].ai=true;seats[slot].nickname="AI "+str(slot+1);seats[slot].hero=hero;seats[slot].hat=hat
	clear_ready();return true

func ready(uid,value: bool) -> bool:
	var index=find_user(uid)
	if state!="lobby" or index<0:return false
	seats[index].ready=value;return true

func begin(uid,now: float) -> bool:
	if uid!=host or state!="lobby":return fail("只有房主可开始 / Host only")
	for s in seats:
		if not s.ai and (s.uid=="" or not s.ready or not s.connected):return fail("请填满空位，并等待所有玩家准备 / Fill seats and ready up")
	sim=Sim.new();sim.networked=true;sim.selected_field=config.field
	sim.network_lineup=seats.duplicate(true);sim.network_formation=config.formation
	sim.roster=seats.map(func(s):return s.hero)
	sim.start_match(config.size,config.limit,config.minutes*60.0 if config.mode==1 else 0.0,config.mode==2)
	sim.controlled=-1;sim.human_slots=[]
	for i in range(seats.size()):
		seats[i].loaded=false;seats[i].seq=-1;seats[i].last_input=now
		if not seats[i].ai:sim.human_slots.append(i)
	match_id=Wire.uuid();state="loading";loading_since=now;result_saved=false;settlement={}
	return true

func loaded(uid,now: float):
	var i=find_user(uid)
	if i<0 or sim==null:return
	seats[i].loaded=true;seats[i].last_input=now
	if i not in sim.human_slots:sim.human_slots.append(i)
	sim.DirectionalMotion.release(sim.players[i]);sim.players[i].want_move=false;sim.players[i].path=[]

func disconnect_player(uid,now: float,leave=false):
	var i=find_user(uid)
	if i<0:return
	var s=seats[i];s.connected=false;s.ready=false;s.loaded=false;s.lost_at=now
	if state in ["lobby","ended"] and leave:seats[i]=empty();clear_ready()
	if sim!=null:
		sim.pending_commands=sim.pending_commands.filter(func(c):return c.player!=i)
		sim.DirectionalMotion.release(sim.players[i]);sim.players[i].want_move=false;sim.players[i].path=[]
	if uid==host:
		for other in seats:
			if other.uid!="" and other.connected:host=other.uid;break

func input(uid,data: Dictionary,now: float) -> bool:
	var i=find_user(uid)
	if state!="playing" or i<0 or not seats[i].connected or not seats[i].loaded:return false
	var kind=str(data.get("kind",""));var seq=int(data.get("seq",-1));var target=data.get("target",Vector2.ZERO)
	if kind not in Wire.COMMANDS or not target is Vector2 or not target.is_finite() or target.length()>25000 or seq<=seats[i].seq:return false
	seats[i].seq=seq;seats[i].last_input=now
	sim.submit_command(kind,i,target)
	return true

func tick(delta: float,now: float,grace=5.0):
	if sim==null:return
	if state=="loading":
		var all_loaded=true
		for s in seats:
			if not s.ai and not s.loaded:all_loaded=false
		if all_loaded:state="playing"
		elif now-loading_since>60:
			state="lobby";sim=null;clear_ready();error="有人加载超时，已返回房间 / Loading timed out"
		return
	if state=="ended":
		# Winning goals still travel into the net and rebound during the cheer.
		if sim.reset_delay>0:sim.advance(delta)
		return
	if state!="playing":return
	for i in range(seats.size()):
		var s=seats[i]
		if s.uid=="":continue
		if not s.connected and now-s.lost_at>=grace:sim.human_slots.erase(i)
		if i in sim.human_slots and now-s.last_input>0.5:
			sim.DirectionalMotion.release(sim.players[i])
	# Dedicated host never accepts client positions/velocities/scores.
	sim.advance(delta)
	if sim.match_state=="ended":
		state="ended";finished_since=now
		var participants=[]
		for i in range(seats.size()):
			var s=seats[i]
			if s.uid=="":continue
			var team=0 if i<config.size else 1
			var outcome="abandoned" if not s.connected or not s.loaded else ("draw" if sim.winner<0 else ("win" if team==sim.winner else "loss"))
			participants.append({"id":s.uid,"outcome":outcome})
		settlement={"match_id":match_id,"players":participants}

func fail(message: String) -> bool:
	error=message;return false
