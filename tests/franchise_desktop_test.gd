extends SceneTree
var game
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func click(button):
	var pos=root.get_final_transform()*button.get_global_rect().get_center()
	var motion=InputEventMouseMotion.new();motion.position=pos;Input.parse_input_event(motion)
	for down in [true,false]:
		var event=InputEventMouseButton.new();event.position=pos;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
		Input.parse_input_event(event);Input.flush_buffered_events()
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.set_process(false)
	game.enter_practice();game.update_visuals(0)
	var f=game.franchise
	click(game.desktop_tools_button)
	var entry=game.desktop_tools.get_children().filter(func(node):return node is Button and node.text=="球队外观")[0]
	check(entry.is_visible_in_tree() and game.desktop_tools.get_global_rect().encloses(entry.get_global_rect()),"desktop More exposes an accessible team entry")
	check(not entry.get_global_rect().intersects(game.hats.desktop_picker.get_global_rect()),"team entry does not overlap hat picker")
	click(entry);await process_frame
	check(f.panel.visible and game.paused,"desktop mouse opens modal")
	check(f.home is OptionButton and f.home.item_count==5 and f.away.item_count==5,"desktop pickers contain five original teams")
	f.home.select(1);f.away.select(3);f.enabled.button_pressed=true;f.frame(0)
	click(f.apply_button);await process_frame
	check(not f.panel.visible and not game.paused and game.sim.franchise_config.home==1 and game.sim.franchise_config.away==3,"desktop Apply changes both teams and resumes play")
	check(game.score_label.text.contains("恐龙队") and game.score_label.text.contains("王牌队"),"desktop scoreboard follows applied selection")
	f.open();await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/franchise-desktop.png")
	var event=InputEventKey.new();event.pressed=true;event.keycode=KEY_ESCAPE;Input.parse_input_event(event);Input.flush_buffered_events()
	check(not f.panel.visible and not game.paused,"Escape closes modal and returns to play")
	check(not game.show_routes,"desktop customization keeps route diagnostics hidden")
	FileAccess.open("res://research/franchise-desktop-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("FRANCHISE DESKTOP ",passed," passed; ",failures.size()," failed")
	game.free();quit(0 if failures.is_empty() else 1)
