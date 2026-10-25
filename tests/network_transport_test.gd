extends SceneTree
class Client extends "res://scripts/net_client.gd":
	var attempts=0
	func open_transport(ip: String,keep_address=false):
		attempts+=1
		super.open_transport(ip,keep_address)
const Sim=preload("res://scripts/match_sim.gd")
var clients=[]
var frames=[0,0]
var failed=false
var endpoint="127.0.0.1"

func manual_connect(client):
	client.start_direct(endpoint,true,false)
	expect(await until(func():return not client.direct_offer_code.is_empty()),"manual offer ready")
	var directory=OS.get_environment("BANJO_DIRECT_STATUS")
	var file=FileAccess.open(directory+"/offer-code.txt",FileAccess.WRITE)
	file.store_string(client.direct_offer_code);file.close()
	var ident=client.direct.id
	expect(await until(func():
		if not FileAccess.file_exists(directory+"/answer-code.txt"):return false
		var answer=client.Direct.decode_code(FileAccess.get_file_as_string(directory+"/answer-code.txt"))
		return answer.get("id","")==ident),"manual answer from NAS component")
	client.paste_direct_answer(FileAccess.get_file_as_string(directory+"/answer-code.txt"))

func _initialize():call_deferred("run")

func expect(ok: bool,message: String):
	if not ok:
		failed=true;push_error(message)
		for c in clients:print("Failure context: ",c.status," connected=",c.connected," match=",c.in_match," room_state=",c.room.get("state","none"))

func until(predicate: Callable,seconds=15.0) -> bool:
	var start=Time.get_ticks_msec()
	while not predicate.call() and Time.get_ticks_msec()-start<seconds*1000:await create_timer(.05).timeout
	return predicate.call()

func run():
	if OS.get_environment("BANJO_TEST_ENDPOINT")!="":endpoint=OS.get_environment("BANJO_TEST_ENDPOINT")
	for i in range(2):
		var client=Client.new();root.add_child(client);client.token="";client.address=endpoint;clients.append(client)
		client.begin_match.connect(func(value):client.loaded_sim(Sim.new(),value.state))
		var name="test"+str(Time.get_ticks_usec())+str(i)
		if OS.get_environment("BANJO_TEST_MANUAL")=="1":await manual_connect(client)
		elif OS.get_environment("BANJO_TEST_DIRECT")=="1":client.start_direct(endpoint,false,false)
		client.authenticate("register",name,"temporary-test-password","球员"+name)
	expect(await until(func():return clients[0].authenticated and clients[1].authenticated,40.0 if OS.get_environment("BANJO_TEST_DIRECT")=="1" or OS.get_environment("BANJO_TEST_SLOW_HANDSHAKE")=="1" else 15.0),"encrypted account registration")
	if failed:
		for client in clients:print("Client status: ",client.status," connected=",client.connected," address=",client.address)
		return finish()
	var report_path=OS.get_environment("BANJO_TEST_USERS_REPORT")
	if report_path!="":
		var users=[]
		for client in clients:users.append({"id":client.profile.id,"username":client.profile.username})
		var report=FileAccess.open(report_path,FileAccess.WRITE)
		if report:report.store_string(JSON.stringify(users))
	if OS.get_environment("BANJO_TEST_DIRECT")=="1":
		for client in clients:
			expect(client.connection_path=="直连 NAS / Direct" and client.direct.received_packets>0,"actual game traffic uses direct bridge")
	if OS.get_environment("BANJO_TEST_SLOW_HANDSHAKE")=="1":
		var expected_attempts=[2,2] if OS.get_environment("BANJO_TEST_DIRECT")=="1" else [1,1]
		var actual_attempts=[clients[0].attempts,clients[1].attempts]
		print("Connection attempts: ",actual_attempts," expected ",expected_attempts)
		expect(actual_attempts==expected_attempts,"slow handshake must finish with only signalling and game connections")
	clients[0].send({"type":"create"})
	expect(await until(func():return not clients[0].room.is_empty()),"create room")
	if failed:return finish()
	if OS.get_environment("BANJO_TEST_ROOM_LIST")=="1":
		clients[1].send({"type":"rooms"})
		expect(await until(func():return clients[1].rooms.any(func(r):return r.id==clients[0].room.id)),"created room appears in cloud list")
		clients[1].send({"type":"join","id":clients[0].room.id})
	else:clients[1].join_room_code(clients[0].RoomCode.code(clients[0].room.id).to_lower())
	expect(await until(func():return not clients[1].room.is_empty()),"join room from list or shareable code")
	clients[1].send({"type":"select","slot":3,"hero":"h001","hat":12})
	await create_timer(.3).timeout
	for slot in [1,2,4,5]:clients[0].send({"type":"ai","slot":slot,"hero":"h005"})
	await create_timer(.3).timeout
	clients[0].send({"type":"ready","value":true});clients[1].send({"type":"ready","value":true})
	await create_timer(.3).timeout
	clients[0].send({"type":"start"})
	expect(await until(func():return clients[0].in_match and clients[1].in_match),"both load same match")
	if failed:return finish()
	expect(await until(func():return clients[0].sim.match_state=="playing" and clients[1].sim.match_state=="playing"),"server countdown")
	expect(clients[0].slot==0 and clients[1].slot==3,"different controlled slots")
	var start=clients[0].sim.players[0].pos
	clients[0].submit("move_direction",Vector2.RIGHT)
	await create_timer(.8).timeout
	clients[0].release_input()
	expect(clients[0].sim.players[0].pos.x>start.x+100,"authoritative movement replicated")
	expect(clients[0].sim.players[0].pos.distance_to(clients[1].sim.players[0].pos)<40,"two clients see same player")
	var token=clients[1].token;var uid=clients[1].profile.id;var match_id=clients[1].match_id
	clients[1].close_connection()
	await create_timer(6).timeout
	clients[1].token=token
	if OS.get_environment("BANJO_TEST_MANUAL")=="1":await manual_connect(clients[1])
	elif OS.get_environment("BANJO_TEST_DIRECT")=="1":clients[1].start_direct(endpoint,false,false)
	else:clients[1].connect_server(endpoint)
	expect(await until(func():return clients[1].in_match),"session reconnect")
	expect(clients[1].profile.id==uid and clients[1].match_id==match_id and clients[1].slot==3,"same account match and slot")
	clients[1].send({"type":"leave"})
	expect(await until(func():return clients[1].room.is_empty()),"leave")
	clients[1].send({"type":"logout"})
	expect(await until(func():return not clients[1].connected and clients[1].token==""),"logout invalidates saved session")
	print("DTLS TRANSPORT: registration, 2 clients, lobby, AI, ready, countdown, movement, reconnect checked")
	finish()

func finish():
	for c in clients:
		c.close_connection()
		c.direct_mode="manual";c.direct_stage="failed"
		c.authenticate("login","unused","temporary-test-password","")
		expect(not c.wants_connection and c.host==null and c.pending_auth.is_empty(),"failed direct login must not silently fall back to relay")
		c.close_connection()
	quit(1 if failed else 0)
