extends SceneTree
## Actual rendered stress scene: all twelve players leave full original trails.
func _initialize():call_deferred("run")

func run():
	var world=load("res://main.tscn").instantiate()
	root.add_child(world)
	world.start_game(6)
	var s=world.sim
	s.match_state="playing";s.bot_enabled=false;s.ball=Vector3(1700,0,0)
	for i in range(12):
		s.Characters.configure(s.players[i],"h005")
		s.players[i].pos=Vector2(-800,-1100+i*200);s.players[i].body=0;s.players[i].angle=0
		s.Characters.use(s,i,Vector2(1000,s.players[i].pos.y))
	world.rebuild_actors();s.advance(15.0/32);world.paused=true;world.update_visuals(0)
	world.set_process(false)
	for i in range(15):
		world.update_visuals(0)
		await process_frame
	var samples=[]
	var paused_started=Time.get_ticks_usec()
	for i in range(45):
		var started=Time.get_ticks_usec()
		world.update_visuals(0)
		samples.append((Time.get_ticks_usec()-started)/1000.0)
		await process_frame
	var paused_wall_ms=(Time.get_ticks_usec()-paused_started)/1000.0
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/tackle-twelve-player-preview.png")
	var valid=s.tackle_shadows.size()==180 and world.tackle_shadow_models.size()==180
	var animated=[]
	var animated_started=Time.get_ticks_usec()
	# Advance only the trails by a known 1/60 step, keeping all 180 visible.
	# Evaluate once per real render frame. Explicit timings avoid the engine's
	# one-second Performance monitor retaining a stale scene-load sample.
	for i in range(45):
		for state in s.tackle_shadows:state.age+=1.0/60
		var started=Time.get_ticks_usec()
		world.update_visuals(0)
		animated.append((Time.get_ticks_usec()-started)/1000.0)
		await process_frame
	var animated_wall_ms=(Time.get_ticks_usec()-animated_started)/1000.0
	await RenderingServer.frame_post_draw
	var sum=0.0
	for sample in samples:sum+=sample
	samples.sort()
	var animated_sum=0.0
	for sample in animated:animated_sum+=sample
	animated.sort()
	var report={"passed":valid,"rendered_frames_after_warmup":45,"players":s.players.size(),"shadows":world.tackle_shadow_models.size(),
		"paused_mean_visual_cpu_ms":sum/samples.size(),"paused_p95_visual_cpu_ms":samples[42],
		"animated_mean_visual_cpu_ms":animated_sum/animated.size(),"animated_p95_visual_cpu_ms":animated[42],
		"paused_mean_frame_wall_ms":paused_wall_ms/45,"animated_mean_frame_wall_ms":animated_wall_ms/45,
		"note":"45 paused frames then 45 advancing full-trail frames. CPU visual-update timings exclude GPU/physics; not active-game FPS guarantee."}
	var f=FileAccess.open("res://research/tackle-render-check.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t"));f.close()
	print(JSON.stringify(report))
	world.queue_free();await process_frame
	quit(0 if valid else 1)
