extends CanvasLayer
## Touch is translated into the same ordered commands as desktop input.
## Each finger owns its initial UI/world role until release: no click-through.
const Characters=preload("res://scripts/character_rules.gd")
const Preview=preload("res://scripts/aim_preview.gd")
const AIM_RADIUS=88.0
const AIM_DEAD_ZONE=0.12
var game
var root: Control
var play_root: Control
var menu: Panel
var report: Panel
var help_panel: Panel
var half_panel: Panel
var tools_panel: Panel
var diagnostics_open=false
var emotes_open=false
var last_notice=""
var notice_remaining=0.0
var score: Label
var clock: Label
var status: Label
var player_label: Label
var phase: Label
var aim_note: Label
var pick_language: TouchPicker
var mana: Control
var mana_note: Label
var actions={}
var buttons={}
var touches={}
var joystick: Control
var joystick_center=Vector2.ZERO
var joystick_axis=Vector2.ZERO
var joystick_clock=0.0
var joystick_sent_axis=Vector2.ZERO
var joystick_id=-1
var world_id=-1
var aim_id=-1
var aim_player=-1
var aim_character=""
# Unbounded finger travel in wheel radii. Only the display and range clamp it.
var aim_axis=Vector2.ZERO
var aim_origin=Vector2.ZERO
var aim_cancelled=false
var aim_pad: Control
var portrait_paths={}
var portrait_textures={}
var portrait_players=[]
var portrait_key=""
var selected_portrait=-1
var last_size=Vector2.ZERO
var movement="stick"
var chosen_team=3
var pick_character: TouchPicker
var pick_field: TouchPicker
var pick_rules: TouchPicker
var pick_team: TouchPicker
var pick_controls: TouchPicker
var pick_quality: TouchPicker
var pick_hat: TouchPicker
var picker_overlay: Control
var picker_panel: Panel
var picker_scroll: ScrollContainer
var picker_list: VBoxContainer
var active_picker: TouchPicker
var picker_finger=-1
var picker_start=Vector2.ZERO
var picker_offset=0
var picker_dragged=false
var character_note: Label
var field_note: Label
var resume: Button
var sound: Button
var report_text: RichTextLabel
var half_select: TouchPicker
var half_title: Label
var was_modal=true
var help_return="menu"
var caption_locale=""

# A normal Control list supports touch dragging; native PopupMenu scrolling
# depends on hover/wheel navigation and is awkward on Android.
class TouchPicker extends Button:
	signal item_selected(index: int)
	var items=[]
	var selected=0
	func add_item(value: String):
		items.append(value)
		if items.size()==1:select(0)
	func select(index: int):
		selected=index;text=items[index]+"  ▾"

class Stick extends Control:
	var axis=Vector2.ZERO
	func _draw():
		var center=size/2
		draw_circle(center,94,Color(0.07,0.13,0.14,0.75))
		draw_arc(center,94,0,TAU,64,Color(0.65,0.84,0.75,0.65),3,true)
		draw_circle(center+axis*65,34,Color(0.56,0.83,0.70,0.8))

class AimPad extends Control:
	const RADIUS=88.0
	const THUMB_RADIUS=19.0
	var axis=Vector2.ZERO
	var cancelled=false
	func _draw():
		var color=Color("ff8585") if cancelled else Color("94e6ff")
		draw_arc(size/2,RADIUS,0,TAU,48,color,2,true)
		draw_circle(size/2+axis.limit_length(1)*(RADIUS-THUMB_RADIUS),THUMB_RADIUS,color*Color(1,1,1,0.8))

class ManaRing extends Control:
	var value=100.0:
		set(next):
			next=clampf(next,0,100)
			if absf(value-next)<0.01:return
			value=next;queue_redraw()
	var active=false:
		set(next):
			if active==next:return
			active=next;queue_redraw()
	func _draw():
		var center=size/2;var radius=minf(size.x,size.y)/2+7
		draw_arc(center,radius,0,TAU,64,Color("1c3445"),7,true)
		if value<=0:return
		var end=-PI/2+TAU*value/100.0;var segments=maxi(2,ceili(64*value/100.0))
		if active:draw_arc(center,radius,-PI/2,end,segments,Color(0.3,0.8,1,0.22),13,true)
		draw_arc(center,radius,-PI/2,end,segments,Color("80e5ff") if active else Color("4babed"),7,true)

func setup(owner_game):
	game=owner_game;layer=5
	movement=game.experience.mobile_mode
	if movement not in ["tap","stick"]:movement="stick"
	game.experience.overlay.mobile=true
	game.experience.follow_camera=true
	root=Control.new();root.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(root)
	play_root=Control.new();play_root.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(play_root)
	build_play()
	build_menu()
	build_report()
	build_help()
	build_half()
	build_picker_overlay()
	apply_quality()
	get_viewport().size_changed.connect(layout)
	layout()

func style(color: String, radius: int=14) -> StyleBoxFlat:
	var s=StyleBoxFlat.new();s.bg_color=Color(color)
	s.border_color=Color("607d69");s.set_border_width_all(2);s.set_corner_radius_all(radius)
	return s

func text(parent: Node, value: String, font_size: int=26) -> Label:
	var l=Label.new();l.text=value;l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font",game.font);l.add_theme_font_size_override("font_size",font_size)
	l.add_theme_color_override("font_color",Color("e5ecd9"))
	l.add_theme_color_override("font_outline_color",Color("101e1b"));l.add_theme_constant_override("outline_size",4)
	parent.add_child(l);return l

func make_button(parent: Node, value: String, callback: Callable, accent=false) -> Button:
	var b=Button.new();b.text=value;b.focus_mode=Control.FOCUS_NONE
	b.add_theme_font_override("font",game.font);b.add_theme_font_size_override("font_size",26)
	b.add_theme_stylebox_override("normal",style("305a48" if accent else "182d28ed"))
	b.add_theme_stylebox_override("hover",style("365842"));b.add_theme_stylebox_override("pressed",style("507859"))
	b.add_theme_stylebox_override("disabled",style("18231fe0"))
	b.pressed.connect(callback);parent.add_child(b);return b

func play_button(id: String,value: String,callback: Callable,accent=false):
	var b=make_button(play_root,value,callback,accent);buttons[id]=b;actions[id]=callback
	# Gameplay handles all fingers itself, including mouse preview input.
	b.mouse_filter=Control.MOUSE_FILTER_IGNORE

func picker(parent: Node, items: Array) -> TouchPicker:
	var b=TouchPicker.new();b.clip_text=true;b.focus_mode=Control.FOCUS_NONE
	b.add_theme_font_override("font",game.font);b.add_theme_font_size_override("font_size",26)
	b.add_theme_stylebox_override("normal",style("233c30"));b.add_theme_stylebox_override("hover",style("365842"))
	for value in items:b.add_item(value)
	b.pressed.connect(func():open_picker(b))
	parent.add_child(b);return b

func build_picker_overlay():
	picker_overlay=Control.new();picker_overlay.mouse_filter=Control.MOUSE_FILTER_STOP;root.add_child(picker_overlay);picker_overlay.hide()
	var shade=ColorRect.new();shade.color=Color(0,0,0,0.65);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);picker_overlay.add_child(shade)
	picker_panel=Panel.new();picker_panel.add_theme_stylebox_override("panel",style("101f1aff",20));picker_overlay.add_child(picker_panel)
	text(picker_panel,"选择选项 · 上下滑动查看更多",28).name="Title"
	var close=make_button(picker_panel,"返回",close_picker);close.name="Close"
	picker_scroll=ScrollContainer.new();picker_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	picker_scroll.mouse_filter=Control.MOUSE_FILTER_IGNORE;picker_scroll.get_v_scroll_bar().mouse_filter=Control.MOUSE_FILTER_IGNORE
	picker_scroll.scroll_deadzone=14;picker_panel.add_child(picker_scroll)
	picker_list=VBoxContainer.new();picker_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	picker_list.mouse_filter=Control.MOUSE_FILTER_IGNORE
	picker_list.add_theme_constant_override("separation",8);picker_scroll.add_child(picker_list)

func open_picker(source: TouchPicker):
	cancel_all();active_picker=source
	for child in picker_list.get_children():picker_list.remove_child(child);child.queue_free()
	for i in range(source.items.size()):
		var item=make_button(picker_list,("✓  " if i==source.selected else "")+source.items[i],func():choose_picker_item(i),i==source.selected)
		item.custom_minimum_size.y=76;item.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		item.mouse_filter=Control.MOUSE_FILTER_IGNORE # The list owns the finger until release, even over a button.
		item.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE
	picker_panel.get_node("Title").text="选择角色 · 上下滑动查看更多" if source in [pick_character,half_select] else "选择选项 · 上下滑动查看更多"
	if source==pick_hat:picker_panel.get_node("Title").text="选择帽子 · 仅改变外观"
	picker_overlay.show();picker_scroll.scroll_vertical=0
	picker_scroll.set_deferred("scroll_vertical",source.selected*84)

func choose_picker_item(index: int):
	if not is_instance_valid(active_picker):return
	var source=active_picker;close_picker();source.select(index);source.item_selected.emit(index)

func close_picker():
	picker_overlay.hide();active_picker=null;picker_finger=-1

func picker_touch(index: int,pos: Vector2,pressed: bool,canceled=false) -> bool:
	if pressed:
		if not picker_scroll.get_global_rect().has_point(pos):return false
		if picker_finger==-1:
			picker_finger=index;picker_start=pos;picker_offset=picker_scroll.scroll_vertical;picker_dragged=false
		return true
	if index!=picker_finger:return false
	picker_drag(pos);picker_finger=-1
	if canceled or picker_dragged or not picker_scroll.get_global_rect().has_point(pos):return true
	for i in range(picker_list.get_child_count()):
		if picker_list.get_child(i).get_global_rect().has_point(pos):choose_picker_item(i);break
	return true

func picker_drag(pos: Vector2):
	if pos.distance_to(picker_start)>14:picker_dragged=true
	if picker_dragged:picker_scroll.scroll_vertical=picker_offset-roundi(pos.y-picker_start.y)

func picker_input(event) -> bool:
	if event is InputEventScreenTouch:return picker_touch(event.index,event.position,event.pressed,event.canceled)
	if event is InputEventScreenDrag and event.index==picker_finger:picker_drag(event.position);return true
	if event is InputEventMouseButton and event.device!=-1 and event.button_index==MOUSE_BUTTON_LEFT:
		return picker_touch(1000,event.position,event.pressed)
	if event is InputEventMouseMotion and picker_finger==1000:picker_drag(event.position);return true
	return false

func modal_panel() -> Panel:
	var p=Panel.new();p.add_theme_stylebox_override("panel",style("101f1af5",20));root.add_child(p);return p

func rect(c: Control,x: float,y: float,w: float,h: float):
	c.position=Vector2(x,y);c.size=Vector2(w,h)

func build_play():
	score=text(play_root,"",34);clock=text(play_root,"",22)
	score.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;clock.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	player_label=text(play_root,"",24);status=text(play_root,"",25)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	phase=text(play_root,"",54);phase.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	aim_note=text(play_root,"",25);aim_note.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	play_button("menu","暂停",func():cancel_all();game.open_menu())
	play_button("tools","更多",toggle_tools)
	play_button("follow","跟随",func():game.experience.follow_camera=true;game.zoom=0.78)
	play_button("perf_toggle","隐藏性能",func():game.perf.toggle_visibility())
	buttons.perf_toggle.add_theme_font_size_override("font_size",21)
	play_button("kick","传 / 射",func():game.set_aim("kick"),true)
	play_button("sprint","冲刺",func():command("sprint"))
	play_button("ability","技能",func():game.choose_ability(),true)
	play_button("secondary","第二技能",func():game.choose_ability(true))
	play_button("switch","切队友",func():game.sim.switch_player();cancel_aim())
	play_button("pass","呼叫传球",func():game.sim.call_for_pass())
	play_button("hold","站定 / 跳",func():command("hold"))
	play_button("jump","守门跳跃",func():
		if game.sim.KeeperRules.eligible(game.sim,game.sim.controlled):command("hold"))
	play_button("stop","停止",func():cancel_aim();command("stop"))
	play_button("cancel","取消选点",cancel_aim)
	buttons.cancel.text="拖到这里\n取消施放"
	portrait_paths=JSON.parse_string(FileAccess.get_file_as_string("res://assets/textures/mobile-portraits.json"))
	for id in portrait_paths:portrait_textures[id]=load(portrait_paths[id])
	for slot in range(6):
		var id="ally_"+str(slot)
		play_button(id,"",func():select_portrait(slot))
		var image=TextureRect.new();image.name="Portrait";image.mouse_filter=Control.MOUSE_FILTER_IGNORE
		image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		buttons[id].add_child(image);rect(image,4,4,60,60)
		var number=text(buttons[id],"",18);number.name="Number";rect(number,4,44,60,24);number.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	for id in ["kick","ability","secondary","sprint","hold","jump","pass","stop","cancel"]:
		var b=buttons[id];b.add_theme_font_size_override("font_size",21);b.clip_text=true
		b.add_theme_stylebox_override("normal",style("305a48ee" if id in ["kick","ability"] else "182d28dd",90))
		b.add_theme_stylebox_override("disabled",style("18231faa",90))
	buttons.pass.text="呼叫\n传球";buttons.switch.hide()
	buttons.hold.hide();buttons.stop.hide()
	mana=ManaRing.new();mana.mouse_filter=Control.MOUSE_FILTER_IGNORE;buttons.sprint.add_child(mana)
	mana_note=text(buttons.sprint,"100%",16)
	buttons.cancel.add_theme_stylebox_override("normal",style("622d37dd",90))
	joystick=Stick.new();joystick.mouse_filter=Control.MOUSE_FILTER_IGNORE;play_root.add_child(joystick)
	aim_pad=AimPad.new();aim_pad.mouse_filter=Control.MOUSE_FILTER_IGNORE;play_root.add_child(aim_pad);aim_pad.hide()
	tools_panel=Panel.new();tools_panel.add_theme_stylebox_override("panel",style("13251df5"));play_root.add_child(tools_panel);tools_panel.hide()
	for row in [["refresh","补魔 / 冷却",func():command("practice_refresh")],["ball","拿回足球",func():command("practice_ball")],["course","切换障碍",func():game.cycle_course()],["bot","练习对手",func():game.toggle_bot()],["morph","放弃借用",func():command("morph_reset")],["help","操作说明",func():show_help()]]:
		play_button(row[0],row[1],row[2]);buttons[row[0]].reparent(tools_panel)
	for row in [["performance","性能面板",func():game.perf.toggle_mode()],["benchmark","60秒自测",func():game.perf.start_benchmark()],["perf_report","性能报告",func():game.perf.show_report()]]:
		play_button(row[0],row[1],row[2]);buttons[row[0]].reparent(tools_panel)
	buttons.perf_toggle.reparent(tools_panel)
	play_button("diagnostics","性能工具",func():set_tools_page(true));buttons.diagnostics.reparent(tools_panel)
	play_button("shout","呐喊",func():command("shout"));buttons.shout.reparent(tools_panel)
	play_button("emotes","表情",func():set_tools_page(false,true));buttons.emotes.reparent(tools_panel)
	play_button("apocalypse","末日事件",func():game.aftermath_controls.request_apocalypse());buttons.apocalypse.reparent(tools_panel)
	var hats=[]
	for id in game.hats.choices:hats.append(game.hats.catalog[id].name)
	pick_hat=picker(tools_panel,hats);pick_hat.hide()
	pick_hat.item_selected.connect(func(i):game.hats.select_hat(game.hats.choices[i]);game.close_menu())
	play_button("hats","帽子",func():tools_panel.hide();game.open_menu();pick_hat.select(game.hats.choices.find(game.hats.selected(game.sim.controlled)));open_picker(pick_hat));buttons.hats.reparent(tools_panel)
	for id in ["taunt","sadface"]:
		play_button(id,"嘲讽" if id=="taunt" else "悲伤",func():command(id));buttons[id].reparent(tools_panel)
	play_button("tools_back","返回工具",func():set_tools_page(false));buttons.tools_back.reparent(tools_panel)
	set_tools_page(false)

func toggle_tools():
	if tools_panel.visible:tools_panel.hide()
	else:set_tools_page(false);tools_panel.show()

func set_tools_page(diagnostics: bool,emotes=false):
	diagnostics_open=diagnostics;emotes_open=emotes
	var normal=["refresh","ball","course","bot","morph","help","diagnostics","shout","emotes"]
	normal.append_array(["hats","apocalypse"])
	if buttons.has("franchise"):normal.append("franchise")
	var debug_tools=["perf_toggle","performance","benchmark","perf_report","tools_back"]
	var emote_tools=["taunt","sadface","tools_back"]
	for id in normal+debug_tools+emote_tools:buttons[id].hide()
	var ids=debug_tools if diagnostics else (emote_tools if emotes else normal)
	tools_panel.size.y=ceilf(ids.size()/3.0)*94+18
	for id in ids:buttons[id].show()
	for i in range(ids.size()):rect(buttons[ids[i]],12+(i%3)*204,12+(i/3)*94,194,84)

func build_menu():
	menu=modal_panel()
	var title=text(menu,"弹跳足球",38);title.name="Title"
	var subtitle=text(menu,"联机游戏 · 单机",22);subtitle.name="Subtitle"
	var version=text(menu,"v"+str(ProjectSettings.get_setting("application/config/version","0.4.35")),20);version.name="Version";version.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	pick_language=picker(menu,Array(game.Language.LABELS));pick_language.select(game.Language.OPTIONS.find(game.Language.choice))
	pick_language.item_selected.connect(func(i):game.change_language(i))
	var names=[]
	for id in Characters.IDS:names.append(Characters.DATA[id].name+" · "+Characters.DATA[id].skill)
	pick_character=picker(menu,names);pick_character.select(game.character_select.selected)
	pick_character.item_selected.connect(func(i):game.character_select.select(i);game.character_select.item_selected.emit(i);update_selection())
	character_note=text(menu,"",23);character_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var fields=[]
	for f in game.sim.arena.fields:fields.append(f.name)
	pick_field=picker(menu,fields);pick_field.select(game.field_select.selected)
	pick_field.item_selected.connect(func(i):game.field_select.select(i);game.field_select.item_selected.emit(i);update_selection())
	field_note=text(menu,"",23);field_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	pick_rules=picker(menu,["先得 10 球","计时赛 · 10 分钟","上下半场 · 各 10 分钟"]);pick_rules.select(game.mode_select.selected)
	pick_rules.item_selected.connect(func(i):game.mode_select.select(i))
	pick_team=picker(menu,["1 对 1","2 对 2","3 对 3","4 对 4","5 对 5","6 对 6"]);pick_team.select(2)
	pick_team.item_selected.connect(func(i):chosen_team=i+1)
	pick_controls=picker(menu,["操作：点地移动","操作：左侧摇杆"]);pick_controls.select(1 if movement=="stick" else 0)
	pick_controls.item_selected.connect(func(i):set_movement("stick" if i==1 else "tap"))
	pick_quality=picker(menu,["画面：均衡 · 上限 30 帧","画面：性能优先 · 上限 60 帧"])
	pick_quality.select(1 if game.experience.quality=="fast" else 0)
	pick_quality.item_selected.connect(func(i):game.experience.quality="fast" if i==1 else "balanced";apply_quality();game.experience.save_settings())
	var online=make_button(menu,"联机游戏",func():game.network_menu.show_menu(),true);online.name="Network"
	var start=make_button(menu,"单机比赛",func():start_match());start.name="Start"
	var practice=make_button(menu,"自由练习",func():start_practice());practice.name="Practice"
	resume=make_button(menu,"继续当前场景",func():game.close_menu());resume.name="Resume"
	sound=make_button(menu,"声音：开",func():game.experience.sound_enabled=not game.experience.sound_enabled;game.experience.save_settings());sound.name="Sound"
	var help=make_button(menu,"操作说明",show_help);help.name="Help"
	var stats=make_button(menu,"比赛记录",func():game.open_results());stats.name="Stats"
	update_selection()

func build_report():
	report=modal_panel();report.hide()
	var title=text(report,"本场比赛",34);title.name="Title"
	report_text=RichTextLabel.new();report_text.add_theme_font_override("normal_font",game.font)
	report_text.add_theme_font_size_override("normal_font_size",25);report.add_child(report_text)
	var replay=make_button(report,"再来一场",func():start_match(),true);replay.name="Replay"
	var back=make_button(report,"返回菜单",func():game.open_menu());back.name="Back"

func build_help():
	help_panel=modal_panel();help_panel.hide()
	var title=text(help_panel,"手机操作",34);title.name="Title"
	var body=RichTextLabel.new();body.name="Body";body.add_theme_font_override("normal_font",game.font);body.add_theme_font_size_override("normal_font_size",27)
	body.text="左手移动：摇杆直接控制方向，顶住障碍时不会自动绕路，斜推才沿边移动；松开停止，冰面保留惯性。\n右手瞄准：按住传射或技能按钮，拖动调整方向；选点技能可用拖动距离调整远近。松手施放，拖到红色取消区松手可取消。轻点则向当前朝向快速释放。\n瞄准时左手仍可移动；已释放的蓄力技能保留原有准备时间。\n\n蓝色显示范围，金色显示方向或轨迹。球的轨迹显示未来2秒的简化方向与弧线，不计算碰撞和反弹；实际射球仍使用原有物理规则。自身技能按角色当前朝向生效。\n\n点击左侧竖排队友头像切换到该队友，金框是当前角色，小圆点表示持球。切换时清空旧角色的触控输入。\n冲刺：开启 / 关闭；按钮外圈蓝环是剩余蓝量，消耗时减少，回蓝时补满，冲刺中高亮。蓄力射门期间再点一次技能可取消蓄力。\n守门跳跃：本方门区内符合守门条件、不持真球时可用；冷却2秒。不可用时按钮置灰。\n\n菜单可切为点地移动；点地模式双指拖动 / 缩放镜头，点“跟随”恢复。\n“更多”中有练习补魔、拿球、障碍切换和变体重置。\n手机返回键先取消瞄准，再暂停；切到后台也会暂停。\n当前为单机体验版。"
	body.text+="\n\n射球：无球也能按住预瞄，接到球后松手射出；松手时无球则不射出，也不预存射球。\n性能默认隐藏，需要时打开“更多 → 性能工具”，可显示 / 隐藏或切换简洁 / 详细面板。\n60秒自测会重新开局，依次跑3对3、半分辨率、6对6；结束后可复制报告。\nFPS后是帧率上限，P95表示95%的帧不超过该耗时，慢帧计数为最近10秒。CPU是游戏处理耗时；GPU不支持时不能据此判断GPU空闲。"
	body.text+="\n\n表情：更多 → 表情，可用嘲讽或悲伤。选人40秒后解锁，两种表情分别冷却5秒；更多中的呐喊也在此时解锁。"
	body.text+="\n\n确认射门后先转向，球离脚后恢复摇杆移动；转身时松开摇杆则不再继续走。丢失球权会取消本次射门。"
	help_panel.add_child(body)
	var back=make_button(help_panel,"明白了，返回",func():help_panel.hide();if_help_return());back.name="Back"

func build_half():
	half_panel=modal_panel();half_panel.hide();half_title=text(half_panel,"中场休息",30)
	var names=[]
	for id in Characters.IDS:names.append(Characters.DATA[id].name)
	half_select=picker(half_panel,names)
	half_select.item_selected.connect(func(i):if game.sim.choose_halftime_character(Characters.IDS[i]):game.rebuild_actors())

func update_selection():
	var kit=Characters.DATA[Characters.IDS[pick_character.selected]]
	character_note.text=kit.description.replace("Q","技能").replace("R","第二技能").replace("W","传射").replace("S","停止").replace("F1","放弃借用").replace("E","冲刺").replace("右键","点地")
	var field=game.sim.arena.fields[pick_field.selected]
	field_note.text=("冰面有惯性，停止后仍会滑行。" if pick_field.selected>=2 else "草地球场 · 正常地面摩擦。")+"\n原图推荐 %d 对 %d"%[field.recommended_team,field.recommended_team]

func start_match():
	cancel_all();tools_panel.hide();help_panel.hide()
	game.start_game(chosen_team);game.zoom=0.78;game.update_camera();game.experience.follow_camera=true
	game.experience.save_settings()

func start_practice():
	cancel_all();tools_panel.hide();help_panel.hide()
	game.enter_practice();game.zoom=0.78;game.update_camera();game.experience.follow_camera=true
	game.experience.save_settings()

func set_movement(value: String):
	cancel_all();movement=value;game.experience.mobile_mode=value;game.experience.save_settings();layout()

func apply_quality():
	Engine.max_fps=60 if game.experience.quality=="fast" else 30
	get_viewport().scaling_3d_scale=0.70 if game.experience.quality=="fast" else 0.85
	for child in game.get_children():
		if child is DirectionalLight3D:child.shadow_enabled=false

func command(kind: String):
	if is_instance_valid(game.aftermath_controls) and game.aftermath_controls.active():
		game.aftermath_controls.army().command(kind);return
	game.sim.submit_command(kind,game.sim.controlled)

func update_portraits():
	var allies=[];var key=""
	for i in range(game.sim.players.size()):
		var p=game.sim.players[i]
		if p.team==game.sim.players[game.sim.controlled].team:
			allies.append(i);key+=str(i)+p.character
	if key!=portrait_key:
		portrait_key=key;portrait_players=allies;selected_portrait=-1
		for slot in range(6):
			var b=buttons["ally_"+str(slot)];b.visible=slot<allies.size()
			if b.visible:b.get_node("Portrait").texture=portrait_textures[game.sim.players[allies[slot]].character]
	for slot in range(portrait_players.size()):
		var index=portrait_players[slot];var b=buttons["ally_"+str(slot)]
		b.get_node("Number").text=("● " if game.sim.has_ball(index) else "")+str(game.sim.players[index].number)+(" · 我" if index==game.sim.controlled else "")
		b.disabled=not game.sim.match_enabled or game.sim.networked
	if selected_portrait!=game.sim.controlled:
		selected_portrait=game.sim.controlled
		for slot in range(portrait_players.size()):
			var selected=portrait_players[slot]==selected_portrait
			var border=style("305a48" if selected else "182d28ed",8)
			border.border_color=Color("ffdb75") if selected else Color("607d69");border.set_border_width_all(3 if selected else 2)
			buttons["ally_"+str(slot)].add_theme_stylebox_override("normal",border)

func select_portrait(slot: int):
	if is_instance_valid(game.aftermath_controls) and game.aftermath_controls.active():game.aftermath_controls.portrait(slot);return
	if slot<0 or slot>=portrait_players.size() or not game.sim.match_enabled:return
	var index=portrait_players[slot]
	if index==game.sim.controlled:return
	cancel_all()
	if game.sim.select_player(index):game.experience.follow_camera=true;update_portraits()

func begin_aim(index: int,id: String,pos: Vector2):
	if aim_id!=-1:return
	var sim=game.sim;var p=sim.players[sim.controlled];var kit=Characters.kit(p)
	# The old Stop button is hidden on mobile; tapping the charging skill cancels it.
	if id=="ability" and p.ability_kind=="powershot" and p.ability_delay>0:command("stop");return
	var action="kick" if id=="kick" else ("ability_secondary" if id=="secondary" else "ability")
	if id!="kick":
		if not Characters.q_available(p,id=="secondary"):return
		if kit.kind in ["powershot","possess","curve","trickster"] and sim.holder!=sim.controlled:
			sim.notice="先拿到足球，再使用这个技能。";return
		if kit.kind=="angel" and not sim.has_ball(sim.controlled):sim.notice="先拿到足球，再使用这个技能。";return
	game.aim=action;aim_id=index;aim_player=sim.controlled;aim_character=p.character+p.get("morph_kit","")
	# Drag direction is finger travel from touch-down, not distance from the
	# button centre. Otherwise an off-centre tap changes direction on release.
	aim_origin=pos;aim_axis=Vector2.ZERO;aim_cancelled=false
	touches[index].role="aim"
	aim_pad.position=aim_origin-root.position-Vector2(100,100);aim_pad.size=Vector2(200,200);aim_pad.show()
	buttons.cancel.show();update_aim_target();game.experience.overlay.preview_key="";game.experience.overlay.refresh(0)

func update_aim_drag(pos: Vector2):
	if aim_id==-1:return
	aim_axis=(pos-aim_origin)/AIM_RADIUS
	aim_cancelled=buttons.cancel.get_global_rect().grow(16).has_point(pos) or not Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size).has_point(pos)
	update_aim_target()

func update_aim_target():
	if aim_id==-1 or aim_player!=game.sim.controlled:return
	var p=game.sim.players[aim_player];var info=Preview.spec(p,game.aim)
	var direction=Vector2.from_angle(p.body);var strength=0.65
	if info.kind=="pillar":strength=0.0
	var finger_distance=aim_axis.length()
	if finger_distance>AIM_DEAD_ZONE:
		var center=get_viewport().get_visible_rect().size/2
		# Direction comes from the full finger displacement, never the clamped
		# thumb. Project a unit ray near screen centre so very long upward drags
		# cannot cross the perspective camera's horizon and invert the aim.
		direction=(game.ground_point(center+aim_axis.normalized()*100)-game.ground_point(center)).normalized()
		strength=minf(finger_distance,1.0)
		if info.kind=="pillar":strength=(strength-AIM_DEAD_ZONE)/(1.0-AIM_DEAD_ZONE)
	var overlay=game.experience.overlay
	overlay.target_world=Preview.target(p,info,direction,strength)
	overlay.pointer=overlay.project(Preview.world(overlay.target_world));overlay.pointer_valid=true;overlay.cancelled=aim_cancelled
	aim_pad.axis=aim_axis.limit_length(1);aim_pad.cancelled=aim_cancelled;aim_pad.queue_redraw()

func cancel_aim():
	game.aim="";game.experience.overlay.pointer_valid=false
	game.experience.overlay.preview.clear();game.experience.overlay.preview_key=""
	aim_id=-1;aim_player=-1;aim_axis=Vector2.ZERO;aim_cancelled=false
	if is_instance_valid(aim_pad):aim_pad.hide()

func cancel_all():
	if joystick_id!=-1:command("move_release")
	cancel_aim()
	touches.clear();world_id=-1;joystick_id=-1;joystick_axis=Vector2.ZERO
	for b in buttons.values():b.modulate=Color.WHITE
	if is_instance_valid(joystick):joystick.axis=Vector2.ZERO;joystick.queue_redraw()

func show_help():
	help_return="menu" if game.menu_root.visible else "play"
	game.open_menu();help_panel.show();cancel_all()

func if_help_return():
	if help_return=="play":game.close_menu()

func back():
	if picker_overlay.visible:close_picker()
	elif is_instance_valid(game.franchise) and game.franchise.panel.visible:game.franchise.close()
	elif is_instance_valid(game.perf) and game.perf.modal.visible:game.perf.modal.hide();game.open_menu()
	elif help_panel.visible:help_panel.hide();if_help_return()
	elif game.results_root.visible:game.open_menu()
	elif game.menu_root.visible:game.close_menu()
	elif game.aim!="":cancel_aim()
	elif tools_panel.visible:
		if diagnostics_open or emotes_open:set_tools_page(false)
		else:tools_panel.hide()
	else:cancel_all();game.open_menu()

func safe_rect() -> Rect2:
	var view=get_viewport().get_visible_rect().size
	if not OS.has_feature("android"):return Rect2(Vector2.ZERO,view)
	var screen=Vector2(DisplayServer.window_get_size())
	var safe=DisplayServer.get_display_safe_area()
	if screen.x<=0 or screen.y<=0:return Rect2(Vector2.ZERO,view)
	var factor=view/screen
	return Rect2(Vector2(safe.position)*factor,Vector2(safe.size)*factor).intersection(Rect2(Vector2.ZERO,view))

func layout():
	if aim_id!=-1:cancel_all()
	var safe=safe_rect();var origin=safe.position;var s=safe.size
	root.position=origin;root.size=s;play_root.size=s;last_size=s
	var w=s.x;var h=s.y
	rect(score,w/2-260,12,520,48);rect(clock,w/2-310,64,620,36)
	rect(player_label,24,18,320,42)
	rect(status,w/2-240,112,580,74);rect(phase,w/2-260,h*0.35,520,90)
	rect(aim_note,w/2-370,h-54,740,44)
	rect(buttons.menu,w-132,16,108,80);rect(buttons.tools,w-252,16,108,80)
	rect(buttons.follow,w-372,16,108,80)
	for slot in range(6):rect(buttons["ally_"+str(slot)],24,98+slot*70,68,68)
	rect(buttons.kick,w-198,h-200,152,152)
	rect(buttons.ability,w-338,h-302,124,124)
	rect(buttons.secondary,w-192,h-352,104,104)
	rect(buttons.sprint,w-458,h-196,104,104)
	rect(mana,0,0,104,104);rect(mana_note,0,72,104,24);mana_note.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	rect(buttons.hold,w-324,h-156,96,96)
	rect(buttons.pass,w-462,h-314,96,96)
	rect(buttons.stop,w-564,h-132,84,84)
	rect(buttons.cancel,w-180,h-500,116,116)
	# Raise the entire thumb cluster, keeping both the aiming pad and buttons
	# comfortably inside the screen instead of hugging its bottom/right edges.
	for id in ["kick","ability","secondary","sprint","pass","cancel"]:buttons[id].position+=Vector2(-64,-112)
	rect(buttons.jump,w-392,h-264,110,110)
	rect(joystick,28,h-268,220,220);joystick_center=joystick.position+joystick.size/2
	joystick.visible=movement=="stick"
	rect(tools_panel,w-650,110,626,300)
	set_tools_page(diagnostics_open,emotes_open)
	var pw=minf(1280,w-60);var ph=minf(740,h-40)
	rect(picker_overlay,0,0,w,h)
	rect(picker_panel,(w-pw)/2,(h-ph)/2,pw,ph)
	rect(picker_panel.get_node("Title"),32,24,pw-220,50)
	rect(picker_panel.get_node("Close"),pw-160,16,128,64)
	rect(picker_scroll,32,102,pw-64,ph-130)
	for p in [menu,report,help_panel]:rect(p,(w-pw)/2,(h-ph)/2,pw,ph)
	var col=(pw-96)/2;var x2=64+col
	rect(menu.get_node("Title"),32,18,col,52);rect(menu.get_node("Subtitle"),32,73,col,34)
	rect(menu.get_node("Version"),32+col-150,38,150,32)
	rect(pick_language,x2,22,col,64)
	rect(pick_character,32,122,col,72);rect(character_note,32,206,col,106)
	rect(pick_field,32,326,col,72);rect(field_note,32,412,col,86)
	for i in range(4):rect([pick_rules,pick_team,pick_controls,pick_quality][i],x2,122+i*96,col,72)
	var action_width=(pw-96)/3
	for i in range(3):rect(menu.get_node(["Network","Start","Practice"][i]),32+i*(action_width+16),ph-208,action_width,88)
	var foot=(pw-88)/4
	for i in range(4):rect([resume,sound,menu.get_node("Help"),menu.get_node("Stats")][i],32+i*(foot+8),ph-102,foot,76)
	for p in [report,help_panel]:rect(p.get_node("Title"),32,20,pw-64,52)
	rect(report_text,32,94,pw-64,ph-220)
	rect(report.get_node("Replay"),32,ph-102,col,76);rect(report.get_node("Back"),x2,ph-102,col,76)
	rect(help_panel.get_node("Body"),32,90,pw-64,ph-202);rect(help_panel.get_node("Back"),32,ph-100,pw-64,76)
	rect(half_panel,w/2-380,h/2-130,760,260);rect(half_title,30,25,700,60);rect(half_select,30,120,700,86)

static func skill_label(value: String) -> String:
	value=value.strip_edges()
	if not TranslationServer.get_locale().begins_with("zh"):
		if value.contains("蓄力中"):return String(TranslationServer.translate("蓄力中\n再点取消"))
		var translated=String(TranslationServer.translate(value))
		# Latin/Cyrillic captions wrap at word boundaries, not Chinese character counts.
		if not translated.contains("\n") and translated.length()>=10 and translated.contains(" "):
			var split=translated.find(" ",maxi(0,translated.length()/2-4))
			if split!=-1:translated=translated.substr(0,split)+"\n"+translated.substr(split+1)
		return translated
	if value.contains("蓄力中"):return "蓄力中\n再点取消"
	if value.begins_with("回溯 ") or value.begins_with("支配中 "):
		var parts=value.split(" ",false)
		return parts[0]+"\n"+parts[1]+"秒"
	if value.ends_with(" s") and value.trim_suffix(" s").is_valid_float():return value.trim_suffix(" s")+"秒"
	return value.insert(4,"\n") if value.length()>5 else value

func fit_action_labels():
	if caption_locale.begins_with("zh"):return
	for button in buttons.values():
		if not button.is_visible_in_tree():continue
		var key=[button.text,button.size,caption_locale]
		if button.get_meta("caption_fit",[])==key:continue
		button.set_meta("caption_fit",key)
		var base_size=int(button.get_meta("base_font_size",button.get_theme_font_size("font_size")))
		var font_size=mini(base_size,19 if base_size<=21 else 21)
		var lines=String(button.tr(button.text)).split("\n")
		while font_size>14:
			var width=0.0
			for line in lines:width=maxf(width,game.font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)
			if width<=button.size.x-8 and game.font.get_height(font_size)*lines.size()<=button.size.y-8:break
			font_size-=1
		button.add_theme_font_size_override("font_size",font_size)

func frame(_delta: float):
	if is_instance_valid(game.network_menu) and game.network_menu.screen.visible:
		play_root.hide();menu.hide();report.hide();half_panel.hide();return
	game.get_node("HUD").hide()
	if caption_locale!=TranslationServer.get_locale():
		caption_locale=TranslationServer.get_locale()
		for button in buttons.values():
			if not button.has_meta("base_font_size"):button.set_meta("base_font_size",button.get_theme_font_size("font_size"))
			# Long translations must not expand touch hitboxes into adjacent buttons.
			button.clip_text=not caption_locale.begins_with("zh")
			button.set_meta("caption_fit",[])
			var base_size=int(button.get_meta("base_font_size"))
			button.add_theme_font_size_override("font_size",mini(base_size,19 if base_size<=21 else 21) if not caption_locale.begins_with("zh") else base_size)
		layout()
	# The hat selector is opened from More as a standalone modal; its backing
	# picker intentionally has no visible field after the tools panel closes.
	if picker_overlay.visible and is_instance_valid(active_picker) and active_picker!=pick_hat and not active_picker.is_visible_in_tree():close_picker()
	var sim=game.sim;var p=sim.players[sim.controlled];var kit=Characters.kit(p)
	var modal=game.menu_root.visible or game.results_root.visible or sim.match_state=="halftime" or help_panel.visible
	if modal and not was_modal:cancel_all()
	was_modal=modal;play_root.visible=not modal
	menu.visible=game.menu_root.visible and not help_panel.visible
	report.visible=game.results_root.visible and not help_panel.visible
	half_panel.visible=sim.match_state=="halftime" and not menu.visible and not report.visible and not help_panel.visible
	if menu.visible:
		resume.disabled=sim.match_state=="ended";sound.text="声音："+("开" if game.experience.sound_enabled else "关")
		menu.get_node("Stats").disabled=not sim.match_enabled
	if report.visible:
		report.get_node("Title").text=game.results_title.text
		report_text.text=game.results_teams[0].text+"\n\n"+game.results_teams[1].text+"\n\n进球记录\n"+game.results_history.text
	if half_panel.visible:half_title.text=game.half_label.text
	half_select.disabled=sim.networked
	if modal:fit_action_labels();return
	if is_instance_valid(game.aftermath_controls) and game.aftermath_controls.mobile_frame(_delta):fit_action_labels();return
	update_portraits()
	if aim_id!=-1:
		if aim_player!=sim.controlled or aim_character!=p.character+p.get("morph_kit","") or game.aim=="":cancel_aim()
		else:update_aim_target()
	game.experience.overlay.refresh(_delta)
	if joystick_id!=-1:
		joystick_clock-=_delta
		if (joystick_clock<=0 or not joystick_sent_axis.is_equal_approx(joystick_axis)) and joystick_axis.length()>0.12 and not p.cast_pending and p.ability_delay<=0:
			joystick_clock=0.12
			joystick_sent_axis=joystick_axis
			var center=get_viewport().get_visible_rect().size/2
			var direction=(game.ground_point(center+joystick_axis*100)-game.ground_point(center)).normalized()
			sim.submit_command("move_direction",sim.controlled,direction)
	score.text="%s  %d : %d  %s"%[sim.team_name(0),sim.score[0],sim.score[1],sim.team_name(1)];clock.text=game.clock_label.text
	player_label.text=Characters.DATA[p.character].name+(" · 持球" if sim.has_ball(sim.controlled) else "")
	mana.value=p.mana;mana.active=p.sprint;mana_note.text="%d%%"%roundi(p.mana);phase.text=game.phase_label.text
	status.text=("目标被挡，将前往可到达的位置。" if p.route_status in ["partial","blocked"] else "")
	if status.text=="":status.text=sim.notice.replace("右键","点地").replace("左键","轻点").replace("Esc","暂停").replace("W ","传射 ").replace("Q ","技能 ").replace("E ","冲刺 ").replace("按 S","点停止")
	# Controls already have labels; avoid repeating desktop key instructions at kickoff.
	if sim.notice.begins_with("开球！") and status.text.begins_with("开球！"):status.text="开球！"
	if status.text!=last_notice:last_notice=status.text;notice_remaining=3.0
	else:notice_remaining=maxf(0,notice_remaining-_delta)
	status.visible=notice_remaining>0 and status.text!=""
	buttons.ability.text=skill_label(game.q_button.text.trim_prefix("Q "));buttons.ability.disabled=kit.kind=="none"
	buttons.secondary.visible=kit.has("secondary");buttons.secondary.text=skill_label(game.r_button.text.trim_prefix("R "))
	buttons.sprint.text=game.e_button.text.trim_prefix("E ").strip_edges()
	buttons.hold.text="起跳\n%.1f"%p.keeper_cooldown if p.keeper_cooldown>0 else ("守门\n起跳" if sim.KeeperRules.eligible(sim,sim.controlled) else "站定")
	var can_jump=sim.KeeperRules.eligible(sim,sim.controlled)
	buttons.jump.disabled=not can_jump
	var jump_hint="" if can_jump else "守门时可用"
	if sim.holder==sim.controlled:jump_hint="先传出球"
	if p.keeper_cooldown>0:jump_hint="%.1f 秒"%p.keeper_cooldown
	buttons.jump.text="守门跳跃"+("\n"+jump_hint if jump_hint!="" else "")
	buttons.kick.disabled=false # Possession is checked on release, not on press.
	buttons.kick.text="转身\n射门" if not p.shot_order.is_empty() else "传 / 射"
	buttons.perf_toggle.text="隐藏性能" if game.perf.mode>0 else "显示性能"
	buttons.performance.text="只看 FPS" if game.perf.mode==2 else "详细指标"
	buttons.switch.disabled=sim.networked or not sim.match_enabled or sim.team_size<=1;buttons.pass.disabled=not sim.match_enabled
	buttons.follow.text="跟随中" if game.experience.follow_camera else "跟随"
	buttons.cancel.visible=game.aim!=""
	aim_note.text=(("松手取消" if aim_cancelled else game.experience.overlay.preview.get("note","拖动瞄准 · 松手施放")) if game.aim!="" else ("点地移动 · 按住技能瞄准" if movement=="tap" else "左手移动 · 右手拖动瞄准 · 点击头像换人"))
	aim_note.visible=game.aim!=""
	buttons.cancel.modulate=Color("ff8585") if aim_cancelled else Color.WHITE
	for id in ["refresh","ball","course","bot"]:buttons[id].disabled=sim.match_enabled
	buttons.morph.disabled=p.character!="h029" or p.morph_kit==""
	var shout_left=sim.shout.remaining(sim,sim.controlled)
	buttons.shout.disabled=not sim.shout.available(sim,sim.controlled)
	buttons.shout.text="呐喊" if shout_left<=0 else ("呐喊 · %.0f秒"%ceilf(shout_left))
	for id in ["taunt","sadface"]:
		var remaining=sim.Emotes.remaining(sim,sim.controlled,id)
		buttons[id].disabled=not sim.Emotes.available(sim,sim.controlled,id)
		buttons[id].text=("嘲讽" if id=="taunt" else "悲伤")+(" · %.0f秒"%ceilf(remaining) if remaining>0 else "")
	buttons.bot.text="对手：追球" if sim.bot_enabled else "对手：静止"
	fit_action_labels()
	joystick.axis=joystick_axis;joystick.queue_redraw()

func interactive() -> bool:
	if is_instance_valid(game.network_menu) and game.network_menu.screen.visible:return false
	return not game.paused and game.sim.match_state!="halftime" and not help_panel.visible and not picker_overlay.visible

func touch_press(index: int,pos: Vector2):
	if not interactive():return
	if touches.has(index):return
	if is_instance_valid(game.perf) and game.perf.close_button.is_visible_in_tree() and game.perf.close_button.get_global_rect().has_point(pos):
		touches[index]={"role":"perf_close","pos":pos};return
	for id in buttons:
		var b=buttons[id]
		if tools_panel.visible and b.get_parent()!=tools_panel and id!="tools":continue
		if b.is_visible_in_tree() and b.get_global_rect().has_point(pos):
			touches[index]={"role":"ui","pos":pos,"button":id}
			if not b.disabled:
				b.modulate=Color("b6e2ba")
				if is_instance_valid(game.aftermath_controls) and game.aftermath_controls.active() and id=="kick":game.aftermath_controls.attack()
				elif id in ["kick","ability","secondary"]:begin_aim(index,id,pos)
				elif id.begins_with("ally_"):pass # A portrait is a tap, not a drag across it.
				else:actions[id].call()
			return
	if tools_panel.visible:
		touches[index]={"role":"ui","pos":pos}
		if not tools_panel.get_global_rect().has_point(pos):tools_panel.hide()
		return
	var local=pos-root.position
	if movement=="stick" and joystick_id==-1 and local.distance_to(joystick_center)<130:
		joystick_id=index;joystick_clock=0;touches[index]={"role":"stick","pos":pos};update_stick(local);return
	if aim_id!=-1:touches[index]={"role":"ignored","pos":pos};return
	if world_id==-1:
		for touch in touches.values():
			if touch.role=="gesture":touches[index]={"role":"ignored","pos":pos};return
	if world_id!=-1:
		if movement=="tap" and game.aim=="" and touches.has(world_id):
			touches[world_id].role="gesture";touches[index]={"role":"gesture","pos":pos}
		else:touches[index]={"role":"ignored","pos":pos}
		return
	world_id=index;touches[index]={"role":"world","pos":pos,"start":pos,"aim":game.aim}
	if game.aim!="":game.experience.overlay.pointer=pos;game.experience.overlay.target_world=game.ground_point(pos);game.experience.overlay.pointer_valid=true

func update_stick(local: Vector2):
	joystick_axis=((local-joystick_center)/75.0).limit_length(1.0)
	if joystick_axis.length()<0.12:joystick_axis=Vector2.ZERO;command("move_release")

func touch_drag(index: int,pos: Vector2):
	if not touches.has(index):return
	var touch=touches[index]
	if touch.role=="stick":update_stick(pos-root.position)
	elif touch.role=="aim" and index==aim_id:update_aim_drag(pos)
	elif touch.role=="world" and game.aim!="":game.experience.overlay.pointer=pos;game.experience.overlay.target_world=game.ground_point(pos);game.experience.overlay.pointer_valid=true
	elif touch.role=="gesture":
		for other in touches:
			if other==index or touches[other].role!="gesture":continue
			var old_center=(touch.pos+touches[other].pos)/2;var new_center=(pos+touches[other].pos)/2
			var old_distance=touch.pos.distance_to(touches[other].pos);var distance=pos.distance_to(touches[other].pos)
			var pan=game.ground_point(old_center)-game.ground_point(new_center)
			game.focus+=Vector3(pan.x/100,0,-pan.y/100)
			if old_distance>20 and distance>20:game.zoom=clampf(game.zoom*old_distance/distance,0.5,1.8)
			game.experience.follow_camera=false;game.update_camera();break
	touch.pos=pos

func touch_release(index: int,pos: Vector2,canceled=false):
	if not touches.has(index):return
	var touch=touches[index];touches.erase(index)
	if touch.has("button"):buttons[touch.button].modulate=Color.WHITE
	if touch.role=="aim":
		if index==aim_id:
			update_aim_drag(pos)
			if not canceled and interactive() and not aim_cancelled and aim_player==game.sim.controlled and game.aim!="":
				release_aim(game.aim,aim_player,game.experience.overlay.target_world)
			cancel_aim()
		return
	if index==joystick_id:joystick_id=-1;joystick_axis=Vector2.ZERO;command("move_release")
	if index==world_id:world_id=-1
	if canceled or not interactive():return
	if not Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size).has_point(pos):return
	if touch.role=="perf_close":
		if game.perf.close_button.is_visible_in_tree() and game.perf.close_button.get_global_rect().has_point(pos):game.perf.set_mode(0)
		return
	if touch.role=="ui" and touch.get("button","").begins_with("ally_"):
		if buttons[touch.button].get_global_rect().has_point(pos):actions[touch.button].call()
		return
	if touch.role=="world":
		if touch.aim!="" and game.aim==touch.aim:
			if buttons.cancel.get_global_rect().has_point(pos):cancel_aim();return
			release_aim(game.aim,game.sim.controlled,game.ground_point(pos));cancel_aim()
		elif touch.aim=="" and game.aim=="" and pos.distance_to(touch.start)<24:
			if is_instance_valid(game.aftermath_controls) and game.aftermath_controls.active():game.aftermath_controls.world_click(pos);return
			if is_instance_valid(game.biz_tree) and game.biz_tree.try_select(pos):return
			game.sim.submit_command("move",game.sim.controlled,game.ground_point(pos));game.marker.visible=true

func release_aim(action: String,index: int,target: Vector2):
	# Do not queue an empty-handed shot that could fire after a later catch.
	# Simulation checks possession again when this ordered command executes.
	if action=="kick" and not game.sim.has_ball(index):
		game.sim.notice="未持球，未射出。";return
	game.sim.submit_command(action,index,target)

func _input(event):
	if is_instance_valid(game.network_menu) and game.network_menu.screen.visible and not picker_overlay.visible:return
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		back();get_viewport().set_input_as_handled();return
	if picker_overlay.visible:
		if picker_input(event):get_viewport().set_input_as_handled()
		return
	if not interactive():return
	if event is InputEventScreenTouch:
		if event.pressed:touch_press(event.index,event.position)
		else:touch_release(event.index,event.position,event.canceled)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		touch_drag(event.index,event.position);get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.device!=-1:
			if event.button_index==MOUSE_BUTTON_LEFT:
				if event.pressed:touch_press(1000,event.position)
				else:touch_release(1000,event.position)
			elif event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:cancel_aim()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if event.device!=-1:touch_drag(1000,event.position)
		get_viewport().set_input_as_handled()
