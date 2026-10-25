extends Node
## Local presentation/settings. No gameplay random numbers or physics changes.
const Overlay=preload("res://scripts/aim_overlay.gd")
var game
var overlay
var sound_enabled=true
var follow_camera=false
var last_sound=0
var last_countdown=-1
var last_phase=""
var voices=[]
var next_voice=0
var sounds={}
var preferences=ConfigFile.new()
var mobile_mode="stick"
var quality="balanced"
var model_audio
var sound_button: Button
var follow_button: Button

func setup(owner_game):
	game=owner_game
	# UI checks start with fresh-install defaults without changing saved choices.
	if "--test-ui" not in OS.get_cmdline_user_args():preferences.load("user://preferences.cfg")
	sound_enabled=preferences.get_value("play","sound",true)
	follow_camera=preferences.get_value("play","follow",false)
	mobile_mode=preferences.get_value("touch","movement","stick")
	quality=preferences.get_value("touch","quality","balanced")
	for pair in [[game.character_select,"character"],[game.field_select,"field"],[game.mode_select,"rules"]]:
		var select=pair[0]
		select.select(clampi(int(preferences.get_value("play",pair[1],0)),0,select.item_count-1))
		select.item_selected.emit(select.selected)
	for name in ["kick","catch","goal","tick","start"]:
		sounds[name]=load("res://assets/audio/"+name+".wav")
	for number in range(1,6):sounds["shout"+str(number)]=load("res://assets/audio/shout"+str(number)+".mp3")
	for i in range(6):
		var voice=AudioStreamPlayer.new();voice.volume_db=-9;add_child(voice);voices.append(voice)
	model_audio=preload("res://scripts/wc3_event_audio.gd").new();add_child(model_audio);model_audio.setup(game)
	var layer=CanvasLayer.new();layer.layer=2;add_child(layer)
	overlay=Overlay.new();overlay.game=game;layer.add_child(overlay)
	if not game.mobile_enabled:
		sound_button=game.button("声音",Rect2(24,197,112,36),func():sound_enabled=not sound_enabled;save_settings())
		follow_button=game.button("跟随镜头",Rect2(148,197,116,36),func():follow_camera=not follow_camera;save_settings())
		sound_button.reparent(game.desktop_tools);sound_button.position=Vector2(12,282)
		follow_button.reparent(game.desktop_tools);follow_button.position=Vector2(144,282)

func save_settings():
	if is_instance_valid(game.perf) and game.perf.benchmarking:return
	# Test and preview runs must not overwrite the player's choices.
	if "--capture" in OS.get_cmdline_user_args() or "--test-ui" in OS.get_cmdline_user_args():return
	preferences.set_value("play","sound",sound_enabled)
	preferences.set_value("play","follow",follow_camera)
	preferences.set_value("touch","movement",mobile_mode)
	preferences.set_value("touch","quality",quality)
	preferences.set_value("play","character",game.character_select.selected)
	preferences.set_value("play","field",game.field_select.selected)
	preferences.set_value("play","rules",game.mode_select.selected)
	preferences.save("user://preferences.cfg")

func play(name: String):
	if not sound_enabled or not sounds.has(name):return
	var voice=voices[next_voice];next_voice=(next_voice+1)%voices.size()
	voice.stream=sounds[name];voice.play()

func frame(delta: float):
	var sim=game.sim
	model_audio.frame()
	for voice in voices:
		if not sound_enabled:voice.stop()
		voice.stream_paused=game.paused
	if is_instance_valid(sound_button):sound_button.text="声音："+("开" if sound_enabled else "关")
	if is_instance_valid(follow_button):follow_button.text="跟随："+("开" if follow_camera else "关")
	for event in sim.audio_events:
		if event.id>last_sound:
			last_sound=event.id
			if not game.paused:play(event.kind)
	var countdown=ceili(sim.countdown) if sim.match_state=="countdown" else -1
	if countdown!=last_countdown and countdown>0 and not game.paused:play("tick")
	if last_phase=="countdown" and sim.match_state=="playing" and not game.paused:play("start")
	last_countdown=countdown;last_phase=sim.match_state
	if follow_camera and not game.paused:
		var player=sim.players[sim.controlled].pos
		var ball=Vector2(sim.ball.x,sim.ball.y)
		var aftermath=is_instance_valid(game.aftermath_controls) and game.aftermath_controls.active()
		if aftermath and game.aftermath_controls.army().local_owner(game.aftermath_controls.army().selected):
			var army=game.aftermath_controls.army();var position=army.units[army.selected].pos
			player=Vector2(position.x,position.y);ball=player
		var target=player.lerp(ball,0.25)
		if not aftermath:
			target.x=clampf(target.x,-sim.arena.half_size.x*0.70,sim.arena.half_size.x*0.70)
			target.y=clampf(target.y,-sim.arena.half_size.y*0.55,sim.arena.half_size.y*0.55)
		game.focus=game.focus.lerp(Vector3(target.x/100,0,-target.y/100),1-exp(-delta*5))
		game.update_camera()

func background_pause():
	if is_instance_valid(game.menu_root) and not game.paused:
		game.open_menu()
		game.sim.notice="已暂停，点继续返回比赛。"

func _exit_tree():
	for voice in voices:
		if is_instance_valid(voice):voice.stop()
