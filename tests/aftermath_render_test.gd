extends SceneTree
var game
var army
var passed=0
var failures=[]
var native_events=[]
var arrow_events=[]
class EventObserver extends Node:
	var events=[]
	func model_event(source,event,_position):
		if source.data.actor.id=="apoc_arrow":events.append(event.code)
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func advance(seconds):
	var end=game.sim.timeline+seconds
	while game.sim.timeline<end-.000001:
		var dt=minf(.03,end-game.sim.timeline);game.sim.advance(dt);game.update_visuals(dt)
func touch(id,point,down):
	var event=InputEventScreenTouch.new();event.index=id;event.position=point;event.pressed=down
	Input.parse_input_event(event);Input.flush_buffered_events()
func tap(point):touch(201,point,true);touch(201,point,false)
func capture(name):
	game.update_visuals(0);game.touch_controls.frame(0)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/aftermath-"+name+".png")
	return root.get_texture().get_image()
func reset_unit(u,pos):
	u.hp=180;u.pos=army.ground(pos);u.previous=u.pos;u.angle=0;u.order="direct";u.axis=Vector2.ZERO
	u.target=-1;u.hit_at=INF;u.attack_at=-INF;u.cooldown_until=0;u.path=PackedVector2Array();u.moving=false
func model(u):return game.apocalypse_visuals.skeletons[u.id].model
func run():
	var observer=EventObserver.new();root.add_child(observer);observer.events=arrow_events;observer.add_to_group("wc3_model_events")
	root.size=Vector2i(1440,810)
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.set_process(false)
	var ui=game.touch_controls;ui.start_practice();game.sim.random.seed=24102026;game.sim.bot_enabled=false
	game.aftermath_controls.frame()
	check(ui.buttons.apocalypse.disabled,"entry stays locked during source first forty seconds")
	game.sim.advance(40);ui.tools_panel.show();ui.frame(0);game.aftermath_controls.frame()
	var entry=ui.buttons.apocalypse.get_global_rect().get_center()
	tap(entry)
	check(game.sim.apocalypse==null and ui.buttons.apocalypse.text.contains("确认"),"first entry tap explains that the football match ends")
	tap(entry);var state=game.sim.apocalypse
	check(state!=null and state.active and not ui.tools_panel.visible,"second actual touch begins live sequence and dismisses tools")
	advance(62.3);army=state.aftermath;ui.frame(0)
	check(army.units.size()==20 and game.apocalypse_visuals.skeletons.size()==20,"actual full sequence binds twenty live models")
	check(ui.buttons.kick.text.contains("攻击") and not ui.buttons.ability.visible,"mobile controls switch from football to combat")
	check(not game.perf.panel.visible and game.perf.mode==0,"aftermath respects clean HUD")
	var first=game.aftermath_controls.portrait_ids.duplicate();tap(ui.buttons.ally_5.get_global_rect().get_center());ui.frame(0)
	check(first!=game.aftermath_controls.portrait_ids and game.aftermath_controls.page==1,"all ten local units reachable through portrait pages")
	tap(ui.buttons.ally_0.get_global_rect().get_center())
	check(army.selected==game.aftermath_controls.portrait_ids[0],"touch portrait selects live local skeleton")
	var warrior=army.units.filter(func(u):return u.owner==0 and u.rawcode=="nske")[0]
	var archer=army.units.filter(func(u):return u.owner==0 and u.rawcode=="nska")[0]
	var enemy=army.units.filter(func(u):return u.team==1)[0]
	for u in army.units:reset_unit(u,Vector2(-1300+u.id*75,900))
	reset_unit(warrior,Vector2(-400,-200));reset_unit(enemy,Vector2(-320,-200));army.choose(warrior.id)
	game.focus=Vector3(-3,0,2);game.zoom=.5;game.update_camera();game.update_visuals(0)
	var click=game.camera.unproject_position(model(warrior).global_position+Vector3.UP*.65)
	army.choose(archer.id);game.aftermath_controls.world_click(click)
	check(army.selected==warrior.id,"PC world picking selects the model under the cursor")
	army.command("attack",Vector2.ZERO,enemy.id);advance(.12)
	check(model(warrior).active_clip.to_lower().begins_with("attack"),"original warrior Attack clip follows live windup")
	var at=warrior.attack_at
	check(absf(model(warrior).animation_time-(state.rules.clock-at))<.031,"attack animation follows simulation attack start")
	await capture("melee")
	army.command("move_direction",Vector2.DOWN);advance(.3)
	check(model(warrior).active_clip.to_lower().begins_with("walk"),"cancel attack immediately transitions to original Walk")
	check(is_equal_approx(model(warrior).rate,1.5),"walk animation scales source speed 180 to gameplay speed 270")
	ui.cancel_all();army.choose(warrior.id);ui.frame(0);var origin=warrior.pos
	touch(202,ui.root.position+ui.joystick_center,true);ui.touch_drag(202,ui.root.position+ui.joystick_center+Vector2(70,0));ui.frame(.03);advance(.3)
	touch(202,ui.root.position+ui.joystick_center+Vector2(70,0),false)
	check(warrior.pos.distance_to(origin)>15 and warrior.axis==Vector2.ZERO,"real joystick moves skeleton and release clears direction")
	reset_unit(warrior,Vector2(-1000,-500));reset_unit(archer,Vector2(-400,100));reset_unit(enemy,Vector2(50,100));army.choose(archer.id)
	army.command("attack",Vector2.ZERO,enemy.id);advance(.87)
	check(not army.arrows.is_empty() and not game.apocalypse_visuals.arrow_models.is_empty(),"ranged shot creates original arrow mesh during flight")
	check(model(archer).active_clip.to_lower().begins_with("attack"),"archer original Attack accompanies projectile release")
	game.focus=Vector3(-1,0,-1);game.update_camera();var with_arrow=await capture("arrow")
	for node in game.apocalypse_visuals.arrow_models.values():node.hide()
	var without_arrow=await capture("arrow-hidden");var changed=0
	for y in range(with_arrow.get_height()):
		for x in range(with_arrow.get_width()):
			var a=with_arrow.get_pixel(x,y);var b=without_arrow.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>.04:changed+=1
	check(changed>4,"original arrow contributes visible pixels in actual aftermath field: "+str(changed))
	for node in game.apocalypse_visuals.arrow_models.values():node.show()
	var clock=state.rules.clock;var anim=model(archer).animation_time;game.paused=true
	for i in range(5):game.update_visuals(.2)
	check(state.rules.clock==clock and model(archer).animation_time==anim,"pause freezes combat animation and missile simulation")
	game.paused=false;advance(.6);check(enemy.hp<180,"visible arrow impact applies combat damage")
	check("MARL" in arrow_events and "MARR" in arrow_events,"original arrow Birth and Death sound events both fire")
	check(game.experience.model_audio.last_event.get("code")=="MARR","arrow impact reaches actual original-sample audio mixer")
	model(enemy).native_event.connect(func(event,_position):native_events.append(event))
	army.damage(enemy.id,1000);advance(.6)
	check(model(enemy).active_clip.to_lower().begins_with("death") and model(enemy).one_shot,"zero HP plays original one-shot Death")
	check(not native_events.is_empty(),"native Death event track is emitted through live model")
	await capture("death");advance(5)
	check(not model(enemy).visible,"native death duration removes corpse model")
	game.mobile_enabled=false;game.aftermath_controls.frame()
	check(game.aftermath_controls.desktop.visible and not game.get_node("HUD").visible,"desktop aftermath uses combat panel")
	var key=InputEventKey.new();key.pressed=true;key.keycode=KEY_TAB;var selected=army.selected
	game._unhandled_input(key);check(army.selected!=selected,"desktop Tab cycles live owned skeletons")
	key.keycode=KEY_ESCAPE;game._unhandled_input(key);game.aftermath_controls.frame()
	check(game.paused and game.menu_root.is_visible_in_tree(),"desktop pause menu remains visible above aftermath")
	game._unhandled_input(key);game.aftermath_controls.frame()
	check(not game.paused and game.aftermath_controls.desktop.visible,"desktop Escape resumes aftermath")
	game.mobile_enabled=true;game.aftermath_controls.frame()
	# Restore while paused: the mobile gameplay frame returns before its normal
	# refresh, so the controller must also restore in its own frame callback.
	ui.frame(0);game.open_menu();game.enter_practice();game.open_menu();game.aftermath_controls.frame()
	check(not ui.buttons.hats.disabled and ui.buttons.kick.text!="攻击\n附近敌人","ordinary buttons restore even while menu remains open")
	game.close_menu();game.start_game(6);game.update_visuals(0);ui.frame(0)
	check(ui.buttons.ally_5.visible and ui.buttons.ally_5.get_node("Portrait").visible and ui.buttons.ally_5.text=="","sixth teammate portrait recovers after pagination button")
	check(ui.buttons.kick.text!="攻击\n附近敌人" and ui.buttons.ability.visible and ui.buttons.sprint.visible,"new football match restores normal skills")
	check(game.apocalypse_visuals.arrow_models.is_empty() and game.apocalypse_visuals.skeletons.is_empty(),"new game releases army visuals and projectiles")
	await capture("restored")
	game.free();await process_frame
	FileAccess.open("res://research/aftermath-render-verification.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"physical_phone_tested":false},"\t"))
	print("AFTERMATH RENDER CHECKS ",passed," passed; ",failures.size()," failed")
	quit(0 if failures.is_empty() else 1)
