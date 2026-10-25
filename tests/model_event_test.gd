extends SceneTree
const Track=preload("res://scripts/wc3_event_track.gd")
const Model=preload("res://scripts/wc3_model.gd")
var passed=0
var failures=[]
var seen=[]
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func run():
	var events=[{"time":0.0,"code":"start"},{"time":.25,"code":"mid"},{"time":1.0,"code":"end"}]
	check(Track.crossed(events,0,0,1,false,true).is_empty(),"paused first frame does not emit events")
	check(Track.crossed(events,0,.25,1,false,true).map(func(e):return e.code)==["start","mid"],"first positive step includes zero and exact endpoint")
	check(Track.crossed(events,.25,.75,1,false,false).map(func(e):return e.code)==["end"],"previous endpoint is not repeated")
	check(Track.crossed(events,1,5,1,false,false).is_empty(),"clamped one-shot cannot replay final event")
	var all=Track.crossed(events,0,2.25,1,true,true)
	check(all.size()==8,"large loop delta includes every cycle and endpoint")
	check(all.filter(func(e):return e.code=="start").size()==3 and all.filter(func(e):return e.code=="end").size()==2,"zero and final keys are distinct across two wraps")
	check(Track.crossed(events,0,.1,1,true,false).is_empty(),"zero key at a completed wrap is not emitted again next frame")
	check(Track.crossed(events,.1,.05,1,false,true).is_empty(),"seeking past zero does not catch up a stale start sound")
	var model=Model.new();root.add_child(model);model.load_actor("h026",Color.WHITE)
	model.native_event.connect(func(e,p):seen.append({"event":e,"position":p}))
	model.play("Walk",true);model.position=Vector3(4,2,-3);model.rotation.y=.7
	model.advance(.199);check(seen.is_empty(),"original ogre walk waits until 200ms footfall")
	model.advance(.001);check(seen.size()==2,"200ms produces original foot decal and sound events")
	check(seen.any(func(e):return e.event.code=="FDFR"),"original right-step sound code is dispatched")
	var e=seen[0].event;var pos=model.global_transform*(Model.CONVERSION*model.vec(e.position)/100)
	check(seen[0].position.distance_to(pos)<.000001,"event position follows model scale rotation and exact event pivot")
	model.advance(0);check(seen.size()==2,"zero-delta repeated pose updates are silent")
	model.rate=2;model.advance(.25);check(seen.size()==4,"animation speed also controls left-foot event at 700ms")
	var before=seen.size();model.play("Walk");model.advance(.001)
	check(seen.size()==before,"selecting same clip without restart keeps event cursor")
	model.play("Walk",true);model.advance(.1)
	check(seen.size()==before+2,"explicit restart plays first footfall again at double speed")
	model.free()
	var ghost=Model.new();root.add_child(ghost);ghost.load_actor("h026",Color.WHITE,true)
	ghost.native_event.connect(func(ev,p):seen.append({"event":ev,"position":p}));before=seen.size()
	ghost.play("Walk",true);ghost.advance(1)
	check(seen.size()==before,"translucent copied actors never duplicate sound or footprints");ghost.free()
	var fx=Model.new();root.add_child(fx);fx.load_actor("fx_shout",Color.WHITE)
	fx.native_event.connect(func(ev,p):seen.append({"event":ev,"position":p}));before=seen.size()
	fx.play("Birth",true);fx.one_shot=true;fx.advance(0)
	check(seen.size()==before,"birth setup at origin remains silent before placement")
	fx.position=Vector3(5,0,6);fx.advance(.01)
	check(seen.size()==before+1 and seen[-1].event.code=="ABTR","real BattleRoar zero-time event emits exactly once")
	fx.advance(5);fx.advance(1);check(seen.size()==before+1,"one-shot ending and tail pruning do not repeat audio");fx.free()
	FileAccess.open("res://research/model-event-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("MODEL EVENTS ",passed," passed; ",failures.size()," failed");quit(1 if not failures.is_empty() else 0)
