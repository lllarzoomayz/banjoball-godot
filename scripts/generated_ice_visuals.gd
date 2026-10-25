extends Node3D
## Script-created destructables share the simulation's original random draws.
## Source MDXs have only Stand: do not invent shattering geometry on Kill.
const Model=preload("res://scripts/wc3_model.gd")
var game
var catalog={}
var rows=[]
var models=[]
var killed={}
var adapter
var native_rows={}

func setup(owner_game):
	game=owner_game
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/scenery/generated-ice.json"))
	frame(0)

func bind():
	for model in models:model.free()
	models.clear();killed.clear();native_rows.clear();adapter=null
	rows=game.sim.generated_ice
	for row in rows:
		var model=Model.new();add_child(model);model.load_actor(catalog[row.id].model,Color.WHITE)
		model.play("Stand",true);models.append(model)

func frame(delta):
	if not is_same(rows,game.sim.generated_ice):bind()
	if adapter!=game.sim.apocalypse:
		adapter=game.sim.apocalypse;native_rows.clear()
		if adapter!=null:
			for row in adapter.rules.world.objects.values():
				if row.get("generated")=="FrozenIce":native_rows[int(row.generated_index)]=row
	var center=game.sim.arena.data.center
	for i in range(models.size()):
		var row=native_rows.get(i,rows[i]);var model=models[i];var p=row.position;var s=row.scale
		model.position=Vector3(p[0]-center[0],p[2]-game.sim.arena.world_height_offset,-(p[1]-center[1]))/100.0
		model.rotation.y=row.angle;model.scale=Vector3(s[0],s[2],s[1])
		if not row.get("alive",true) and not killed.has(i):
			killed[i]=true
			get_tree().call_group("wc3_destructable_events","destructable_death",self,row.id,model.global_position)
			# No Death sequence exists in any of the five source ice models.
			# Retain the source model; Warcraft's missing-sequence fallback is
			# uncalibrated, as with the map's generated water destructables.
		model.advance(0 if game.paused else maxf(0,delta))
