extends Node
# Only game UDP is bridged. No TUN, VPN service, subnet route or relay fallback.
signal progress(message: String)
signal transport_ready(port: int)
signal failed(message: String)

const NAS="10.154.37.1"
var core_pid=-1
var query_pid=-1
var elapsed=0.0
var next_query=0.0
var rpc_port=0
var game_port=0
var active=false
var path_ready=false
var peers_seen=false
var core_path=""
var cli_path=""
var guard_path=""
var work=""
var windows=false
var last_peers=[]
var last_node={}
var query_kind="peer"
var query_count=0
var lost_polls=0

func begin():
	shutdown()
	windows=OS.get_name()=="Windows"
	work=ProjectSettings.globalize_path("user://easytier")
	DirAccess.make_dir_recursive_absolute(work)
	if windows:
		core_path=ProjectSettings.globalize_path("res://bin/easytier/windows/easytier-core.exe")
		cli_path=ProjectSettings.globalize_path("res://bin/easytier/windows/easytier-cli.exe")
	elif OS.get_name()=="Android":
		# Android extracts the signed APK's native files to a read-only executable
		# directory. Never execute a downloaded binary or a writable data file.
		var folder=""
		if Engine.has_singleton("AndroidRuntime"):
			var runtime=Engine.get_singleton("AndroidRuntime")
			var loader=runtime.getApplicationContext().getClassLoader()
			var library=loader.findLibrary("easytier_core")
			if library is String:folder=library.get_base_dir()
		if folder.is_empty() or "!" in folder:
			fail("内置联网组件路径不可用，请更新安装包 / Embedded connector unavailable");return
		core_path=folder.path_join("libeasytier_core.so")
		cli_path=folder.path_join("libeasytier_cli.so")
		guard_path=folder.path_join("libeasytier_guard.so")
	else:
		fail("此平台暂不支持内置 EasyTier / Platform not supported");return
	# Android FileAccess resolves external paths through its asset provider.
	# ClassLoader.findLibrary above has already resolved installed native files.
	if windows and (not FileAccess.file_exists(core_path) or not FileAccess.file_exists(cli_path)):
		fail("安装包缺少 EasyTier 组件 / Missing embedded connector");return
	var cfg=JSON.parse_string(FileAccess.get_file_as_string("res://assets/network/easytier.json"))
	if not cfg is Dictionary or not cfg.get("p2p_only",false):
		fail("直连配置无效 / Invalid direct-only configuration");return
	var tcp=TCPServer.new()
	if tcp.listen(0,"127.0.0.1")!=OK:fail("无法分配联网管理端口 / Port unavailable");return
	rpc_port=tcp.get_local_port();tcp.stop()
	var udp=PacketPeerUDP.new()
	if udp.bind(0,"127.0.0.1")!=OK:fail("无法分配游戏端口 / Port unavailable");return
	game_port=udp.get_local_port();udp.close()
	var local_ip="10.154.%d.%d"%[randi_range(38,254),randi_range(2,254)]
	var text='instance_name = "Banjoball-Player"\nhostname = "Banjoball-Player"\nipv4 = "%s"\nlisteners = ["udp://0.0.0.0:0", "tcp://0.0.0.0:0"]\n'%local_ip
	text+='stun_servers = '+JSON.stringify(cfg.stun)+'\n'
	text+='[network_identity]\nnetwork_name = '+JSON.stringify(cfg.name)+'\nnetwork_secret = '+JSON.stringify(cfg.secret)+'\n'
	text+='[flags]\nno_tun = true\np2p_only = true\ndisable_relay_data = true\nrelay_network_whitelist = ""\nlatency_first = false\nbind_device = false\ndisable_upnp = true\nenable_exit_node = false\nmulti_thread_count = 2\n'
	text+='[console_logger]\nlevel = "warn"\n'
	var endpoints=cfg.peers.duplicate()
	# Do not retry a home-LAN address while the phone is using cellular data.
	for local_address in IP.get_local_addresses():
		if local_address.begins_with("192.168.0."):
			endpoints.append(cfg.lan_peer);break
	for peer in endpoints:text+='[[peer]]\nuri = '+JSON.stringify(peer)+'\n'
	text+='[[port_forward]]\nbind_addr = "127.0.0.1:%d"\ndst_addr = "%s:27888"\nproto = "udp"\n'%[game_port,NAS]
	text+='[[acl.acl_v1.chains]]\nname = "nas_replies_only"\nchain_type = 1\nenabled = true\ndefault_action = 2\n'
	# Upstream 2.6.4 ACL runs before fragment reassembly: subsequent fragments
	# have no UDP port header. Restrict replies to the NAS IP, not a source port.
	text+='[[acl.acl_v1.chains.rules]]\nname = "nas_reply"\nenabled = true\npriority = 1000\nprotocol = 2\nsource_ips = ["'+NAS+'/32"]\naction = 1\n'
	text+='[[acl.acl_v1.chains]]\nname = "no_forward"\nchain_type = 3\nenabled = true\ndefault_action = 2\n'
	var file=FileAccess.open(work.path_join("client.toml"),FileAccess.WRITE)
	if file==null:fail("无法保存联网配置 / Cannot write configuration");return
	file.store_string(text);file.close()
	# A random installation ID avoids Android's unsupported desktop state path.
	var id_path=work.path_join("installation-id")
	var installation_id=FileAccess.get_file_as_string(id_path).strip_edges() if FileAccess.file_exists(id_path) else ""
	if installation_id.is_empty():
		installation_id=Crypto.new().generate_random_bytes(16).hex_encode()
		var id_file=FileAccess.open(id_path,FileAccess.WRITE)
		if id_file==null:fail("无法保存联网标识 / Cannot save connector identity");return
		id_file.store_string(installation_id);id_file.close()
	core_pid=spawn(core_path,["-c",work.path_join("client.toml"),"-r","127.0.0.1:"+str(rpc_port),"--machine-id",installation_id],"core.log",0)
	if core_pid<=0:fail("EasyTier 启动失败 / Connector could not start");return
	active=true;elapsed=0;next_query=1;path_ready=false;peers_seen=false;lost_polls=0;query_count=0;last_node={};last_peers=[]
	progress.emit("EasyTier 正在寻找 NAS，仅允许直连 / Finding NAS; direct only…")

func spawn(path: String,args: Array,log_name: String,timeout: int) -> int:
	if windows:return OS.create_process(path,PackedStringArray(args),false)
	return OS.create_process(guard_path,PackedStringArray([path,work.path_join(log_name),str(timeout)]+args),false)

func _process(delta):
	if not active:return
	elapsed+=delta
	if not OS.is_process_running(core_pid):
		fail("EasyTier 进程已退出；可复制诊断信息 / Connector stopped");return
	if query_pid>0 and not OS.is_process_running(query_pid):
		query_pid=-1
		var result=JSON.parse_string(FileAccess.get_file_as_string(work.path_join(query_kind+".json")))
		if query_kind=="node" and result is Dictionary:
			last_node={"stun":result.get("stun_info",{}),"ip_list":result.get("ip_list",{}),"feature_flag":result.get("feature_flag",{})}
		if result is Array:
			last_peers=result
			var direct=false
			for item in result:
				if item.get("cost","")!="Local":peers_seen=true
				if item.get("ipv4","")==NAS and item.get("cost","")=="p2p":direct=true
			if direct:
				lost_polls=0
				if not path_ready:
					path_ready=true;progress.emit("EasyTier 已直连 NAS，正在连接游戏 / Direct NAS path ready")
					transport_ready.emit(game_port)
			elif path_ready:
				lost_polls+=1
				if lost_polls>=2:fail("NAS 直连已中断，未使用中继；请重新连接 / Direct path lost; no relay");return
			else:
				progress.emit("已交换地址，正在打洞直连 NAS / Establishing direct NAS path…" if peers_seen else "正在联系接头节点 / Finding NAS…")
	if not path_ready and elapsed>100:
		fail("EasyTier 直连未成功，未使用中继；请复制诊断信息 / Direct connection timed out; no relay");return
	if query_pid<0 and elapsed>=next_query:
		next_query=elapsed+3
		query_kind="node" if query_count%4==0 else "peer";query_count+=1
		if windows:
			# Windows output collection runs on a worker to keep the UI responsive.
			if query_thread!=null:
				if query_thread.is_alive():return
				query_thread.wait_to_finish();query_thread=null
			query_thread=Thread.new();query_thread.start(query_windows)
		else:query_pid=spawn(cli_path,["-p","127.0.0.1:"+str(rpc_port),"-o","json",query_kind],query_kind+".json",5)

var query_thread: Thread
func query_windows():
	var output=[]
	var code=OS.execute(cli_path,PackedStringArray(["-p","127.0.0.1:"+str(rpc_port),"-o","json",query_kind]),output,false,false)
	if code==0 and not output.is_empty():
		var file=FileAccess.open(work.path_join(query_kind+".json"),FileAccess.WRITE)
		if file!=null:file.store_string(str(output[0]));file.close()
	call_deferred("windows_query_done")

func windows_query_done():
	# Feed the same completion path used by the Android bounded query process.
	if active:query_pid=2147483647

func diagnostics() -> String:
	var peers=[]
	for peer in last_peers:
		peers.append({"ip":peer.get("ipv4",""),"route":peer.get("cost",""),"nat":peer.get("nat_type",""),"ms":peer.get("lat_ms",""),"proto":peer.get("tunnel_proto","")})
	var report={"version":"0.4.39","p2p_only":true,"active":active,"direct_ready":path_ready,"seconds":int(elapsed),"peers":peers,"node":last_node}
	if not work.is_empty() and FileAccess.file_exists(work.path_join("core.log")):
		var file=FileAccess.open(work.path_join("core.log"),FileAccess.READ)
		if file!=null:
			file.seek(maxi(0,file.get_length()-262144))
			var tail=file.get_buffer(262144).get_string_from_utf8()
			var config=JSON.parse_string(FileAccess.get_file_as_string("res://assets/network/easytier.json"))
			if config is Dictionary and not str(config.get("secret","")).is_empty():tail=tail.replace(str(config.secret),"[redacted]")
			var clues=[]
			for line in tail.split("\n"):
				var lower=line.to_lower()
				if "connecting to peer" in lower or "connect to peer error" in lower:continue
				if "punch" in lower or "listener" in lower or "error" in lower or "failed" in lower or "terminated" in lower:
					clues.append(line.right(340))
			if clues.size()>8:clues=clues.slice(0,2)+clues.slice(clues.size()-6)
			report["punch_log"]=clues
	return JSON.stringify(report)

func fail(message):
	shutdown();failed.emit(message)

func shutdown():
	active=false
	for pid in [query_pid,core_pid]:
		if pid>0 and pid!=2147483647 and OS.is_process_running(pid):OS.kill(pid)
	query_pid=-1;core_pid=-1
	if query_thread!=null:
		query_thread.wait_to_finish();query_thread=null

func _exit_tree():
	shutdown()
