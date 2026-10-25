extends SceneTree
const Visuals=preload("res://scripts/spell_visuals.gd")
var game
var passed=0
var failures=[]
var observations=[]
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func capture(name):
	game.touch_controls.frame(0);await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var result=root.get_texture().get_image();result.save_png("res://research/black-hole-"+name+".png");return result
func difference(a,b):
	var pixels=0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var c=a.get_pixel(x,y);var d=b.get_pixel(x,y)
			if absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b)>.04:pixels+=1
	return pixels
func run():
	root.size=Vector2i(960,540)
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.set_process(false)
	# Literal source countdown order, independent of the renderer age helper.
	var count=3.5;var size=.01;var beam_left=1.1
	for tick in range(114):
		var state=Visuals.black_hole_visual({"pos":Vector3(20,30,50),"age":tick/32.0},-120)
		check(is_equal_approx(state.scale,size),"source size at tick "+str(tick))
		check(state.beam==(beam_left>0),"source lightning lifetime at tick "+str(tick))
		check(state.position==Vector3(20,30,-70) and state.caster_height==(80.0 if tick==0 else 60.0),"source endpoints at tick "+str(tick))
		count-=1.0/32;beam_left-=1.0/32
		if count>3.5-1.1:size+=(.5-.01)/1.1/32
	for field in range(4):
		game.character_select.select(game.sim.Characters.IDS.find("h003"))
		game.field_select.select(field);game.touch_controls.start_practice();var sim=game.sim;sim.bot_enabled=false
		sim.players[1].pos=Vector2(1500,900)
		var target=Vector2(-1280,-960) if field==1 else Vector2.ZERO
		sim.players[0].pos=target+Vector2(-250,0);sim.players[0].previous=sim.players[0].pos
		check(sim.Characters.use(sim,0,target),"real black hole cast field "+str(field))
		var effect=sim.skill_effects.filter(func(e):return e.kind=="black_hole")[0]
		var rng=sim.random.state;var physics_pos=effect.pos
		game.focus=Vector3(target.x/100,0,-target.y/100);game.zoom=.55;game.update_camera();game.update_visuals(0)
		var fx=game.original_effects;var key=fx.persistent.keys().filter(func(k):return k.begins_with("black_hole:"))[0];var model=fx.persistent[key]
		var ground=game.field_scenery.height_at(target)
		check(model.active_clip=="Stand" and not model.one_shot,"source unit starts Stand field "+str(field))
		check(is_equal_approx(model.position.y,(ground+50)/100),"rendered terrain sets black hole height field "+str(field))
		check(is_equal_approx(model.scale.x,.01),"initial scale field "+str(field))
		sim.advance(1.09375);game.update_visuals(1.09375)
		check(is_equal_approx(model.scale.x,.01+35*(.5-.01)/1.1/32),"source growth stops below .5 field "+str(field))
		check(fx.lightning.nodes.BKHL.visible,"lightning remains through tick 35 field "+str(field))
		var aabb=fx.lightning.nodes.BKHL.mesh.get_aabb()
		check(aabb.position.y<=(ground+50)/100 and aabb.end.y>=(ground+50)/100,"lightning reaches terrain-adjusted black hole field "+str(field))
		var shown=await capture("field-"+str(field));model.hide();fx.lightning.hide();fx.flush_particles();var hidden=await capture("field-"+str(field)+"-hidden")
		var pixels=difference(shown,hidden);check(pixels>20,"native model/lightning visible field "+str(field));model.show();fx.lightning.show();fx.flush_particles()
		observations.append({"field":field,"ground":ground,"pixels":pixels,"scale":model.scale.x})
		var time=model.animation_time;game.update_visuals(0);check(model.animation_time==time,"pause freezes animation field "+str(field))
		sim.advance(1.0/32);game.update_visuals(1.0/32)
		check(not fx.lightning.nodes.BKHL.visible,"lightning removed at tick 36 field "+str(field))
		check(effect.pos==physics_pos and sim.random.state==rng,"presentation preserves simulation position and RNG field "+str(field))
		sim.advance(2.375);game.update_visuals(2.375)
		check(not fx.persistent.has(key),"unit killed at 3.5 seconds field "+str(field))
		for i in range(180):game.update_visuals(1.0/60)
		check(fx.bursts.is_empty(),"Death and tail drain field "+str(field))
	check(game.perf.mode==0,"performance stays hidden")
	FileAccess.open("res://research/black-hole-visual-render-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"observations":observations},"\t"))
	print("BLACK HOLE VISUAL CHECKS ",passed," passed; ",failures.size()," failed")
	game.free();quit(0 if failures.is_empty() else 1)
