extends SceneTree
const Model=preload("res://scripts/wc3_model.gd")
var game
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func fresh():
	game.touch_controls.start_practice();game.sim.bot_enabled=false
	var sim=game.sim;var p=sim.players[0]
	p.pos=sim.arena.keeper_position(0);p.previous=p.pos;sim.players[1].pos=Vector2(1500,700)
	sim.holder=-1;sim.ball=Vector3(0,0,0)
	game.focus=Vector3(p.pos.x/100,0,-p.pos.y/100);game.zoom=.55;game.update_camera();game.update_visuals(0)
	return sim
func snapshot(name):
	game.touch_controls.frame(0);await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/effect-lifecycle-"+name+".png")
func run():
	root.size=Vector2i(960,540)
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.set_process(false)
	var sim=fresh();var fx=game.original_effects
	check(sim.KeeperRules.hold(sim,0),"real goalkeeper hold order starts jump")
	var event=sim.native_visuals.filter(func(e):return e.model=="fx_jump")[0]
	check(event.destroy_after==2 and event.on_terrain,"source Jump timer and terrain placement are retained")
	game.update_visuals(0);check(fx.timed.size()==1 and not fx.bursts.any(func(e):return e.model.data.actor.id=="fx_jump"),"jump uses a held effect handle rather than an immediate burst")
	var entry=fx.timed[0];var model=entry.model;var origin=model.position
	sim.advance(.15);game.update_visuals(.15)
	check(model.active_clip=="Birth" and model.particles.particle_count()>0,"original Birth produces particles")
	await snapshot("jump-birth")
	var age=entry.elapsed;game.update_visuals(0);game.update_visuals(0)
	check(entry.elapsed==age and fx.timed.size()==1,"paused render does not advance or duplicate the held effect")
	sim.players[0].pos+=Vector2(250,0);sim.KeeperRules.clear(sim)
	sim.advance(1.35);game.update_visuals(1.35)
	check(sim.players[0].keeper_cooldown==0 and fx.timed.size()==1 and not entry.destroyed,"early cooldown clear does not destroy the outstanding timer handle")
	check(model.position==origin,"jump effect remains at its original world location")
	check(model.active_clip=="Birth" and model.particles.particle_count()==0,"Birth-only source is quiet while handle waits for destruction")
	sim.advance(.499);game.update_visuals(.499);check(not entry.destroyed,"no premature destruction before two seconds")
	sim.advance(.0011);game.update_visuals(.0011)
	check(entry.destroyed and model.active_clip=="Death","timer executes the original Death sequence")
	check(fx.timed.is_empty(),"empty authored Death drains and releases the handle")
	sim=fresh();sim.KeeperRules.hold(sim,0);sim.advance(1.5);game.update_visuals(1.5)
	check(fx.timed.size()==1 and is_equal_approx(fx.timed[0].elapsed,1.5) and fx.timed[0].model.particles.particle_count()==0,"late first render catches up without replaying old Birth particles")
	sim.advance(.6);game.update_visuals(.6);check(fx.timed.is_empty(),"late update crosses the destruction boundary without restarting Birth")
	sim=fresh();sim.KeeperRules.hold(sim,0);game.update_visuals(0);fresh()
	check(fx.timed.is_empty(),"new match releases all held handles")
	# Same real attached model, different render cadence across Birth -> Stand.
	var alive={};var a=fx.attach_buff("cadence:a","fx_divine",game.actors[0],"origin",alive)
	var b=fx.attach_buff("cadence:b","fx_divine",game.actors[0],"origin",alive)
	var birth_duration=float(a.clip.duration)
	fx.advance_bound(a,.2)
	for i in range(20):fx.advance_bound(b,.01)
	check(a.active_clip=="Stand" and b.active_clip=="Stand","both render cadences enter Stand")
	check(is_equal_approx(a.animation_time,.2-birth_duration) and is_equal_approx(a.animation_time,b.animation_time),"Birth overshoot is retained, independent of frame cadence")
	check(not a.has_meta("buff_birth") and not a.one_shot,"persistent Stand keeps its original loop")
	fx.flush_particles();await snapshot("buff-stand")
	var time=a.animation_time;fx.advance_bound(a,0);check(a.animation_time==time,"paused attached buff clock stays frozen")
	check(game.perf.mode==0,"lifecycle repairs keep diagnostics hidden")
	FileAccess.open("res://research/effect-lifecycle-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("EFFECT LIFECYCLE CHECKS ",passed," passed; ",failures.size()," failed")
	game.free();quit(0 if failures.is_empty() else 1)
