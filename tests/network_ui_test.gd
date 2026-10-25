extends SceneTree
var game
func _initialize():call_deferred("run")
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game)
	await process_frame
	game.network_menu.show_menu();game.network.close_connection()
	await process_frame;await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/network-tests/login-mobile.png")
	var Room=load("res://scripts/net_room.gd")
	var room=Room.new("playerone","我的昵称")
	room.set_ai("playerone",1,"h005");room.set_ai("playerone",2,"h003")
	game.network.authenticated=true;game.network.profile={"id":"playerone","nickname":"我的昵称","completed":5,"wins":3,"losses":2};game.network.room=room.view()
	game.network_menu.refresh()
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/network-tests/room-mobile.png")
	game.touch_controls.open_picker(game.network_menu.hero)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/network-tests/picker-mobile.png")
	game.touch_controls.close_picker()
	game.network_menu.hide_menu()
	game.network.in_match=true;game.network.slot=0
	room.set_ai("playerone",3,"h001");room.set_ai("playerone",4,"h00F");room.set_ai("playerone",5,"h01R");room.ready("playerone",true);room.begin("playerone",0)
	var data={"room":room.view(),"slot":0,"state":load("res://scripts/net_snapshot.gd").capture(room.sim)}
	game.start_network_match(data)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/network-tests/match-mobile.png")
	game.network.close_connection()
	print("Network UI rendered")
	quit()
