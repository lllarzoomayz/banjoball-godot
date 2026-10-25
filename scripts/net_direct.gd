extends Node
# The game keeps its pinned DTLS connection inside this direct-only datagram path.
signal offer_ready(value)
signal transport_ready(port)
signal failed(reason)
signal progress(message)
var pc: WebRTCPeerConnection
var channel: WebRTCDataChannel
var loop_udp: PacketPeerUDP
var id=""
var offer={}
var sdp=""
var candidates=[]
var ticks=0.0
var answered_at=-1.0
var path_ready=false
var stopped=true
var local_client_port=0
var received_packets=0
var sent_packets=0
var use_stun=true

static func encode_code(value: Dictionary) -> String:
	return "BNC1."+Marshalls.raw_to_base64(JSON.stringify(value).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP))

static func decode_code(code: String) -> Dictionary:
	var clean=code.replace("\n","").replace("\r","").replace(" ","").replace("\t","")
	if not clean.begins_with("BNC1.") or clean.length()>30000:return {}
	var bytes=Marshalls.base64_to_raw(clean.substr(5))
	var raw=bytes.decompress_dynamic(32768,FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():return {}
	var value=JSON.parse_string(raw.get_string_from_utf8())
	return value if value is Dictionary else {}

func begin():
	shutdown()
	stopped=false;path_ready=false;ticks=0;answered_at=-1;local_client_port=0
	id=Crypto.new().generate_random_bytes(12).hex_encode();offer={};sdp="";candidates=[]
	pc=WebRTCPeerConnection.new()
	pc.session_description_created.connect(func(kind,value):
		if kind!="offer" or stopped:return
		sdp=value
		if pc.set_local_description(kind,value)!=OK:fail("无法生成连接信息 / Cannot create connection"))
	pc.ice_candidate_created.connect(func(_media,_index,value):
		# No relay, loopback or link-local candidates leave the client.
		var fields=value.split(" ",false)
		if fields.size()<8 or fields[2].to_lower()!="udp" or fields[7]=="relay":return
		var ip=fields[4].to_lower()
		if ip.begins_with("127.") or ip=="::1" or ip.begins_with("fe80:") or ip.begins_with("169.254."):return
		if value not in candidates:candidates.append(value))
	var config={"iceServers":[{"urls":["stun:stun.cloudflare.com:3478","stun:stun.l.google.com:19302"]}]} if use_stun else {"iceServers":[]}
	if pc.initialize(config)!=OK:
		fail("直连组件不可用 / Direct component unavailable");return
	channel=pc.create_data_channel("banjo-game",{"ordered":false,"maxRetransmits":0})
	if channel==null or pc.create_offer()!=OK:
		fail("无法创建直连通道 / Cannot create direct channel");return
	progress.emit("正在获取连接地址 / Gathering connection addresses…")

func accept_answer(value: Dictionary):
	if stopped or pc==null or value.get("kind","")!="answer" or value.get("id","")!=id:
		progress.emit("回应码与本次连接不匹配 / Answer does not match this connection");return
	var answer_sdp=str(value.get("sdp",""))
	if answer_sdp.length()>16000 or " typ relay " in answer_sdp or "m=audio " in answer_sdp or "m=video " in answer_sdp:
		fail("回应码内容无效 / Invalid answer");return
	if answered_at>=0:
		progress.emit("正在直连，请稍候 / Direct connection in progress…");return
	if pc.set_remote_description("answer",answer_sdp)!=OK:
		fail("无法读取 NAS 回应 / Cannot apply NAS answer");return
	answered_at=ticks
	progress.emit("地址已交换，正在直连 NAS / Connecting directly to NAS…")

func _process(delta):
	if stopped or pc==null:return
	ticks+=delta
	pc.poll()
	if stopped or pc==null:return
	if not sdp.is_empty() and offer.is_empty() and (pc.get_gathering_state()==WebRTCPeerConnection.GATHERING_STATE_COMPLETE or ticks>12):
		var lines=[]
		for line in sdp.split("\n"):
			if not line.begins_with("a=candidate:") and not line.begins_with("a=end-of-candidates"):
				if not line.strip_edges().is_empty():lines.append(line.strip_edges())
		for candidate in candidates:lines.append("a="+candidate)
		lines.append("a=end-of-candidates")
		offer={"kind":"offer","id":id,"sdp":"\r\n".join(lines)+"\r\n"}
		offer_ready.emit(offer)
	if stopped or pc==null:return
	if pc.get_connection_state()==WebRTCPeerConnection.STATE_FAILED:
		fail("当前网络未能直连 NAS；可重新连接或使用中继 / Direct connection failed");return
	if answered_at>=0 and not path_ready and ticks-answered_at>45:
		fail("直连超时，没有切换到中继 / Direct connection timed out; no relay fallback");return
	if not path_ready and ticks>600:
		fail("连接码已过期，请重新生成 / Connection code expired");return
	if channel==null:return
	channel.poll()
	if channel.get_ready_state()==WebRTCDataChannel.STATE_OPEN and not path_ready:
		loop_udp=PacketPeerUDP.new()
		if loop_udp.bind(0,"127.0.0.1")!=OK:
			fail("无法连接本机游戏通道 / Local game bridge unavailable");return
		path_ready=true;transport_ready.emit(loop_udp.get_local_port())
	if not path_ready:return
	if channel.get_ready_state()!=WebRTCDataChannel.STATE_OPEN:
		fail("NAS 直连已断开 / Direct connection lost");return
	for _i in range(256):
		if loop_udp.get_available_packet_count()==0:break
		var packet=loop_udp.get_packet()
		if loop_udp.get_packet_ip()!="127.0.0.1" or packet.size()>2048:continue
		if local_client_port==0:local_client_port=loop_udp.get_packet_port()
		if loop_udp.get_packet_port()!=local_client_port:continue
		if channel.get_buffered_amount()<262144:
			channel.put_packet(packet);sent_packets+=1
	for _i in range(256):
		if channel.get_available_packet_count()==0:break
		var packet=channel.get_packet()
		if channel.was_string_packet() or packet.size()>2048 or local_client_port==0:continue
		loop_udp.set_dest_address("127.0.0.1",local_client_port);loop_udp.put_packet(packet);received_packets+=1

func fail(message: String):
	if stopped:return
	shutdown();failed.emit(message)

func shutdown():
	stopped=true;path_ready=false
	if channel!=null:channel.close();channel=null
	if pc!=null:pc.close();pc=null
	if loop_udp!=null:loop_udp.close();loop_udp=null

func _exit_tree():
	shutdown()
