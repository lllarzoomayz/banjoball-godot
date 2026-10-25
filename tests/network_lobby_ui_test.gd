extends SceneTree
const Room=preload("res://scripts/net_room.gd")
class PreviewClient extends "res://scripts/net_client.gd":
	var sent=[]
	func _ready():pass
	func _process(_delta):pass
	func send(value: Dictionary):sent.append(value)
	func connect_server(_ip: String):wants_connection=true
	func save_session():pass
var game
var menu
var client
var failed=false
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	if not ok:failed=true;push_error(message)
func settle():
	for i in range(8):await process_frame
func buttons(parent,text: String) -> Array:
	var found=[]
	for child in parent.get_children():
		if child is Button and child.text==text:found.append(child)
		found.append_array(buttons(child,text))
	return found
func click(text: String):
	var found=buttons(menu.screen,text);check(not found.is_empty(),"Button exists: "+text)
	if found.is_empty():return
	var b=found[0];check(not b.disabled,"Button enabled: "+text)
	var point=b.get_global_rect().get_center()
	for pressed in [true,false]:
		var e=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.position=point;e.global_position=point;e.pressed=pressed;root.push_input(e,true);await process_frame
	await settle()
func screenshot(name: String):
	await settle();await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/ui-0.4.41/"+name+".png")
	var bounds=Rect2(Vector2.ZERO,root.get_visible_rect().size)
	check(bounds.encloses(menu.panel.get_global_rect()),"Panel inside viewport: "+name)
	check(menu.content.size.x<=menu.scroll.size.x+2,"No horizontal overflow: "+name)
	if menu.footer.visible:check(bounds.encloses(menu.footer.get_global_rect()),"Ready footer inside viewport: "+name)
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);await settle()
	game.network.close_connection();client=PreviewClient.new();root.add_child(client)
	client.address="127.0.0.1:27888";client.profile={"id":"self","nickname":"示例球员","completed":12,"wins":8,"losses":4};client.status="已连接 / Connected"
	menu=game.network_menu;menu.net.changed.disconnect(menu.refresh);menu.net=client;client.changed.connect(menu.refresh)
	root.size=Vector2i(1440,664);game.Language.apply("zh");menu.show_menu();await settle()
	await screenshot("login-zh")
	check(not menu.nickname.visible,"Login hides registration-only field")
	menu.username.text="draft_player";menu.password.text="temporary-draft"
	await click("注册账号");check(menu.nickname.is_visible_in_tree(),"Registration tab opens nickname")
	check(menu.username.text=="draft_player" and menu.password.text=="temporary-draft","Switching auth tabs preserves unsent input")
	menu.username.text="";menu.password.text=""
	await screenshot("register-zh")
	var r=Room.new("friend","柠檬队长");r.id="room-a";r.set_ai("friend",1,"h005",12)
	var full=Room.new("other","周末球赛");full.id="room-b";full.state="playing"
	client.authenticated=true;client.connected=true;client.rooms=[r.view(),full.view()];menu.rebuild();await settle()
	await screenshot("lobby-zh")
	await click("加入房间");check(client.sent.back()=={"type":"join","id":"room-a"},"List join sends correct room id")
	await click("可以加入");check(buttons(menu.screen,"比赛中").is_empty(),"Filter hides unjoinable matches")
	client.rooms=[];menu.rebuild();await screenshot("empty-zh")
	r=Room.new("self","柠檬球员");r.join("friend","队友小熊");r.set_ai("self",3,"h005",12);client.room=r.view();menu.rebuild();await settle()
	await screenshot("room-zh")
	check(buttons(menu.screen,"开始比赛")[0].disabled,"Cannot start with empty/unready seats")
	await click("准备好了");check(client.sent.back()=={"type":"ready","value":true},"Ready sends command")
	await click("比赛规则");await screenshot("rules-zh")
	await click("比赛规则");await click("＋ AI");check(client.sent.back().type=="ai" and client.sent.back().slot==2,"AI button targets correct empty slot")
	for i in [2,4,5]:r.set_ai("self",i,"h005",12)
	r.ready("self",true);r.ready("friend",true);client.room=r.view();menu.rebuild();await settle()
	check(not buttons(menu.screen,"开始比赛")[0].disabled,"Start enabled only when all ready")
	await click("开始比赛");check(client.sent.back()=={"type":"start"},"Start sends command")
	for locale in ["en","ru"]:
		game.Language.apply(locale);menu.rebuild();await screenshot("room-"+locale)
		client.room={};client.rooms=[r.view(),full.view()];menu.rebuild();await screenshot("lobby-"+locale)
		client.room=r.view()
	game.Language.apply("zh");r.configure("self",{"size":6});client.room=r.view();menu.rebuild();await screenshot("room-6v6-zh")
	menu.scroll.scroll_vertical=10000;await screenshot("room-6v6-bottom-zh")
	root.size=Vector2i(1440,900);menu.scroll.scroll_vertical=0;await screenshot("room-pc-zh")
	client.room={};client.rooms=[r.view(),full.view()];menu.rebuild();await screenshot("lobby-pc-zh")
	for locale in ["zh","en","ru"]:
		game.Language.apply(locale);root.size=Vector2i(1280,720);client.room={};menu.rebuild();await screenshot("lobby-16x9-"+locale)
		r.configure("self",{"size":3});client.room=r.view();menu.rebuild();await screenshot("room-16x9-"+locale)
	print("LOBBY UI: login/register, list joining, filters, empty state, ready/start, AI, three locales, scrolling, phone/PC bounds checked")
	quit(1 if failed else 0)
