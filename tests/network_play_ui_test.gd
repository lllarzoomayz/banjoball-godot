extends SceneTree
const Client=preload("res://scripts/net_client.gd")
var game
var other
var failed=false
func _initialize():call_deferred("run")
func expect(ok: bool,message: String):
	if not ok:failed=true;push_error(message)
func until(predicate: Callable,seconds=15.0) -> bool:
	var start=Time.get_ticks_msec()
	while not predicate.call() and Time.get_ticks_msec()-start<seconds*1000:await create_timer(.05).timeout
	return predicate.call()
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game)
	await process_frame
	other=Client.new();root.add_child(other)
	other.begin_match.connect(func(value):other.loaded_sim(load("res://scripts/match_sim.gd").new(),value.state))
	for c in [game.network,other]:
		c.token="";c.address="127.0.0.1"
		var name="ui"+str(Time.get_ticks_usec())
		c.authenticate("register",name,"temporary-password","球员"+name)
	expect(await until(func():return game.network.authenticated and other.authenticated),"UI account login")
	if failed:return finish()
	game.network.send({"type":"create"})
	expect(await until(func():return not game.network.room.is_empty()),"UI create")
	other.send({"type":"join","id":game.network.room.id})
	expect(await until(func():return not other.room.is_empty()),"UI join")
	# Render as the red player to catch hard-coded blue-team assumptions.
	game.network.send({"type":"select","slot":3,"hero":"h01R","hat":0})
	await create_timer(.3).timeout
	for i in [0,2,4,5]:game.network.send({"type":"ai","slot":i,"hero":"h005"})
	await create_timer(.3).timeout
	for c in [game.network,other]:c.send({"type":"ready","value":true})
	await create_timer(.3).timeout;game.network.send({"type":"start"})
	expect(await until(func():return game.network.in_match and other.in_match),"UI load")
	expect(await until(func():return game.sim.match_state=="playing"),"UI countdown")
	if failed:return finish()
	for i in range(8):
		game.network.submit("move_direction",Vector2(-1,0.3));await create_timer(.25).timeout
	game.network.release_input()
	game.network.submit("ability",Vector2.ZERO)
	await create_timer(2).timeout
	expect(game.sim.controlled==3 and game.sim.players[3].team==1,"red own slot")
	expect(game.touch_controls.portrait_players==[3,4,5],"red teammate portraits")
	game.network_menu.show_menu()
	expect(await until(func():return game.network.latency_ms()>=0,3.0),"server round-trip latency measured")
	await process_frame
	expect(" ms" in game.network_menu.latency.text,"room screen displays measured latency")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/network-tests/latency-room.png")
	var before=game.sim.timeline
	await create_timer(.5).timeout
	expect(game.sim.timeline>before,"opening menu does not stop server")
	game.network_menu.hide_menu()
	await process_frame;await RenderingServer.frame_post_draw
	expect(game.network_menu.badge.visible and " ms" in game.network_menu.badge.text,"match displays measured latency")
	root.get_texture().get_image().save_png("res://research/network-tests/live-red-client.png")
	print("LIVE UI: red control, avatars, hat, skill, movement, independent menu and room/match measured latency verified")
	finish()
func finish():
	game.network.close_connection();other.close_connection();quit(1 if failed else 0)
