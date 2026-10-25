extends Node3D
## Original samples / authored event times. Godot spatial mixing is an
## approximation of Warcraft's mixer; EAX, channel budgets and occlusion differ.
const VOICE_LIMIT=24
var game
var catalog={}
var scenery_catalog={}
var samples={}
var voices=[]
var cosmetic_random=RandomNumberGenerator.new()
var serial=0
var played_count=0
var last_event={}
var listener: AudioListener3D

func setup(owner_game):
	game=owner_game;cosmetic_random.seed=270151
	listener=AudioListener3D.new();add_child(listener);listener.make_current();update_listener()
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/model-events/catalog.json"))
	for row in catalog.values():
		for path in row.files:
			if not samples.has(path):samples[path]=load(path)
	for i in range(VOICE_LIMIT):
		var voice=AudioStreamPlayer3D.new();voice.max_db=-9
		voice.attenuation_filter_cutoff_hz=20500;voice.doppler_tracking=AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(voice);voices.append(voice)
	add_to_group("wc3_model_events")
	add_to_group("wc3_destructable_events")

func clear():
	for voice in voices:voice.stop();voice.stream_paused=false
	last_event={}

func frame():
	update_listener()
	if not game.experience.sound_enabled:
		clear();return
	for voice in voices:voice.stream_paused=game.paused

func update_listener():
	var camera=get_viewport().get_camera_3d()
	if camera:
		# Listen near the viewed pitch, not 30+ metres above it at the camera.
		# Otherwise the source's 30-metre cutoff mutes even the centre of view.
		listener.global_transform=Transform3D(camera.global_basis,Vector3(game.focus.x,1.5,game.focus.z))

func model_event(model,event: Dictionary,position: Vector3):
	if event.type!="SND" or not game.is_ancestor_of(model):return
	if game.paused or not game.experience.sound_enabled or not model.is_visible_in_tree() or model.visibility_amount<=0.01 or model.fade_alpha<=0.01:return
	if not catalog.has(event.code):return
	var row=catalog[event.code]
	play_row(row,position,{"code":event.code,"model":model.data.actor.id,"clip":model.active_clip,"time":event.time})

func destructable_death(source_field,kind: String,position: Vector3):
	if not game.is_ancestor_of(source_field) or game.paused or not game.experience.sound_enabled:return
	if scenery_catalog.is_empty():scenery_catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/scenery-events/catalog.json"))
	var label=str(scenery_catalog.types.get(kind,"_"))
	if not scenery_catalog.sounds.has(label):return
	play_row(scenery_catalog.sounds[label],position,{"code":label,"model":kind,"clip":"Death","time":0.0})

func play_row(row: Dictionary,position: Vector3,identity: Dictionary):
	if game.paused or not game.experience.sound_enabled:return
	if row.files.is_empty():return # Deliberate map mutes or absent source paths.
	var source=row.source
	update_listener()
	if listener.global_position.distance_to(position)>float(source.DistanceCutoff)/100.0:return
	var voice=null
	for candidate in voices:
		if not candidate.playing:voice=candidate;break
	if voice==null:
		# Deterministic bounded local mixer; no changes to simulation RNG. Exact
		# original per-channel preemption rules are not claimed here.
		var ordered=voices.duplicate()
		ordered.sort_custom(func(a,b):return a.get_meta("priority",0)<b.get_meta("priority",0) or (a.get_meta("priority",0)==b.get_meta("priority",0) and a.get_meta("serial",0)<b.get_meta("serial",0)))
		voice=ordered[0]
		if float(source.Priority)<float(voice.get_meta("priority",0)):return
	voice.stop();voice.stream_paused=false
	var path=row.files[cosmetic_random.randi_range(0,row.files.size()-1)]
	if not samples.has(path):samples[path]=load(path)
	voice.stream=samples[path];voice.global_position=position
	voice.unit_size=maxf(.01,float(source.MinDistance)/100.0)
	voice.max_distance=maxf(voice.unit_size,float(source.DistanceCutoff)/100.0)
	voice.volume_db=-9+linear_to_db(maxf(.0001,float(source.Volume)/127.0))
	var variance=float(source.PitchVariance) if "RANDOMPITCH" in str(source.Flags) else 0.0
	voice.pitch_scale=maxf(.01,float(source.Pitch)+cosmetic_random.randf_range(-variance,variance))
	serial+=1;voice.set_meta("serial",serial);voice.set_meta("priority",float(source.Priority))
	voice.play();played_count+=1
	last_event=identity.duplicate();last_event.merge({"position":position,"file":path,"pitch":voice.pitch_scale,"serial":serial})
