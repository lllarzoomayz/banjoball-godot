extends RefCounted
## Original map-wide BizTree, attached to the live Apocalypse registry.
## Native absolute coordinates remain independent of the current scene crop.
var host: WeakRef
var chosen={}
var object={}
var replacement={}
var next_time=INF
var text_at=-INF
var text_position=Vector3.ZERO
var invalid_selection_callbacks=0

func setup(adapter,source: Dictionary,already_replaced: bool,pending: float,text_age: float=-1):
	host=weakref(adapter);chosen=source.duplicate(true)
	var world=adapter.rules.world
	var old=world.find_editor(int(chosen.editor_id))
	if not old.is_empty():world.remove(int(old.uid))
	var p=Vector3(chosen.position[0],chosen.position[1],chosen.position[2])
	p.z=world.ground_height(Vector2(p.x,p.y))
	object={"pos":adapter.local(p),"previous":adapter.local(p),"apoc_velocity":Vector3.ZERO,"removed":already_replaced}
	if already_replaced:
		make_replacement(p)
		if text_age>=0:text_position=p;text_at=adapter.rules.clock-text_age
	else:
		adapter.register_external(chosen.model,object) # h01K/h01L are ANCIENT, non-Locust.
		if pending>=0:next_time=adapter.host.get_ref().clock_now()+pending

func select() -> bool:
	if object.removed:return false
	if next_time==INF:next_time=host.get_ref().host.get_ref().clock_now()+.5
	return true

func make_replacement(position: Vector3):
	var adapter=host.get_ref();var world=adapter.rules.world
	var ground=world.ground_height(Vector2(position.x,position.y))
	replacement=world.add({"id":chosen.type,"position":[position.x,position.y,ground],"angle":1.5*PI,"scale":[2.3,2.3,2.3],"variation":6,"life":100,"editor_id":-1,"original_editor":chosen.editor_id,"generated":"BizTree"})

func step(now: float):
	if now+1e-8<next_time:return
	next_time=INF
	# AutoIndex deindexes removed units before GetUnitById callbacks. Native
	# null/reused-index behaviour has not been sampled: retain explicit evidence
	# instead of resurrecting the removed tree or inventing a replacement here.
	if object.removed:invalid_selection_callbacks+=1;return
	var adapter=host.get_ref();text_position=adapter.absolute(object.pos)
	adapter.remove_nonplayer(object);make_replacement(text_position);text_at=now

func replacement_present() -> bool:
	return not replacement.is_empty() and host.get_ref().rules.world.objects.has(int(replacement.uid))
