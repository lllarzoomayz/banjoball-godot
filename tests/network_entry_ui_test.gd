extends SceneTree
var game
var failed=false
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	if not ok:failed=true;push_error(message)
func click_button(button: Button):
	var point=button.get_global_rect().get_center()
	for pressed in [true,false]:
		var event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.global_position=point;event.pressed=pressed
		Input.parse_input_event(event)
		await process_frame
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game)
	for i in range(5):await process_frame
	var entry=game.touch_controls.menu.get_node("Network")
	check(entry.is_visible_in_tree(),"LAN entry is visible at normal startup")
	check(game.touch_controls.menu.get_global_rect().encloses(entry.get_global_rect()),"LAN entry is inside main menu")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/network-tests/startup-entry-mobile.png")
	await click_button(entry)
	for i in range(3):await process_frame
	check(game.network_menu.screen.visible,"Normal menu click opens network screen")
	check(is_instance_valid(game.network_menu.username) and game.network_menu.username.is_visible_in_tree(),"Account form is visible")
	check(is_instance_valid(game.network_menu.nickname) and not game.network_menu.nickname.visible,"Login keeps registration-only nickname field hidden")
	check(game.network_menu.ip.text=="127.0.0.1:27888","Local development address is prefilled")
	check(game.network.direct_mode=="" and game.network.easytier==null,"Cloud menu does not start EasyTier or punching")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/network-tests/startup-entry-login-mobile.png")
	game.network_menu.hide_menu()
	for i in range(3):await process_frame
	check(entry.is_visible_in_tree(),"Back restores visible LAN entry")
	root.size=Vector2i(1440,664)
	for i in range(5):await process_frame
	check(game.touch_controls.safe_rect().encloses(entry.get_global_rect()),"LAN entry remains inside safe layout on wide phone")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/network-tests/startup-entry-wide-mobile.png")
	game.network.close_connection()
	print("NETWORK ENTRY: startup, actual button click, account/register fields, return, wide layout checked")
	quit(1 if failed else 0)
