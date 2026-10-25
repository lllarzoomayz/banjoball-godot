extends RefCounted
static func code(room_id: String) -> String:
	return room_id.left(6).to_upper()
static func normalize(value: String) -> String:
	var text=value.strip_edges().replace(" ","").replace("-","").to_upper()
	if text.length()!=6:return ""
	for character in text:
		if not character in "0123456789ABCDEF":return ""
	return text
static func find_room(rooms: Array,value: String) -> String:
	var wanted=normalize(value)
	if wanted.is_empty():return ""
	var matches=[]
	for room in rooms:
		if code(str(room.get("id","")))==wanted:matches.append(str(room.id))
	# Never send the player into a different room if two prefixes collide.
	return matches[0] if matches.size()==1 else ""
