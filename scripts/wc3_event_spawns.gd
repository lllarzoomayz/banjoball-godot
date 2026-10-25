extends Node3D
## Detached models emitted by original MDX SPN keys. Source sequence zero
## runs once in world space, then releases the effect at its authored end.
const Model=preload("res://scripts/wc3_model.gd")
var game
var catalog={}
var active=[]
var emitted_count=0
var missing_count=0

func setup(owner_game):
	game=owner_game
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/events/spawns.json"))
	add_to_group("wc3_model_events")

func clear():
	for model in active:
		if is_instance_valid(model):model.free()
	active.clear()

func model_event(parent_model,event: Dictionary,world_position: Vector3):
	if event.type!="SPN" or not game.is_ancestor_of(parent_model):return
	if game.paused or not parent_model.is_visible_in_tree() or parent_model.visibility_amount<=.01 or parent_model.fade_alpha<=.01:return
	if not catalog.has(event.code):return
	var source=catalog[event.code]
	if source.model=="":
		if source.get("missing",false):missing_count+=1
		return
	var model=Model.new();add_child(model)
	model.load_actor(source.model,parent_model.team_color)
	model.one_shot=true
	model.play(model.data.clips[0].name,true)
	var values=event.basis
	var native_basis=Basis(Vector3(values[0],values[1],values[2]),Vector3(values[3],values[4],values[5]),Vector3(values[6],values[7],values[8]))
	model.global_transform=Transform3D(parent_model.global_basis*Model.CONVERSION*native_basis*Model.CONVERSION.inverse(),world_position)
	model.visibility_amount=parent_model.visibility_amount
	model.fade_alpha=parent_model.fade_alpha
	model.advance(0)
	active.append(model);emitted_count+=1

func advance(delta: float):
	if delta<=0 or game.paused:return
	# Event consumers may append children while an animation advances.
	for model in active.duplicate():
		model.advance(delta)
		if model.animation_time>=float(model.clip.duration):
			active.erase(model);model.free()
