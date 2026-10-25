extends RefCounted
## Original Franchise table and CreateDestructable transformations.
static var source={}
static func data() -> Dictionary:
	if source.is_empty():source=JSON.parse_string(FileAccess.get_file_as_string("res://assets/scenery/franchise.json"))
	return source
static func normalized(value: Dictionary) -> Dictionary:
	var home=clampi(int(value.get("home",1)),0,4);var away=clampi(int(value.get("away",4)),0,4)
	if home==away:away=(home+1)%5
	return {"enabled":bool(value.get("enabled",false)),"home":home,"away":away,"jersey":bool(value.get("jersey",true))}
static func team(config: Dictionary,index: int) -> Dictionary:
	return data().teams[int(config.get("home" if index==0 else "away",1 if index==0 else 4))]
static func name_for(config: Dictionary,index: int) -> String:
	return team(config,index).short if config.get("enabled",false) else ("蓝队" if index==0 else "红队")
static func color_for(config: Dictionary,index: int) -> Color:
	if config.get("enabled",false) and config.get("jersey",true):return Color(team(config,index).color)
	return Color("4f98ff") if index==0 else Color("e96653")
static func replacements(config: Dictionary,world) -> Array:
	var rows=[]
	if not config.get("enabled",false):return rows
	for original in data().placeholders:
		var pos=original.position;var is_logo=original.id=="B006"
		var chosen=team(config,1 if original.id=="B00D" else 0)
		var raw=chosen.logo if is_logo else chosen.banner
		var angle=270.0;var size=2.5
		if not is_logo:
			if pos[1]>12500:size=5.0
			else:angle=315.0 if pos[0]<-2000 else 225.0;size=2.0
		rows.append({"id":raw,"editor_id":-1,"original_editor":original.editor_id,"generated":"Franchise",
			"position":[pos[0],pos[1],world.ground_height(Vector2(pos[0],pos[1]))],"angle":deg_to_rad(angle),"scale":[size,size,size],"variation":0,"life":100})
	return rows
