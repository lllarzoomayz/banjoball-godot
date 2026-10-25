extends SceneTree
const Model=preload("res://scripts/wc3_model.gd")
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func run():
	var game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.enter_practice()
	var renderer=game.event_spawns
	check(renderer.catalog.size()==8,"all eight authored spawn codes including animal hat death resolved or explicitly missing")
	check(renderer.catalog.HBS0.missing and renderer.catalog.HBS0.model=="","missing original Small0 is not replaced by a different blood model")
	for pair in [["h004","NBDH"],["h00F","NBDH"],["h00P","DNAS"],["h01I","HBF0"],["h01R","HBP0"],["h029","UBAC"],["h02B","HBF0"],["h02C","OBT0"],["hat_21","CBAL"]]:
		renderer.clear()
		var actor=Model.new();game.add_child(actor);actor.load_actor(pair[0],Color.WHITE)
		actor.position=Vector3(3,1,-4);actor.rotation=Vector3(.2,.7,-.3);actor.scale=Vector3(1.2,.8,1.4)
		actor.play("Death",true);actor.one_shot=true
		var ev=actor.clip.events.filter(func(e):return e.type=="SPN")[0]
		actor.advance(0);check(renderer.active.is_empty(),pair[0]+" pose setup does not spawn")
		actor.advance(float(ev.time)+.001)
		check(renderer.active.size()==1,pair[0]+" real authored death key creates one model")
		var child=renderer.active[0]
		var nested=[]
		child.native_event.connect(func(event,_position):nested.append(event.code))
		check(child.data.actor.id==renderer.catalog[pair[1]].model and child.one_shot,pair[0]+" original model and source sequence zero")
		var v=ev.basis;var source=Basis(Vector3(v[0],v[1],v[2]),Vector3(v[3],v[4],v[5]),Vector3(v[6],v[7],v[8]))
		var expected=Transform3D(actor.global_basis*Model.CONVERSION*source*Model.CONVERSION.inverse(),actor.global_transform*(Model.CONVERSION*actor.vec(ev.position)/100.0))
		check(child.global_transform.is_equal_approx(expected),pair[0]+" exact event pivot rotation and scale")
		var fixed=child.global_transform;actor.position+=Vector3(5,1,3);actor.free()
		check(is_instance_valid(child) and child.global_transform==fixed,pair[0]+" detached child survives parent moving and deletion")
		game.paused=true;renderer.advance(.2);check(child.animation_time==0,pair[0]+" pause freezes new effect")
		game.paused=false
		for i in range(15):renderer.advance(1.0/60)
		check(is_equal_approx(child.animation_time,.25),pair[0]+" spawned sequence advances independently")
		if pair[1]=="DNAS":
			check(nested==["DELB"],"nested source zero-time sound is dispatched exactly once")
			check(game.experience.model_audio.catalog.DELB.files.is_empty() and not game.experience.model_audio.catalog.DELB.muted_map_overrides.is_empty(),"nested building death respects original map's deliberate silent override")
		var peak=0
		while is_instance_valid(child):
			var count=0
			if is_instance_valid(child.particles):
				for emitter in child.particles.emitters:count+=emitter.particles.size()
			peak=maxi(peak,count);renderer.advance(1.0/60)
		check(peak>0,pair[0]+" original emitter produces actual particles during its source visibility window")
		check(renderer.active.is_empty(),pair[0]+" source sequence end releases child")
	var actor=Model.new();game.add_child(actor);actor.load_actor("h01I",Color.WHITE);actor.play("Death",true);actor.hide();actor.advance(.2)
	check(renderer.active.is_empty(),"hidden parent cannot leak an event effect")
	actor.show();actor.play("Death",true);game.paused=true;actor.advance(.2)
	check(renderer.active.is_empty(),"paused dispatch is ignored");game.paused=false
	actor.play("Death",true);actor.advance(.2);check(renderer.active.size()==1,"restart plays a new original event")
	actor.advance(1);check(renderer.active.size()==1,"continuing same death does not duplicate spawn")
	game.rebuild_actors();check(renderer.active.is_empty(),"restart clears all detached effects");actor.free()
	game.free()
	FileAccess.open("res://research/event-spawn-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("EVENT SPAWN ",passed," passed; ",failures.size()," failed");quit(1 if not failures.is_empty() else 0)
