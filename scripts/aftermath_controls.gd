extends CanvasLayer
## Input/HUD for the controllable native skeletons after the football match.
var game
var was_active=false
var saved_visibility={}
var page=0
var portrait_ids=[]
var portraits={}
var desktop: Panel
var desktop_status: Label
var entry_button: Button
var confirm_until=0

func setup(owner_game):
	game=owner_game;layer=5
	desktop=Panel.new();add_child(desktop);desktop.position=Vector2(24,100);desktop.size=Vector2(350,160);desktop.hide()
	desktop_status=Label.new();desktop.add_child(desktop_status);desktop_status.position=Vector2(16,12)
	desktop_status.add_theme_font_override("font",game.font);desktop_status.add_theme_font_size_override("font_size",19)
	for i in range(3):
		var button=Button.new();desktop.add_child(button);button.text=["攻击附近","下一个","暂停"][i]
		button.position=Vector2(12+i*110,110);button.size=Vector2(104,38);button.add_theme_font_override("font",game.font)
		button.pressed.connect(attack if i==0 else (cycle if i==1 else game.open_menu))
	entry_button=game.button("末日事件",Rect2(0,0,266,34),request_apocalypse)
	entry_button.reparent(game.desktop_tools);entry_button.position=Vector2(12,142)
	entry_button.tooltip_text="开局 40 秒后可触发。结束当前足球比赛，进入末日与骷髅战斗。"

func request_apocalypse():
	if game.sim.networked:return
	if game.paused or game.sim.clock_now()<game.sim.field_started+40:return
	if game.sim.apocalypse!=null and game.sim.apocalypse.active:return
	if Time.get_ticks_msec()>confirm_until:
		confirm_until=Time.get_ticks_msec()+5000;update_entry();return
	confirm_until=0
	if is_instance_valid(game.touch_controls):game.touch_controls.cancel_all();game.touch_controls.tools_panel.hide()
	game.aim="";game.desktop_tools.hide()
	game.sim.prepare_apocalypse().vote(0)
	update_entry()

func update_entry():
	var running=game.sim.apocalypse!=null and game.sim.apocalypse.active
	var left=maxi(0,ceili(game.sim.field_started+40-game.sim.clock_now()))
	var caption="末日进行中" if running else ("末日事件 · %d秒"%left if left>0 else ("确认结束比赛\n触发末日" if confirm_until>Time.get_ticks_msec() else "末日事件"))
	for button in [entry_button,game.touch_controls.buttons.get("apocalypse") if is_instance_valid(game.touch_controls) else null]:
		if button==null:continue
		button.text=caption.replace("\n"," · ") if button==entry_button else caption
		button.disabled=game.sim.networked or running or left>0

func army():return null if game.sim.apocalypse==null else game.sim.apocalypse.aftermath
func active() -> bool:return army()!=null and army().active()
func attack():
	if active():army().attack_nearest()
func cycle():
	if active():army().cycle()

func pick(screen: Vector2) -> int:
	var best=-1;var distance=INF
	for entry in game.apocalypse_visuals.skeletons:
		var u=entry.source
		if u.hp<=0 or not entry.model.is_visible_in_tree():continue
		var point=entry.model.global_position+Vector3.UP*.65
		if game.camera.is_position_behind(point):continue
		var d=game.camera.unproject_position(point).distance_to(screen)
		if d<45 and d<distance:distance=d;best=u.id
	return best

func world_click(screen: Vector2,select_friendly=true):
	if not active() or game.paused:return
	var id=pick(screen)
	if id>=0:
		if army().units[id].owner==0 and select_friendly:army().choose(id);return
		if army().units[id].team==1:army().command("attack",Vector2.ZERO,id);return
	army().command("move",game.ground_point(screen))

func input(event) -> bool:
	if not active():return false
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:return false
		if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:world_click(event.position,event.button_index==MOUSE_BUTTON_LEFT)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB:cycle()
			KEY_A,KEY_W:attack()
			KEY_S:army().command("stop")
			KEY_ESCAPE,KEY_P:game.open_menu()
			KEY_F5:game.enter_practice()
			KEY_SPACE:
				if army().local_owner(army().selected):
					var p=army().units[army().selected].pos;game.focus=Vector3(p.x,0,-p.y)/100;game.update_camera()
	return true

func counts() -> Array:
	var result=[0,0]
	for u in army().units:
		if u.hp>0:result[u.team]+=1
	return result

func selected_text() -> String:
	if not army().local_owner(army().selected):return "己方骷髅已全部倒下"
	var u=army().units[army().selected];var data=army().spec(u)
	return "%s · %d / %d"%[data.name,ceili(u.hp),int(data.hp)]

func portrait(slot: int):
	if not active():return
	if slot==5:page+=1;return
	if slot<portrait_ids.size():army().choose(portrait_ids[slot])

func restore_mobile():
	if not is_instance_valid(game.touch_controls):return
	var ui=game.touch_controls
	ui.cancel_all()
	for id in saved_visibility:
		var button=ui.buttons[id];var saved=saved_visibility[id]
		button.visible=saved.visible;button.disabled=saved.disabled;button.text=saved.text;button.modulate=saved.modulate
		if saved.has("portrait"):
			button.get_node("Portrait").visible=saved.portrait
	saved_visibility.clear();game.touch_controls.portrait_key="";game.touch_controls.selected_portrait=-1

func mobile_frame(delta: float) -> bool:
	if not active():
		if not saved_visibility.is_empty():restore_mobile()
		return false
	var ui=game.touch_controls
	if saved_visibility.is_empty():
		for id in ui.buttons:
			var button=ui.buttons[id]
			saved_visibility[id]={"visible":button.visible,"disabled":button.disabled,"text":button.text,"modulate":button.modulate}
			if button.has_node("Portrait"):saved_visibility[id].portrait=button.get_node("Portrait").visible
		ui.cancel_all();page=0
	for id in ["ability","secondary","sprint","jump","pass","hold","stop","switch","cancel"]:ui.buttons[id].hide()
	ui.buttons.kick.show();ui.buttons.kick.text="攻击\n附近敌人";ui.buttons.kick.disabled=not army().local_owner(army().selected)
	for id in ["refresh","ball","course","bot","morph","shout","taunt","sadface","hats"]:ui.buttons[id].disabled=true
	var count=counts();ui.score.text="%s %d : %d %s"%[game.sim.team_name(0),count[0],count[1],game.sim.team_name(1)];ui.clock.text="末日之后"
	ui.player_label.text=selected_text();ui.status.hide();ui.phase.text="";ui.aim_note.hide()
	ui.buttons.follow.text="跟随中" if game.experience.follow_camera else "跟随"
	ui.buttons.perf_toggle.text="隐藏性能" if game.perf.mode>0 else "显示性能"
	ui.buttons.performance.text="只看 FPS" if game.perf.mode==2 else "详细指标"
	var owned=[]
	for u in army().units:
		if army().local_owner(u.id):owned.append(u.id)
	var pages=maxi(1,ceili(owned.size()/5.0));page=posmod(page,pages);portrait_ids=owned.slice(page*5,page*5+5)
	for slot in range(6):
		var button=ui.buttons["ally_"+str(slot)];var icon=button.get_node("Portrait");var number=button.get_node("Number")
		button.visible=slot<portrait_ids.size() or (slot==5 and pages>1);button.disabled=false
		if slot==5:
			icon.hide();number.text="";button.text="下一页";continue
		button.text=""
		if slot>=portrait_ids.size():continue
		var u=army().units[portrait_ids[slot]];var data=army().spec(u)
		if not portraits.has(u.rawcode):portraits[u.rawcode]=load(data.portrait)
		icon.show();icon.texture=portraits[u.rawcode];number.text=str(page*5+slot+1)
		button.modulate=Color("b6e2ba") if u.id==army().selected else Color.WHITE
	if ui.joystick_id!=-1 and ui.joystick_axis.length()>.12:
		var center=game.get_viewport().get_visible_rect().size/2
		var direction=(game.ground_point(center+ui.joystick_axis*100)-game.ground_point(center)).normalized()
		army().command("move_direction",direction*ui.joystick_axis.length())
	ui.joystick.axis=ui.joystick_axis;ui.joystick.queue_redraw();game.marker.hide()
	return true

func frame():
	var tools_visible=game.touch_controls.tools_panel.visible if game.mobile_enabled else game.desktop_tools.visible
	if not tools_visible:confirm_until=0
	update_entry()
	if not active() and not saved_visibility.is_empty():restore_mobile()
	if active() and not game.mobile_enabled:
		game.get_node("HUD").visible=game.paused;desktop.visible=not game.paused
		var count=counts();desktop_status.text="末日之后 · %s %d / %s %d\n%s\n左键选人 · 右键移动 / 攻击"%[game.sim.team_name(0),count[0],game.sim.team_name(1),count[1],selected_text()]
	else:
		desktop.hide()
		if was_active and not game.mobile_enabled:game.get_node("HUD").show()
	was_active=active()
