extends SceneTree
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func wait_mixer(seconds: float):
	# Audio runs in wall time. A SceneTreeTimer created in a slow loading frame
	# can consume that frame's old delta immediately, before a mixer buffer runs.
	var until=Time.get_ticks_usec()+int(seconds*1000000)
	while Time.get_ticks_usec()<until:await process_frame
func run():
	var game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	game.enter_practice();game.experience.sound_enabled=true
	var bus=game.experience.model_audio
	check(bus.catalog.size()==91 and bus.samples.size()==97 and bus.catalog.has("MARL") and bus.catalog.has("MARR"),"resolved native SND definitions and original WAVs include arrow launch/impact")
	for path in bus.samples:
		check(bus.samples[path] is AudioStreamWAV and bus.samples[path].get_length()>0,"imported playable original sample "+path)
	check(bus.catalog.ACSI.files.is_empty() and bus.catalog.ACSI.muted_map_overrides.size()==1,"map intentionally muted Silence is not restored from base MPQ")
	check(bus.catalog.DANP.files.is_empty() and bus.catalog.DANP.missing.size()==1,"missing tree sound remains documented rather than substituted")
	var rng=game.sim.random.state
	var fx=game.original_effects.burst("fx_shout",Vector3.ZERO)
	var count=bus.played_count;fx.advance(0)
	check(bus.played_count==count,"effect setup does not play before positive animation progress")
	fx.advance(.01)
	check(bus.played_count==count+1 and bus.last_event.code=="ABTR","actual effect animation reaches the runtime audio mixer")
	check(bus.voices.any(func(v):return v.playing and v.stream==bus.samples[bus.last_event.file]),"a live spatial audio voice uses the selected original stream")
	check(game.sim.random.state==rng,"cosmetic audio does not consume gameplay random state")
	await process_frame
	await process_frame
	var active=bus.voices.filter(func(v):return v.playing)
	check(not active.is_empty(),"pause check has a started audio voice rather than an empty pool")
	game.open_menu();bus.frame()
	check(bus.voices.filter(func(v):return v.playing).all(func(v):return v.stream_paused),"pause freezes active sound voices")
	# Stream pause reaches the mixer on its next buffer. Measure the stationary
	# position after that handoff, rather than racing the already mixed buffer.
	await wait_mixer(.06)
	var frozen=active[0].get_playback_position()
	await wait_mixer(.06)
	check(absf(active[0].get_playback_position()-frozen)<.002,"paused audio playback position stays frozen across mixer frames")
	fx.play("Birth",true);fx.advance(.01);check(bus.played_count==count+1,"paused gameplay cannot start another voice")
	game.close_menu();bus.frame();check(bus.voices.all(func(v):return not v.stream_paused),"resume unpauses active voices")
	await wait_mixer(.06)
	check(active[0].get_playback_position()>frozen,"resumed voice advances from the paused sample")
	game.experience.sound_enabled=false;bus.frame()
	check(bus.voices.all(func(v):return not v.playing),"mute stops already playing spatial sound immediately")
	fx.play("Birth",true);fx.advance(.01);check(bus.played_count==count+1,"muted animation event is discarded")
	game.experience.sound_enabled=true;fx.advance(.01);check(bus.played_count==count+1,"unmuting does not replay an event missed while muted")
	fx.play("Birth",true);fx.hide();fx.advance(.01);check(bus.played_count==count+1,"hidden models do not leak spatial sound")
	fx.show();fx.position=Vector3(1000,0,0);fx.play("Birth",true);fx.advance(.01)
	check(bus.played_count==count+1,"source distance cutoff prevents far-away voice allocation")
	fx.position=Vector3.ZERO;fx.play("Birth",true);fx.advance(.01)
	check(bus.played_count==count+2,"new visible audible cast can play after mute and pause")
	game.rebuild_actors();check(bus.voices.all(func(v):return not v.playing),"reset clears old-match sound voices")
	# Apocalypse art is not exposed as a gameplay mode yet. Its real source
	# animation events must nevertheless reach the same mixer/decal systems.
	for row in [["apoc_nuclear","Birth","DHLB",1],["apoc_animate_dead","Birth","ASKW",1],["apoc_absorb","Death","MKGH",1],["apoc_skeleton","Death","DSKE",2]]:
		var art=preload("res://scripts/wc3_model.gd").new();game.add_child(art);art.load_actor(row[0],Color.WHITE)
		art.play(row[1],true);var audio_before=bus.played_count;var decals_before=game.event_decals.total_emitted
		var cue=art.clip.events.filter(func(e):return e.type=="SND" and e.code==row[2])
		check(cue.size()==row[3],"source clip retains original Apocalypse sound nodes, including the two skeleton death nodes "+row[0])
		if cue.is_empty():art.free();continue
		if cue[0].time>0:
			art.advance(float(cue[0].time)*.5)
			check(bus.played_count==audio_before,"Apocalypse sound waits for its original event time "+row[0])
		art.advance(float(cue[0].time)-art.animation_time+.001)
		check(bus.played_count==audio_before+row[3] and bus.last_event.code==row[2],"every original Apocalypse event reaches mixer "+row[0])
		if row[0]=="apoc_nuclear":
			check(game.event_decals.total_emitted==decals_before+1,"nuclear source UBR event creates the original ground scorch")
		art.free();bus.clear()
	var source_field=game.field_scenery;var audio_before=bus.played_count
	check(bus.scenery_catalog.is_empty(),"destructable audio is lazy and adds no normal-match sample loading")
	bus.destructable_death(source_field,"LTlt",Vector3.ZERO)
	check(bus.played_count==audio_before+1 and bus.last_event.code=="TreeWallDeath","original SLK TreeWallDeath reaches spatial audio")
	check(bus.scenery_catalog.sounds.TreeWallDeath.files.size()==3,"all three original TreeFall variants retained")
	game.paused=true;bus.destructable_death(source_field,"LTlt",Vector3.ZERO)
	game.paused=false;game.experience.sound_enabled=false;bus.destructable_death(source_field,"LTlt",Vector3.ZERO)
	game.experience.sound_enabled=true;bus.destructable_death(source_field,"LTlt",Vector3(1000,0,0))
	check(bus.played_count==audio_before+1,"destructable pause mute and native cutoff gates are respected")
	bus.clear();audio_before=bus.played_count
	var expected=0;bus.update_listener()
	for placed in source_field.scene_cache[source_field.field_id].placements:
		if not source_field.is_placement_visible(int(placed.editor_id)):continue
		var kind=str(placed.key).get_slice("_",0);var label=str(bus.scenery_catalog.types.get(kind,"_"))
		if not bus.scenery_catalog.sounds.has(label) or float(placed.get("life",100))<=0:continue
		var source=bus.scenery_catalog.sounds[label];var p=placed.position;var position=Vector3(p[0],p[2],-p[1])/100.0
		if not source.files.is_empty() and bus.listener.global_position.distance_to(position)<=float(source.source.DistanceCutoff)/100:expected+=1
	var rng_before=game.sim.random.state;var state=source_field.destruction_state();state.kill_destructables()
	check(expected>0 and bus.played_count==audio_before+expected,"actual field destruction emits every audible original death sound")
	check(game.sim.random.state==rng_before,"destructable sound choice leaves gameplay RNG untouched")
	audio_before=bus.played_count;state.kill_destructables()
	check(bus.played_count==audio_before,"repeated cleanup does not replay death audio")
	state.clear()
	for id in source_field.placement_slots:
		var placed=source_field.placement_slots[id].placement
		if str(placed.key).begins_with("LTlt_"):
			state.replace_tree(id,3);break
	check(bus.played_count==audio_before,"CreateDeadDestructable replacement does not trigger a KillDestructable sound")
	game.free()
	FileAccess.open("res://research/model-event-audio-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("MODEL AUDIO ",passed," passed; ",failures.size()," failed");quit(1 if not failures.is_empty() else 0)
