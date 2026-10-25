extends CanvasLayer
## Low-frequency UI; fixed-size telemetry. Timings are observed durations, not % load.
const Stats=preload("res://scripts/performance_stats.gd")
const Benchmark=preload("res://scripts/benchmark_driver.gd")
var game
var stats=Stats.new()
var panel: Panel
var label: Label
var close_button: Button
var graph: Control
var modal: Panel
var report_text: RichTextLabel
var mode=0
var visible_mode=1
var pending={}
var previous_start=0
var current_start=0
var warmup_until=0
var refresh_at=0
var latest={}
var device={}
var benchmarking=false
var automated=false
var phase=-1
var phase_started=0
var phase_seconds=20.0
var phase_rows=[]
var phase_reports=[]
var saved={}
var last_report={}
var test_path=""
var benchmark_note=""

class FrameGraph extends Control:
	var values=[]
	func _draw():
		if values.size()<2:return
		var points=PackedVector2Array()
		for i in range(values.size()):points.append(Vector2(float(i)/(values.size()-1)*size.x,size.y*(1-clampf(float(values[i])/100,0,1))))
		draw_line(Vector2(0,size.y/2),Vector2(size.x,size.y/2),Color(0.9,0.6,0.2,0.6))
		draw_polyline(points,Color("84dfb0"),1.5,true)

# One-time upgrade: older builds enabled telemetry by default. Afterwards,
# preserve an explicit choice to show it, including across app restarts.
static func migrate_clean_hud(preferences: ConfigFile):
	if int(preferences.get_value("touch","clean_hud_version",0))>=6:return
	preferences.set_value("touch","performance",0)
	preferences.set_value("touch","performance_visible_mode",1)
	preferences.set_value("touch","clean_hud_version",6)

func setup(owner_game):
	game=owner_game;layer=8
	migrate_clean_hud(game.experience.preferences)
	game.experience.save_settings()
	mode=clampi(int(game.experience.preferences.get_value("touch","performance",0)),0,2)
	visible_mode=clampi(int(game.experience.preferences.get_value("touch","performance_visible_mode",1)),1,2)
	if mode>0:visible_mode=mode
	device={"model":OS.get_model_name(),"os":OS.get_name(),"os_version":OS.get_version(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"version":str(ProjectSettings.get_setting("application/config/version","0.4.35")),"native_acceleration":ClassDB.class_exists("BanjoAccelerator") and "--script-only" not in OS.get_cmdline_user_args(),"screen":str(DisplayServer.window_get_size())}
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),mode>0)
	panel=Panel.new();panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_theme_stylebox_override("panel",game.touch_controls.style("101c21df",10));add_child(panel)
	panel.hide()
	label=game.touch_controls.text(panel,"正在采集性能…",21);label.position=Vector2(12,8)
	close_button=game.touch_controls.make_button(panel,"×",func():set_mode(0))
	close_button.tooltip_text="隐藏性能；可在更多 → 性能工具重新打开"
	close_button.focus_mode=Control.FOCUS_NONE
	graph=FrameGraph.new();graph.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_child(graph)
	modal=Panel.new();modal.hide();modal.add_theme_stylebox_override("panel",game.touch_controls.style("101f1afa",18));add_child(modal)
	report_text=RichTextLabel.new();report_text.add_theme_font_override("normal_font",game.font);report_text.add_theme_font_size_override("normal_font_size",25);modal.add_child(report_text)
	var copy=game.touch_controls.make_button(modal,"复制报告",func():DisplayServer.clipboard_set(JSON.stringify(last_report,"\t"));benchmark_note="已复制，可粘贴发送。";show_report());copy.name="Copy"
	var back=game.touch_controls.make_button(modal,"返回菜单",func():modal.hide();game.open_menu());back.name="Back"
	get_viewport().size_changed.connect(layout);layout()
	if FileAccess.file_exists("user://performance-report.json"):
		var parsed=JSON.parse_string(FileAccess.get_file_as_string("user://performance-report.json"))
		if parsed is Dictionary:last_report=parsed
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--perf-output="):test_path=arg.trim_prefix("--perf-output=")
		if arg.begins_with("--perf-seconds="):phase_seconds=maxf(3,float(arg.trim_prefix("--perf-seconds=")))
	if "--perf-benchmark" in OS.get_cmdline_user_args():automated=true;call_deferred("start_benchmark")

func layout():
	var safe=game.touch_controls.safe_rect();var s=safe.size
	panel.position=safe.position+Vector2(108 if game.mobile_enabled else 24,192);panel.size=Vector2(474,282) if mode==2 else Vector2(192,46)
	close_button.position=Vector2(panel.size.x-46,1);close_button.size=Vector2(44,44)
	label.size=Vector2(400,236) if mode==2 else Vector2(118,30)
	graph.position=Vector2(12,246);graph.size=Vector2(400,25)
	var size=Vector2(minf(1250,s.x-60),minf(740,s.y-40))
	modal.position=safe.position+(s-size)/2;modal.size=size
	report_text.position=Vector2(28,22);report_text.size=size-Vector2(56,130)
	for i in range(2):
		var b=modal.get_node("Copy" if i==0 else "Back");b.position=Vector2(28+i*(size.x/2),size.y-92);b.size=Vector2(size.x/2-42,68)

func toggle_mode():
	set_mode(1 if mode==2 else 2)

func toggle_visibility():
	set_mode(0 if mode>0 else visible_mode)

func set_mode(value: int):
	var was_hidden=mode==0
	mode=clampi(value,0,2)
	if was_hidden and mode>0:stats.clear();latest={};invalidate()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),mode>0 or benchmarking)
	if mode>0:visible_mode=mode
	game.experience.preferences.set_value("touch","performance",mode)
	game.experience.preferences.set_value("touch","performance_visible_mode",visible_mode)
	game.experience.save_settings()
	panel.visible=mode>0 and not game.paused and not modal.visible
	graph.visible=mode==2
	layout();refresh_text();refresh_at=0

func invalidate():
	previous_start=0;pending={};warmup_until=Time.get_ticks_usec()+500000

func begin_frame():
	current_start=Time.get_ticks_usec()
	if game.paused or (mode==0 and not benchmarking):invalidate();return
	if previous_start>0 and not pending.is_empty() and current_start>=warmup_until:
		var row=pending.duplicate();row.frame_ms=(current_start-previous_start)/1000.0
		var rid=get_viewport().get_viewport_rid()
		var gpu=RenderingServer.viewport_get_measured_render_time_gpu(rid)
		# Godot GLES on Android has no GPU timestamp queries; zero is unavailable.
		row.gpu_ms=gpu if gpu>0 and not (OS.has_feature("android") and device.renderer=="gl_compatibility") else null
		var render_cpu=RenderingServer.viewport_get_measured_render_time_cpu(rid)
		row.render_cpu_ms=render_cpu+RenderingServer.get_frame_setup_time_cpu() if render_cpu>0 else null
		row.draw_calls=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		row.primitives=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		row.render_memory_mb=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)/1048576.0
		stats.add(row)
		if benchmarking and previous_start-phase_started>=2000000 and phase_rows.size()<6000:phase_rows.append(row)
	previous_start=current_start

func end_frame(profile: Dictionary):
	if mode==0 and not benchmarking:
		panel.hide();pending={};return
	pending=profile if not game.paused else {}
	var now=Time.get_ticks_usec()
	if now>=refresh_at:
		refresh_at=now+500000;latest=stats.snapshot();refresh_text();layout()
	panel.visible=mode>0 and not game.paused and not modal.visible
	graph.visible=mode==2
	if benchmarking:benchmark_frame(now)

func refresh_text():
	if latest.get("frames",0)==0:label.text="FPS —" if mode!=2 else "FPS — · 正在采集性能…";return
	var avg=latest.average;var peak=latest.peak
	label.text="FPS %d"%roundi(latest.fps_recent)
	if mode==2:
		label.text="FPS %.1f / %d  ·  帧 %.1f ms"%[latest.fps_recent,Engine.max_fps,latest.frame_ms]
		label.text+="\n近10秒 P95 %.1f  最慢 %.1f ms"%[latest.p95_ms,latest.max_ms]
		label.text+="\n慢帧 >50ms %d  >100ms %d"%[latest.over50,latest.over100]
		label.text+="\nCPU游戏 %.1f / 峰 %.1f ms"%[avg.get("cpu_ms",0),peak.get("cpu_ms",0)]
		label.text+="\n逻辑 %.1f  画面 %.1f  UI %.1f"%[avg.get("sim_ms",0),avg.get("visual_ms",0),avg.get("ui_ms",0)]
		label.text+="\n渲染CPU %s · GPU %s"%[("%.1fms"%avg.render_cpu_ms) if avg.has("render_cpu_ms") else "—",("%.1fms"%avg.gpu_ms) if avg.has("gpu_ms") else "不支持"]
		label.text+="\n绘制 %d · 图形资源 %.0fMB"%[avg.get("draw_calls",0),avg.get("render_memory_mb",0)]
	if mode!=2:return
	graph.values=[]
	var stride=maxi(1,stats.samples.size()/120)
	for i in range(0,stats.samples.size(),stride):
		var maximum=0.0
		for j in range(i,mini(i+stride,stats.samples.size())):maximum=maxf(maximum,stats.samples[j].frame_ms)
		graph.values.append(maximum)
	graph.queue_redraw()

func start_benchmark():
	if game.sim.networked:
		game.sim.notice="联机中可查看性能指标；完整自测请离开房间后运行。"
		return
	if benchmarking:return
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	benchmarking=true;phase=-1;phase_reports=[];modal.hide();benchmark_note=""
	saved={"character":game.character_select.selected,"field":game.field_select.selected,"rules":game.mode_select.selected,"scale":get_viewport().scaling_3d_scale,"cap":Engine.max_fps,"follow":game.experience.follow_camera}
	game.character_select.select(0);game.field_select.select(0);game.mode_select.select(0)
	game.touch_controls.cancel_all();game.touch_controls.tools_panel.hide()
	Engine.max_fps=60
	next_phase()

func next_phase():
	phase+=1
	if phase>=3:finish_benchmark();return
	# Replace every simulation clock, random state and old command queue. Resetting
	# only the RNG would still inherit timer alignment from the previous match.
	game.sim=preload("res://scripts/match_sim.gd").new()
	game.sim.random.seed=Benchmark.SEED
	game.experience.last_sound=0;game.experience.last_countdown=-1;game.experience.last_phase=""
	game.start_game(6 if phase==2 else 3)
	game.sim.benchmark_driver=Benchmark.new()
	game.sim.countdown=0;game.sim.match_state="playing"
	game.experience.follow_camera=true
	get_viewport().scaling_3d_scale=0.425 if phase==1 else 0.85
	phase_started=Time.get_ticks_usec();phase_rows=[];stats.clear();invalidate()

func benchmark_frame(now: int):
	if game.paused:
		finish_benchmark(true);return
	var elapsed=(now-phase_started)/1000000.0
	game.sim.notice="性能自测 %d/3 · %s · 剩余 %d 秒"%[phase+1,["3对3","3对3 · 半分辨率","6对6"][phase],maxi(0,ceili(phase_seconds-elapsed))]
	if elapsed>=phase_seconds:
		var report=Stats.summarize(phase_rows);report.name=["3v3","3v3_half_resolution","6v6"][phase];report.scale=get_viewport().scaling_3d_scale;report.cap=Engine.max_fps
		report.simulation_seconds=game.sim.timeline;report.movement_ticks=game.sim.movement_tick
		phase_reports.append(report);next_phase()

func finish_benchmark(canceled=false):
	benchmarking=false
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),mode>0)
	game.sim.benchmark_driver=null
	get_viewport().scaling_3d_scale=saved.scale;Engine.max_fps=saved.cap
	game.experience.follow_camera=saved.follow
	game.character_select.select(saved.character);game.field_select.select(saved.field);game.mode_select.select(saved.rules)
	last_report={"device":device,"completed":not canceled,"phases":phase_reports,"protocol":Benchmark.PROTOCOL,"seed":Benchmark.SEED,"notes":"Each phase starts a fresh simulation with the same seed and fixed-tick commands, excluding 2s warmup. Phase length is wall time; simulation_seconds records any time lost to long-frame clamps. Older benchmark protocols are not directly comparable. CPU is instrumented game work, not total utilization. Render timings are asynchronous. GPU null means unavailable. Low resolution comparison is suggestive, not proof of a GPU bottleneck. Loading and pauses excluded.","created":Time.get_datetime_string_from_system()}
	if "--test-ui" not in OS.get_cmdline_user_args():
		var file=FileAccess.open("user://performance-report.json",FileAccess.WRITE)
		if file:file.store_string(JSON.stringify(last_report,"\t"))
	# Android truncates long log lines. Emit a few bounded chunks only on completion.
	var encoded=JSON.stringify(last_report);var chunks=ceili(encoded.length()/200.0)
	for i in range(chunks):print("PERFORMANCE_REPORT_PART %d/%d "%[i+1,chunks]+encoded.substr(i*200,200))
	if test_path!="":FileAccess.open(test_path,FileAccess.WRITE).store_string(JSON.stringify(last_report,"\t"))
	game.open_menu();invalidate();show_report()
	if automated:call_deferred("finish_automated")

func finish_automated():
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		if test_path!="":get_viewport().get_texture().get_image().save_png(test_path.get_basename()+".png")
	get_tree().quit()

func show_report():
	game.open_menu();modal.show();layout()
	var lines="性能报告 · "+str(device.model)+"\n"+str(device.gpu)+"\n"
	if last_report.is_empty():
		lines+="还没有自测报告。比赛中点 更多 → 性能工具 → 60秒自测。\n自测将重新开局，依次运行3对3、降低分辨率、6对6；每段20秒，开头2秒不计入。"
	else:
		lines+=("已完成" if last_report.completed else "自测被暂停，报告不完整")+" · 每段开头2秒不计入\n"
		for row in last_report.phases:
			if row.get("frames",0)==0:continue
			var title={"3v3":"3对3","3v3_half_resolution":"3对3 · 半分辨率","6v6":"6对6"}.get(row.name,row.name)
			lines+="\n%s：%.1f FPS · P95 %.1f ms · 最慢 %.1f ms\n慢帧 >50ms %d · >100ms %d · CPU游戏均值 %.1f ms\n逻辑 %.1f · 门框 %.1f · 角色 %.1f · 特效 %.1f ms\n"%[title,row.fps,row.p95_ms,row.max_ms,row.over50,row.over100,row.average.get("cpu_ms",0),row.average.get("sim_ms",0),row.average.get("goals_ms",0),row.average.get("actors_ms",0),row.average.get("effects_ms",0)]
			lines+="最慢一帧：CPU游戏 %.1f / 逻辑 %.1f / 画面 %.1f ms\n"%[row.worst.get("cpu_ms",0),row.worst.get("sim_ms",0),row.worst.get("visual_ms",0)]
	lines+="\nCPU为游戏处理耗时（含本地加速），不是整机占用率。GPU不支持时不能仅凭FPS断定显卡瓶颈。\n帧率到达30/60上限属于限帧；图形资源内存不等于手机总内存。\n"+benchmark_note
	report_text.text=lines

