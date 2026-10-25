extends CanvasLayer
## Presentation only; cloud protocol and match rules are unchanged.
const Pitch=preload("res://scripts/net_pitch_art.gd")
const INK=Color("edf3ee")
const MUTED=Color("99b0a7")
const GOLD=Color("e4c27a")
const GREEN=Color("73d6ad")
var game
var net
var screen: Control
var panel: PanelContainer
var body: VBoxContainer
var info: Label
var latency: Label
var latency_key=""
var title: Label
var back_button: Button
var content: VBoxContainer
var scroll: ScrollContainer
var footer: HBoxContainer
var launch: Button
var badge: Button
var view_key=""
var ip: LineEdit
var username: LineEdit
var password: LineEdit
var nickname: LineEdit
var hero
var hat
var seat
var register_mode=false
var rules_open=false
var account_open=false
var room_filter="all"
var portraits={}
var last_locale=""
var last_room_id=""
var auth_draft={"username":"","password":"","nickname":""}

func t(zh: String,en: String,ru: String) -> String:
	var locale=TranslationServer.get_locale().substr(0,2)
	return zh if locale=="zh" else (ru if locale=="ru" else en)

func translated(value: String) -> String:return TranslationServer.translate(value)

func box(color: Color,border=Color("30483e"),radius=16,pad=18) -> StyleBoxFlat:
	var s=StyleBoxFlat.new();s.bg_color=color;s.border_color=border;s.set_border_width_all(1);s.set_corner_radius_all(radius)
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:s.set_content_margin(edge,pad)
	return s

func setup(owner_game,client):
	game=owner_game;net=client;layer=30
	var theme=Theme.new();theme.default_font=game.font;theme.default_font_size=20
	theme.set_color("font_color","Label",INK)
	for kind in ["Button","OptionButton"]:
		theme.set_stylebox("normal",kind,box(Color("203a30")))
		theme.set_stylebox("hover",kind,box(Color("2e5040"),GREEN))
		theme.set_stylebox("pressed",kind,box(Color("3b604c"),GREEN))
		theme.set_stylebox("disabled",kind,box(Color("1a2923"),Color("27382f")))
		theme.set_stylebox("focus",kind,box(Color(0,0,0,0),GOLD,16,0))
		for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:theme.set_color(state,kind,INK)
		theme.set_color("font_disabled_color",kind,Color("64796e"))
	for state in ["normal","read_only"]:theme.set_stylebox(state,"LineEdit",box(Color("101f19")))
	theme.set_stylebox("focus","LineEdit",box(Color(0,0,0,0),GOLD,16,0))
	theme.set_color("font_color","LineEdit",INK);theme.set_color("font_placeholder_color","LineEdit",MUTED)
	theme.set_stylebox("panel","PopupMenu",box(Color("172b22")))
	screen=Control.new();screen.auto_translate_mode=Node.AUTO_TRANSLATE_MODE_DISABLED;screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);screen.theme=theme;add_child(screen)
	var shade=ColorRect.new();shade.color=Color("0b1712");screen.add_child(shade);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel=PanelContainer.new();screen.add_child(panel);panel.add_theme_stylebox_override("panel",box(Color("10231a"),Color("2b4435"),24,24))
	body=vbox(panel,12)
	var top=hbox(body);var headings=vbox(top,2);headings.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label(headings,"BANJOBALL  /  ONLINE",15,GOLD);title=label(headings,"",30)
	latency=label(top,"",18);latency.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	back_button=button(top,t("返回","Back","Назад"),hide_menu)
	info=paragraph(body,"",17)
	scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.add_child(scroll)
	content=vbox(scroll,16);content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer=hbox(body);footer.hide();screen.hide()
	launch=Button.new();launch.text=t("联机游戏","Play online","Играть онлайн");launch.theme=theme;launch.position=Vector2(18,18);launch.size=Vector2(245,56);add_child(launch);launch.pressed.connect(show_menu)
	badge=Button.new();badge.theme=theme;badge.position=Vector2(18,18);badge.size=Vector2(250,48);add_child(badge);badge.hide();badge.pressed.connect(show_menu)
	net.changed.connect(refresh)
	var paths=JSON.parse_string(FileAccess.get_file_as_string("res://assets/textures/mobile-portraits.json"))
	for id in paths:portraits[id]=load(paths[id])
	if game.mobile_enabled:
		var pick_layer=CanvasLayer.new();pick_layer.layer=31;game.add_child(pick_layer);game.touch_controls.picker_overlay.reparent(pick_layer)
	layout()

func layout():
	var area=game.touch_controls.safe_rect() if game.mobile_enabled else get_viewport().get_visible_rect()
	panel.position=area.position+Vector2(20,16);panel.size=area.size-Vector2(40,32)

func label(parent,value: String,font_size=20,color=INK) -> Label:
	var node=Label.new();node.text=value;node.add_theme_font_size_override("font_size",font_size);node.add_theme_color_override("font_color",color);parent.add_child(node);return node

func paragraph(parent,value: String,font_size=18,color=MUTED) -> Label:
	var node=label(parent,value,font_size,color);node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;node.size_flags_horizontal=Control.SIZE_EXPAND_FILL;return node

func button(parent,value: String,action: Callable,primary=false) -> Button:
	var node=Button.new();node.text=value;node.custom_minimum_size.y=54;parent.add_child(node);node.pressed.connect(action)
	if primary:
		node.add_theme_stylebox_override("normal",box(GOLD,GOLD));node.add_theme_stylebox_override("hover",box(Color("f3d596"),GOLD));node.add_theme_stylebox_override("pressed",box(Color("c7a45e"),GOLD))
		for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:node.add_theme_color_override(state,Color("17251a"))
	return node

func vbox(parent,gap=10) -> VBoxContainer:
	var node=VBoxContainer.new();node.add_theme_constant_override("separation",gap);parent.add_child(node);return node

func hbox(parent,gap=12) -> HBoxContainer:
	var node=HBoxContainer.new();node.add_theme_constant_override("separation",gap);parent.add_child(node);return node

func card(parent,color=Color("192f24")) -> VBoxContainer:
	var frame=PanelContainer.new();frame.size_flags_horizontal=Control.SIZE_EXPAND_FILL;frame.add_theme_stylebox_override("panel",box(color));parent.add_child(frame);return vbox(frame)

func entry(parent,placeholder: String,secret=false) -> LineEdit:
	var node=LineEdit.new();node.placeholder_text=placeholder;node.secret=secret;node.custom_minimum_size=Vector2(180,56);node.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(node);return node

func picker(parent,items: Array,selected=0):
	if game.mobile_enabled:
		var p=game.touch_controls.picker(parent,items);p.select(maxi(0,selected));p.custom_minimum_size=Vector2(180,56);p.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		p.add_theme_stylebox_override("normal",box(Color("203a30")));p.add_theme_font_size_override("font_size",20);return p
	var p=OptionButton.new();p.custom_minimum_size=Vector2(180,54);p.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(p)
	for item in items:p.add_item(str(item))
	p.select(maxi(0,selected));return p

func show_menu():
	game.paused=true;game.aim="";net.release_input()
	if game.mobile_enabled:game.touch_controls.cancel_all()
	screen.show();view_key="";layout();refresh()
	if not net.connected and not net.wants_connection:net.connect_server(net.address)
	elif net.authenticated and net.room.is_empty():net.send({"type":"rooms"})

func hide_menu():
	screen.hide()
	if net.in_match:game.menu_root.hide();game.results_root.hide();game.paused=false
	else:game.open_menu()

func _process(_delta):
	launch.visible=not game.mobile_enabled and not screen.visible and game.menu_root.visible and not net.in_match;badge.visible=not screen.visible and net.in_match
	if badge.visible:
		var area=game.touch_controls.safe_rect() if game.mobile_enabled else get_viewport().get_visible_rect();badge.position=Vector2(area.end.x-badge.size.x-18,area.position.y+104)
	update_latency()
	if screen.visible:
		layout();info.text=status_text()
		if last_locale!=TranslationServer.get_locale():rebuild()

func status_text() -> String:
	var value=str(net.status);var parts=value.split(" / ",false,1)
	if parts.size()==2:return parts[0] if TranslationServer.get_locale().begins_with("zh") else parts[1]
	return value

func update_latency():
	if not is_instance_valid(latency):return
	var ms=net.latency_ms();var key=str(ms)+str(net.connected)+str(net.authenticated)+TranslationServer.get_locale()
	if key==latency_key:return
	latency_key=key
	var value="%d ms"%ms if ms>=0 else "—";latency.text=t("上海 · ","Shanghai · ","Шанхай · ")+value
	badge.text=t("房间 · ","Room · ","Комната · ")+value if net.authenticated and net.connected else t("连接已断开","Disconnected","Нет соединения")
	latency.tooltip_text=t("游戏消息往返耗时","Game message round-trip time","Время обмена с сервером")
	latency.add_theme_color_override("font_color",MUTED if ms<0 else (GREEN if ms<100 else (GOLD if ms<200 else Color("ff9290"))))

func rebuild():
	# Let the current touch/mouse release finish before replacing its button.
	view_key="";call_deferred("refresh")

func refresh():
	if not screen.visible:return
	last_locale=TranslationServer.get_locale();info.text=status_text()
	back_button.text=t("返回","Back","Назад");launch.text=t("联机游戏","Play online","Играть онлайн")
	var key="login"+str(register_mode)+last_locale if not net.authenticated else JSON.stringify(net.room if not net.room.is_empty() else net.rooms)+JSON.stringify(net.profile)+str(rules_open)+str(account_open)+room_filter+last_locale
	if key==view_key:return
	view_key=key
	if not net.authenticated and is_instance_valid(username):
		auth_draft={"username":username.text,"password":password.text,"nickname":nickname.text}
	elif net.authenticated:auth_draft={"username":"","password":"","nickname":""}
	var scroll_position=scroll.scroll_vertical;var room_id=str(net.room.get("id",""))
	if room_id!=last_room_id:rules_open=false;scroll_position=0;last_room_id=room_id
	for parent in [content,footer]:
		for child in parent.get_children():parent.remove_child(child);child.queue_free()
	footer.hide()
	if not net.authenticated:title.text=t("一起上场","Take the field","Вместе на поле");login_view()
	elif net.room.is_empty():title.text=t("比赛大厅","Match lobby","Игровое лобби");lobby_view()
	else:title.text=t("赛前准备","Team room","Комната команды");room_view()
	scroll.set_deferred("scroll_vertical",scroll_position)

func login_view():
	ip=LineEdit.new();ip.text=net.address;content.add_child(ip);ip.hide()
	var columns=hbox(content,24);var welcome=card(columns)
	label(welcome,"BANJOBALL",36,GOLD)
	paragraph(welcome,t("组队、选位，踢一场痛快的球。","Pick a side. Build your team. Play ball.","Выберите команду и выходите на поле."),24,INK)
	var pitch=Pitch.new();pitch.custom_minimum_size=Vector2(220,180);pitch.size_flags_vertical=Control.SIZE_EXPAND_FILL;welcome.add_child(pitch)
	paragraph(welcome,t("手机 × 电脑 · 同场竞技\n登录后直接浏览房间，点击即可加入。","Phone × PC · Play together\nBrowse rooms and join with one tap.","Телефон × ПК · Играйте вместе\nВыберите комнату и присоединяйтесь."))
	var form=card(columns);form.get_parent().size_flags_stretch_ratio=1.1
	var tabs=hbox(form)
	button(tabs,t("登录","Sign in","Вход"),func():register_mode=false;rebuild(),not register_mode).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button(tabs,t("注册账号","Register","Регистрация"),func():register_mode=true;rebuild(),register_mode).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	username=entry(form,t("账号（字母、数字、下划线）","Username (letters, numbers, _)","Логин (латиница, цифры, _)"));username.max_length=24
	password=entry(form,t("密码（至少 8 位）","Password (at least 8 characters)","Пароль (не менее 8 символов)"),true);password.max_length=128
	nickname=entry(form,t("游戏昵称（唯一，2–20 字）","Unique nickname (2–20 characters)","Уникальный ник (2–20 символов)"));nickname.max_length=20;nickname.visible=register_mode
	username.text=auth_draft.username;password.text=auth_draft.password;nickname.text=auth_draft.nickname
	button(form,t("注册并进入大厅","Register & enter lobby","Создать аккаунт") if register_mode else t("进入比赛大厅","Enter match lobby","Войти в лобби"),func():login("register" if register_mode else "login"),true)
	password.text_submitted.connect(func(_value):login("register" if register_mode else "login"))
	paragraph(form,t("注册开放至 11 月 1 日 00:00（北京时间）。\n已有账号此后仍可登录。","Registration closes Nov 1, 00:00 (UTC+8).\nExisting accounts can still sign in.","Регистрация до 1 ноября, 00:00 (UTC+8).\nВход в созданные аккаунты останется доступен."),16)
	button(form,t("重新连接服务器","Reconnect to server","Переподключиться"),func():net.connect_server(net.address))

func login(action: String):
	net.authenticate(action,username.text.strip_edges(),password.text,nickname.text.strip_edges())
	if is_instance_valid(password):password.text=""
	auth_draft.password=""

func field_name(config: Dictionary) -> String:
	var fields=game.sim.arena.fields;return translated(fields[clampi(int(config.get("field",0)),0,fields.size()-1)].name)

func state_name(state: String) -> String:
	match state:
		"lobby":return t("等待加入","Waiting","Ожидание")
		"loading":return t("加载中","Loading","Загрузка")
		"playing":return t("比赛中","In match","В игре")
		"ended":return t("已结束","Finished","Завершена")
	return state

func host_name(r: Dictionary) -> String:
	for s in r.seats:
		if s.uid==r.host:return str(s.nickname)
	return t("球友","Player","Игрок")

func rules_summary(c: Dictionary) -> String:
	var modes=[t("%d 球获胜","First to %d goals","До %d голов")%int(c.limit),t("计时 %d 分钟","%d-minute match","Матч %d мин")%int(c.minutes),t("上下半场","Two halves","Два тайма")]
	return "%dv%d  ·  %s  ·  %s"%[c.size,c.size,field_name(c),modes[clampi(int(c.mode),0,2)]]

func can_join(r: Dictionary) -> bool:
	if r.seats.any(func(s):return s.uid==net.profile.id):return true
	return r.state=="lobby" and r.seats.any(func(s):return s.uid=="" and not s.ai)

func lobby_view():
	var profile_line=hbox(content);var summary=vbox(profile_line,3);summary.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label(summary,str(net.profile.nickname),24)
	label(summary,t("完成 %d 场  ·  胜 %d  /  负 %d","%d completed  ·  %d wins / %d losses","Матчей: %d  ·  Побед: %d / Поражений: %d")%[net.profile.completed,net.profile.wins,net.profile.losses],17,MUTED)
	button(profile_line,t("账号","Account","Аккаунт"),func():account_open=not account_open;rebuild())
	button(profile_line,t("＋ 创建房间","＋ Create room","＋ Создать комнату"),func():net.send({"type":"create"}),true)
	if account_open:
		var account=card(content);var line=hbox(account);var name=entry(line,t("新的昵称","New nickname","Новый ник"))
		button(line,t("保存昵称","Save name","Сохранить"),func():net.send({"type":"rename","nickname":name.text.strip_edges(),"token":net.token}))
		button(line,t("退出登录","Sign out","Выйти"),func():net.send({"type":"logout"}))
	var toolbar=hbox(content)
	button(toolbar,t("全部房间","All rooms","Все комнаты"),func():room_filter="all";rebuild(),room_filter=="all")
	button(toolbar,t("可以加入","Joinable","Доступные"),func():room_filter="joinable";rebuild(),room_filter=="joinable")
	var auto_label=label(toolbar,t("每 3 秒自动刷新","Refreshes every 3 seconds","Обновление каждые 3 секунды"),16,MUTED);auto_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;auto_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	button(toolbar,t("刷新","Refresh","Обновить"),func():net.send({"type":"rooms"}))
	var shown=0
	for r in net.rooms:
		if room_filter=="joinable" and not can_join(r):continue
		shown+=1;room_card(r)
	if shown==0:
		var empty=card(content);var line=hbox(empty,24);var pitch=Pitch.new();pitch.custom_minimum_size=Vector2(220,150);line.add_child(pitch)
		var text=vbox(line,12);text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		label(text,t("等你开场","Your match starts here","Ваша игра начинается здесь"),28,GOLD)
		paragraph(text,t("暂时没有可显示的房间。创建一间，朋友登录后就能在列表中找到你。","No rooms to show. Create one and your friends can find it here after signing in.","Комнат пока нет. Создайте комнату — друзья увидят её в списке после входа."))
	paragraph(content,t("找到朋友的房间，直接点「加入」。比赛中的房间只允许原玩家重连。","Find your friend's room and tap Join. Only returning players can rejoin a match in progress.","Найдите комнату друга и нажмите «Войти». В начатый матч могут вернуться только его участники."),16)

func room_card(r: Dictionary):
	var area=card(content);var line=hbox(area,20);var pitch=Pitch.new();pitch.custom_minimum_size=Vector2(154,104);pitch.field=int(r.config.field);line.add_child(pitch)
	var text=vbox(line,6);text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var name=label(text,t("%s 的房间","%s's room","Комната: %s")%host_name(r),25);name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;name.custom_minimum_size.x=100
	paragraph(text,rules_summary(r.config),18)
	var humans=r.seats.filter(func(s):return s.uid!="").size();var bots=r.seats.filter(func(s):return s.ai).size()
	label(text,t("玩家 %d  ·  AI %d  ·  空位 %d","%d players  ·  %d AI  ·  %d open","Игроков: %d  ·  ИИ: %d  ·  Мест: %d")%[humans,bots,r.seats.size()-humans-bots],17,MUTED)
	var action=vbox(line,8);action.custom_minimum_size.x=160
	var state=label(action,state_name(r.state),17,GREEN if r.state=="lobby" else GOLD);state.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var reserved=r.seats.any(func(s):return s.uid==net.profile.id)
	var caption=t("重返比赛","Rejoin","Вернуться") if reserved and r.state!="lobby" else t("加入房间","Join room","Войти")
	if not can_join(r):caption=t("房间已满","Full","Нет мест") if r.state=="lobby" else t("比赛中","In match","В игре")
	button(action,caption,func():net.send({"type":"join","id":r.id}),can_join(r)).disabled=not can_join(r)

func room_view():
	var r=net.room;var mine=net.profile.id==r.host;var c=r.config
	var heading=hbox(content);var description=vbox(heading,4);description.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label(description,t("%s 的房间","%s's room","Комната: %s")%host_name(r),24);paragraph(description,rules_summary(c),18)
	if r.state=="lobby":button(heading,t("比赛规则","Match rules","Правила"),func():rules_open=not rules_open;rebuild())
	button(heading,t("离开房间","Leave room","Покинуть"),func():net.release_input();net.send({"type":"leave"}))
	if rules_open and r.state=="lobby":rules_view(r,mine)
	var teams=hbox(content,16);var own=-1
	for i in range(r.seats.size()):
		if r.seats[i].uid==net.profile.id:own=i
	for team_index in range(2):
		var team=card(teams,Color("192e38") if team_index==0 else Color("382620"))
		label(team,t("蓝队","BLUE TEAM","СИНЯЯ КОМАНДА") if team_index==0 else t("红队","RED TEAM","КРАСНАЯ КОМАНДА"),21,Color("89c4ef") if team_index==0 else Color("f0a291"))
		for j in range(int(c.size)):seat_row(team,r,team_index*int(c.size)+j,mine)
	if r.state!="lobby":
		paragraph(content,t("掉线 5 秒后 AI 临时接管，本局结束前可以回到原角色。","AI takes over after 5 seconds offline. You can reclaim your player until the match ends.","После 5 секунд отключения игроком управляет ИИ. Вернуться можно до конца матча."))
		footer.show();label(footer,state_name(r.state),22,GOLD).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if net.in_match:button(footer,t("回到比赛","Return to match","Вернуться в матч"),hide_menu,true)
		if r.state=="ended" and mine:button(footer,t("再来一场","Play again","Ещё матч"),func():net.send({"type":"return"}),true).disabled=not r.result_saved
		return
	if own<0:return
	var selection=card(content);var choices=hbox(selection);var slots=[]
	for i in range(r.seats.size()):slots.append(position_name(i,c)+(" · "+t("已占用","Taken","Занято") if i!=own and (r.seats[i].uid!="" or r.seats[i].ai) else ""))
	var position_col=vbox(choices,6);position_col.size_flags_horizontal=Control.SIZE_EXPAND_FILL;label(position_col,t("队伍 / 站位","Team / Position","Команда / Позиция"),16,MUTED);seat=picker(position_col,slots,own)
	var hero_col=vbox(choices,6);hero_col.size_flags_horizontal=Control.SIZE_EXPAND_FILL;label(hero_col,t("球员","Character","Персонаж"),16,MUTED)
	var names=[]
	for id in game.sim.Characters.IDS:names.append(translated(game.sim.Characters.DATA[id].name))
	hero=picker(hero_col,names,game.sim.Characters.IDS.find(r.seats[own].hero))
	var hat_col=vbox(choices,6);hat_col.size_flags_horizontal=Control.SIZE_EXPAND_FILL;label(hat_col,t("装扮","Headwear","Головной убор"),16,MUTED)
	var hats=[]
	for id in game.hats.choices:hats.append(translated(game.hats.catalog[id].name))
	hat=picker(hat_col,hats,maxi(0,game.hats.choices.find(int(r.seats[own].hat))))
	var confirm=button(choices,t("确认选择","Confirm","Подтвердить"),func():net.send({"type":"select","slot":seat.selected,"hero":game.sim.Characters.IDS[hero.selected],"hat":game.hats.choices[hat.selected]}));confirm.size_flags_vertical=Control.SIZE_SHRINK_END
	paragraph(selection,t("更改选择后需要重新准备。新 AI 使用房主在这里选择的球员和装扮。","Changes reset readiness. New AI uses the host's selected character and headwear.","После изменений нужна повторная готовность. Новый ИИ получает выбранные хозяином персонажа и убор."),16)
	footer.show()
	var filled=r.seats.all(func(s):return s.uid!="" or s.ai);var all_ready=r.seats.all(func(s):return s.ai or (s.uid!="" and s.ready and s.connected))
	var tip=t("所有玩家准备后即可开赛","Ready up to start","Подтвердите готовность")
	if all_ready:tip=t("全员准备就绪","Everyone is ready","Все готовы")
	elif not filled:tip=t("还有空位 · 邀请朋友或添加 AI","Open slots · Invite friends or add AI","Есть места · Пригласите друзей или добавьте ИИ")
	paragraph(footer,tip,18,GREEN if all_ready else MUTED)
	button(footer,t("取消准备","Not ready","Не готов") if r.seats[own].ready else t("准备好了","Ready","Готов"),func():net.send({"type":"ready","value":not r.seats[own].ready}),not r.seats[own].ready)
	if mine:button(footer,t("开始比赛","Start match","Начать матч"),func():net.send({"type":"start"}),true).disabled=not all_ready

func position_name(index: int,c: Dictionary) -> String:
	var team=t("蓝队","Blue","Синие") if index<int(c.size) else t("红队","Red","Красные");var number=index%int(c.size)+1
	return team+" · "+(t("门将","Goalkeeper","Вратарь") if number==int(c.size) and int(c.size)>=3 else str(number))

func seat_row(parent,r: Dictionary,index: int,mine: bool):
	var s=r.seats[index];var line=hbox(parent,10);line.custom_minimum_size.y=68
	var icon=TextureRect.new();icon.custom_minimum_size=Vector2(54,54);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;line.add_child(icon)
	if s.uid!="" or s.ai:icon.texture=portraits.get(s.hero);icon.modulate=Color.WHITE if s.connected or s.ai else Color(.5,.5,.5)
	var text=vbox(line,2);text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var name=str(s.nickname) if s.uid!="" or s.ai else t("等待球友","Open slot","Свободное место")
	if s.uid==net.profile.id:name+=" · "+t("我","You","Вы")
	var nickname_label=label(text,name,20);nickname_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;nickname_label.custom_minimum_size.x=60
	var state=t("AI 球员","AI player","Игрок ИИ") if s.ai else (t("已准备","Ready","Готов") if s.ready else t("未准备","Not ready","Не готов"))
	if s.uid!="" and not s.connected:state=t("已掉线","Offline","Не в сети")
	if s.uid=="" and not s.ai:state=t("可加入","Available","Доступно")
	label(text,position_name(index,r.config)+" · "+state,15,GREEN if s.ready or s.ai else MUTED)
	if r.state!="lobby":return
	if mine and s.uid=="":
		button(line,t("移除 AI","Remove AI","Убрать ИИ") if s.ai else t("＋ AI","＋ AI","＋ ИИ"),func():
			if not is_instance_valid(hero) or not is_instance_valid(hat):return
			net.send({"type":"ai","slot":index,"hero":"" if s.ai else game.sim.Characters.IDS[hero.selected],"hat":game.hats.choices[hat.selected]}))
	elif mine and s.uid!=net.profile.id:button(line,t("移出","Remove","Убрать"),func():net.send({"type":"remove","slot":index}))

func rules_view(r: Dictionary,mine: bool):
	var c=r.config;var area=card(content);label(area,t("比赛规则","Match rules","Правила матча"),22,GOLD)
	if not mine:paragraph(area,rules_summary(c)+"\n"+t("规则由房主设置","Rules are set by the host","Правила задаёт хозяин"));return
	var first=hbox(area);var sizes=picker(first,["1v1","2v2","3v3","4v4","5v5","6v6"],int(c.size)-1);var field_names=[]
	for f in game.sim.arena.fields:field_names.append(translated(f.name))
	var field=picker(first,field_names,int(c.field));var mode=picker(first,[t("进球赛","Goal limit","До голов"),t("计时赛","Timed","По времени"),t("上下半场","Two halves","Два тайма")],int(c.mode))
	var form=picker(area,[t("原版一排站位","Original row formation","Расстановка в ряд"),t("战术预设站位","Tactical formation","Тактическая расстановка")],0 if c.formation=="row" else 1)
	var limits=hbox(area);label(limits,t("进球数","Goals","Голы"),18)
	var goals=SpinBox.new();goals.min_value=1;goals.max_value=50;goals.value=c.limit;goals.custom_minimum_size=Vector2(130,54);limits.add_child(goals)
	label(limits,t("比赛分钟","Minutes","Минуты"),18)
	var minutes=SpinBox.new();minutes.min_value=1;minutes.max_value=60;minutes.value=c.minutes;minutes.custom_minimum_size=Vector2(130,54);limits.add_child(minutes)
	button(limits,t("保存规则","Save rules","Сохранить"),func():
		net.send({"type":"configure","config":{"size":sizes.selected+1,"field":field.selected,"mode":mode.selected,"formation":"row" if form.selected==0 else "tactical","limit":goals.value,"minutes":minutes.value}})
		rules_open=false,true)
	paragraph(area,t("修改规则后，全员需要重新准备。","Changing rules resets everyone's readiness.","После изменения правил все должны снова подтвердить готовность."),16)
