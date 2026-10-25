extends Node
signal changed
signal begin_match(data)
signal left_match
const Wire=preload("res://scripts/net_wire.gd")
const Snapshot=preload("res://scripts/net_snapshot.gd")
const Endpoint=preload("res://scripts/net_endpoint.gd")
const RoomCode=preload("res://scripts/net_room_code.gd")
const Direct=preload("res://scripts/net_direct.gd")
const EasyTier=preload("res://scripts/net_easytier.gd")
const HANDSHAKE_TIMEOUT=25.0
var host: ENetConnection
var peer: ENetPacketPeer
var udp=PacketPeerUDP.new()
var address="127.0.0.1"
var status="未连接 / Offline"
var profile={}
var token=""
var room={}
var rooms=[]
var servers=[]
var match_id=""
var slot=0
var in_match=false
var sim
var snapshots=[]
var elapsed=0.0
var newest_at=0.0
var seq=0
var clock=0.0
var ping_clock=0.0
var refresh_clock=0.0
var connecting_at=0.0
var last_received=0.0
var retry_at=0.0
var wants_connection=false
var connected=false
var authenticated=false
var ping_ms=0
var last_pong_at=-1.0
var stick=Vector2.ZERO
var stick_clock=0.0
var pending_auth={}
var pending_room_code=""
var direct
var easytier
var direct_mode=""
var direct_stage=""
var direct_offer={}
var direct_offer_code=""
var direct_bootstrap_ready=false
var direct_started=0.0
var connection_path=""

func _ready():
	address=Endpoint.packaged_address()
	var cfg=ConfigFile.new()
	if cfg.load("user://network.cfg")==OK:restore_session(cfg)
	udp.bind(0);udp.set_broadcast_enabled(true)

func restore_session(cfg: ConfigFile):
	if str(cfg.get_value("network","deployment",""))==Endpoint.packaged_deployment():
		var saved_address=str(cfg.get_value("network","address",address))
		# Existing LAN installs pick up the public entry when it is packaged.
		if saved_address not in ["127.0.0.1","127.0.0.1:27888"] and not Endpoint.parse(saved_address).is_empty():address=saved_address
		token=str(cfg.get_value("network","token",""))

func save_session():
	var cfg=ConfigFile.new();cfg.set_value("network","address",address);cfg.set_value("network","token",token)
	cfg.set_value("network","deployment",Endpoint.packaged_deployment())
	cfg.save("user://network.cfg") # Passwords are never persisted.

func discover():
	servers=[]
	udp.set_dest_address("255.255.255.255",Wire.DISCOVERY);udp.put_packet("BANJOBALL_DISCOVER_1".to_utf8_buffer())

func connect_server(ip: String):
	clear_direct()
	connection_path="普通连接 / Standard"
	open_transport(ip)

func open_transport(ip: String, keep_address=false):
	if not keep_address:address=ip.strip_edges()
	wants_connection=true;connected=false;authenticated=false
	last_pong_at=-1.0
	if host!=null:host.destroy();host=null
	peer=null
	var endpoint=Endpoint.parse(ip.strip_edges(),Wire.PORT)
	if endpoint.is_empty():
		status="服务器地址无效，请填写域名或 IP，可附加 :端口 / Invalid server address"
		pending_auth={};wants_connection=false;changed.emit();return
	host=ENetConnection.new()
	var cert=X509Certificate.new()
	var err=cert.load("res://assets/network/server.crt")
	if err==OK:err=host.create_host(1,2)
	if err==OK:err=host.dtls_client_setup("banjoball.lan",TLSOptions.client(cert))
	if err!=OK:status="加密连接初始化失败 / TLS setup failed";wants_connection=false;changed.emit();return
	peer=host.connect_to_host(endpoint.host,endpoint.port,2)
	if peer==null:
		host.destroy();host=null;status="无法解析或连接服务器 / Server unavailable";wants_connection=false;changed.emit();return
	connecting_at=elapsed;last_received=elapsed;status="正在连接 / Connecting…";changed.emit()

func clear_direct():
	if is_instance_valid(direct):direct.shutdown();direct.queue_free()
	if is_instance_valid(easytier):easytier.shutdown();easytier.queue_free()
	easytier=null
	direct=null;direct_mode="";direct_stage="";direct_offer={};direct_offer_code="";direct_bootstrap_ready=false

func start_easytier():
	clear_direct()
	address="10.154.37.1";direct_mode="easytier";direct_stage="connecting";connection_path=""
	if host!=null:host.destroy();host=null
	peer=null;connected=false;authenticated=false;last_pong_at=-1;wants_connection=true
	easytier=EasyTier.new();add_child(easytier)
	easytier.progress.connect(func(message):status=message;changed.emit())
	easytier.failed.connect(direct_failed)
	easytier.transport_ready.connect(func(port):
		direct_stage="game";connection_path="EasyTier 直连 / Direct"
		open_transport("127.0.0.1:"+str(port),true))
	easytier.begin()

func copy_easytier_diagnostics():
	if is_instance_valid(easytier):
		DisplayServer.clipboard_set(easytier.diagnostics())
		status="直连诊断已复制 / Direct diagnostics copied";changed.emit()

func start_direct(ip: String, manual=false, use_stun=true):
	clear_direct()
	address=ip.strip_edges();direct_mode="manual" if manual else "auto";direct_stage="gathering"
	direct_started=elapsed;connection_path=""
	if host!=null:host.destroy();host=null
	peer=null;connected=false;authenticated=false;last_pong_at=-1;wants_connection=true
	direct=Direct.new();direct.use_stun=use_stun;add_child(direct)
	direct.progress.connect(func(message):status=message;changed.emit())
	direct.failed.connect(direct_failed)
	direct.offer_ready.connect(func(value):
		direct_offer=value;direct_offer_code=Direct.encode_code(value)
		if direct_mode=="manual":
			DisplayServer.clipboard_set(direct_offer_code);status="直连码已复制，交给 NAS 后粘贴回应码 / Connection code copied; paste NAS answer";changed.emit()
		else:send_direct_offer())
	direct.transport_ready.connect(func(port):
		direct_stage="game";connection_path="直连 NAS / Direct"
		open_transport("127.0.0.1:"+str(port),true)
		status="直连通道已建立，正在连接游戏 / Direct path ready; connecting game…";changed.emit())
	if not manual:open_transport(address);status="通过 Playit 交换连接信息 / Contacting NAS for direct connection…"
	direct.begin();changed.emit()

func send_direct_offer():
	if direct_mode!="auto" or not direct_bootstrap_ready or direct_offer.is_empty() or direct_stage=="waiting_answer":return
	send({"type":"direct_offer","offer":direct_offer});direct_stage="waiting_answer"
	status="已联系 NAS，正在交换直连地址 / Exchanging direct addresses…";changed.emit()

func paste_direct_answer(code: String):
	if not is_instance_valid(direct):status="请先生成直连码 / Create a connection code first";changed.emit();return
	var answer=Direct.decode_code(code)
	if answer.is_empty():status="回应码不完整，请重新复制 / Incomplete answer code";changed.emit();return
	direct.accept_answer(answer)

func copy_direct_code(ip: String):
	if direct_mode=="manual" and is_instance_valid(direct) and not direct.stopped and not direct_offer_code.is_empty():
		DisplayServer.clipboard_set(direct_offer_code);status="本次直连码已复制 / Current connection code copied";changed.emit()
	else:start_direct(ip,true)

func direct_failed(message: String):
	if host!=null:host.destroy();host=null
	peer=null;connected=false;authenticated=false;wants_connection=false;pending_auth={};last_pong_at=-1
	if is_instance_valid(direct):direct.shutdown()
	if is_instance_valid(easytier):easytier.shutdown()
	direct_stage="failed";connection_path="";status=message;changed.emit()

func authenticate(action: String,user: String,password: String,nickname: String):
	pending_auth={"type":action,"username":user,"password":password,"nickname":nickname}
	if connected and (direct_mode.is_empty() or direct_stage=="game"):send(pending_auth);pending_auth={}
	elif not direct_mode.is_empty():
		if not wants_connection:
			pending_auth={};status="请先重新直连 NAS，再登录 / Reconnect directly before signing in";changed.emit()
	else:connect_server(address)

func send(value: Dictionary):
	Wire.send(peer,value)

func join_room_code(value: String):
	if not authenticated:return
	pending_room_code=RoomCode.normalize(value)
	if pending_room_code.is_empty():
		status="请输入 6 位房间码 / Enter a 6-character room code";changed.emit();return
	status="正在查找房间 / Finding room…";send({"type":"rooms"});changed.emit()

func submit(kind: String,target: Vector2):
	if not in_match or not authenticated:return
	if kind=="move_direction":stick=target
	elif kind in ["stop","move_release","move","move_order"]:stick=Vector2.ZERO
	seq+=1
	send({"type":"input","match_id":match_id,"kind":kind,"target":target,"seq":seq})

func release_input():
	stick=Vector2.ZERO;submit("move_release",Vector2.ZERO)

func _process(delta: float):
	elapsed+=delta;refresh_clock+=delta;ping_clock+=delta;stick_clock+=delta
	if direct_mode=="auto" and direct_stage not in ["game","failed"] and elapsed-direct_started>65:
		direct_failed("自动接头未完成，可使用手动直连码 / Automatic exchange failed; use a manual connection code")
	while udp.get_available_packet_count()>0:
		var bytes=udp.get_packet();var ip=udp.get_packet_ip()
		if bytes.size()>1024:continue
		var found=JSON.parse_string(bytes.get_string_from_utf8())
		if found is Dictionary and found.get("protocol",0)==Wire.VERSION and ip not in servers:servers.append(ip);changed.emit()
	if host!=null:
		for _i in range(64):
			if host==null:break
			var event=host.service(0)
			if event[0]==ENetConnection.EVENT_NONE:break
			match event[0]:
				ENetConnection.EVENT_CONNECT:
					connected=true;peer=event[1];peer.ping_interval(500)
					if direct_mode=="auto" and direct_stage!="game":peer.set_timeout(32,15000,30000)
					else:peer.set_timeout(8,3000,5000)
					# A slow public DTLS handshake is not established-connection silence.
					last_received=elapsed
					status="已联系 NAS，正在准备直连 / NAS reached; preparing direct connection…" if direct_mode=="auto" and direct_stage!="game" else "已连接，请登录 / Connected — sign in";changed.emit()
				ENetConnection.EVENT_DISCONNECT:connection_lost()
				ENetConnection.EVENT_RECEIVE:
					last_received=elapsed;receive(Wire.decode(event[1].get_packet()))
		# Before login the server only sends hello; ENet handles transport liveness.
		# The application heartbeat starts after authentication, so an idle login
		# form must not be mistaken for a dead game connection after eight seconds.
		if connected and authenticated and elapsed-last_received>8 and (direct_mode.is_empty() or direct_stage=="game"):connection_lost()
		if not connected and wants_connection and elapsed-connecting_at>HANDSHAKE_TIMEOUT and elapsed>=retry_at:
			if not direct_mode.is_empty():
				if direct_stage=="game":direct_failed("直连通道已建立，但游戏连接未完成 / Direct path ready, game connection failed")
			else:retry_at=elapsed+3;connect_server(address)
		if connected and authenticated and ping_clock>=1:
			ping_clock=0;send({"type":"ping","stamp":Time.get_ticks_msec()})
		if connected and authenticated and room.is_empty() and refresh_clock>=3:refresh_clock=0;send({"type":"rooms"})
		if in_match and authenticated and stick_clock>=0.15:
			stick_clock=0
			if stick.length()>0.01:submit("move_direction",stick)
		if host!=null:host.flush()
	if in_match and sim!=null and not snapshots.is_empty():render_snapshot()

func connection_lost():
	if direct_mode=="easytier":
		direct_failed("直连已中断，点击“直连 NAS”可重连本局；未使用中继 / Direct connection lost; reconnect to resume");return
	if not direct_mode.is_empty():
		direct_failed("直连连接中断，点击自动直连可重连本局 / Direct connection lost; reconnect to resume" if direct_stage=="game" else "接头连接中断，可点复制直连码手动交换 / Signalling disconnected; use a manual connection code");return
	connected=false;authenticated=false;stick=Vector2.ZERO;pending_auth={}
	last_pong_at=-1.0
	status="连接中断，正在重连；角色会由 AI 临时接管 / Reconnecting…";connecting_at=elapsed-HANDSHAKE_TIMEOUT;retry_at=elapsed+2;changed.emit()

func receive(value: Dictionary):
	match str(value.get("type","")):
		"hello":
			if value.get("protocol",0)!=Wire.VERSION:status="版本不一致 / Update required";wants_connection=false;changed.emit();return
			if direct_mode=="auto" and direct_stage!="game":
				if not value.get("direct",false):direct_failed("NAS 尚未更新直连组件 / Update NAS direct connector first");return
				direct_bootstrap_ready=true;send_direct_offer();return
			if direct_stage=="game":status="已直连 NAS，请登录 / Direct NAS connected — sign in";changed.emit()
			if not pending_auth.is_empty():send(pending_auth);pending_auth={}
			elif token!="":send({"type":"resume","token":token})
		"direct_answer":
			if is_instance_valid(direct) and direct_mode=="auto" and direct_stage=="waiting_answer":
				direct_stage="connecting";direct.accept_answer(value.get("answer",{}))
		"direct_error":
			if not direct_mode.is_empty():direct_failed(str(value.get("message","Direct connection unavailable")))
		"account":
			authenticated=true;profile=value.profile;token=value.token;save_session();status="已登录 / Signed in";changed.emit()
		"error":status=str(value.get("message","Error"));changed.emit()
		"rooms":
			rooms=value.rooms
			if not pending_room_code.is_empty():
				var found=RoomCode.find_room(rooms,pending_room_code)
				pending_room_code=""
				if found!="":send({"type":"join","id":found});status="正在加入房间 / Joining room…"
				else:status="未找到房间，请检查房间码或让房主重新建房 / Room not found"
			changed.emit()
		"profile":profile=value.profile;changed.emit()
		"signed_out":token="";save_session();close_connection();changed.emit()
		"no_room":
			if in_match:
				in_match=false;room={};match_id="";snapshots=[];status="原比赛已结束 / Previous match ended";left_match.emit();changed.emit()
		"room":
			if value.room.get("result_saved",false) and not room.get("result_saved",false):send({"type":"profile"})
			room=value.room
			if room.state=="lobby" and in_match:in_match=false;match_id="";snapshots=[];left_match.emit()
			changed.emit()
		"begin":
			room=value.room;slot=int(value.slot);match_id=room.match_id;seq=0;stick=Vector2.ZERO;snapshots=[];in_match=true
			begin_match.emit(value)
			send({"type":"loaded","match_id":match_id});status="比赛连接正常 / Match connected";changed.emit()
		"snapshot":
			if not in_match or value.get("match_id","")!=match_id:return
			var state=value.state
			if not snapshots.is_empty() and state.timeline<=snapshots.back().timeline:return
			snapshots.append(state);newest_at=elapsed
			while snapshots.size()>8:snapshots.pop_front()
		"left":
			in_match=false;room={};match_id="";snapshots=[];left_match.emit();changed.emit()
		"pong":
			ping_ms=maxi(0,Time.get_ticks_msec()-int(value.stamp));last_pong_at=elapsed

func latency_ms() -> int:
	# Do not show an old or unmeasured value as a healthy 0 ms connection.
	if not connected or not authenticated or last_pong_at<0 or elapsed-last_pong_at>4.0:return -1
	return ping_ms

func render_snapshot():
	var latest=snapshots.back()
	var at=latest.timeline+minf(elapsed-newest_at,0.1)-0.075
	var a=snapshots.front();var b=latest
	for frame in snapshots:
		if frame.timeline<=at:a=frame
		if frame.timeline>=at:b=frame;break
	var alpha=clampf((at-a.timeline)/maxf(0.001,b.timeline-a.timeline),0,1)
	Snapshot.interpolate(sim,a,b,alpha);sim.controlled=slot

func loaded_sim(target,state: Dictionary):
	sim=target;sim.networked=true;sim.remote_client=true;sim.controlled=slot;sim.command_sink=submit
	Snapshot.apply(sim,state)
	snapshots=[state];newest_at=elapsed

func close_connection():
	clear_direct();connection_path=""
	pending_room_code=""
	last_pong_at=-1.0
	wants_connection=false;connected=false;authenticated=false;pending_auth={};in_match=false;room={};snapshots=[];stick=Vector2.ZERO
	if host!=null:host.destroy();host=null
	peer=null;status="未连接 / Offline"

func _exit_tree():
	close_connection();udp.close()
