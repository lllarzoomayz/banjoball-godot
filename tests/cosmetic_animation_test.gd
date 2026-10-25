extends SceneTree
const Model=preload("res://scripts/wc3_model.gd")
const CosmeticAnimation=preload("res://scripts/cosmetic_animation.gd")
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func make_model(id):
	var model=Model.new();root.add_child(model);model.load_actor(id,Color.WHITE);model.events_enabled=false
	return model
func run():
	var coverage=JSON.parse_string(FileAccess.get_file_as_string("res://research/effect-sequence-coverage.json"))
	var native=JSON.parse_string(FileAccess.get_file_as_string("res://research/native-cosmetic-weights.json"))
	var models={};var drivers={};var source_clips=0
	for row in coverage.rows:
		if row.catalog!="cosmetic-assets.json":continue
		var model=make_model(row.id);models[row.id]=model
		var driver=CosmeticAnimation.new();driver.rng.seed=12;driver.setup(model);drivers[row.id]=driver
		for source in row.source_sequences:
			var matches=model.data.clips.filter(func(c):return c.name==source.name)
			check(matches.size()==1,row.id+" retains original "+source.name)
			if matches.size()!=1:continue
			var clip=matches[0];source_clips+=1
			check(is_equal_approx(clip.duration,float(source.interval[1]-source.interval[0])/1000) and clip.loop==source.loop and clip.rarity==source.rarity,row.id+" source timing/loop/rarity "+source.name)
			check(int(clip.offset)+int(clip.frames)*model.data.bone_ids.size()*16<=model.frames.size(),row.id+" bone frame data covers "+source.name)
			model.play(source.name,true);model.advance(float(clip.duration)*.6)
			check(model.active_clip==source.name and is_equal_approx(model.animation_time,float(clip.duration)*.6),row.id+" independently samples "+source.name)
			for i in range(model.skeleton.get_bone_count()):
				check(model.skeleton.get_bone_pose(i).is_finite(),row.id+" finite source pose "+source.name+" bone "+str(i))
		for clip in driver.stands:
			check(not ("swim" in clip.name.to_lower() or "fourth" in clip.name.to_lower() or "ready" in clip.name.to_lower() or "portrait" in clip.name.to_lower()),row.id+" excludes explicit modifier from ordinary Stand")
	for sample in native.checks:
		check(CosmeticAnimation.pick(drivers[sample.model].stands,float(sample.fraction)).name==sample.selected,sample.model+" matches native weighted choice "+str(sample.fraction))
	# Birth must actually appear, and a long frame must carry time into Stand.
	var born=models.hat_08;var birth_driver=drivers.hat_08;birth_driver.setup(born)
	check(born.active_clip=="Birth","original wreath attachment starts with Birth")
	var duration=float(born.clip.duration);birth_driver.advance(born,duration+.125)
	check(born.active_clip=="Stand" and is_equal_approx(born.animation_time,.125),"Birth carries frame remainder into Stand")
	check(not born.tail_only and not born.one_shot,"living attachment is not treated as a dead particle tail")
	# Different display frame sizes must not change the sequence of chosen clips.
	var a=make_model("hat_13");var b=make_model("hat_13")
	var da=CosmeticAnimation.new();var db=CosmeticAnimation.new();da.rng.seed=311;db.rng.seed=311;da.setup(a);db.setup(b)
	da.advance(a,39.375)
	for i in range(315):db.advance(b,.125)
	check(a.active_clip==b.active_clip and absf(a.animation_time-b.animation_time)<.00001 and da.rng.state==db.rng.state,"large frame and small frames select identical clips with identical remainder")
	check(is_equal_approx(a.visual_time,39.375) and is_equal_approx(b.visual_time,39.375),"variant selection preserves independent visual clocks")
	var state=da.rng.state;var time=a.animation_time;da.advance(a,0)
	check(state==da.rng.state and a.animation_time==time,"pause consumes neither animation time nor cosmetic randomness")
	# Check actual model event dispatch on a two-clip synthetic event fixture.
	a.data=a.data.duplicate(true);a.events_enabled=true;var seen=[]
	var clips=a.data.clips.filter(func(c):return c.name in ["Stand","Stand 2"])
	for clip in clips:
		clip.duration=1.0;clip.rarity=0
		clip.events=[{"time":0.0,"code":clip.name+" start","position":[0,0,0]},{"time":1.0,"code":clip.name+" end","position":[0,0,0]}]
	da.stands=clips;da.rng.seed=3;da.next_stand(a);a.visual_time=0
	a.native_event.connect(func(event,_position):seen.append(event.code))
	var first=a.active_clip;da.advance(a,1.0)
	check(seen==[first+" start",first+" end"],"boundary emits old endpoint once without spuriously restarting old clip")
	var second=a.active_clip;da.advance(a,.1)
	check(seen==[first+" start",first+" end",second+" start"],"next positive step emits new clip start exactly once")
	a.events_enabled=false;a.play("Death",true);a.one_shot=true;state=da.rng.state;da.advance(a,20)
	check(a.active_clip=="Death" and da.rng.state==state,"retirement never randomizes back into a live Stand")
	a.free();b.free()
	for model in models.values():model.free()
	await process_frame
	FileAccess.open("res://research/cosmetic-animation-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"source_clips":source_clips,"native_choices":native.checks.size()},"\t"))
	print("COSMETIC ANIMATION ",passed," passed; ",failures.size()," failed");quit(1 if not failures.is_empty() else 0)
