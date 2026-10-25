extends SceneTree
var game
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func step(seconds):
	while seconds>.000001:
		var dt=minf(seconds,1.0/60);game.sim.advance(dt);game.update_visuals(dt);seconds-=dt
func setup_character(id):
	game.character_select.select(game.sim.Characters.IDS.find(id));game.enter_practice();game.sim.bot_enabled=false
	game.sim.players[0].pos=Vector2(-400,0);game.sim.players[0].previous=Vector2(-400,0)
	game.sim.players[1].pos=Vector2(1500,900);game.sim.ball=Vector3(1500,-900,0)
	game.focus=Vector3(-3,0,0);game.zoom=.5;game.update_camera();game.update_visuals(0)
func capture(name):
	game.touch_controls.frame(0);await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/skill-text-"+name+".png")
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	setup_character("h026");var fx=game.original_effects
	game.sim.Characters.use(game.sim,0,Vector2.ZERO);step(.18)
	check(fx.pass_tags.size()==1 and fx.pass_tags[0].node.text=="OGRE SMASH!","real ogre impact renders original words")
	check(fx.pass_tags[0].node.modulate==Color("a9d5f5"),"ogre uses original emote color")
	await capture("ogre")
	step(1);check(fx.pass_tags.is_empty(),"ogre message expires independently of later animation")
	setup_character("h01I");game.sim.Characters.use(game.sim,0,Vector2.ZERO);step(.90)
	check(fx.pass_tags.is_empty(),"real delayed blink has no early countdown")
	step(.12);check(fx.pass_tags.size()==1 and fx.pass_tags[0].node.text=="2.0!","real cast and half-second callback display first shadow value")
	check(fx.pass_tags[0].origin==Vector3(-4.4,1.5,0),"shadow countdown remains at departure ghost rather than following caster")
	await capture("shadow")
	game.sim.Characters.use(game.sim,0,Vector2.ZERO);step(.8)
	check(fx.pass_tags.is_empty(),"recall leaves no new countdown, existing label drains naturally")
	setup_character("h027");var s=game.sim
	s.Characters.use(s,0,Vector2.ZERO);step(1.51);s.Characters.use(s,0,Vector2(-400,-500));step(.7)
	check(s.rifts.size()==1 and s.rifts[0].b!=null,"actual projectile sequence opens paired portals")
	check(fx.pass_tags.any(func(e):return e.node.text=="3.0!"),"new pair resets countdown to three")
	await capture("rift")
	step(3.8);check(fx.pass_tags.is_empty(),"portal cleanup leaves no orphaned text")
	# Client-side audience checks are independent of cosmetic simulation events.
	game.start_game(3);s=game.sim;s.countdown=0;s.match_state="playing";s.bot_enabled=false;game.update_visuals(0)
	var own=s.emit_world_text(Vector3.ZERO,"owner",.75);own.audience_owner=1
	var enemy=s.emit_world_text(Vector3.ZERO,"enemy team",.75);enemy.audience_team=1
	var ally=s.emit_world_text(Vector3.ZERO,"ally team",.75);ally.audience_team=0
	game.update_visuals(0)
	check(fx.pass_tags.size()==1 and fx.pass_tags[0].node.text=="ally team","teammate pair visible while another owner's entrance and enemy countdown stay hidden")
	s.select_player(1);own=s.emit_world_text(Vector3.ZERO,"new owner",.75);own.audience_owner=1;game.update_visuals(0)
	check(fx.pass_tags.any(func(e):return e.node.text=="new owner"),"switching control enables that actor's future private cues")
	var old=fx.pass_tags.size();s.select_player(3);enemy=s.emit_world_text(Vector3.ZERO,"team1",.75);enemy.audience_team=1;game.update_visuals(0)
	# select_player only allows friendly players; validate audience against current local team.
	check(fx.pass_tags.size()==old,"enemy-only cue stays hidden when enemy control is rejected")
	step(.5);check(fx.pass_tags.all(func(e):return is_equal_approx(e.node.modulate.a,.5)),".75-second countdown fades from .25 to .75 seconds")
	var pos=fx.pass_tags[0].node.position;game.open_menu();game.update_visuals(0)
	check(fx.pass_tags[0].node.position==pos,"pause freezes world text age and ascent")
	game.close_menu();step(.25);check(fx.pass_tags.is_empty(),"countdown tags disappear at .75 seconds")
	setup_character("h005");s=game.sim;s.start_match(3);s.countdown=0;s.match_state="playing";s.bot_enabled=false;game.rebuild_actors();game.update_visuals(0)
	s.ball=Vector3(-1800,0,0);s.holder=-1;s.stall_counter=209;s.StallRules.step(s);game.update_visuals(0)
	var warning=fx.pass_tags[0]
	check(warning.node.text=="!" and warning.node.modulate==Color("ffcc00"),"real stall threshold displays gold exclamation")
	check(warning.node.font_size==43 and warning.origin==Vector3(-17.94,1,0),"warning has source size ratio and ball offset")
	game.focus=Vector3(-18,0,0);game.update_camera();await capture("warning")
	var anchor=warning.origin;s.ball=Vector3.ZERO;game.update_visuals(0)
	check(warning.origin==anchor,"warning remains at event position when ball moves")
	step(1.5);check(fx.pass_tags.is_empty(),"warning expires after its own 1.5 seconds")
	game.free()
	FileAccess.open("res://research/skill-text-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("SKILL TEXT RENDER ",passed," passed; ",failures.size()," failed");quit(1 if not failures.is_empty() else 0)
