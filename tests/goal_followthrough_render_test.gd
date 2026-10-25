extends SceneTree
var game
var checks=[]
var failed=false
func _initialize():call_deferred("run")
func check(ok: bool,label: String):
	checks.append({"test":label,"passed":ok})
	if not ok:failed=true;push_error(label)
func capture(label: String):
	game.sim.previous_ball=game.sim.ball
	game.update_visuals(1.0/32)
	game.touch_controls.frame(0)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/goal-followthrough-"+label+".png")
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	game.start_game(3)
	var s=game.sim;s.bot_enabled=false;s.match_state="playing"
	for p in s.players:p.pos=Vector2(0,900);p.previous=p.pos;p.target=p.pos
	game.focus=Vector3(22,0,0);game.zoom=.55;game.update_camera()
	s.ball=Vector3(2230,0,50);s.velocity=Vector3(70,0,0)
	s.step_ball();await capture("scored")
	check(game.ball_model.position.x>22.4 and s.score==[1,0],"rendered ball continues beyond score plane")
	for i in range(3):s.step_ball()
	await capture("inside")
	check(game.ball_model.position.x>24.8 and s.velocity.x>0,"ball visibly travels to rear of goal")
	for i in range(6):s.step_ball()
	await capture("rebound")
	check(game.ball_model.position.x<22.4 and s.velocity.x<0 and s.score==[1,0],"rendered rebound exits while score stays one")
	game.start_game(3);s.bot_enabled=false;s.match_state="playing";s.score_limit=1
	for p in s.players:p.pos=Vector2(0,900);p.previous=p.pos
	s.ball=Vector3(2230,0,50);s.velocity=Vector3(70,0,0);s.step_ball()
	game._process(0)
	check(not game.results_root.visible and not game.paused,"winning goal does not immediately freeze behind results")
	for i in range(128):s.step_ball()
	game._process(0)
	check(game.results_root.visible and game.paused,"results open after winning shot follow-through")
	game.enter_practice();s.bot_enabled=false
	s.players[0].pos=Vector2(-400,60);s.players[0].previous=s.players[0].pos;s.players[0].body=0;s.players[0].angle=0
	s.players[1].pos=Vector2.ZERO;s.players[1].previous=Vector2.ZERO;s.players[1].body=PI;s.players[1].angle=PI
	game.focus=Vector3.ZERO;game.zoom=.55;game.update_camera()
	s.take(0);s.DirectionalMotion.order(s,0,Vector2.RIGHT)
	s.advance(1.1);await capture("steal")
	check(s.holder==1 and absf(game.ball_model.position.x+1.0)<0.001,"rendered ball follows defender immediately after front steal")
	s.advance(1.9);await capture("dribbler-passed")
	check(s.holder==1 and s.players[0].pos.x>0,"runner passes defender without taking the stolen ball along")
	FileAccess.open("res://research/goal-followthrough-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks},"\t"))
	print("Goal render checks: ",checks.size(),"; failed: ",failed)
	quit(1 if failed else 0)
