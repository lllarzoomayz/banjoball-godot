extends SceneTree
const Wire=preload("res://scripts/net_wire.gd")
const Room=preload("res://scripts/net_room.gd")
const Snapshot=preload("res://scripts/net_snapshot.gd")
var host=ENetConnection.new()
var udp=PacketPeerUDP.new()
var peers={}
var rooms={}
var config={}
var key=""
var snapshot_clock=0.0
var room_clock=0.0
var now=0.0
var data=""
var recovery_clock=0.0
var recovering={}

func _initialize():
	Engine.max_fps=64
	data=OS.get_environment("BANJO_DATA")
	if data=="":data=ProjectSettings.globalize_path("res://server/data")
	var config_path=OS.get_environment("BANJO_CONFIG")
	if config_path=="":config_path="res://server/config.json"
	config=JSON.parse_string(FileAccess.get_file_as_string(config_path))
	key=FileAccess.get_file_as_string(data+"/service.key").strip_edges()
	var cert=X509Certificate.new();var secret=CryptoKey.new()
	if cert.load(data+"/server.crt")!=OK or secret.load(data+"/server.key")!=OK or key=="":push_error("Missing server credentials");quit(1);return
	var err=host.create_host_bound("*",int(config.get("port",Wire.PORT)),32,2)
	if err==OK:err=host.dtls_server_setup(TLSOptions.server(secret,cert))
	if err!=OK:push_error("Server transport startup failed "+str(err));quit(2);return
	udp.bind(Wire.DISCOVERY)
	print("Banjoball encrypted LAN server ready, UDP ",Wire.PORT)
	call_deferred("recover_results")

func recover_results():
	for filename in DirAccess.get_files_at(data):
		if not filename.begins_with("pending-") or not filename.ends_with(".json") or recovering.has(filename):continue
		var payload=JSON.parse_string(FileAccess.get_file_as_string(data+"/"+filename))
		if not payload is Dictionary:continue
		var active=false
		for r in rooms.values():
			if r.match_id==payload.get("match_id",""):active=true
		if active:continue
		recovering[filename]=true
		api("settle",payload,func(result):
			recovering.erase(filename)
			if result.get("ok",false):DirAccess.remove_absolute(data+"/"+filename))

func api(action: String,body: Dictionary,callback: Callable):
	var req=HTTPRequest.new();root.add_child(req);req.timeout=15.0
	req.request_completed.connect(func(_result,code,_headers,bytes):
		var response=JSON.parse_string(bytes.get_string_from_utf8()) if code==200 else null
		callback.call(response if response is Dictionary else {"ok":false,"error":"账号服务不可用 / Account service unavailable"})
		req.queue_free())
	var err=req.request("http://127.0.0.1:27890/"+action,["Content-Type: application/json","Authorization: Bearer "+key],HTTPClient.METHOD_POST,JSON.stringify(body))
	if err!=OK:req.queue_free();callback.call({"ok":false,"error":"Account request failed"})

func _process(delta: float) -> bool:
	now+=delta
	recovery_clock+=delta
	if recovery_clock>10:recovery_clock=0;recover_results()
	for _i in range(256):
		var event=host.service(0)
		if event[0]==ENetConnection.EVENT_NONE:break
		var peer=event[1]
		match event[0]:
			ENetConnection.EVENT_CONNECT:
				peers[peer]={"uid":"","profile":{},"room":"","busy":false,"packets":0,"epoch":now,"last":now,"joined":now}
				peer.ping_interval(500);peer.set_timeout(8,3000,5000)
				Wire.send(peer,{"type":"hello","protocol":Wire.VERSION,"direct":bool(config.get("direct_enabled",true))})
			ENetConnection.EVENT_DISCONNECT:drop(peer)
			ENetConnection.EVENT_RECEIVE:
				var packet=peer.get_packet()
				if peers.has(peer) and packet.size()<16384:receive(peer,Wire.decode(packet))
	for peer in peers.keys():
		if peers[peer].uid=="" and now-peers[peer].joined>120:peer.disconnect_now();drop(peer)
	while udp.get_available_packet_count()>0:
		var raw=udp.get_packet();var address=udp.get_packet_ip();var port=udp.get_packet_port()
		if raw.get_string_from_utf8()=="BANJOBALL_DISCOVER_1":
			udp.set_dest_address(address,port);udp.put_packet(JSON.stringify({"name":"Banjoball NAS","port":Wire.PORT,"protocol":Wire.VERSION}).to_utf8_buffer())
	snapshot_clock+=delta;room_clock+=delta
	for id in rooms.keys():
		var r=rooms[id];var before=r.state
		r.tick(minf(delta,0.1),now,float(config.get("disconnect_grace_seconds",5)))
		var online=false
		for s in r.seats:
			if s.uid!="" and s.connected:online=true
		if online:r.offline_since=-1.0
		elif r.offline_since<0:r.offline_since=now
		elif now-r.offline_since>float(config.get("all_offline_seconds",300)):rooms.erase(id);continue
		if before!=r.state:broadcast_room(r)
		if r.state=="ended" and not r.result_saved and not r.result_pending and room_clock>=1:
			r.result_pending=true
			api("settle",r.settlement,func(result):
				r.result_pending=false;r.result_saved=result.get("ok",false)
				if not r.result_saved:push_warning("Match result pending; will retry")
				else:
					var file=data+"/pending-"+r.match_id+".json"
					if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
					broadcast_room(r))
			var pending=FileAccess.open(data+"/pending-"+r.match_id+".json",FileAccess.WRITE)
			if pending:pending.store_string(JSON.stringify(r.settlement))
		if r.sim!=null and snapshot_clock>=0.05:
			var frame={"type":"snapshot","match_id":r.match_id,"state":Snapshot.capture(r.sim)}
			for peer in peers:
				if peers[peer].room==id:Wire.send(peer,frame,false)
	if snapshot_clock>=0.05:snapshot_clock=0
	if room_clock>=1:room_clock=0
	host.flush()
	return false

func drop(peer):
	if not peers.has(peer):return
	var p=peers[peer]
	if rooms.has(p.room):rooms[p.room].disconnect_player(p.uid,now);broadcast_room(rooms[p.room])
	peers.erase(peer)

func receive(peer,message: Dictionary):
	if message.is_empty():return
	var p=peers[peer]
	if now-p.epoch>=1:p.epoch=now;p.packets=0
	p.packets+=1;p.last=now
	if p.packets>120:return
	var kind=str(message.get("type",""))
	if kind=="direct_offer":
		if not bool(config.get("direct_enabled",true)):return
		# One bounded connection request per pinned-DTLS signalling peer.
		if p.get("direct_requested",false):return
		p.direct_requested=true
		var offer=message.get("offer",{})
		if not offer is Dictionary or str(offer.get("sdp","")).length()>16000:return
		var req=HTTPRequest.new();root.add_child(req);req.timeout=20
		req.request_completed.connect(func(_result,code,_headers,bytes):
			if peers.has(peer):
				var result=JSON.parse_string(bytes.get_string_from_utf8()) if code==200 else null
				if result is Dictionary and result.get("ok",false):Wire.send(peer,{"type":"direct_answer","answer":result.answer})
				else:Wire.send(peer,{"type":"direct_error","message":"NAS 直连组件尚未就绪 / NAS direct connector unavailable"})
			req.queue_free())
		var err=req.request("http://127.0.0.1:27892/offer",["Content-Type: application/json","Authorization: Bearer "+key],HTTPClient.METHOD_POST,JSON.stringify(offer))
		if err!=OK:
			req.queue_free();Wire.send(peer,{"type":"direct_error","message":"NAS direct connector unavailable"})
		return
	if kind in ["login","register","resume","rename"]:
		if p.uid!="" and kind!="rename":return
		if p.busy:return
		if kind=="rename" and (p.uid=="" or p.room!=""):return error(peer,"请先离开房间再改昵称 / Leave the room first")
		p.busy=true
		var body={}
		for field in ["username","password","nickname","token"]:body[field]=message.get(field,"")
		body.remote=peer.get_remote_address()
		api(kind,body,func(result):
			if not peers.has(peer):return
			p.busy=false
			if not result.get("ok",false):error(peer,result.get("error","Login failed"));return
			p.uid=result.profile.id;p.profile=result.profile;p.token=result.get("token",message.get("token",""))
			for old in peers.keys():
				if old!=peer and peers[old].uid==p.uid:old.disconnect_now();drop(old)
			Wire.send(peer,{"type":"account","profile":result.profile,"token":result.get("token",message.get("token",""))})
			var found=false
			for r in rooms.values():
				if r.find_user(p.uid)>=0:
					found=true
					r.join(p.uid,p.profile.nickname);p.room=r.id;broadcast_room(r)
					if r.sim!=null:send_begin(peer,r)
					break
			if not found:Wire.send(peer,{"type":"no_room"})
			room_list(peer))
		return
	if p.uid=="":return
	if kind=="profile":
		api("profile",{"id":p.uid},func(result):
			if peers.has(peer) and result.get("ok",false):p.profile=result.profile;Wire.send(peer,{"type":"profile","profile":result.profile}))
		return
	if kind=="logout":
		api("logout",{"token":p.get("token","")},func(result):
			if not peers.has(peer):return
			if not result.get("ok",false):error(peer,"退出登录失败，请重试 / Sign out failed");return
			Wire.send(peer,{"type":"signed_out"});drop(peer))
		return
	if kind=="rooms":room_list(peer);return
	if kind=="ping":Wire.send(peer,{"type":"pong","stamp":message.get("stamp",0)},false);return
	if kind=="create":
		if p.room!="":return error(peer,"请先离开当前房间 / Leave current room")
		for existing in rooms.values():
			if existing.find_user(p.uid)>=0 and existing.state in ["loading","playing"]:return error(peer,"上一局仍在进行，请重连原房间 / Rejoin your ongoing match")
		if rooms.size()>=int(config.get("max_rooms",2)):return error(peer,"服务器房间已满 / Server room limit")
		var r=Room.new(p.uid,p.profile.nickname);rooms[r.id]=r;p.room=r.id;broadcast_room(r);return
	if kind=="join":
		if p.room!="":return error(peer,"请先离开当前房间 / Leave current room")
		var id=str(message.get("id",""))
		if not rooms.has(id):return error(peer,"房间已关闭 / Room closed")
		var r=rooms[id]
		if not r.join(p.uid,p.profile.nickname):return error(peer,r.error)
		p.room=id;broadcast_room(r)
		if r.sim!=null:send_begin(peer,r)
		return
	if not rooms.has(p.room):return
	var r=rooms[p.room];var ok=true
	match kind:
		"leave":
			r.disconnect_player(p.uid,now,true);p.room="";Wire.send(peer,{"type":"left"});broadcast_room(r);room_list(peer);return
		"configure":ok=r.configure(p.uid,message.get("config",{}))
		"select":ok=r.select(p.uid,int(message.get("slot",-1)),str(message.get("hero","")),int(message.get("hat",12)))
		"ai":ok=r.set_ai(p.uid,int(message.get("slot",-1)),str(message.get("hero","")),int(message.get("hat",12)))
		"remove":
			var index=int(message.get("slot",-1))
			if p.uid!=r.host or r.state!="lobby" or index<0 or index>=r.seats.size():return
			var removed=r.seats[index].uid
			if removed==p.uid:return
			r.seats[index]=r.empty();r.clear_ready()
			for other in peers:
				if peers[other].uid==removed:peers[other].room="";Wire.send(other,{"type":"left"})
		"ready":ok=r.ready(p.uid,bool(message.get("value",false)))
		"start":
			ok=r.begin(p.uid,now)
			if ok:
				for target in peers:
					if peers[target].room==r.id:send_begin(target,r)
		"loaded":
			if message.get("match_id","")==r.match_id:r.loaded(p.uid,now)
		"input":
			if message.get("match_id","")==r.match_id:r.input(p.uid,message,now)
			return
		"return":
			if p.uid!=r.host or r.state!="ended" or not r.result_saved:return
			r.state="lobby";r.sim=null;r.clear_ready()
		_:return
	if not ok:error(peer,r.error)
	broadcast_room(r)

func send_begin(peer,r):
	Wire.send(peer,{"type":"begin","room":r.view(),"slot":r.find_user(peers[peer].uid),"state":Snapshot.capture(r.sim)})

func broadcast_room(r):
	for peer in peers:
		if peers[peer].room==r.id:Wire.send(peer,{"type":"room","room":r.view()})

func room_list(peer):
	var rows=[]
	for r in rooms.values():rows.append(r.view())
	Wire.send(peer,{"type":"rooms","rooms":rows})

func error(peer,message):
	Wire.send(peer,{"type":"error","message":message})
