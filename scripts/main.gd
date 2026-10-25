extends Node3D
const MatchSim=preload("res://scripts/match_sim.gd")
const WCModel=preload("res://scripts/wc3_model.gd")
const MatchReport=preload("res://scripts/match_report.gd")
const FieldScenery=preload("res://scripts/field_scenery.gd")
const SpellVisuals=preload("res://scripts/spell_visuals.gd")
const OriginalGoals=preload("res://scripts/original_goals.gd")
const Language=preload("res://scripts/language_settings.gd")
var language_select: OptionButton
var original_effects
var original_goals
var sim=MatchSim.new()
var camera: Camera3D
var actors=[]
var ball_model
var selection: MeshInstance3D
var marker: MeshInstance3D
var shadow: MeshInstance3D
var move_clock=0.0
var ball_clock=0.0
var aim=""
var score_label: Label
var status_label: Label
var mana_bar: ProgressBar
var q_button: Button
var r_button: Button
var e_button: Button
var bot_button: Button
var font: Font
var focus=Vector3.ZERO
var zoom=1.12
var paused=false
var capture_frames=0
var capture=false
var gallery_id=""
var gallery_select: OptionButton
var actor_catalog=[]
var unit_name: Label
var hint: Label
var notice_timer=0.0
var last_desktop_notice=""
var trail_points=[]
var trail: MeshInstance3D
var show_trace=false
var checks={}
var obstacle_nodes: Node3D
var course_button: Button
var route_label: Label
var route_mesh: MeshInstance3D
var debug_nodes: Node3D
var debug_rings=[]
var show_routes=false
var menu_root: Control
var menu_title: Label
var resume_button: Button
var clock_label: Label
var phase_label: Label
var team_label: Label
var result_shown=false
var gallery_caption: Label
var character_select: OptionButton
var character_note: Label
var spell_mesh: MeshInstance3D
var spell_vertices=0
var pillar_models={}
var dying_pillars=[]
var pillar_player_ref
var projectile_models={}
var fake_models={}
var pitch_nodes: Node3D
var field_scenery: Node3D
var field_select: OptionButton
var field_note: Label
var surface_hint: Label
var referee_model
var stall_label: Label
var rift_models={}
var dying_rifts=[]
var rift_player_ref
var morph_models={}
var tackle_shadow_models={}
var mode_select: OptionButton
var report_button: Button
var results_root: Control
var results_title: Label
var results_teams=[]
var results_history: RichTextLabel
var half_panel: Control
var half_label: Label
var half_select: OptionButton
var shown_sides_swapped=false
var hold_button: Button
var injury_toggle: CheckButton
var refresh_button: Button
var recall_button: Button
var mobile_enabled=OS.has_feature("android") or "--mobile" in OS.get_cmdline_user_args()
var experience
var touch_controls
var perf
var franchise
var visual_profile={}
var desktop_tools: Panel
var desktop_tools_button: Button
var event_decals
var event_spawns
var hats
var biz_tree
var apocalypse_visuals
var aftermath_controls
var generated_ice_visuals
var network
var network_menu

func _ready():
	Language.load_choice()
	tree_exiting.connect(Language.release)
	if mobile_enabled:
		get_window().content_scale_size=Vector2i(1440,810)
		get_window().content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	get_tree().auto_accept_quit=false
	get_tree().quit_on_go_back=false
	font=load("res://assets/fonts/msyh.ttc")
	build_world()
	original_effects=SpellVisuals.new();add_child(original_effects)
	for color in [Color("4f98ff"),Color("e96653")]:
		var actor=WCModel.new()
		add_child(actor)
		actor.load_actor("h005",color)
		actors.append(actor)
	ball_model=WCModel.new()
	add_child(ball_model)
	ball_model.load_actor("h000",Color.WHITE)
	selection=ring(0.52,Color("5ee3a9"))
	marker=ring(0.35,Color("8ce8bc"))
	marker.visible=false
	shadow=disc(0.28,Color(0.02,0.03,0.02,0.5))
	build_ui()
	build_menu()
	build_match_panels()
	build_obstacles()
	experience=preload("res://scripts/play_feedback.gd").new();add_child(experience);experience.setup(self)
	event_decals=preload("res://scripts/wc3_event_decals.gd").new();add_child(event_decals);event_decals.setup(self)
	event_spawns=preload("res://scripts/wc3_event_spawns.gd").new();add_child(event_spawns);event_spawns.setup(self)
	hats=preload("res://scripts/hat_visuals.gd").new();add_child(hats);hats.setup(self)
	biz_tree=preload("res://scripts/biz_tree.gd").new();add_child(biz_tree);biz_tree.setup(self)
	apocalypse_visuals=preload("res://scripts/apocalypse_visuals.gd").new();add_child(apocalypse_visuals);apocalypse_visuals.setup(self)
	generated_ice_visuals=preload("res://scripts/generated_ice_visuals.gd").new();add_child(generated_ice_visuals);generated_ice_visuals.setup(self)
	if mobile_enabled:
		touch_controls=preload("res://scripts/mobile_controls.gd").new();add_child(touch_controls);touch_controls.setup(self)
		perf=preload("res://scripts/performance_hud.gd").new();add_child(perf);perf.setup(self)
	franchise=preload("res://scripts/franchise_visuals.gd").new();add_child(franchise);franchise.setup(self)
	aftermath_controls=preload("res://scripts/aftermath_controls.gd").new();add_child(aftermath_controls);aftermath_controls.setup(self)
	network=preload("res://scripts/net_client.gd").new();add_child(network)
	network_menu=preload("res://scripts/net_menu.gd").new();add_child(network_menu);network_menu.setup(self,network)
	network.begin_match.connect(start_network_match)
	network.left_match.connect(leave_network_match)
	capture="--capture" in OS.get_cmdline_user_args()
	if "--smoke" in OS.get_cmdline_user_args():run_smoke()
	if "--match" in OS.get_cmdline_user_args():start_game(3)
	if "--obstacles" in OS.get_cmdline_user_args():
		sim.set_course(1)
		build_obstacles()
		course_button.text="场地：绕墙练习 [B]"
	if capture and "--obstacles" in OS.get_cmdline_user_args():
		sim.players[0].pos=Vector2(-550,0)
		sim.command(0,Vector2(700,-200))
		sim.ball=Vector3(-250,-150,80)
		show_routes=true
		paused=true
	elif capture and "--match" in OS.get_cmdline_user_args():
		for i in range(140):sim.advance(0.05)
		paused=true
	elif capture:
		sim.take(0)
		sim.command(0,Vector2(900,300))
		for i in range(50):sim.step_movement();sim.step_ball()
		sim.kick(0,Vector2(1800,0))
		for i in range(8):sim.step_ball()
		paused=true
		actors[0].play("Walk")
		actors[0].advance(0.25)
	update_visuals(0)
	if not capture and not "--match" in OS.get_cmdline_user_args():open_menu()
	else:menu_root.hide()
	if "--menu-preview" in OS.get_cmdline_user_args():open_menu()
	if "--network-preview" in OS.get_cmdline_user_args():network_menu.show_menu()
	if "--ice-menu-preview" in OS.get_cmdline_user_args():
		field_select.select(2);field_select.item_selected.emit(2);open_menu()
	if "--ice-preview" in OS.get_cmdline_user_args():
		field_select.select(2);character_select.select(0);enter_practice()
		sim.players[0].pos=Vector2(-1000,-350);sim.players[1].pos=Vector2(1600,1000)
		sim.ball=Vector3(-300,500,0);sim.velocity=Vector3(28,0,0)
		sim.command(0,Vector2(1000,-350));sim.advance(1.5);sim.stop(0);sim.advance(0.15)
		sim.notice="已按 S 停止，冰面上的人物仍在减速滑行。"
		paused=true;update_visuals(0)
	if "--large-field-preview" in OS.get_cmdline_user_args():
		field_select.select(3);start_game(5)
		sim.advance(5);paused=true;update_visuals(0)
	for field in range(4):
		if ("--scenery-"+str(field)) in OS.get_cmdline_user_args():
			field_select.select(field);start_game(int(sim.arena.fields[field].recommended_team))
			sim.advance(5);paused=true;update_visuals(0)
	if "--injury-preview" in OS.get_cmdline_user_args():
		field_select.select(0);character_select.select(0);enter_practice()
		sim.players[0].pos=Vector2(-350,-200);sim.players[1].pos=Vector2(550,100)
		sim.stop(0);sim.advance(0.12);sim.stop(0);sim.advance(1.5)
		zoom=0.55;focus=Vector3(-3.5,0,2);update_camera()
		paused=true;update_visuals(0)
	if "--tackle-preview" in OS.get_cmdline_user_args():setup_tackle_preview()
	if "--tackle-order-preview" in OS.get_cmdline_user_args():setup_tackle_order_preview()
	if "--hook-tackle-preview" in OS.get_cmdline_user_args():setup_hook_tackle_preview()
	if "--narrow-route-preview" in OS.get_cmdline_user_args():setup_narrow_route_preview()
	if "--goal-entry-preview" in OS.get_cmdline_user_args():setup_goal_entry_preview()
	if "--referee-preview" in OS.get_cmdline_user_args():
		field_select.select(0);start_game(3)
		sim.match_state="playing";sim.bot_enabled=false
		sim.players[sim.controlled].pos=Vector2(-1850,0);sim.players[sim.controlled].body=0
		sim.take(sim.controlled);sim.advance(7.75)
		paused=true;update_visuals(0)
	if "--halftime-preview" in OS.get_cmdline_user_args():
		mode_select.select(2);start_game(3);sim.match_state="playing";sim.bot_enabled=false
		sim.score=[2,1];sim.time_left=0.001;sim.advance(3.1)
		build_pitch();paused=true;update_visuals(0)
	if "--keeper-preview" in OS.get_cmdline_user_args():
		character_select.select(MatchSim.Characters.IDS.find("h00R"));enter_practice()
		sim.players[0].pos=sim.arena.keeper_position(0);sim.players[0].previous=sim.players[0].pos
		sim.players[1].pos=Vector2(1500,600);sim.ball=Vector3(-1730,0,220);sim.velocity=Vector3(-35,0,10)
		sim.submit_command("hold",0);sim.advance(0.23)
		focus=Vector3(-14,0,0);zoom=0.7;update_camera()
		paused=true;update_visuals(0);actors[0].advance(0.23)
	if "--original-goals-preview" in OS.get_cmdline_user_args():
		field_select.select(0);character_select.select(0);enter_practice()
		sim.players[0].pos=Vector2(-1800,0);sim.players[0].previous=sim.players[0].pos
		sim.players[1].pos=Vector2(1500,600);sim.ball=Vector3(-1950,-90,70)
		focus=Vector3(-18,0,0);zoom=0.60;update_camera()
		paused=true;update_visuals(0)
		sim.notice="原地图门框 · 原球门与边界判定"
	if "--result-preview" in OS.get_cmdline_user_args():
		mode_select.select(0);start_game(6);sim.bot_enabled=false
		for team in [0,1,0,0,1,0,0,0,1,0,0,0,0]:
			sim.match_state="playing";sim.elapsed+=43.0
			sim.take(team*6);sim.kick(team*6,Vector2(500,0));sim.take(team*6+1);sim.award_goal(team)
		result_shown=true;open_results();update_visuals(0)
	if "--pillar-preview" in OS.get_cmdline_user_args():
		character_select.select(MatchSim.Characters.IDS.find("h02C"))
		enter_practice()
		sim.players[0].pos=Vector2(-500,0)
		sim.Characters.use(sim,0,Vector2(100,0))
		sim.advance(1.5)
		sim.command(1,Vector2(-700,200))
		show_routes=true
		paused=true
		update_visuals(0)
	if "--mobility-preview" in OS.get_cmdline_user_args():
		character_select.select(MatchSim.Characters.IDS.find("h00R"))
		start_game(3)
		sim.match_state="playing";sim.bot_enabled=false
		var preview_ids=["h00R","h004","h010","h00R","h005","h010"]
		var positions=[Vector2(-700,-200),Vector2(-900,500),Vector2(100,300),Vector2(600,-300),Vector2(1100,600),Vector2(1100,-600)]
		for i in range(6):
			sim.Characters.configure(sim.players[i],preview_ids[i]);sim.players[i].pos=positions[i]
		rebuild_actors()
		sim.set_sprint(3,true);sim.advance(1.1)
		sim.Characters.use(sim,0,Vector2.ZERO)
		sim.set_sprint(1,true)
		sim.take(2);sim.step_ball();sim.Characters.use(sim,2,Vector2.ZERO)
		sim.advance(0.1);sim.command(2,Vector2(1600,300));sim.advance(0.25)
		paused=true
		update_visuals(0)
		actors[0].advance(0.5)
	if "--tricks-preview" in OS.get_cmdline_user_args():
		character_select.select(MatchSim.Characters.IDS.find("h01N"));enter_practice()
		sim.players[0].pos=Vector2(-700,-200);sim.players[1].pos=Vector2(900,500)
		sim.Characters.configure(sim.players[1],"h001");rebuild_actors()
		sim.take(0);sim.step_ball()
		sim.Characters.use(sim,0,Vector2(1500,350))
		sim.Characters.use(sim,1,Vector2(-1800,500))
		sim.advance(0.55);paused=true;update_visuals(0)
	if "--curve-preview" in OS.get_cmdline_user_args():
		character_select.select(MatchSim.Characters.IDS.find("h012"));enter_practice()
		sim.players[0].pos=Vector2(-1400,-100);sim.players[1].pos=Vector2(1700,-1000)
		sim.take(0);sim.step_ball();sim.Characters.use(sim,0,Vector2(1700,-100))
		trail_points.clear();show_trace=true
		for i in range(34):
			sim.advance(sim.BALL_DT)
			update_visuals(sim.BALL_DT)
			trail_points.append(Vector3(sim.ball.x,sim.ball.z+10,-sim.ball.y)/100)
		paused=true;update_visuals(0)
	if "--interactions-preview" in OS.get_cmdline_user_args():setup_interactions_preview()
	if "--effects-preview" in OS.get_cmdline_user_args():setup_effects_preview()
	if "--boundary-preview" in OS.get_cmdline_user_args():setup_boundary_preview()
	if "--final-kits-preview" in OS.get_cmdline_user_args():
		character_select.select(MatchSim.Characters.IDS.find("h01R"));start_game(3)
		sim.match_state="playing";sim.bot_enabled=false
		var ids=["h01R","h027","h029","h005","h012","h00P"]
		var positions=[Vector2(-1000,-250),Vector2(-400,550),Vector2(-600,-750),Vector2(50,-250),Vector2(1100,400),Vector2(1100,-700)]
		for i in range(6):sim.Characters.configure(sim.players[i],ids[i]);sim.players[i].pos=positions[i];sim.players[i].role="field"
		rebuild_actors();sim.ball=Vector3(1500,-900,0)
		sim.Characters.use(sim,1,Vector2(200,550));sim.advance(1.6)
		sim.Characters.use(sim,1,Vector2(-400,-50));sim.advance(0.8)
		sim.players[2].morph_kit="h00P";sim.players[2].morph_casts=3
		sim.Characters.use(sim,0,Vector2(1100,-250));sim.Characters.use(sim,2,Vector2.ZERO)
		sim.advance(0.5);paused=true;update_visuals(0)

func setup_effects_preview():
	start_game(3);sim.match_state="playing";sim.bot_enabled=false
	var ids=["h00P","h003","h00F","h01R","h012","h027"]
	var positions=[Vector2(-900,-480),Vector2(-350,500),Vector2(650,-480),Vector2(1400,700),Vector2(1400,-900),Vector2(800,950)]
	for i in range(6):
		sim.Characters.configure(sim.players[i],ids[i]);sim.players[i].pos=positions[i];sim.players[i].previous=positions[i];sim.players[i].role="field"
	rebuild_actors();sim.take(2);sim.step_ball()
	sim.Characters.use(sim,0,Vector2.ZERO)
	sim.Characters.use(sim,1,Vector2(200,400))
	sim.Characters.use(sim,2,Vector2(1800,-480))
	sim.Characters.use(sim,3,Vector2(500,900))
	for i in range(29):
		sim.advance(1.0/60);update_visuals(1.0/60)
	paused=true;menu_root.hide();sim.notice="原版特效：践踏、迷你黑洞、蓄力与钩绳。"

func setup_narrow_route_preview():
	field_select.select(0);character_select.select(0);enter_practice()
	var key=InputEventKey.new();key.pressed=true;key.keycode=KEY_B
	for i in range(4):_unhandled_input(key)
	show_routes=true;sim.submit_command("move",0,Vector2(0,600));sim.advance(1.2)
	zoom=0.65;focus=Vector3(-2,0,-2.5);update_camera()
	paused=true;update_visuals(0)

func setup_tackle_order_preview():
	field_select.select(0);character_select.select(0);enter_practice()
	sim.players[0].pos=Vector2(-300,-350);sim.players[1].pos=Vector2(-120,-350)
	for p in sim.players:p.body=0;p.angle=0;p.previous_body=0
	sim.ball=Vector3(1200,-700,0)
	sim.submit_command("ability",1,Vector2(1000,-350));sim.submit_command("ability",0,Vector2(1000,-350))
	sim.advance(0.22)
	zoom=0.5;focus=Vector3(0.5,0,3.5);update_camera()
	paused=true;update_visuals(0)

func setup_hook_tackle_preview():
	field_select.select(0);character_select.select(0);enter_practice()
	sim.players[0].pos=Vector2.ZERO
	sim.players[0].angle=PI;sim.players[0].body=PI;sim.players[0].previous_body=PI
	sim.Characters.configure(sim.players[1],"h01R");sim.players[1].pos=Vector2(-850,0)
	sim.players[1].angle=0;sim.players[1].body=0;sim.players[1].previous_body=0
	rebuild_actors()
	sim.ball=Vector3(1400,-900,0)
	sim.submit_command("ability",1,Vector2(500,0));sim.submit_command("ability",0,Vector2(-1600,0))
	sim.advance(0.35)
	zoom=0.5;focus=Vector3(-4,0,0);update_camera()
	paused=true;update_visuals(0)

func setup_goal_entry_preview():
	field_select.select(0);character_select.select(0);enter_practice()
	sim.players[0].pos=Vector2(1595,-200);sim.players[0].body=0;sim.players[0].angle=0
	sim.players[1].pos=Vector2(2250,0);sim.ball=Vector3(0,1000,0)
	sim.submit_command("ability",0,Vector2(2200,-200));sim.advance(0.22)
	zoom=0.55;focus=Vector3(16,0,0);update_camera()
	paused=true;update_visuals(0)

func setup_tackle_preview():
	field_select.select(0);character_select.select(0);enter_practice()
	sim.players[0].pos=Vector2(-600,-600);sim.players[0].body=0
	sim.players[1].pos=Vector2(900,600);sim.ball=Vector3(1200,-700,0)
	sim.Characters.use(sim,0,Vector2(1200,-600));sim.advance(0.39)
	zoom=0.55;focus=Vector3(-3,0,6);update_camera()
	paused=true;update_visuals(0)

func setup_boundary_preview():
	field_select.select(0);field_select.item_selected.emit(0)
	character_select.select(MatchSim.Characters.IDS.find("h026"));start_game(3)
	sim.match_state="playing";sim.bot_enabled=false
	sim.players[0].pos=Vector2(-600,1000);sim.players[0].angle=PI/2;sim.players[0].body=PI/2
	sim.players[1].pos=Vector2(-600,1180)
	sim.players[3].pos=Vector2(-1595,0);sim.players[3].knock=Vector2(-40,0)
	sim.players[4].pos=Vector2(700,500);sim.ball=Vector3(700,-600,0)
	sim.Characters.use(sim,0,Vector2.ZERO);sim.advance(0.31)
	paused=true;update_visuals(0)
	actors[0].advance(0.31)

func setup_interactions_preview():
	character_select.select(MatchSim.Characters.IDS.find("h00P"));start_game(3)
	sim.match_state="playing";sim.bot_enabled=false
	var ids=["h00P","h01N","h02C","h00F","h01R","h012"]
	var positions=[Vector2(-700,-150),Vector2(-850,220),Vector2(500,-300),Vector2(900,400),Vector2(1100,-600),Vector2(1200,900)]
	for i in range(6):
		sim.Characters.configure(sim.players[i],ids[i]);sim.players[i].pos=positions[i];sim.players[i].role="field"
	rebuild_actors()
	sim.take(1);sim.step_ball();sim.Characters.use(sim,1,Vector2(1600,220));sim.kick(1,Vector2(1600,-200))
	sim.Characters.use(sim,0,Vector2.ZERO);sim.Characters.use(sim,2,Vector2(-100,100))
	sim.advance(0.90);paused=true;update_visuals(0)
	for actor in actors:actor.advance(0.2)

func rebuild_actors():
	if is_instance_valid(experience) and is_instance_valid(experience.model_audio):experience.model_audio.clear()
	if is_instance_valid(event_decals):event_decals.clear()
	if is_instance_valid(event_spawns):event_spawns.clear()
	if is_instance_valid(hats):hats.clear()
	for model in morph_models.values():model.queue_free()
	morph_models.clear()
	for actor in actors:actor.queue_free()
	actors.clear()
	for p in sim.players:
		var actor=WCModel.new()
		add_child(actor)
		actor.load_actor(p.character,sim.team_color(p.team))
		actors.append(actor)
		var number=Label3D.new()
		number.name="PlayerNumber"
		number.font=font
		number.text=sim.team_name(p.team).trim_suffix("队")+" "+str(p.number)+( " · 门将" if p.role=="keeper" else "")
		number.font_size=40
		number.pixel_size=0.009
		number.position.y=2.2
		number.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		number.modulate=Color("93bfff") if p.team==0 else Color("ffac92")
		actor.add_child(number)
	gallery_id=sim.players[sim.controlled].character
	unit_name.text=MatchSim.Characters.DATA[gallery_id].name
	for i in range(gallery_select.item_count):
		if gallery_select.get_item_metadata(i)==gallery_id:gallery_select.select(i)
	gallery_select.visible=not sim.match_enabled
	gallery_caption.visible=not sim.match_enabled

func start_network_match(data: Dictionary):
	if is_instance_valid(touch_controls):touch_controls.cancel_all()
	var room=data.room
	sim.networked=true;sim.remote_client=false;sim.network_lineup=room.seats.duplicate(true)
	sim.network_formation=room.config.formation;sim.selected_field=int(room.config.field)
	sim.start_match(int(room.config.size),int(room.config.limit),room.config.minutes*60.0 if int(room.config.mode)==1 else 0.0,int(room.config.mode)==2)
	network.loaded_sim(sim,data.state)
	build_pitch();rebuild_actors();build_obstacles()
	aim="";marker.visible=false;trail_points.clear();paused=false;result_shown=false
	menu_root.hide();results_root.hide();network_menu.screen.hide()
	focus=Vector3.ZERO;zoom=0.78 if mobile_enabled else 1.12*sim.arena.half_size.x/2016.0
	experience.follow_camera=true;update_camera()

func leave_network_match():
	sim.remote_client=false;sim.networked=false;sim.network_lineup=[];sim.human_slots=[];sim.command_sink=Callable()
	sim.start_practice();build_pitch();rebuild_actors();build_obstacles();result_shown=false;results_root.hide()
	open_menu();network_menu.show_menu()

func start_game(size: int):
	if sim.networked:network_menu.show_menu();return
	sim.selected_character=character_select.get_item_metadata(character_select.selected)
	sim.mixed_roster=true
	sim.selected_field=field_select.selected
	var mode=mode_select.selected
	sim.start_match(size,10,600.0 if mode==1 else 0.0,mode==2)
	build_pitch()
	rebuild_actors()
	build_obstacles()
	aim=""
	marker.visible=false
	trail_points.clear()
	paused=false
	result_shown=false
	menu_root.hide()
	results_root.hide()
	focus=Vector3.ZERO
	zoom=0.78 if mobile_enabled else 1.12*sim.arena.half_size.x/2016.0
	update_camera()
	bot_button.text="暂停比赛 [P]"
	course_button.text="比赛：%d 对 %d"%[size,size]
	if is_instance_valid(experience):experience.save_settings()

func enter_practice():
	if sim.networked:network_menu.show_menu();return
	sim.selected_character=character_select.get_item_metadata(character_select.selected)
	sim.selected_field=field_select.selected
	sim.start_practice()
	build_pitch()
	rebuild_actors()
	build_obstacles()
	menu_root.hide()
	results_root.hide()
	paused=false
	result_shown=false
	aim=""
	marker.visible=false
	trail_points.clear()
	focus=Vector3.ZERO
	zoom=0.78 if mobile_enabled else 1.12*sim.arena.half_size.x/2016.0
	update_camera()
	bot_button.text="练习对手：静止 [P]"
	course_button.text="场地："+sim.arena.COURSE_NAMES[sim.arena.course]+" [B]"
	if is_instance_valid(experience):experience.save_settings()

func open_menu():
	if is_instance_valid(network) and network.in_match:network_menu.show_menu();return
	paused=true
	aim=""
	menu_root.show()
	if is_instance_valid(desktop_tools):desktop_tools.hide()
	results_root.hide()
	report_button.visible=sim.match_enabled
	menu_title.text="弹跳足球 · 单机比赛"
	if sim.match_state=="ended":
		menu_title.text=(sim.team_name(sim.winner)+"获胜")+"    %d : %d"%[sim.score[0],sim.score[1]]
	resume_button.visible=sim.match_state!="ended"

func close_menu():
	if sim.match_state=="ended":return
	menu_root.hide()
	paused=false
	if sim.notice=="已暂停，点继续返回比赛。":sim.notice="比赛继续。"

func open_results():
	if not sim.match_enabled:return
	paused=true;aim="";menu_root.hide();results_root.show()
	results_title.text=((sim.team_name(sim.winner)+"获胜") if sim.match_state=="ended" else "本场比赛记录")+"    %d : %d"%[sim.score[0],sim.score[1]]
	for team in [0,1]:results_teams[team].text=MatchReport.team_text(sim,team)
	results_history.text=MatchReport.history_text(sim)

func build_match_panels():
	results_root=Control.new();results_root.size=Vector2(1440,900);$HUD.add_child(results_root)
	var shade=ColorRect.new();shade.color=Color(0.015,0.025,0.02,0.86);shade.size=Vector2(1440,900);results_root.add_child(shade)
	var backdrop=panel(Rect2(200,65,1040,770));backdrop.reparent(results_root)
	results_title=label("比赛记录",Vector2(245,95),30);results_title.reparent(results_root)
	var caption=label("个人统计",Vector2(245,145),16,Color("b9c5a8"));caption.reparent(results_root)
	var history_caption=label("进球记录 · 比赛有效时间",Vector2(880,145),16,Color("b9c5a8"));history_caption.reparent(results_root)
	for team in [0,1]:
		var column=label("",Vector2(245+team*315,190),19,Color("93bfff") if team==0 else Color("ffac92"))
		column.reparent(results_root);results_teams.append(column)
	results_history=RichTextLabel.new();results_history.position=Vector2(880,190);results_history.size=Vector2(320,510)
	results_history.add_theme_font_override("normal_font",font);results_history.add_theme_font_size_override("normal_font_size",16)
	results_root.add_child(results_history)
	var menu_button=button("返回比赛菜单",Rect2(245,755,285,45),open_menu);menu_button.reparent(results_root)
	var replay=button("再来一场",Rect2(560,755,285,45),func():start_game(sim.team_size));replay.reparent(results_root)
	results_root.hide()
	half_panel=panel(Rect2(430,250,580,220))
	half_label=label("中场休息",Vector2(455,275),23);half_label.reparent(half_panel)
	var hint_label=label("更换当前角色，统计保留；休息结束自动进入下半场。",Vector2(455,325),16);hint_label.reparent(half_panel)
	half_select=OptionButton.new();half_select.position=Vector2(25,125);half_select.size=Vector2(530,46)
	half_select.add_theme_font_override("font",font);half_select.add_theme_font_size_override("font_size",19)
	for id in MatchSim.Characters.IDS:
		half_select.add_item(MatchSim.Characters.DATA[id].name);half_select.set_item_metadata(half_select.item_count-1,id)
	half_select.item_selected.connect(func(index):
		if sim.choose_halftime_character(half_select.get_item_metadata(index)):rebuild_actors())
	half_panel.add_child(half_select);half_panel.hide()

func material(color: Color) -> StandardMaterial3D:
	var mat=StandardMaterial3D.new()
	mat.albedo_color=color
	mat.roughness=1.0
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	if color.a<1:
		mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

func box(size: Vector3,p: Vector3,color: Color) -> MeshInstance3D:
	var node=MeshInstance3D.new()
	var mesh=BoxMesh.new()
	mesh.size=size
	node.mesh=mesh
	node.material_override=material(color)
	add_child(node)
	node.position=p
	return node

func line(a: Vector3,b: Vector3,width: float,color: Color):
	var mesh=ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var side=(b-a).cross(Vector3.UP).normalized()*width/2
	for v in [a-side,a+side,b+side,a-side,b+side,b-side]:
		mesh.surface_set_normal(Vector3.UP)
		mesh.surface_add_vertex(v)
	mesh.surface_end()
	var node=MeshInstance3D.new()
	node.mesh=mesh
	node.material_override=material(color)
	add_child(node)

func ring(radius: float,color: Color) -> MeshInstance3D:
	var mesh=TorusMesh.new()
	mesh.inner_radius=radius-0.025
	mesh.outer_radius=radius+0.025
	mesh.rings=48
	mesh.ring_segments=6
	var node=MeshInstance3D.new()
	node.mesh=mesh
	node.material_override=material(color)
	add_child(node)
	return node

func disc(radius: float,color: Color) -> MeshInstance3D:
	var mesh=CylinderMesh.new()
	mesh.top_radius=radius
	mesh.bottom_radius=radius
	mesh.height=0.005
	var node=MeshInstance3D.new()
	node.mesh=mesh
	node.material_override=material(color)
	add_child(node)
	return node

func build_world():
	var env=WorldEnvironment.new()
	var e=Environment.new()
	e.background_mode=Environment.BG_COLOR
	e.background_color=Color("17271f")
	e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color=Color("b0c2b6")
	e.ambient_light_energy=0.30
	e.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	env.environment=e
	add_child(env)
	var light=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-52,-35,0)
	light.light_color=Color("fff1ce")
	light.light_energy=0.60
	light.shadow_enabled=true
	add_child(light)
	camera=Camera3D.new()
	add_child(camera)
	camera.fov=45
	camera.far=180
	update_camera()
	build_pitch()

func build_pitch():
	shown_sides_swapped=sim.arena.sides_swapped
	if is_instance_valid(pitch_nodes):pitch_nodes.free()
	pitch_nodes=Node3D.new();add_child(pitch_nodes)
	var existing=get_children()
	var half=sim.arena.half_size/100
	var dx=half.x-20.16
	field_scenery=FieldScenery.new();add_child(field_scenery)
	field_scenery.load_field(sim.arena.data.id)
	original_goals=OriginalGoals.new();add_child(original_goals)
	original_goals.load_field(sim.arena,field_scenery)
	var chalk=Color("c9cda0")
	for z in [-half.y,half.y]:line(Vector3(-half.x,0.012,z),Vector3(half.x,0.012,z),0.06,chalk)
	for x in [-half.x,half.x]:line(Vector3(x,0.012,-half.y),Vector3(x,0.012,half.y),0.06,chalk)
	line(Vector3(0,0.012,-half.y),Vector3(0,0.012,half.y),0.06,chalk)
	var center=ring(3.2,chalk)
	center.position.y=0.025
	disc(0.1,chalk).position.y=0.012
	# Use the actual protected-area edges. The old hard-coded front line
	# was 160 Warcraft units behind GoalBlock, making rejection look premature.
	for team in range(2):
		var r: Rect2=sim.arena.guards[team][0]
		var corners=[r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]
		for i in range(4):
			var a: Vector2=corners[i];var b: Vector2=corners[(i+1)%4]
			line(Vector3(a.x/100,0.02,-a.y/100),Vector3(b.x/100,0.02,-b.y/100),0.06,chalk)
	# Draw the actual playable outline, including both narrow goal corridors.
	var f=sim.arena.field_rect;var left=sim.arena.rect(sim.arena.data.regions.Goal_1_Area);var right=sim.arena.rect(sim.arena.data.regions.Goal_2_Area)
	var outline=[f.position,Vector2(f.end.x,f.position.y),right.position,Vector2(right.end.x,right.position.y),right.end,Vector2(f.end.x,right.end.y),f.end,Vector2(f.position.x,f.end.y),Vector2(f.position.x,left.end.y),Vector2(left.position.x,left.end.y),left.position,Vector2(f.position.x,left.position.y)]
	for i in range(outline.size()):
		var a: Vector2=outline[i]
		var b: Vector2=outline[(i+1)%outline.size()]
		line(Vector3(a.x/100,0.025,-a.y/100),Vector3(b.x/100,0.025,-b.y/100),0.055,Color("e0bd77"))
	for team in [0,1]:
		var r: Rect2=sim.arena.guards[team][0]
		var tint=Color(0.2,0.45,0.85,0.12) if team==0 else Color(0.85,0.3,0.2,0.12)
		box(Vector3(r.size.x/100,0.008,r.size.y/100),Vector3(r.get_center().x/100,0.006,-r.get_center().y/100),tint)
	for child in get_children():
		if not existing.has(child):child.reparent(pitch_nodes)

func build_obstacles():
	if is_instance_valid(obstacle_nodes):obstacle_nodes.free()
	obstacle_nodes=Node3D.new()
	add_child(obstacle_nodes)
	for o in sim.arena.obstacles:
		var r: Rect2=o.rect
		var center=r.get_center()
		var p=Vector3(center.x/100,o.height/200,-center.y/100)
		var c=Color("64664b") if o.height<100 else Color("4b4638")
		var wall=box(Vector3(r.size.x/100,o.height/100,r.size.y/100),p,c)
		wall.reparent(obstacle_nodes)
		var cap=box(Vector3(r.size.x/100+0.05,0.06,r.size.y/100+0.05),Vector3(p.x,o.height/100+0.02,p.z),Color("8a7957"))
		cap.reparent(obstacle_nodes)
		if sim.arena.course==4:continue # Keep the narrow playable strip unobscured.
		var text=Label3D.new()
		text.font=font
		text.text="低墙 · 可高球越过" if o.height<100 else "障碍墙"
		text.font_size=36
		text.pixel_size=0.012
		text.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		text.position=Vector3(p.x,o.height/100+0.4,p.z)
		obstacle_nodes.add_child(text)
	if is_instance_valid(debug_nodes):debug_nodes.free()
	debug_nodes=Node3D.new()
	add_child(debug_nodes)
	debug_rings.clear()
	for p in sim.players:
		var circle=ring(p.radius/100,Color("64fff0"))
		circle.reparent(debug_nodes)
		debug_rings.append(circle)
	route_mesh=MeshInstance3D.new()
	route_mesh.material_override=material(Color("8cfff4"))
	debug_nodes.add_child(route_mesh)

func cycle_course():
	if sim.networked:return
	if sim.match_enabled:open_menu();return
	sim.set_course(sim.arena.course+1)
	build_obstacles()
	course_button.text="场地："+sim.arena.COURSE_NAMES[sim.arena.course]+" [B]"
	aim=""
	marker.visible=false
	trail_points.clear()

func update_routes():
	debug_nodes.visible=show_routes
	if not show_routes:return
	for i in range(debug_rings.size()):
		debug_rings[i].position=actors[i].position+Vector3(0,0.04,0)
	var p=sim.players[sim.controlled]
	if p.path.is_empty():route_mesh.visible=false;return
	route_mesh.visible=true
	var mesh=ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	mesh.surface_add_vertex(Vector3(p.pos.x/100,0.08,-p.pos.y/100))
	for point in p.path:mesh.surface_add_vertex(Vector3(point.x/100,0.08,-point.y/100))
	mesh.surface_end()
	route_mesh.mesh=mesh

func update_camera():
	camera.position=focus+Vector3(0,34,23)*zoom
	camera.look_at(focus,Vector3.UP)

func panel(rect: Rect2) -> Panel:
	var node=Panel.new()
	node.position=rect.position
	node.size=rect.size
	var s=StyleBoxFlat.new()
	s.bg_color=Color(0.045,0.075,0.07,0.96)
	s.border_color=Color("53634a")
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	node.add_theme_stylebox_override("panel",s)
	$HUD.add_child(node)
	return node

func label(text: String,p: Vector2,size: int,color: Color=Color("e1e6cb")) -> Label:
	var l=Label.new()
	l.text=text
	l.position=p
	l.add_theme_font_override("font",font)
	l.add_theme_font_size_override("font_size",size)
	l.add_theme_color_override("font_color",color)
	l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(l)
	return l

func button(text: String,rect: Rect2,action: Callable) -> Button:
	var b=Button.new()
	b.text=text
	b.position=rect.position
	b.size=rect.size
	b.add_theme_font_override("font",font)
	b.add_theme_font_size_override("font_size",16)
	b.focus_mode=Control.FOCUS_NONE
	for pair in [["normal","26372d"],["hover","40523a"],["pressed","536c44"]]:
		var style=StyleBoxFlat.new()
		style.bg_color=Color(pair[1])
		style.border_color=Color("65734c")
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		b.add_theme_stylebox_override(pair[0],style)
	b.pressed.connect(action)
	$HUD.add_child(b)
	return b

func build_ui():
	var ui=CanvasLayer.new()
	ui.name="HUD"
	add_child(ui)
	panel(Rect2(22,20,210,56))
	label("弹跳足球",Vector2(42,29),26)
	panel(Rect2(529,20,382,72))
	score_label=label("蓝队    0  :  0    红队",Vector2(566,35),25)
	clock_label=label("",Vector2(529,71),13,Color("d4c295"))
	clock_label.size.x=382;clock_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var tools_start=$HUD.get_child_count()
	bot_button=button("练习对手：静止 [P]",Rect2(1150,20,266,38),toggle_bot)
	button("重新开局 [F5]",Rect2(1150,65,128,34),reset_practice)
	button("轨迹 [Shift+G]",Rect2(1288,65,128,34),func():show_trace=not show_trace)
	course_button=button("场地：标准球场 [B]",Rect2(1150,108,266,34),cycle_course)

	refresh_button=button("刷新冷却 / 补魔 [F6]",Rect2(1150,192,266,34),func():sim.submit_command("practice_refresh",sim.controlled))
	refresh_button.tooltip_text="仅自由练习：技能结束后刷新冷却并补满魔法，保留人物位置和场地。"
	recall_button=button("拿回足球 [F7]",Rect2(1150,234,266,34),func():sim.submit_command("practice_ball",sim.controlled))
	recall_button.tooltip_text="仅自由练习：将真球交给当前角色；球被钩住或支配时需先结束技能。"
	var tool_nodes=$HUD.get_children().slice(tools_start)
	desktop_tools=panel(Rect2(1128,65,288,346))
	for node in tool_nodes:
		node.reparent(desktop_tools);node.position-=Vector2(1138,8)
	desktop_tools.hide()
	desktop_tools_button=button("更多",Rect2(1150,20,128,36),func():desktop_tools.visible=not desktop_tools.visible)
	button("菜单 [Esc]",Rect2(1288,20,128,36),open_menu)
	route_label=label("",Vector2(26,111),15,Color("d4c295"))
	surface_hint=label("冰面：右键积累滑行；M 选点移动；S 停止后仍有惯性。",Vector2(26,132),13,Color("a5d9ed"))
	for note in [route_label,surface_hint]:
		note.add_theme_color_override("font_outline_color",Color("14231f"))
		note.add_theme_constant_override("outline_size",4)
	hold_button=button("H  守门起跳",Rect2(24,150,240,36),func():sim.submit_command("hold",sim.controlled))
	hold_button.tooltip_text="站定；本方门区内、不持有真球时起跳，冷却 2 秒。按当前朝向施加向前上方的冲量。"
	panel(Rect2(22,769,1394,110))
	unit_name=label("铁壁萨满",Vector2(44,783),24)
	team_label=label("蓝队  /  训练模式",Vector2(45,819),14,Color("a3b395"))
	mana_bar=ProgressBar.new()
	mana_bar.position=Vector2(44,850)
	mana_bar.size=Vector2(205,9)
	mana_bar.show_percentage=false
	for type in ["background","fill"]:
		var style=StyleBoxFlat.new()
		style.bg_color=Color("73b8ed") if type=="fill" else Color("253b47")
		style.set_corner_radius_all(3)
		mana_bar.add_theme_stylebox_override(type,style)
	$HUD.add_child(mana_bar)
	button("W  射门",Rect2(282,790,148,61),func():set_aim("kick"))
	e_button=button("E  冲刺",Rect2(442,790,148,61),func():sim.submit_command("sprint",sim.controlled))
	q_button=button("Q  铁壁滑铲",Rect2(602,790,180,61),choose_ability)
	r_button=button("R  另一技能",Rect2(602,823,180,28),func():choose_ability(true))
	r_button.hide()
	status_label=label("",Vector2(810,786),17)
	status_label.size=Vector2(580,30)
	hint=label("右键移动 · W 传射 · Q 角色技能 · E 冲刺 · S 停止\nTab 切队友 · F 呼叫传球 · 空格居中 · Esc 菜单",Vector2(810,822),13,Color("a3b395"))
	phase_label=label("",Vector2(600,370),42)
	phase_label.size=Vector2(240,80)
	phase_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	gallery_caption=label("练习换人（切换会重置当前练习）",Vector2(26,709),12,Color("a3b395"))
	actor_catalog=JSON.parse_string(FileAccess.get_file_as_string("res://research/actors.json"))
	gallery_select=OptionButton.new()
	gallery_select.position=Vector2(24,732)
	gallery_select.size=Vector2(258,30)
	gallery_select.add_theme_font_override("font",font)
	gallery_select.add_theme_font_size_override("font_size",14)
	for actor in actor_catalog:
		if actor.id=="h000": continue
		gallery_select.add_item(actor.name)
		gallery_select.set_item_metadata(gallery_select.item_count-1,actor.id)
		if actor.id=="h005":gallery_select.select(gallery_select.item_count-1)
	gallery_select.item_selected.connect(select_model)
	$HUD.add_child(gallery_select)

func build_menu():
	menu_root=Control.new()
	menu_root.size=Vector2(1440,900)
	$HUD.add_child(menu_root)
	var shade=ColorRect.new()
	shade.color=Color(0.015,0.025,0.02,0.78)
	shade.size=Vector2(1440,900)
	menu_root.add_child(shade)
	var backdrop=panel(Rect2(300,50,840,800))
	backdrop.reparent(menu_root)
	menu_title=label("弹跳足球 · 单机比赛",Vector2(345,85),30)
	menu_title.reparent(menu_root)
	var subtitle=label("操控主队，与电脑队友配合对战客队。",Vector2(345,132),18,Color("b9c5a8"))
	subtitle.reparent(menu_root)
	mode_select=OptionButton.new();mode_select.position=Vector2(345,172);mode_select.size=Vector2(750,40)
	mode_select.add_theme_font_override("font",font);mode_select.add_theme_font_size_override("font_size",18)
	for text in ["进球赛 · 先得 10 球（原版默认）","计时赛 · 10 分钟，平局追加 2 分钟","上下半场 · 各 10 分钟，中场换边，可换角色"]:mode_select.add_item(text)
	menu_root.add_child(mode_select)
	var caption=label("选择开场角色",Vector2(345,224),17)
	caption.reparent(menu_root)
	character_select=OptionButton.new()
	character_select.position=Vector2(345,254)
	character_select.size=Vector2(750,40)
	character_select.add_theme_font_override("font",font)
	character_select.add_theme_font_size_override("font_size",20)
	for id in MatchSim.Characters.IDS:
		var data=MatchSim.Characters.DATA[id]
		character_select.add_item(data.name+"  ·  "+data.skill)
		character_select.set_item_metadata(character_select.item_count-1,id)
	menu_root.add_child(character_select)
	character_note=label(MatchSim.Characters.DATA.h005.description,Vector2(345,303),15,Color("b9c5a8"))
	character_note.size=Vector2(750,44);character_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	character_note.reparent(menu_root)
	character_select.item_selected.connect(func(index):character_note.text=MatchSim.Characters.DATA[character_select.get_item_metadata(index)].description)
	field_select=OptionButton.new()
	field_select.position=Vector2(345,350);field_select.size=Vector2(750,36)
	field_select.add_theme_font_override("font",font);field_select.add_theme_font_size_override("font_size",18)
	for field in sim.arena.fields:field_select.add_item(field.name+" · "+("大场" if field.block_width>32 else "中场")+" · 原图推荐 %d 对 %d"%[field.recommended_team,field.recommended_team])
	menu_root.add_child(field_select)
	field_note=label("草地：正常摩擦与地面运动。",Vector2(345,386),14,Color("b9c5a8"));field_note.reparent(menu_root)
	field_select.item_selected.connect(func(index):field_note.text="冰面：球滚得更远；右键移动积累滑行，按 S 后仍有惯性。" if index in [2,3] else "草地：正常摩擦与地面运动。")
	for option in [["1 对 1",1,345],["2 对 2",2,605],["3 对 3",3,865],["4 对 4",4,345],["5 对 5",5,605],["6 对 6",6,865]]:
		var count=int(option[1])
		var b=button(option[0],Rect2(option[2],410 if count<=3 else 465,230,45),func():start_game(count))
		b.reparent(menu_root)
	var practice=button("自由练习 / 障碍练习",Rect2(345,525,750,42),enter_practice)
	practice.reparent(menu_root)
	resume_button=button("继续当前场景",Rect2(345,580,750,42),close_menu)
	resume_button.reparent(menu_root)
	report_button=button("本场统计与进球记录",Rect2(345,632,750,42),open_results);report_button.reparent(menu_root)
	var note=label("W / 定点技能按 Q 后左键选点；其他技能按 Q 立即施放。\nTab 切队友 · F 呼叫传球 · M 选点移动 · 右键移动/取消。\n已接入 %d 名角色；电脑队伍会搭配这些角色。"%MatchSim.Characters.IDS.size(),Vector2(345,690),16,Color("a3b395"))
	note.reparent(menu_root)
	injury_toggle=CheckButton.new();injury_toggle.position=Vector2(345,780);injury_toggle.size=Vector2(470,38)
	injury_toggle.text="允许双击 S 假摔"
	injury_toggle.add_theme_font_override("font",font);injury_toggle.add_theme_font_size_override("font_size",17)
	injury_toggle.button_pressed=sim.fake_injury_enabled
	injury_toggle.tooltip_text="未持有真球时快速按两次 S 播放倒地动作；仍可接球和碰撞。右键移动可起身。"
	injury_toggle.toggled.connect(func(enabled):sim.fake_injury_enabled=enabled)
	menu_root.add_child(injury_toggle)
	var quit_button=button("退出游戏",Rect2(925,780,170,38),func():get_tree().quit())
	quit_button.reparent(menu_root)
	language_select=OptionButton.new();menu_root.add_child(language_select)
	language_select.position=Vector2(850,78);language_select.size=Vector2(245,42)
	language_select.add_theme_font_override("font",font);language_select.add_theme_font_size_override("font_size",17)
	for language_caption in Language.LABELS:language_select.add_item(language_caption)
	language_select.select(Language.OPTIONS.find(Language.choice))
	language_select.item_selected.connect(change_language)

func change_language(index: int):
	if index<0 or index>=Language.OPTIONS.size():return
	Language.apply(Language.OPTIONS[index])
	language_select.select(index)
	experience.preferences.set_value("play","language",Language.choice)
	experience.save_settings()
	if is_instance_valid(touch_controls):
		touch_controls.pick_language.select(index)
		touch_controls.frame(0)

func select_model(index: int):
	var id=gallery_select.get_item_metadata(index)
	if MatchSim.Characters.DATA.has(id):
		sim.selected_character=id
		for i in range(character_select.item_count):
			if character_select.get_item_metadata(i)==id:character_select.select(i)
		character_note.text=MatchSim.Characters.DATA[id].description
		sim.reset()
		rebuild_actors()
		aim=""
		sim.notice=MatchSim.Characters.DATA[id].description
		return
	actors[sim.controlled].queue_free()
	var actor=WCModel.new()
	add_child(actor)
	actor.load_actor(id,Color("4f98ff"))
	actors[sim.controlled]=actor
	gallery_id=id
	unit_name.text=gallery_select.get_item_text(index)
	sim.notice="外观预览；技能仍使用"+MatchSim.Characters.DATA[sim.players[sim.controlled].character].name+"配置。"

func choose_ability(secondary: bool=false):
	var p=sim.players[sim.controlled]
	var kit=MatchSim.Characters.kit(p)
	if not MatchSim.Characters.q_available(p,secondary):return
	if secondary and not kit.has("secondary"):return
	if kit.kind in ["powershot","possess","curve","trickster"] and sim.holder!=sim.controlled:sim.notice="持有真球后才能使用"+kit.skill+"。";return
	if kit.kind=="angel" and not sim.has_ball(sim.controlled):sim.notice="持球后才能使用"+kit.skill+"。";return
	if kit.kind=="pillar" and aim=="ability" and not secondary:
		sim.submit_command("ability",sim.controlled,p.pos);aim="";return
	if not p.hook.is_empty():sim.submit_command("ability_secondary" if secondary else "ability",sim.controlled);return
	if kit.targeted:
		aim="ability_secondary" if secondary else "ability"
		sim.notice="左键选择"+(kit.secondary if secondary else kit.skill)+"目标；右键或 Esc 取消。"
		if kit.kind=="pillar":sim.notice="左键选图腾位置 · 再按 Q 放在脚下 · 右键或 Esc 取消。"
		if mobile_enabled:sim.notice="轻点球场选择"+(kit.secondary if secondary else kit.skill)+"目标；点取消可退出瞄准。"
	else:sim.submit_command("ability",sim.controlled)

func toggle_bot():
	if sim.networked:open_menu();return
	if sim.match_enabled:open_menu();return
	sim.bot_enabled=not sim.bot_enabled
	bot_button.text="练习对手：追球 [P]" if sim.bot_enabled else "练习对手：静止 [P]"
	if not sim.bot_enabled:sim.stop(1,false)

func reset_practice():
	if sim.networked:return
	if sim.match_enabled:start_game(sim.team_size);return
	sim.reset()
	aim=""
	trail_points.clear()
	marker.visible=false

func set_aim(which: String):
	if which=="kick" and not mobile_enabled and not sim.has_ball(sim.controlled):
		sim.notice="先靠近足球，拿到球后再射门。"
		return
	if which=="tackle" and sim.players[sim.controlled].cooldown>0:return
	aim=which
	sim.notice="左键选择移动地点 · 右键或 Esc 取消" if which=="move_order" else ("左键选择射门方向 · 右键或 Esc 取消" if which=="kick" else "左键选择滑铲方向 · 右键或 Esc 取消")
	if mobile_enabled:sim.notice="轻点球场选择方向，拖动可预览；点取消退出瞄准。"

func ground_point(screen: Vector2) -> Vector2:
	var start=camera.project_ray_origin(screen)
	var direction=camera.project_ray_normal(screen)
	var distance=-start.y/direction.y
	var point=start+direction*distance
	return Vector2(point.x*100,-point.z*100)

func _unhandled_input(event):
	if is_instance_valid(network_menu) and network_menu.screen.visible:return
	if mobile_enabled:return
	if is_instance_valid(franchise) and franchise.panel.visible:
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:franchise.close()
		return
	if results_root.visible:
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:open_menu()
		return
	if menu_root.visible:
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:close_menu()
		return
	if is_instance_valid(aftermath_controls) and aftermath_controls.input(event):return
	if sim.match_state=="halftime":
		if event is InputEventKey and event.pressed:
			if event.keycode in [KEY_ESCAPE,KEY_P]:open_menu()
			elif event.keycode==KEY_F5:reset_practice()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP:
			zoom=clampf(zoom-0.08,0.55,1.4);update_camera()
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:
			zoom=clampf(zoom+0.08,0.55,1.4);update_camera()
		elif event.button_index==MOUSE_BUTTON_RIGHT:
			if aim!="":aim="";sim.notice="已取消选点。";return
			var target=ground_point(event.position)
			sim.submit_command("move",sim.controlled,target)
			marker.visible=true
		elif event.button_index==MOUSE_BUTTON_LEFT and aim!="":
			var target=ground_point(event.position)
			if aim=="move_order":marker.visible=true
			sim.submit_command(aim,sim.controlled,target)
			aim=""
		elif event.button_index==MOUSE_BUTTON_LEFT and is_instance_valid(biz_tree):
			biz_tree.try_select(event.position)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_M:set_aim("move_order")
			KEY_W:set_aim("kick")
			KEY_E:sim.submit_command("sprint",sim.controlled)
			KEY_Q:choose_ability()
			KEY_S:sim.submit_command("stop",sim.controlled)
			KEY_H:sim.submit_command("hold",sim.controlled)
			KEY_R:
				if MatchSim.Characters.kit(sim.players[sim.controlled]).has("secondary"):choose_ability(true)
				elif sim.players[sim.controlled].character!="h029":reset_practice()
			KEY_F1:sim.submit_command("morph_reset",sim.controlled)
			KEY_F5:reset_practice()
			KEY_F6:sim.submit_command("practice_refresh",sim.controlled)
			KEY_F7:sim.submit_command("practice_ball",sim.controlled)
			KEY_P:toggle_bot()
			KEY_G:
				if event.shift_pressed:show_trace=not show_trace
				else:sim.submit_command("shout",sim.controlled)
			KEY_T:sim.submit_command("taunt",sim.controlled)
			KEY_A:sim.submit_command("sadface",sim.controlled)
			KEY_B:cycle_course()
			KEY_F2:show_routes=not show_routes
			KEY_TAB:sim.switch_player();aim=""
			KEY_F:sim.call_for_pass()
			KEY_ESCAPE:
				if aim!="":aim=""
				else:open_menu()
			KEY_SPACE:focus=Vector3(sim.players[sim.controlled].pos.x/100,0,-sim.players[sim.controlled].pos.y/100);update_camera()

func _process(delta):
	if is_instance_valid(perf):perf.begin_frame()
	var profile_start=Time.get_ticks_usec()
	if not paused:
		var pan=Vector3(Input.get_axis("ui_left","ui_right"),0,Input.get_axis("ui_up","ui_down"))
		if pan.length()>0:
			focus+=pan*delta*18;update_camera()
			if is_instance_valid(experience):experience.follow_camera=false
		if not sim.remote_client:sim.advance(minf(delta,0.1))
	if sim.match_state=="ended" and sim.reset_delay<=0 and not result_shown:
		result_shown=true
		open_results()
	if sim.arena.sides_swapped!=shown_sides_swapped:build_pitch()
	var simulation_end=Time.get_ticks_usec()
	update_visuals(delta if not paused else 0.0)
	var visuals_end=Time.get_ticks_usec()
	if is_instance_valid(experience):experience.frame(delta)
	if is_instance_valid(touch_controls):touch_controls.frame(delta)
	if is_instance_valid(aftermath_controls):aftermath_controls.frame()
	if is_instance_valid(perf):
		var end=Time.get_ticks_usec()
		var profile=visual_profile.duplicate()
		profile.merge(sim.profile)
		profile.merge({"sim_ms":(simulation_end-profile_start)/1000.0,"visual_ms":(visuals_end-simulation_end)/1000.0,"ui_ms":(end-visuals_end)/1000.0,"cpu_ms":(end-profile_start)/1000.0})
		perf.end_frame(profile)
	if capture:
		capture_frames+=1
		if capture_frames==8:
			await RenderingServer.frame_post_draw
			var filename="obstacle-preview.png" if "--obstacles" in OS.get_cmdline_user_args() else ("singleplayer-preview.png" if "--match" in OS.get_cmdline_user_args() else "3d-preview.png")
			if "--menu-preview" in OS.get_cmdline_user_args():filename="menu-preview.png"
			if "--pillar-preview" in OS.get_cmdline_user_args():filename="pillar-preview.png"
			if "--mobility-preview" in OS.get_cmdline_user_args():filename="mobility-preview.png"
			if "--tricks-preview" in OS.get_cmdline_user_args():filename="tricks-preview.png"
			if "--curve-preview" in OS.get_cmdline_user_args():filename="curve-preview.png"
			if "--final-kits-preview" in OS.get_cmdline_user_args():filename="final-kits-preview.png"
			if "--large-field-preview" in OS.get_cmdline_user_args():filename="large-field-preview.png"
			if "--referee-preview" in OS.get_cmdline_user_args():filename="referee-preview.png"
			if "--halftime-preview" in OS.get_cmdline_user_args():filename="halftime-preview.png"
			if "--result-preview" in OS.get_cmdline_user_args():filename="result-preview.png"
			if "--keeper-preview" in OS.get_cmdline_user_args():filename="keeper-preview.png"
			if "--interactions-preview" in OS.get_cmdline_user_args():filename="interactions-preview.png"
			if "--ice-preview" in OS.get_cmdline_user_args():filename="ice-preview.png"
			if "--ice-menu-preview" in OS.get_cmdline_user_args():filename="ice-menu-preview.png"
			if "--boundary-preview" in OS.get_cmdline_user_args():filename="boundary-preview.png"
			if "--injury-preview" in OS.get_cmdline_user_args():filename="injury-preview.png"
			if "--tackle-preview" in OS.get_cmdline_user_args():filename="tackle-preview.png"
			if "--tackle-order-preview" in OS.get_cmdline_user_args():filename="tackle-order-preview.png"
			if "--hook-tackle-preview" in OS.get_cmdline_user_args():filename="hook-tackle-preview.png"
			if "--narrow-route-preview" in OS.get_cmdline_user_args():filename="narrow-route-preview.png"
			if "--goal-entry-preview" in OS.get_cmdline_user_args():filename="goal-entry-preview.png"
			if "--effects-preview" in OS.get_cmdline_user_args():filename="effects-preview.png"
			if "--original-goals-preview" in OS.get_cmdline_user_args():filename="original-goals-preview.png"
			for field in range(4):
				if ("--scenery-"+str(field)) in OS.get_cmdline_user_args():filename="scenery-"+str(field)+"-preview.png"
			if mobile_enabled:filename="mobile-"+filename
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://research/"+filename))
			get_tree().quit()

func _notification(what):
	if what==NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_instance_valid(touch_controls):touch_controls.back()
		elif is_instance_valid(menu_root):open_menu()
	elif what==NOTIFICATION_APPLICATION_PAUSED:
		if is_instance_valid(touch_controls):touch_controls.cancel_all()
		if is_instance_valid(experience):experience.background_pause()
	elif what==NOTIFICATION_WM_CLOSE_REQUEST:
		if is_instance_valid(experience):experience.save_settings()
		get_tree().quit()

func update_visuals(delta: float):
	if is_instance_valid(event_decals):event_decals.advance(delta)
	if is_instance_valid(event_spawns):event_spawns.advance(delta)
	var visual_start=Time.get_ticks_usec()
	if is_instance_valid(original_goals) and original_goals.visible:original_goals.advance(delta)
	var goals_end=Time.get_ticks_usec()
	route_label.visible=show_routes
	hold_button.visible=sim.KeeperRules.eligible(sim,sim.controlled)
	surface_hint.visible=sim.SurfaceRules.icy(sim) and (desktop_tools.visible or show_routes)
	refresh_button.visible=not sim.match_enabled
	recall_button.visible=not sim.match_enabled
	var alpha=clampf((sim.timeline-sim.next_move+MatchSim.MOVE_DT)/MatchSim.MOVE_DT,0,1) if not paused else 1.0
	var ball_alpha=clampf((sim.timeline-sim.next_ball+MatchSim.BALL_DT)/MatchSim.BALL_DT,0,1) if not paused else 1.0
	for i in range(actors.size()):
		var p=sim.players[i]
		actors[i].set_team_color(sim.team_color(p.team))
		var number=actors[i].get_node_or_null("PlayerNumber")
		if number!=null:
			number.text=str(p.get("nickname",sim.team_name(p.team).trim_suffix("队")+" "+str(p.number)))+(" · 门将" if p.role=="keeper" else "")
			number.modulate=sim.team_color(p.team).lightened(.35)
		var position: Vector2=p.previous.lerp(p.pos,alpha)
		actors[i].position=Vector3(position.x/100,lerpf(p.previous_z,p.z,ball_alpha)/100,-position.y/100)
		actors[i].rotation.y=lerp_angle(p.previous_body,p.body,alpha)
		actors[i].visible=sim.unit_present(i) and p.possess_time<=0 and not (p.invisible and p.team!=sim.players[sim.controlled].team)
		actors[i].visibility_amount=0.4 if p.invisible else 1.0
		actors[i].tint=Color(1,155.0/255,155.0/255) if p.character=="h026" and p.sprint else Color.WHITE
		actors[i].scale=Vector3.ONE*(float(actors[i].data.actor.scale) if p.flight_steps<=0 else lerpf(0.5,1.8,p.flight_steps/4.0))
		actors[i].rate=1.0
		var animation_delta=delta
		if p.injury_pose:
			actors[i].play("Death")
			var age=maxf(0,sim.timeline-p.injury_start)
			animation_delta=maxf(0,age-actors[i].animation_time) if delta>0 else 0.0
			if delta<=0:actors[i].animation_time=age
		elif p.flip_time>0:
			actors[i].play("Stand - 3")
			actors[i].rate=4.0 if p.flip_time>0.99 else 0.41
		elif p.character=="h004" and p.sprint:actors[i].play("Walk");actors[i].rate=4.0
		elif p.action>0:
			actors[i].play(p.get("action_clip","Spell"))
			if p.ability_kind=="smash" and p.ability_delay>0:actors[i].rate=2.0
			if p.ability_kind=="pillar" and p.ability_delay>0.1:actors[i].rate=4.0
		elif p.keeper_pose>0:actors[i].play_keeper_jump()
		elif p.tackle>0:actors[i].play("Attack")
		elif p.moving:actors[i].play("Walk")
		else:actors[i].play("Stand")
		actors[i].advance(animation_delta)
		update_morph(i,delta)
	var ball_pos=sim.previous_ball.lerp(sim.ball,ball_alpha)
	ball_model.position=Vector3(ball_pos.x/100,ball_pos.z/100+0.06,-ball_pos.y/100)
	ball_model.visible=sim.ball_present
	shadow.visible=sim.ball_present
	selection.visible=sim.unit_present(sim.controlled)
	ball_model.advance(delta)
	selection.position=actors[sim.controlled].position+Vector3(0,0.025,0)
	if sim.players[sim.controlled].possess_time>0:selection.position=ball_model.position
	shadow.position=Vector3(ball_model.position.x,0.012,ball_model.position.z)
	shadow.scale=Vector3.ONE*(1+sim.ball.z/1000)
	var actors_end=Time.get_ticks_usec()
	score_label.text="%s  %d : %d  %s"%[sim.team_name(0),sim.score[0],sim.score[1],sim.team_name(1)]
	var active=sim.players[sim.controlled]
	hold_button.text="H  起跳冷却 %.1f s"%active.keeper_cooldown if active.keeper_cooldown>0 else ("H  守门起跳" if sim.KeeperRules.eligible(sim,sim.controlled) else "H  站定 / 守门起跳")
	var kit=MatchSim.Characters.kit(active)
	unit_name.text=MatchSim.Characters.DATA[active.character].name
	mana_bar.value=active.mana
	e_button.text=("E  神圣之力" if active.character=="h028" else "E  冲刺")+("中" if active.sprint else "")
	if active.character=="h026":e_button.text="E 狂暴中" if active.sprint else ("E %.1f s"%active.sprint_cooldown if active.sprint_cooldown>0 else "E 狂暴冲刺")
	if active.character=="h004":e_button.text="E 超级冲刺中" if active.sprint else ("E %.1f s"%active.sprint_cooldown if active.sprint_cooldown>0 else "E 超级冲刺")
	if active.character=="h00R":e_button.text="E 潜行中" if active.invisible else ("E 潜行准备" if active.sprint else "E 潜行冲刺")
	q_button.text="Q  "+kit.skill
	q_button.size.y=28 if kit.has("secondary") else 61
	r_button.visible=kit.has("secondary")
	if r_button.visible:r_button.text="R "+(kit.secondary if active.cooldown<=0 else "%.1f s"%active.cooldown)
	q_button.disabled=kit.kind=="none"
	if active.possess_time>0:q_button.text="支配中 %.1f s"%active.possess_time
	elif active.flight_steps>0:q_button.text="进入皮球"
	elif active.ability_kind=="powershot" and active.ability_delay>0:q_button.text="蓄力中 · S 取消"
	elif active.shadow_return>0:q_button.text="Q 回溯 %.1f"%active.shadow_return
	elif active.pull_time>0:q_button.text="Q 取消牵引"
	elif active.cooldown>0:q_button.text="Q  %.1f s"%active.cooldown
	elif active.cast_pending:q_button.text="Q  转身准备"
	if kit.kind=="hook":
		q_button.text="Q 钩敌人" if active.cooldown<=0 else "Q %.1f s"%active.cooldown
		r_button.text="R 钩队友" if active.secondary_cooldown<=0 else "R %.1f s"%active.secondary_cooldown
		if not active.hook.is_empty():
			var control=r_button if active.hook.friendly else q_button
			control.text=("R " if active.hook.friendly else "Q ")+("松开" if active.hook.caught!=-1 else ("收回中" if active.hook.returning else "提前收回"))
	if active.morph_roll>0:q_button.text="突变中 %.1f s"%active.morph_roll
	if not active.rift.is_empty() and active.rift.count==1:
		q_button.text="入口飞行中" if active.rift.projectile!=0 else ("Q %.1f s"%active.rift.unlock if active.rift.unlock>0 else "Q 放置出口")
	if active.silence>0:q_button.text="暂时沉默"
	team_label.text="%s %d 号 / %s · 向%s进攻"%[sim.team_name(active.team),active.number,"门将" if active.role=="keeper" else "球员","右" if sim.arena.attack_direction(active.team)>0 else "左"] if sim.match_enabled else sim.team_name(active.team)+" / 训练模式"
	clock_label.text=sim.MatchRules.clock_text(sim) if sim.match_enabled else "自由练习 · "+sim.arena.data.name
	if sim.match_enabled:clock_label.text+=" · "+sim.arena.data.name
	phase_label.text=str(ceili(sim.countdown)) if sim.match_state=="countdown" else ("进球！" if sim.match_state=="goal" else "")
	var halftime_visible=sim.match_state=="halftime" and not menu_root.visible and not results_root.visible
	if halftime_visible and not half_panel.visible:half_select.select(MatchSim.Characters.IDS.find(active.character))
	half_panel.visible=halftime_visible
	half_select.disabled=sim.networked
	half_label.text="中场休息 · %d 秒后准备开球"%ceili(sim.halftime_left)
	status_label.text="假摔中 · 右键起身，仍可接球和碰撞。" if active.injury_pose else sim.notice
	if status_label.text!=last_desktop_notice:last_desktop_notice=status_label.text;notice_timer=3.0
	elif not paused:notice_timer=maxf(0,notice_timer-delta)
	status_label.visible=active.injury_pose or (notice_timer>0 and status_label.text!="")
	hint.text="右键移动 · W 传射 · Q/R 角色技能 · E 冲刺\nTab 切队友 · F 呼叫传球 · F5 重开 · Esc 菜单" if kit.has("secondary") else "右键移动 · W 传射 · Q 角色技能 · E 冲刺 · S 停止\nTab 切队友 · F 呼叫传球 · 空格居中 · Esc 菜单"
	if active.character=="h029":
		if active.morph_kit!="":hint.text="借用："+kit.name+" · 剩余 %d 次 · F1 放弃借用\nQ/R 使用借用技能 · W 传射 · E 冲刺 · F5 重开"%active.morph_casts
		elif active.morph_roll>0:hint.text="正在随机选择："+MatchSim.Characters.DATA[active.morph_preview].name+"\n本次突变完成前不能移动。"
	var p=active
	marker.position=Vector3(p.destination.x/100,0.04,-p.destination.y/100)
	if p.route_status=="escaping":
		route_label.text="先让出重叠位置，再继续前往目标。"
	elif p.route_status in ["partial","blocked"]:
		route_label.text="目标被挡：前往可到达位置；通路恢复后继续。"
	elif sim.arena.course>0:
		route_label.text="新增练习场 · 右键试绕行 · F2 看路线 · B 换场地"
	else:route_label.text="门前色块：一名本方球员可进入，H 起跳拦高球。"
	update_routes()
	var effects_start=Time.get_ticks_usec()
	update_pillars(delta)
	update_tackle_shadows()
	update_projectiles(delta)
	update_rifts(delta)
	update_spell_visuals()
	var buff_start=Time.get_ticks_usec()
	original_effects.sync(sim,delta,paused,actors,ball_model,field_scenery.height_at)
	var buff_ms=(Time.get_ticks_usec()-buff_start)/1000.0
	update_referee(delta)
	if is_instance_valid(hats):hats.frame(delta)
	if is_instance_valid(biz_tree):biz_tree.frame(delta)
	if is_instance_valid(apocalypse_visuals):apocalypse_visuals.frame()
	if is_instance_valid(generated_ice_visuals):generated_ice_visuals.frame(delta)
	if is_instance_valid(franchise):franchise.frame(delta)
	if is_instance_valid(field_scenery):field_scenery.advance(0 if paused else delta)
	if show_trace:
		if trail_points.is_empty() or trail_points[-1].distance_to(ball_model.position)>0.15:
			trail_points.append(ball_model.position)
			if trail_points.size()>150:trail_points.pop_front()
		redraw_trail()
	elif is_instance_valid(trail):trail.visible=false
	visual_profile={"goals_ms":(goals_end-visual_start)/1000.0,"actors_ms":(actors_end-goals_end)/1000.0,"effects_ms":(Time.get_ticks_usec()-effects_start)/1000.0}
	visual_profile["buffs_ms"]=buff_ms

func redraw_trail():
	if not is_instance_valid(trail):
		trail=MeshInstance3D.new()
		add_child(trail)
		trail.material_override=material(Color("f2d886"))
	trail.visible=true
	if trail_points.size()<2:return
	var mesh=ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in trail_points:mesh.surface_add_vertex(p)
	mesh.surface_end()
	trail.mesh=mesh

func spell_line(mesh: ImmediateMesh,a: Vector3,b: Vector3,color: Color):
	spell_vertices+=2
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(Vector3(a.x,a.z,-a.y)/100.0)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(Vector3(b.x,b.z,-b.y)/100.0)

func spell_ring(mesh: ImmediateMesh,center: Vector3,radius: float,color: Color):
	for j in range(48):
		var a=j*TAU/48;var b=(j+1)*TAU/48
		spell_line(mesh,center+Vector3(cos(a),sin(a),0)*radius,center+Vector3(cos(b),sin(b),0)*radius,color)

func update_tackle_shadows():
	var alive={}
	# Sample visual time from the simulation, so menu pause never advances it.
	var fraction=clampf(sim.timeline-sim.next_ball+MatchSim.BALL_DT,0,MatchSim.BALL_DT)
	for state in sim.tackle_shadows:
		alive[state.id]=true
		if not tackle_shadow_models.has(state.id):
			var copy=WCModel.new()
			add_child(copy)
			copy.load_actor(MatchSim.TackleVisuals.MODEL,sim.team_color(state.team),true)
			copy.play("Attack",true)
			tackle_shadow_models[state.id]=copy
		var model=tackle_shadow_models[state.id]
		model.set_team_color(sim.team_color(state.team))
		var age=state.age+fraction
		model.position=Vector3(state.pos.x,state.pos.z,-state.pos.y)/100.0
		model.rotation.y=state.angle
		model.fade_alpha=MatchSim.TackleVisuals.alpha(age)
		model.visible=age<MatchSim.TackleVisuals.LIFETIME and model.fade_alpha>0
		model.tint=Color.WHITE if age<MatchSim.BALL_DT else MatchSim.TackleVisuals.COLOR
		model.animation_time=MatchSim.TackleVisuals.animation_time(age)
		if model.visible:model.advance(0)
	for id in tackle_shadow_models.keys():
		if not alive.has(id):tackle_shadow_models[id].queue_free();tackle_shadow_models.erase(id)

func update_pillars(delta: float):
	if pillar_player_ref==null or not is_same(pillar_player_ref,sim.players[0]):
		for model in pillar_models.values():model.queue_free()
		for entry in dying_pillars:entry.model.queue_free()
		pillar_models.clear();dying_pillars.clear();pillar_player_ref=sim.players[0]
	for entry in dying_pillars:
		entry.model.advance(delta);entry.life-=delta
		if entry.life<=0:entry.model.queue_free()
	dying_pillars=dying_pillars.filter(func(entry):return entry.life>0)
	var alive={}
	for pillar in sim.arena.pillars:
		alive[pillar.id]=true
		var fresh=not pillar_models.has(pillar.id)
		if not pillar_models.has(pillar.id):
			var prop=WCModel.new()
			add_child(prop)
			prop.load_actor("h02D",sim.team_color(sim.players[pillar.owner].team))
			prop.position=Vector3(pillar.center.x/100,0,-pillar.center.y/100)
			prop.play("Birth",true)
			prop.advance(minf(pillar.age,0.999))
			pillar_models[pillar.id]=prop
		var model=pillar_models[pillar.id]
		model.set_team_color(sim.team_color(sim.players[pillar.owner].team))
		model.position=Vector3(pillar.center.x/100,0,-pillar.center.y/100)
		if pillar.age>=1.0:model.play("Stand")
		if not fresh:model.advance(delta)
	for id in pillar_models.keys():
		if not alive.has(id):
			var model=pillar_models[id]
			model.play("Death",true);model.advance(0)
			dying_pillars.append({"model":model,"life":float(model.clip.duration)})
			pillar_models.erase(id)

func update_referee(delta: float):
	if not is_instance_valid(stall_label):
		stall_label=label("",Vector2(550,126),22,Color("ffdb79"))
	stall_label.visible=sim.stall_warned and sim.match_state=="playing"
	stall_label.text="请及时出球，避免停留过久"
	if sim.referee.is_empty():
		if is_instance_valid(referee_model):referee_model.queue_free();referee_model=null
		return
	if not is_instance_valid(referee_model):
		referee_model=WCModel.new();add_child(referee_model);referee_model.load_actor("h00T",Color("93dfff"));referee_model.play("Attack")
	var point=sim.referee.pos
	referee_model.position=Vector3(point.x,point.z,-point.y)/100
	referee_model.rotation.y=atan2(-point.y,-point.x)
	referee_model.visibility_amount=minf(1,minf(sim.referee.age*14,(1.5-sim.referee.age)*5))
	referee_model.advance(delta)

func update_morph(index: int,delta: float):
	var p=sim.players[index]
	if p.morph_ghost<=0 or p.morph_kit=="":
		if morph_models.has(index):morph_models[index].queue_free();morph_models.erase(index)
		return
	if not morph_models.has(index):
		var ghost=WCModel.new();add_child(ghost)
		ghost.load_actor(p.morph_kit,sim.team_color(p.team))
		morph_models[index]=ghost
	var ghost=morph_models[index]
	ghost.set_team_color(sim.team_color(p.team))
	ghost.position=actors[index].position;ghost.rotation=actors[index].rotation
	ghost.visibility_amount=minf(1,p.morph_ghost/2)
	actors[index].visibility_amount=maxf(0.2,1-ghost.visibility_amount)
	ghost.play("Stand - 3" if p.flip_time>0 else (p.get("action_clip","Spell") if p.action>0 else ("Walk" if p.moving else "Stand")))
	ghost.rate=4.0 if p.flip_time>0.99 else (0.41 if p.flip_time>0 else 1.0)
	if p.action>0 and p.ability_kind=="smash" and p.ability_delay>0:ghost.rate=2.0
	if p.action>0 and p.ability_kind=="pillar" and p.ability_delay>0.1:ghost.rate=4.0
	ghost.advance(delta)

func update_rifts(delta: float):
	if not is_same(rift_player_ref,sim.players[0]):
		for model in rift_models.values():model.queue_free()
		for entry in dying_rifts:entry.model.queue_free()
		rift_models.clear();dying_rifts.clear();rift_player_ref=sim.players[0]
	for entry in dying_rifts:
		entry.model.advance(delta);entry.life-=delta
		if entry.life<=0:entry.model.queue_free()
	dying_rifts=dying_rifts.filter(func(entry):return entry.life>0)
	var alive=[]
	for r in sim.rifts:
		for endpoint in ["a","b"]:
			if r[endpoint]==null:continue
			var id=str(r.id)+endpoint;alive.append(id)
			if not rift_models.has(id):
				var model=WCModel.new();add_child(model);model.load_actor("h02E",Color("8edcff"));rift_models[id]=model
			var point=r[endpoint];var model=rift_models[id]
			model.position=Vector3(point.x,point.z,-point.y)/100
			model.rotation.y=r.get("facing_"+endpoint,0.0)
			# Once B lands, A stays full size; only B starts its growth anew.
			var growth=0.75 if endpoint=="a" and r.b!=null else minf(0.75,r.age*1.5)
			model.scale=Vector3.ONE*maxf(0.0001,growth)
			model.advance(delta)
	for id in rift_models.keys():
		if not alive.has(id):
			var model=rift_models[id];model.one_shot=true;model.play("Death",true);model.rate=2.5
			dying_rifts.append({"model":model,"life":2.0});rift_models.erase(id)

func update_projectiles(delta: float):
	var alive=[]
	for projectile in sim.projectiles:
		alive.append(projectile.id)
		if not projectile_models.has(projectile.id):
			var actor=WCModel.new();add_child(actor)
			actor.load_actor({"swap":"h011","hook":"h01S","rift":"h02A"}[projectile.kind],Color("8edcff"))
			if projectile.kind=="hook":actor.tint=Color(100.0/255,1,100.0/255) if projectile.friendly else Color(1,100.0/255,100.0/255)
			projectile_models[projectile.id]=actor
		var model=projectile_models[projectile.id]
		model.position=Vector3(projectile.pos.x,projectile.pos.z,-projectile.pos.y)/100
		model.rotation.y=atan2(projectile.velocity.y,projectile.velocity.x)
		if projectile.kind=="hook":
			model.position=SpellVisuals.point(SpellVisuals.hook_position(sim,projectile,paused))
			# Hook_iterate32 faces opposite its returning velocity, so the hook
			# remains pointed outward instead of flipping around on retrieval.
			if projectile.returning:model.rotation.y=atan2(-projectile.velocity.y,-projectile.velocity.x)
		model.advance(delta)
	for id in projectile_models.keys():
		if not alive.has(id):projectile_models[id].queue_free();projectile_models.erase(id)
	alive.clear()
	var alpha=clampf((sim.timeline-sim.next_ball+MatchSim.BALL_DT)/MatchSim.BALL_DT,0,1) if not paused else 1.0
	for copy in sim.fake_balls:
		alive.append(copy.id)
		if not fake_models.has(copy.id):
			var actor=WCModel.new();add_child(actor);actor.load_actor("h000",Color.WHITE)
			actor.tint=Color(0.39,0.39,1) if copy.team==0 else Color.WHITE
			fake_models[copy.id]=actor
		var model=fake_models[copy.id]
		var point: Vector3=copy.previous.lerp(copy.position,alpha)
		model.position=Vector3(point.x,point.z+6,-point.y)/100
		model.advance(delta)
	for id in fake_models.keys():
		if not alive.has(id):fake_models[id].queue_free();fake_models.erase(id)

func update_spell_visuals():
	if not is_instance_valid(spell_mesh):
		spell_mesh=MeshInstance3D.new()
		add_child(spell_mesh)
		var mat=StandardMaterial3D.new()
		mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo=true
		mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		spell_mesh.material_override=mat
	var visible_effect=not sim.skill_effects.is_empty() or aim!="" or sim.powershot_active or not sim.projectiles.is_empty() or not sim.fake_balls.is_empty() or not sim.curve.is_empty() or not sim.rifts.is_empty()
	for p in sim.players:visible_effect=visible_effect or p.pull_time>0 or p.shadow_return>0 or p.z>1 or p.keeper_cooldown>0 or p.stun>0 or p.possess_time>0 or (p.ability_kind=="powershot" and p.ability_delay>0) or (p.character in ["h028","h026","h004"] and p.sprint)
	spell_mesh.visible=visible_effect
	if not visible_effect:return
	spell_vertices=0
	var mesh=ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for effect in sim.skill_effects:
		if not show_routes and effect.kind in ["body_bump","swap_link","slam","blink","smash","black_hole"]:continue
		match effect.kind:
			"body_bump":spell_ring(mesh,effect.pos+Vector3(0,0,8),35+effect.age*160,Color(1,0.9,0.6,effect.life/0.35))
			"swap_link":spell_line(mesh,effect.pos+Vector3(0,0,80),effect.end+Vector3(0,0,80),Color("b7b2ff"))
			"fake_pop":spell_ring(mesh,effect.pos,35+effect.age*170,Color(0.5,0.7,1,effect.life/0.4))
			"black_hole":
				var scale=clampf(effect.age/1.1,0.05,1)
				spell_ring(mesh,Vector3(effect.pos.x,effect.pos.y,2),700,Color(0.65,0.35,1,0.35))
				for ring_id in range(5):
					for j in range(48):
						var a=j*TAU/48+effect.age*4;var b=(j+1)*TAU/48+effect.age*4
						var radius=(25+ring_id*18)*scale
						spell_line(mesh,effect.pos+Vector3(cos(a),sin(a)*0.4,sin(a)*0.8)*radius,effect.pos+Vector3(cos(b),sin(b)*0.4,sin(b)*0.8)*radius,Color("ca8dff"))
			"slam":
				spell_ring(mesh,effect.pos+Vector3(0,0,4),minf(720,effect.age*1200),Color(1,0.77,0.3,effect.life/0.65))
				spell_ring(mesh,effect.pos+Vector3(0,0,8),minf(650,effect.age*1000),Color(1,0.92,0.6,effect.life/0.65))
			"blink":spell_ring(mesh,effect.pos+Vector3(0,0,12),35+effect.age*250,Color(0.75,0.55,1,effect.life*2))
			"smash":
				var forward=Vector3(cos(effect.facing),sin(effect.facing),0)
				var side=Vector3(-forward.y,forward.x,0)*200
				spell_line(mesh,effect.pos-side+Vector3(0,0,8),effect.pos+forward*350-side+Vector3(0,0,8),Color("ffae64"))
				spell_line(mesh,effect.pos+side+Vector3(0,0,8),effect.pos+forward*350+side+Vector3(0,0,8),Color("ffae64"))
				spell_line(mesh,effect.pos+forward*350-side+Vector3(0,0,8),effect.pos+forward*350+side+Vector3(0,0,8),Color("ffae64"))
	for p in sim.players:
		if p.invisible and p.team!=sim.players[sim.controlled].team:continue
		var point=MatchSim.Characters.world_position(p)
		if p.possess_time>0:
			spell_ring(mesh,sim.ball+Vector3(0,0,4),38,Color("8ee9ff") if p.team==0 else Color("ff9f97"))
			if p.team==0 and p.jump_due:spell_ring(mesh,Vector3(p.jump_target.x,p.jump_target.y,4),45,Color("8ee9ff"))
			continue
		if show_routes and p.pull_time>0:spell_line(mesh,point+Vector3(0,0,60),sim.ball,Color("df97ff"))
		if show_routes and p.shadow_return>0:
			spell_ring(mesh,Vector3(p.shadow_origin.x,p.shadow_origin.y,3),45,Color("b597e6"))
		if show_routes and p.keeper_cooldown>0:
			spell_ring(mesh,Vector3(p.keeper_origin.x,p.keeper_origin.y,3),45,Color(0.4,0.95,0.8,p.keeper_cooldown/2.0))
		if p.z>1:spell_ring(mesh,Vector3(p.pos.x,p.pos.y,3),30+p.z*0.1,Color(0.02,0.04,0.03,0.8))
		if show_routes and p.character=="h028" and p.sprint:spell_ring(mesh,point+Vector3(0,0,5),45,Color("ffe697"))
		if show_routes and p.character=="h026" and p.sprint:spell_ring(mesh,point+Vector3(0,0,5),45,Color("ff975c"))
		if show_routes and p.character=="h004" and p.sprint:spell_line(mesh,point+Vector3(0,0,60),point-Vector3(p.knock.x,p.knock.y,-60)*4,Color("bc82ff"))
		if show_routes and p.stun>0:spell_ring(mesh,point+Vector3(0,0,180),32,Color("fff2a7"))
		if p.ability_kind=="powershot" and p.ability_delay>0:
			spell_line(mesh,point+Vector3(-60,0,180),point+Vector3(60-p.ability_delay*240,0,180),Color("ffd374"))
	for projectile in sim.projectiles:
		if show_routes and projectile.kind=="hook":spell_line(mesh,MatchSim.Characters.world_position(sim.players[projectile.owner])+Vector3(0,0,75),projectile.pos+Vector3(0,0,75),Color("8dff87") if projectile.friendly else Color("ff978d"))
		elif show_routes and projectile.kind=="swap":spell_line(mesh,MatchSim.Characters.world_position(sim.players[projectile.owner])+Vector3(0,0,80),projectile.pos,Color("b7b2ff"))
		elif projectile.kind=="rift":
			spell_line(mesh,projectile.pos,projectile.pos-projectile.velocity*2,Color("b6d2ff"))
			spell_ring(mesh,Vector3(projectile.pos.x,projectile.pos.y,3),28,Color(0.05,0.08,0.12,0.6))
	for r in sim.rifts:
		if show_routes and r.a!=null:spell_ring(mesh,r.a+Vector3(0,0,5),100,Color("9ac9ff"))
		if r.b!=null:
			if show_routes:spell_ring(mesh,r.b+Vector3(0,0,5),100,Color("9ac9ff"))
			if show_routes:spell_line(mesh,r.a+Vector3(0,0,20),r.b+Vector3(0,0,20),Color("bea2ff"))
	for copy in sim.fake_balls:spell_ring(mesh,Vector3(copy.position.x,copy.position.y,2),25+copy.position.z*0.03,Color(0.02,0.04,0.03,0.7))
	if sim.powershot_active:spell_line(mesh,sim.ball,sim.ball-sim.velocity*2,Color("ffd374"))
	if show_routes and not sim.curve.is_empty():spell_line(mesh,sim.ball,sim.ball-sim.velocity*3,Color("8cdfff"))
	if aim!="" and not mobile_enabled:
		var p=sim.players[sim.controlled]
		var target=ground_point(experience.overlay.pointer if mobile_enabled else get_viewport().get_mouse_position())
		spell_line(mesh,MatchSim.Characters.world_position(p)+Vector3(0,0,10),Vector3(target.x,target.y,10),Color("ffdf8e"))
		if aim=="ability" and p.character=="h003":spell_ring(mesh,Vector3(p.pos.x,p.pos.y,3),900,Color(0.7,0.5,1,0.5))
		if aim=="ability" and p.character=="h02C":spell_ring(mesh,Vector3(target.x,target.y,3),60,Color("d4bc8f"))
	if spell_vertices==0:
		spell_mesh.visible=false
		return
	mesh.surface_end()
	spell_mesh.mesh=mesh

func run_smoke():
	# Exercise game handlers and the rendered actor without OS input automation.
	sim.take(0)
	set_aim("kick")
	checks.aim_selected=aim=="kick"
	checks.shot=sim.kick(0,Vector2(1000,0))
	for i in range(20):sim.step_ball()
	checks.ball_travelled=sim.ball.x>0
	sim.reset()
	sim.command(0,Vector2(700,0))
	for i in range(100):sim.step_movement();sim.step_ball()
	checks.moved=sim.players[0].pos.x>-300
	checks.original_meshes=actors[0].mesh_nodes.size()>0
	checks.bones=actors[0].skeleton.get_bone_count()>0
	cycle_course()
	checks.obstacle_meshes=obstacle_nodes.get_child_count()==6 and sim.arena.course==1
	show_routes=true
	sim.submit_command("move",0,Vector2(900,0))
	sim.advance(0.04)
	update_routes()
	checks.queued_move=sim.pending_commands.is_empty() and sim.players[0].want_move
	checks.route_overlay=debug_nodes.visible and route_mesh.visible
	sim.set_course(0)
	build_obstacles()
	course_button.text="场地：标准球场 [B]"
	var f=FileAccess.open("res://research/3d-smoke.json",FileAccess.WRITE)
	# Use the actual menu button callbacks and input handlers, without OS input.
	for count in [1,2,3,4,5,6]:
		open_menu()
		for child in menu_root.get_children():
			if child is Button and child.text=="%d 对 %d"%[count,count]:child.pressed.emit();break
		checks["menu_%dv%d"%[count,count]]=sim.team_size==count and actors.size()==count*2 and not menu_root.visible
		update_visuals(0)
	open_menu()
	var before=sim.time_left
	_process(0.1)
	checks.menu_pauses_clock=paused and sim.time_left==before
	resume_button.pressed.emit()
	checks.menu_resumes=not paused and not menu_root.visible
	sim.advance(3.1)
	var key=InputEventKey.new()
	key.keycode=KEY_TAB
	key.pressed=true
	_unhandled_input(key)
	update_visuals(0)
	checks.switch_updates_selection=sim.controlled!=0 and selection.position.distance_to(actors[sim.controlled].position+Vector3(0,0.025,0))<0.001
	sim.score=[9,0]
	sim.award_goal(0)
	_process(0.01)
	checks.winning_goal_follows_through=not results_root.visible and not paused
	sim.advance(4.0);_process(0)
	checks.result_menu=results_root.visible and results_title.text.begins_with("蓝队获胜") and not menu_root.visible
	for selected in range(character_select.item_count):
		character_select.select(selected)
		character_select.item_selected.emit(selected)
		enter_practice()
		var id=character_select.get_item_metadata(selected)
		if id in ["h028","h00F","h010","h012","h01N"]:sim.take(0);sim.step_ball()
		key.keycode=KEY_E if id=="h004" else KEY_Q
		_unhandled_input(key)
		if aim=="ability":
			var click=InputEventMouseButton.new()
			click.button_index=MOUSE_BUTTON_LEFT
			click.pressed=true
			click.position=camera.unproject_position(Vector3(1,0,0))
			_unhandled_input(click)
		sim.advance(0.1)
		update_visuals(0)
		var active=sim.players[0]
		checks["select_and_cast_"+id]=active.character==id and actors[0].data.actor.id==id and (active.cooldown>0 or active.pull_time>0 or active.morph_roll>0 or not active.rift.is_empty() or (id=="h004" and active.sprint) or (id=="h028" and sim.holder<0))
		if id=="h001":checks["select_and_cast_"+id]=checks["select_and_cast_"+id] and sim.projectiles.size()==1 and projectile_models.size()==1
		if id in ["h01R","h027"]:checks["select_and_cast_"+id]=checks["select_and_cast_"+id] and sim.projectiles.size()==1 and projectile_models.size()==1
		if id=="h012":checks["select_and_cast_"+id]=checks["select_and_cast_"+id] and not sim.curve.is_empty()
		if id=="h01N":checks["select_and_cast_"+id]=checks["select_and_cast_"+id] and sim.fake_balls.size()==1 and fake_models.size()==1
		if id=="h01R":
			key.keycode=KEY_Q;_unhandled_input(key);sim.advance(0.03)
			checks.hook_retract_input=aim=="" and (sim.players[0].hook.is_empty() or sim.players[0].hook.returning)
		if id=="h027":
			sim.advance(1.6);key.keycode=KEY_Q;_unhandled_input(key)
			var click=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
			click.position=camera.unproject_position(Vector3(-5,0,5));_unhandled_input(click)
			sim.advance(0.8);update_visuals(0)
			checks.rift_second_cast_input=sim.rifts.size()==1 and sim.rifts[0].b!=null and rift_models.size()==2
		if id=="h029":
			sim.advance(2.5);key.keycode=KEY_F1;_unhandled_input(key);sim.advance(0.03)
			checks.morph_reset_input=sim.players[0].morph_kit=="" and sim.players[0].cooldown>19
			sim.players[0].morph_kit="h012";sim.players[0].morph_casts=3;sim.players[0].cooldown=0
			sim.take(0);sim.step_ball();sim.score=[2,1]
			key.keycode=KEY_R;_unhandled_input(key)
			var click=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
			click.position=camera.unproject_position(Vector3(8,0,0));_unhandled_input(click)
			sim.advance(0.1);update_visuals(0)
			checks.morph_borrowed_r_input=not sim.curve.is_empty() and sim.players[0].morph_casts==2 and sim.score==[2,1] and morph_models.size()==1 and r_button.visible
		if MatchSim.Characters.DATA[id].has("secondary"):
			enter_practice();sim.take(0);sim.step_ball();sim.score=[2,1]
			key.keycode=KEY_R;_unhandled_input(key)
			var click=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
			click.position=camera.unproject_position(Vector3(1,0,0));_unhandled_input(click)
			sim.advance(0.1);update_visuals(0)
			checks["secondary_input_"+id]=(sim.players[0].cooldown>0 or sim.players[0].secondary_cooldown>0) and sim.score==[2,1] and r_button.visible
	start_game(3);sim.score=[2,1]
	key.keycode=KEY_F5;_unhandled_input(key)
	checks.f5_restarts_match=sim.score==[0,0] and sim.match_state=="countdown" and sim.team_size==3 and actors.size()==6
	for field in range(field_select.item_count):
		field_select.select(field);start_game(int(sim.arena.fields[field].recommended_team))
		update_visuals(0)
		checks["original_scenery_"+str(field)]=field_scenery.field_id==sim.arena.data.id and field_scenery.placement_count>200 and field_scenery.batch_count>0 and field_scenery.get_node("OriginalTerrain").mesh.get_surface_count()==1
		var rendered_goal=original_goals.field_id==sim.arena.data.id and original_goals.parts.size()==68
		for part in original_goals.parts:
			rendered_goal=rendered_goal and part.data.actor.id=="h00H" and part.particles.particle_count()>0
		checks["field_select_"+str(field)]=sim.arena.field_index==field and rendered_goal and actors.size()==sim.arena.data.recommended_team*2
	field_select.select(0);start_game(3);sim.match_state="playing";sim.bot_enabled=false
	sim.players[0].pos=Vector2(-1850,0);sim.players[0].body=0;sim.take(0);sim.advance(7.75);update_visuals(0)
	checks.stall_warning_and_referee=stall_label.visible and is_instance_valid(referee_model) and referee_model.data.actor.id=="h00T"
	sim.advance(1.5);update_visuals(0)
	checks.referee_releases_ball=sim.holder!=0 and not stall_label.visible and not is_instance_valid(referee_model)
	for mode in range(mode_select.item_count):
		mode_select.select(mode);start_game(3);update_visuals(0)
		checks["match_mode_menu_"+str(mode)]=sim.mode==["score","timed","tournament"][mode] and not results_root.visible and ("不限时" in clock_label.text if mode==0 else "10:00" in clock_label.text)
	sim.match_state="playing";sim.bot_enabled=false;sim.time_left=0.001;sim.advance(3.1);_process(0)
	checks.halftime_panel_and_side_colors=half_panel.visible and shown_sides_swapped and "向左进攻" in team_label.text
	var before_controlled=sim.controlled
	key.keycode=KEY_TAB;_unhandled_input(key)
	checks.halftime_locks_player_switch=sim.controlled==before_controlled and "中场休息" in clock_label.text
	half_select.select(MatchSim.Characters.IDS.find("h003"));half_select.item_selected.emit(half_select.selected)
	checks.halftime_hero_selection=sim.players[sim.controlled].character=="h003" and actors[sim.controlled].data.actor.id=="h003"
	open_menu();checks.halftime_menu_can_pause=paused and menu_root.visible
	report_button.pressed.emit();update_visuals(0)
	checks.stats_open_during_match=results_root.visible and not half_panel.visible and "尚无进球" in results_history.text
	open_menu();close_menu();sim.advance(15);_process(0)
	checks.halftime_resumes_second_half=not half_panel.visible and sim.match_state=="playing" and sim.half==2
	mode_select.select(0)
	character_select.select(MatchSim.Characters.IDS.find("h00R"));enter_practice()
	sim.players[0].pos=sim.arena.keeper_position(0);sim.players[0].previous=sim.players[0].pos
	sim.ball=Vector3(1000,700,0)
	key.keycode=KEY_H;_unhandled_input(key);sim.advance(0.25);update_visuals(0)
	checks.h_key_defensive_jump=sim.players[0].z>100 and sim.players[0].keeper_cooldown>1.7 and actors[0].position.y>1
	checks.jump_original_slam_animation="slam" in actors[0].active_clip.to_lower() and "冷却" in hold_button.text
	sim.reset();sim.command(0,Vector2(1000,0));hold_button.pressed.emit();sim.advance(0.03)
	checks.h_button_holds_outside_goal=not sim.players[0].want_move and sim.players[0].keeper_cooldown==0
	setup_interactions_preview()
	checks.slam_lifts_real_and_fake=sim.ball.z>80 and sim.fake_balls.size()==1 and sim.fake_balls[0].position.z>80
	checks.mixed_skill_models_visible=fake_models.size()==1 and pillar_models.size()==1 and actors.size()==6 and spell_mesh.visible
	setup_boundary_preview()
	checks.smash_ally_rebounds_from_pitch=sim.players[1].knock.y<0 and sim.players[1].pos.y<sim.arena.half_size.y and sim.players[1].stun==0
	checks.goal_intruder_rebounds_with_effect=sim.players[3].knock.x>0 and not sim.arena.in_guard(sim.players[3].pos,0) and sim.skill_effects.any(func(effect):return effect.kind=="body_bump") and spell_mesh.visible
	field_select.select(2);field_select.item_selected.emit(2);character_select.select(0);enter_practice()
	sim.players[0].pos=Vector2(-900,-600);sim.players[1].pos=Vector2(1500,900);sim.ball=Vector3(1400,-900,0)
	sim.submit_command("move",0,Vector2(1100,-600));sim.advance(1.5)
	var braking_start: Vector2=sim.players[0].pos
	key.keycode=KEY_S;_unhandled_input(key);sim.advance(0.15);update_visuals(0)
	checks.ice_stop_key_keeps_inertia=not sim.players[0].slide_order and not sim.players[0].want_move and sim.players[0].knock.x>0 and sim.players[0].pos.x>braking_start.x+20
	checks.ice_surface_hints=surface_hint.visible==(desktop_tools.visible or show_routes) and "冰面" in field_note.text and "冰封之地" in clock_label.text
	enter_practice();sim.players[0].pos=Vector2(-900,-600);sim.players[1].pos=Vector2(1500,900);sim.ball=Vector3(1400,-900,0)
	key.keycode=KEY_M;_unhandled_input(key)
	checks.move_order_key_selects_ground=aim=="move_order" and "移动地点" in sim.notice
	var move_click=InputEventMouseButton.new();move_click.button_index=MOUSE_BUTTON_LEFT;move_click.pressed=true
	move_click.position=camera.unproject_position(Vector3(8,0,6));_unhandled_input(move_click);sim.advance(0.3);update_visuals(0)
	checks.move_order_click_walks_without_ice_thrust=aim=="" and marker.visible and sim.players[0].pos.x> -900 and sim.players[0].knock==Vector2.ZERO and not sim.players[0].slide_order
	key.keycode=KEY_M;_unhandled_input(key);key.keycode=KEY_ESCAPE;_unhandled_input(key)
	checks.move_order_escape_cancels_selection=aim=="" and not menu_root.visible and sim.players[0].want_move
	key.keycode=KEY_M;_unhandled_input(key);move_click.button_index=MOUSE_BUTTON_RIGHT;_unhandled_input(move_click);sim.step_movement()
	checks.move_order_right_click_cancels_selection=aim=="" and not sim.players[0].slide_order
	field_select.select(0);field_select.item_selected.emit(0)
	character_select.select(0)
	character_select.item_selected.emit(0)
	enter_practice()
	checks.practice_restores_ui=actors.size()==2 and gallery_select.visible and not menu_root.visible and not paused and not sim.match_enabled
	key.keycode=KEY_S;key.pressed=true;key.echo=false
	_unhandled_input(key);sim.advance(0.04);_unhandled_input(key);sim.advance(0.04);update_visuals(0)
	checks.double_stop_plays_original_death=sim.players[0].injury_pose and actors[0].active_clip.to_lower().begins_with("death")
	var count_before=sim.players[0].injury_count
	key.echo=true;_unhandled_input(key);sim.advance(0.04);key.echo=false
	checks.held_stop_key_does_not_retrigger=sim.players[0].injury_count==count_before
	sim.advance(0.6);update_visuals(0)
	var pose_time=actors[0].animation_time
	paused=true;_process(0.3)
	checks.injury_animation_pauses=actors[0].animation_time==pose_time
	paused=false;sim.command(0,Vector2(100,0));sim.advance(0.3);update_visuals(0)
	checks.move_recovers_from_injury=not sim.players[0].injury_pose and actors[0].active_clip.to_lower().begins_with("walk")
	injury_toggle.button_pressed=false
	_unhandled_input(key);sim.advance(0.04);_unhandled_input(key);sim.advance(0.04);update_visuals(0)
	checks.injury_menu_toggle=not sim.fake_injury_enabled and not sim.players[0].injury_pose
	injury_toggle.button_pressed=true
	for id in MatchSim.Characters.IDS:
		character_select.select(MatchSim.Characters.IDS.find(id));enter_practice()
		sim.stop(0);sim.advance(0.12);sim.stop(0);sim.advance(0.4);update_visuals(0)
		checks["original_death_"+id]=sim.players[0].injury_pose and actors[0].active_clip.to_lower().begins_with("death") and not actors[0].clip.loop and actors[0].animation_time>0.39
	setup_tackle_preview()
	# Resets retain timer phase. Count one original shadow for every consumed
	# 44.6-unit step, rather than assuming this window always contains 12 ticks.
	var tackle_steps=roundi((MatchSim.Skills.TACKLE_RANGE-sim.players[0].tackle)/MatchSim.Skills.TACKLE_SPEED)
	checks.tackle_original_shadows=tackle_steps in [12,13] and sim.tackle_shadows.size()==tackle_steps and tackle_shadow_models.size()==tackle_steps
	var first_shadow=tackle_shadow_models[sim.tackle_shadows[0].id]
	var second_shadow=tackle_shadow_models[sim.tackle_shadows[1].id]
	var original_mesh_bones={}
	for geo in first_shadow.data.meshes:
		for group in geo.groups:
			for bone in group:original_mesh_bones[int(bone)]=true
	checks.tackle_shadow_original_mesh=first_shadow.data.actor.id=="h00E" and original_mesh_bones.size()==55 and first_shadow.active_clip.to_lower().begins_with("attack")
	checks.tackle_shadow_origin=first_shadow.position.is_equal_approx(Vector3(-6,0,6)) and is_equal_approx(first_shadow.scale.x,1.41)
	checks.tackle_shadow_blue_fade=first_shadow.tint.is_equal_approx(MatchSim.TackleVisuals.COLOR) and first_shadow.fade_alpha>0 and first_shadow.fade_alpha<0.5
	var shadow_material=first_shadow.mesh_nodes[0].material_override
	checks.tackle_shadow_true_alpha="ALPHA=" in shadow_material.shader.code and "depth_draw_never" in shadow_material.shader.code and is_equal_approx(shadow_material.get_shader_parameter("model_alpha"),first_shadow.fade_alpha)
	checks.tackle_shadow_no_cast_shadow=first_shadow.mesh_nodes.all(func(node):return node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	checks.tackle_shadow_shared_mesh=first_shadow.mesh_nodes[0].mesh==second_shadow.mesh_nodes[0].mesh
	checks.tackle_shadow_independent_pose=first_shadow.skeleton!=second_shadow.skeleton and first_shadow.mesh_nodes[0].material_override!=second_shadow.mesh_nodes[0].material_override and first_shadow.animation_time>second_shadow.animation_time
	checks.tackle_opaque_actor_retained=actors[0].fade_alpha==1 and not "ALPHA=" in actors[0].mesh_nodes[0].material_override.shader.code
	var frozen_time=first_shadow.animation_time;var frozen_alpha=first_shadow.fade_alpha
	_process(0.3)
	checks.tackle_shadow_pause=first_shadow.animation_time==frozen_time and first_shadow.fade_alpha==frozen_alpha
	paused=false;sim.advance(1.6);update_visuals(0)
	checks.tackle_shadow_cleanup=tackle_shadow_models.is_empty() and sim.tackle_shadows.is_empty()
	enter_practice();sim.players[0].pos=Vector2(-600,0);sim.players[1].pos=Vector2(-450,0);sim.players[1].z=80
	sim.Characters.use(sim,0,Vector2(1000,0));sim.advance(0.032);update_visuals(0)
	checks.tackle_air_hit_in_scene=sim.players[0].tackle==0 and sim.players[1].vz>0 and tackle_shadow_models.size()==1
	start_game(6);sim.match_state="playing";sim.bot_enabled=false;sim.ball=Vector3(1700,0,0)
	for i in range(12):
		sim.Characters.configure(sim.players[i],"h005");sim.players[i].pos=Vector2(-800,-1100+i*200);sim.players[i].body=0;sim.players[i].angle=0
		sim.Characters.use(sim,i,Vector2(1000,sim.players[i].pos.y))
	rebuild_actors();sim.advance(15.0/32);update_visuals(0)
	checks.tackle_twelve_players_render=sim.tackle_shadows.size()==180 and tackle_shadow_models.size()==180 and actors.size()==12
	sim.reset();update_visuals(0)
	checks.tackle_reset_cleans_render=tackle_shadow_models.is_empty()
	character_select.select(0);enter_practice()
	sim.players[0].pos=Vector2(-600,-600);sim.players[1].pos=Vector2(1500,900);sim.ball=Vector3(1400,-900,0)
	sim.command(0,Vector2(600,-600))
	sim.players[0].path=[Vector2(-590,-600),Vector2(-300,-300),Vector2(0,-300),Vector2(600,-600)]
	sim.players[0].replan=1;show_routes=true;sim.advance(0.03);update_visuals(0)
	checks.fine_route_skips_visible_detour=sim.players[0].path==[Vector2(600,-600)] and route_mesh.visible and debug_nodes.visible
	checks.fine_route_keeps_original_destination=sim.players[0].destination==Vector2(600,-600) and sim.players[0].want_move
	sim.advance(0.15);paused=true;update_visuals(0)
	checks.fine_route_actor_continues=actors[0].position.x> -5.8 and absf(actors[0].position.z-6)<0.01
	sim.stop(0);update_visuals(0)
	checks.fine_route_stop_hides_overlay=not route_mesh.visible and sim.players[0].path.is_empty()
	show_routes=false;enter_practice()
	setup_goal_entry_preview()
	checks.tackle_goal_entry_repairs_actor=sim.players[0].pos.is_equal_approx(Vector2(1590,-200)) and is_equal_approx(actors[0].position.x,15.9)
	# Round restart preserves clock phase; the queued cast leaves 6 or 7 steps
	# in this 0.22-second window depending on the next movement callback.
	checks.tackle_goal_entry_keeps_trail=sim.players[0].tackle>0 and sim.tackle_shadows.size() in [6,7] and tackle_shadow_models.size()==sim.tackle_shadows.size()
	checks.tackle_goal_entry_impact_visible=original_effects.bursts.any(func(entry):return entry.model.data.actor.id=="fx_goal_block" and entry.model.is_visible_in_tree() and entry.model.mesh_nodes.any(func(mesh_node):return mesh_node.visible)) and sim.skill_effects.any(func(effect):return effect.kind=="body_bump" and effect.pos==Vector3(1640,-200,80))
	enter_practice();sim.players[0].team=1;sim.players[0].pos=Vector2(1595,-200);sim.players[1].pos=Vector2(1000,-900)
	sim.Characters.use(sim,0,Vector2(2200,-200));sim.advance(0.1);rebuild_actors();update_visuals(0)
	checks.tackle_first_own_goal_entry_allowed=sim.arena.in_guard(sim.players[0].pos,1) and sim.players[0].tackle>0 and sim.skill_effects.is_empty()
	enter_practice()
	sim.players[0].pos=Vector2(-400,0);sim.players[1].pos=Vector2.ZERO;sim.ball=Vector3(1400,900,0)
	sim.arena.add_box(Rect2(-1000,64,2000,1500),200)
	sim.arena.add_box(Rect2(-1000,-1564,2000,1500),200)
	sim.submit_command("move",0,Vector2(400,0))
	for i in range(140):sim.step_movement()
	show_routes=true;update_visuals(0)
	checks.navigation_waiting_overlay=sim.players[0].want_move and sim.players[0].path.is_empty() and not route_mesh.visible
	# Freeze the other simulation phases here to isolate an unchanged-XY pathing
	# toggle. Full clock/render-rate integration is covered by navigation_state.
	sim.players[1].flip_time=1.09;sim.set_unit_pathing(1,false)
	for i in range(35):sim.step_movement()
	paused=true;update_visuals(0)
	checks.navigation_state_restores_route=route_mesh.visible and sim.players[0].path==[Vector2(400,0)]
	checks.navigation_resumed_actor=actors[0].position.x>1 and actors[0].position.x<3.5 and sim.players[0].moving
	# A later direct pathing enable must close the same corridor even though
	# the blocker's prior skill remains active. Freeze only those skill phases.
	sim.players[0].pos=Vector2(-300,0);sim.players[0].previous=sim.players[0].pos
	sim.players[1].tackle=640;sim.set_unit_pathing(1,true)
	sim.command(0,Vector2(400,0))
	for i in range(140):sim.step_movement()
	update_visuals(0)
	checks.pathing_enable_closes_route=sim.players[1].tackle>0 and sim.navigation_solid(sim.players[1]) and sim.players[0].path.is_empty() and not route_mesh.visible
	checks.pathing_enable_keeps_actor_outside=actors[0].position.x<0 and sim.players[0].pos.distance_to(sim.players[1].pos)>=59.99
	sim.begin_tackle(1)
	for i in range(35):sim.step_movement()
	update_visuals(0)
	checks.pathing_later_disable_reopens_route=not sim.navigation_solid(sim.players[1]) and route_mesh.visible and actors[0].position.x>1
	sim.apply_impulse(1,Vector3.ZERO);sim.step_object_impulses()
	checks.pathing_ground_callback_overrides_skill=sim.navigation_solid(sim.players[1]) and sim.players[1].tackle>0 and not sim.players[1].object_active
	sim.submit_command("stop",0);sim.step_movement();update_visuals(0)
	checks.navigation_stop_keeps_route_hidden=not route_mesh.visible and not sim.players[0].want_move
	show_routes=false;enter_practice()
	setup_tackle_order_preview()
	checks.tackle_order_two_active=sim.players[0].tackle>0 and sim.players[1].tackle>0 and sim.players[0].knock==Vector2.ZERO and sim.players[1].knock==Vector2.ZERO
	checks.tackle_order_actor_spacing=is_equal_approx(actors[1].position.x-actors[0].position.x,1.8)
	var correct_order=true
	for i in range(sim.tackle_shadows.size()):
		if sim.tackle_shadows[i].owner!=1-i%2:correct_order=false
	checks.tackle_order_original_trails=correct_order and sim.tackle_shadows.size()>=12 and tackle_shadow_models.size()==sim.tackle_shadows.size()
	enter_practice();sim.players[0].pos=Vector2.ZERO;sim.players[1].pos=Vector2(180,0)
	for p in sim.players:p.body=0;p.angle=0
	sim.ball=Vector3(1200,-700,0)
	sim.submit_command("ability",0,Vector2(1000,0));sim.submit_command("ability",1,Vector2(1000,0))
	sim.advance(0.05);update_visuals(0)
	checks.tackle_order_reversed_contact=sim.players[0].tackle==0 and sim.players[1].tackle>0 and sim.players[1].knock.x>0
	enter_practice()
	setup_narrow_route_preview()
	checks.narrow_course_keyboard=sim.arena.course==4 and "转角窄道" in course_button.text and obstacle_nodes.get_child_count()==8
	checks.narrow_course_route_visible=route_mesh.visible and sim.players[0].path.size()>=2 and sim.players[0].destination==Vector2(0,600)
	checks.narrow_course_actor_progress=actors[0].position.x> -3.5 and actors[0].position.x<0 and sim.arena.point_free(sim.players[0].pos,30)
	sim.advance(4.5);update_visuals(0)
	checks.narrow_course_reaches_ball=sim.holder==0 and sim.players[0].pos.distance_to(Vector2(0,600))<=MatchSim.Native.MIN_POINT_STOP+0.001
	key=InputEventKey.new();key.pressed=true;key.keycode=KEY_F5;_unhandled_input(key);update_visuals(0)
	checks.narrow_course_reset=sim.arena.course==4 and sim.players[0].pos==Vector2(-600,0) and sim.ball==Vector3(0,600,0)
	key.keycode=KEY_B;_unhandled_input(key)
	checks.narrow_course_wraps_to_original=sim.arena.course==0 and sim.arena.obstacles.is_empty() and "标准球场" in course_button.text
	show_routes=false;enter_practice()
	setup_hook_tackle_preview()
	checks.hook_tackle_both_active=sim.players[0].hooked!=0 and sim.players[0].tackle>0 and sim.players[1].hook.caught==0
	checks.hook_tackle_original_models=actors[0].data.actor.id=="h005" and actors[1].data.actor.id=="h01R" and projectile_models.size()==1
	var hooked_tackle_steps=roundi((MatchSim.Skills.TACKLE_RANGE-sim.players[0].tackle)/MatchSim.Skills.TACKLE_SPEED)
	checks.hook_tackle_retains_trail=hooked_tackle_steps in [10,11,12] and sim.tackle_shadows.size()==hooked_tackle_steps and tackle_shadow_models.size()==hooked_tackle_steps and actors[0].position.x< -4
	sim.advance(1.5);update_visuals(0)
	checks.hook_tackle_cleans_up=sim.players[0].hooked==0 and sim.players[0].tackle==0 and projectile_models.is_empty()
	var release_position=sim.players[0].pos
	sim.submit_command("move",0,Vector2(0,500));sim.advance(1.2);update_visuals(0)
	checks.hook_tackle_can_move_after_release=sim.players[0].pos.distance_to(release_position)>150 and actors[0].position.x>release_position.x/100
	character_select.select(0);enter_practice()
	sim.players[0].cooldown=20;sim.players[0].mana=5
	refresh_button.pressed.emit();sim.step_movement();update_visuals(0)
	checks.practice_refresh_button=sim.players[0].cooldown==0 and mana_bar.value==100 and refresh_button.visible
	sim.players[0].cooldown=10;key.keycode=KEY_F6;_unhandled_input(key);sim.step_movement()
	checks.practice_refresh_keyboard=sim.players[0].cooldown==0
	key.keycode=KEY_F7;_unhandled_input(key);sim.step_movement();paused=true;update_visuals(0)
	checks.practice_recall_keyboard=sim.holder==0 and ball_model.position==Vector3(sim.ball.x/100,sim.ball.z/100+0.06,-sim.ball.y/100)
	sim.holder=-1;sim.ball=Vector3(1200,700,0);recall_button.pressed.emit();sim.step_movement()
	checks.practice_recall_button=sim.holder==0
	start_game(3);sim.match_state="playing";sim.bot_enabled=false;update_visuals(0)
	sim.players[0].cooldown=10;sim.players[0].mana=5
	key.keycode=KEY_F6;_unhandled_input(key);key.keycode=KEY_F7;_unhandled_input(key);sim.step_movement()
	checks.practice_tools_disabled_in_match=not refresh_button.visible and not recall_button.visible and sim.players[0].cooldown==10 and sim.players[0].mana==5 and sim.holder==-1
	enter_practice();sim.players[0].pos=Vector2(-400,0);sim.players[1].pos=Vector2(-365,0)
	sim.ball=Vector3(1300,900,0);sim.arena.add_box(Rect2(-200,-300,70,600),200);build_obstacles()
	sim.submit_command("move",0,Vector2(600,0));sim.step_movement();show_routes=true;paused=true;update_visuals(0)
	checks.overlap_escape_shows_route=sim.players[0].route_status=="escaping" and route_mesh.visible and "重叠" in route_label.text
	for i in range(650):sim.step_movement()
	update_visuals(0)
	checks.overlap_escape_actor_reaches_target=sim.players[0].pos.distance_to(Vector2(600,0))<=16 and actors[0].position.x>5.8
	show_routes=false
	enter_practice();sim.players[0].pos=Vector2(70,0);sim.players[1].pos=Vector2.ZERO
	sim.ball=Vector3(1300,900,0);sim.apply_impulse(1,Vector3(20,0,0));sim.step_object_impulses();paused=true;update_visuals(0)
	checks.object_order_same_pass_actor=absf(actors[0].position.x-0.887)<0.00001 and absf(actors[1].position.x-0.1935)<0.00001
	checks.object_order_receiver_motion_phased=not sim.navigation_solid(sim.players[0]) and sim.players[0].object_active and absf(sim.players[0].knock.x-18.7)<0.0001
	sim.submit_command("move",0,Vector2(700,400));sim.advance(3);update_visuals(0)
	checks.object_order_receiver_can_resume_walk=sim.players[0].pos.distance_to(Vector2(700,400))<=16 and actors[0].position.x>6.8
	enter_practice();sim.players[0].pos=Vector2(-400,0);sim.players[1].pos=Vector2.ZERO;sim.ball=Vector3(1300,900,0)
	sim.arena.add_box(Rect2(-1000,64,2000,1500),200);sim.arena.add_box(Rect2(-1000,-1564,2000,1500),200);build_obstacles()
	sim.apply_impulse(1,Vector3(10,0,0));sim.step_object_impulses();sim.command(0,Vector2(400,0));show_routes=true;paused=true;update_visuals(0)
	checks.object_height_motion_opens_route=sim.players[0].path==[Vector2(400,0)] and route_mesh.visible and not sim.navigation_solid(sim.players[1])
	sim.advance(3);update_visuals(0)
	checks.object_height_rest_closes_route=sim.navigation_solid(sim.players[1]) and sim.players[0].pos.x<sim.players[1].pos.x-59.99 and sim.players[0].want_move and not route_mesh.visible
	sim.set_unit_pathing(1,false);sim.advance(3);update_visuals(0)
	checks.object_height_later_disable_reopens=sim.players[0].pos.distance_to(Vector2(400,0))<=16 and actors[0].position.x>3.8
	show_routes=false
	enter_practice()
	f.store_string(JSON.stringify(checks,"\t"))
	for name in checks:
		if not checks[name]:push_error("3D smoke failed: "+name);get_tree().quit(1)
