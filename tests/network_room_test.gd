extends SceneTree
const Room=preload("res://scripts/net_room.gd")
var count=0
var failed=false
func check(ok: bool,message: String):
	count+=1
	if not ok:failed=true;push_error(message)

func _initialize():
	var room=Room.new("alice","Alice")
	check(room.configure("alice",{"size":2,"formation":"row"}),"configure")
	check(room.join("bob","Bob"),"join")
	check(room.select("bob",2,"h001",12),"red seat")
	check(not room.select("bob",0,"h005",12),"occupied")
	check(not room.configure("bob",{"size":6}),"non-host settings")
	check(not room.begin("alice",0),"not-ready start")
	check(room.set_ai("alice",1,"h003"),"AI blue")
	check(room.set_ai("alice",3,"h005"),"AI red")
	room.ready("alice",true);room.ready("bob",true)
	check(room.begin("alice",0),"start")
	check(room.state=="loading","wait for load")
	room.loaded("alice",0);room.tick(0.03,1)
	check(room.state=="loading","wait for other client")
	room.loaded("bob",0);room.tick(0.03,2)
	check(room.state=="playing","all loaded")
	var sim=room.sim
	check(sim.human_slots==[0,2],"human control slots")
	check(sim.players[0].pos.x==sim.players[1].pos.x,"original row formation")
	check(sim.players[2].character=="h001","red hero")
	var Snapshot=load("res://scripts/net_snapshot.gd")
	var frozen=Snapshot.capture(sim).duplicate(true);var copy=SimCopy()
	Snapshot.apply(copy,frozen)
	var stable=copy.players
	Snapshot.interpolate(copy,frozen,frozen,0.5)
	check(is_same(stable,copy.players),"snapshots preserve renderer identity")
	copy.players[0].pos+=Vector2(50,50)
	check(copy.players[0].pos!=frozen.players[0].pos,"render interpolation does not mutate snapshot")
	for i in range(110):room.tick(0.03,2+i*0.03)
	var other=sim.players[0].pos
	check(room.input("bob",{"kind":"move_direction","target":Vector2.LEFT,"seq":1,"player":0},6),"input")
	room.tick(0.03,6)
	check(sim.players[0].pos==other,"cannot forge other player index")
	check(not room.input("bob",{"kind":"kick","target":Vector2.ZERO,"seq":1},6),"stale sequence")
	check(not room.input("bob",{"kind":"practice_ball","target":Vector2.ZERO,"seq":2},6),"practice cheat rejected")
	check(not room.select("bob",3,"h005",12),"cannot switch to AI")
	var body=sim.players[2]
	room.disconnect_player("bob",10);room.tick(0.03,12)
	check(2 in sim.human_slots,"disconnect grace")
	room.tick(0.03,16)
	check(2 not in sim.human_slots,"AI takeover")
	check(room.join("bob","Bob"),"reconnect")
	check(is_same(body,sim.players[2]),"reconnect preserves live player")
	room.loaded("bob",17)
	check(2 in sim.human_slots,"control returned after snapshot ack")
	check(not room.join("charlie","Charlie"),"no late join")
	room.disconnect_player("alice",18)
	check(room.host=="bob","host transfer")
	sim.match_state="ended";sim.winner=1;room.tick(0.03,19)
	check(room.state=="ended" and room.settlement.players.size()==2,"settlement")
	check(room.settlement.players[0].outcome=="abandoned" and room.settlement.players[1].outcome=="win","completion policy")
	sim.reset_delay=4;sim.goal_ball_live=true;sim.velocity=Vector3(15,0,0)
	var goal_time=sim.timeline
	room.tick(0.1,20)
	check(sim.reset_delay<4 and sim.timeline>goal_time,"winning goal follow-through continues on dedicated server")
	print("NETWORK ROOM: ",count," checks passed")
	quit(1 if failed else 0)

func SimCopy():return load("res://scripts/match_sim.gd").new()
