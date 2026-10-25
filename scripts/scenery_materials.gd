extends RefCounted
## Shared original texture-index animation for placed, static geometry.
## Each field has its own clock/materials; all its matching instances share them.
const Tracks=preload("res://scripts/wc3_uv.gd")
static var catalog={}
static var texture_cache={}
var clock=0.0
var bindings=[]
var texture_changes=0
func _init():
	if catalog.is_empty():catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/scenery/animated_materials.json"))
func bind(key: String,index: int,node: MultiMeshInstance3D,original: Material):
	if not catalog.has(key):return
	var data=catalog[key];var layers=data.meshes[index].layers
	assert(layers.size()==1,"Animated scenery layer composition needs explicit support")
	var layer=layers[0]
	if not layer.TextureID is Dictionary:return
	if not texture_cache.has(key):
		var textures=[]
		for source in data.textures:textures.append(load(texture_name(source.Image)))
		texture_cache[key]=textures
	var material=original.duplicate();node.material_override=material
	bindings.append({"data":data,"layer":layer,"material":material,"textures":texture_cache[key],"texture_id":-1})
	update_materials()
func advance(delta: float):
	clock+=delta
	if delta>0:update_materials()
func update_materials():
	for row in bindings:
		var interval=row.data.interval
		var frame=interval[0]+fposmod(clock*1000,interval[1]-interval[0])
		var index=int(Tracks.sample(row.layer.TextureID,[0],frame,interval,clock,row.data.periods)[0])
		assert(index>=0 and index<row.textures.size())
		if index!=row.texture_id:
			row.material.albedo_texture=row.textures[index];row.texture_id=index;texture_changes+=1

static func texture_name(source: String) -> String:
	var regex=RegEx.new();regex.compile("[^a-z0-9._-]+")
	return "res://assets/textures/"+regex.sub(source.to_lower(),"_",true)+".png"
