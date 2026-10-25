extends RefCounted
## Shared, deterministic geometry; no renderer or PhysicsServer dependency.
## Native ball boundaries are CENTER-trigger volumes with authored normals.
## Practice solids use a 25-unit ball radius. Units use swept circular footprints.
const EPS=0.001
const BALL_RADIUS=25.0
var data: Dictionary
var fields=[]
var authored_pathing=[]
var field_index=0
var sides_swapped=false
var field_rect: Rect2
var bounds: Rect2
var half_size: Vector2
var walls: Array=[]
var obstacles: Array=[]
var boundaries: Array=[]
var goals: Array=[]
var guards: Array=[]
var revision=0
var course=0
var pillars=[]
var next_pillar_id=0
var world_height_offset=0.0
const COURSE_NAMES=["标准球场", "绕墙练习", "U 形绕行", "窄道练习", "转角窄道"]

func _init():
	fields=JSON.parse_string(FileAccess.get_file_as_string("res://research/fields.json")).fields
	authored_pathing=JSON.parse_string(FileAccess.get_file_as_string("res://research/authored-pathing.json")).fields
	set_field(0)

func set_field(index: int):
	sides_swapped=false
	field_index=clampi(index,0,fields.size()-1)
	data=fields[field_index]
	world_height_offset=float(data.world_height_offset)
	field_rect=rect(data.regions.Field)
	half_size=field_rect.size/2
	var left=rect(data.regions.Goal_1_Area);var right=rect(data.regions.Goal_2_Area)
	bounds=field_rect.merge(left).merge(right)
	walls.clear();boundaries.clear();goals.clear();guards.clear()
	# The map's placed YTpb blockers sit 32 units beyond the scripted pitch /
	# goal-corridor edges. Those event regions are not physical walking walls.
	# Preserve authored footprints, including concave corners and open mouths.
	for field in authored_pathing:
		if field.id==data.id:
			for raw in field.rectangles:walls.append(rect(raw))
			break
	# WPM terrain plus destructible pathing; include the thin outer walkable
	# strip newly exposed by removing the old synthetic enclosing rectangles.
	for raw in data.stall_blocked:walls.append(rect(raw))
	for b in data.boundaries:
		boundaries.append({"rect":rect(b.rect),"normal":Vector3(cos(deg_to_rad(b.normal_degrees)),sin(deg_to_rad(b.normal_degrees)),0),"low":float(b.min_height),"high":float(b.max_height),"name":b.name})
	for side in [1,2]:
		goals.append(rect(data.regions["Goal_"+str(side)]))
		guards.append([rect(data.regions["Goal_"+str(side)+"_Front"]),rect(data.regions["Goal_"+str(side)+"_Area"])])
	set_course(course)

func keeper_position(team: int) -> Vector2:
	return Vector2(-attack_direction(team)*(half_size.x+74),0)

func attack_direction(team: int) -> float:
	return -signf(goals[team].get_center().x)

func swap_ends():
	goals.reverse();guards.reverse();sides_swapped=not sides_swapped
	revision+=1

func shot_target(team: int,y: float=0) -> Vector2:
	var goal: Rect2=goals[1-team]
	return Vector2(goal.position.x+160 if attack_direction(team)>0 else goal.end.x-160,clampf(y,-145,145))

func terrain_walkable(point: Vector2) -> bool:
	# Source WPM, independent of pitch wall rectangles and temporary pillars.
	for raw in data.stall_blocked:
		if rect(raw).has_point(point):return false
	return rect(data.terrain_sample_bounds).has_point(point)

func in_playable_region(point: Vector2) -> bool:
	# Tackle tests the map's scripted region union independently of native
	# walking pathing. Authored ground blockers extend a further 32 units.
	return field_rect.has_point(point) or rect(data.regions.Goal_1_Area).has_point(point) or rect(data.regions.Goal_2_Area).has_point(point)

static func rect(raw: Array) -> Rect2:
	return Rect2(Vector2(raw[0],raw[1]),Vector2(raw[2]-raw[0],raw[3]-raw[1]))

func set_course(index: int):
	course=posmod(index,COURSE_NAMES.size())
	obstacles.clear()
	clear_pillars()
	match course:
		1:
			add_box(Rect2(-70,-480,140,720),240)
			add_box(Rect2(620,300,100,330),65)
		2:
			add_box(Rect2(-180,-380,90,760),240)
			add_box(Rect2(-180,290,700,90),240)
			add_box(Rect2(-180,-380,700,90),240)
		3:
			# 48-unit opening blocks a 60-unit diameter unit; 96 admits it.
			add_box(Rect2(-40,-half_size.y,80,half_size.y-24),240)
			add_box(Rect2(-40,24,80,half_size.y-24),240)
			add_box(Rect2(620,-half_size.y,80,half_size.y-248),240)
			add_box(Rect2(620,-152,80,half_size.y+152),240)
		4:
			# Added practice: 96-wide L corridor, with low walls for visibility.
			add_box(Rect2(-1000,48,952,80),96)
			add_box(Rect2(-128,128,80,872),96)
			add_box(Rect2(48,-48,80,1048),96)
			add_box(Rect2(-1000,-128,1128,80),96)
	revision+=1

func add_box(r: Rect2,height: float):
	obstacles.append({"rect":r,"height":height})
	revision+=1

func add_pillar(center: Vector2,owner: int) -> Dictionary:
	next_pillar_id+=1
	var pillar={"id":next_pillar_id,"center":center,"radius":60.0,"height":300.0,"life":3.0,"age":0.0,"owner":owner,"knocked_units":{},"ball_knocked":false}
	pillars.append(pillar)
	revision+=1
	return pillar

func clear_pillars():
	if not pillars.is_empty():pillars.clear();revision+=1

func expire_pillars():
	var remaining=pillars.filter(func(p):return p.life>0)
	if remaining.size()!=pillars.size():pillars=remaining;revision+=1

static func circle_overlaps_rect(p: Vector2,radius: float,r: Rect2) -> bool:
	var nearest=p.clamp(r.position,r.end)
	return p.distance_squared_to(nearest)<radius*radius-minf(EPS,radius*radius*0.001)

func point_free(p: Vector2,radius: float,extra: Array=[]) -> bool:
	if not bounds.grow(512).has_point(p):return false
	for r in walls:
		if circle_overlaps_rect(p,radius,r):return false
	for o in obstacles:
		if circle_overlaps_rect(p,radius,o.rect):return false
	for pillar in pillars:
		if p.distance_to(pillar.center)<radius+pillar.radius:return false
	for r in extra:
		if circle_overlaps_rect(p,radius,r):return false
	return true

static func circle_hit(a: Vector2,d: Vector2,center: Vector2,radius: float) -> Dictionary:
	var q=a-center
	var c=q.length_squared()-radius*radius
	if c<=EPS:
		var normal=q.normalized() if q.length()>EPS else -d.normalized()
		return {"t":0.0,"normal":normal} if d.dot(normal)<-EPS else {}
	var aa=d.length_squared()
	if aa<EPS:return {}
	var bb=q.dot(d)
	var disc=bb*bb-aa*c
	if disc<0:return {}
	var t=(-bb-sqrt(disc))/aa
	if t<0 or t>1:return {}
	var normal=(a+d*t-center).normalized()
	return {"t":t,"normal":normal} if d.dot(normal)<-EPS else {}

static func disk_rect_hit(a: Vector2,d: Vector2,r: Rect2,radius: float) -> Dictionary:
	# Exact rounded Minkowski boundary: four side segments and four corner arcs.
	var best={}
	# A phased skill may finish with the footprint already intersecting a solid.
	# Permit escape, but don't miss an inward sweep whose entry is behind us.
	if circle_overlaps_rect(a,radius,r):
		var away=a-a.clamp(r.position,r.end)
		if away.length_squared()>EPS and d.dot(away.normalized())<-EPS:
			return {"t":0.0,"normal":away.normalized()}
	for axis in range(2):
		if absf(d[axis])<EPS:continue
		var other=1-axis
		for side in [-1,1]:
			var face=(r.position[axis]-radius) if side==-1 else (r.end[axis]+radius)
			var normal=Vector2.ZERO
			normal[axis]=side
			if d.dot(normal)>=-EPS:continue
			var t=(face-a[axis])/d[axis]
			var across=a[other]+d[other]*t
			if t>=-EPS and t<=1 and across>=r.position[other] and across<=r.end[other]:
				if best.is_empty() or t<best.t:best={"t":maxf(0,t),"normal":normal}
	for corner in [r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]:
		var h=circle_hit(a,d,corner,radius)
		if not h.is_empty() and (best.is_empty() or h.t<best.t):best=h
	return best

func sweep_unit(a: Vector2,d: Vector2,radius: float,extra: Array=[],height: float=0,owner: int=-1) -> Dictionary:
	var best={}
	for r in walls+extra:
		var h=disk_rect_hit(a,d,r,radius)
		if not h.is_empty() and (best.is_empty() or h.t<best.t):best=h
	for o in obstacles:
		var h=disk_rect_hit(a,d,o.rect,radius)
		if not h.is_empty() and (best.is_empty() or h.t<best.t):best=h
	for pillar in pillars:
		if height>=pillar.height or pillar.knocked_units.has(owner):continue
		var h=circle_hit(a,d,pillar.center,pillar.radius+radius)
		if not h.is_empty() and (best.is_empty() or h.t<best.t):
			h.damping=0.9;h.name="pillar";best=h
	return best

static func box_hit(a: Vector3,d: Vector3,low: Vector3,high: Vector3) -> Dictionary:
	var enter=-INF
	var leave=INF
	var normal=Vector3.ZERO
	for axis in range(3):
		if absf(d[axis])<0.0000001:
			if a[axis]<low[axis] or a[axis]>high[axis]:return {}
			continue
		var t0=(low[axis]-a[axis])/d[axis]
		var t1=(high[axis]-a[axis])/d[axis]
		var near=minf(t0,t1)
		if near>enter:
			enter=near
			normal=Vector3.ZERO
			normal[axis]=-signf(d[axis])
		leave=minf(leave,maxf(t0,t1))
		if enter>leave:return {}
	if leave<0 or enter>1:return {}
	return {"t":maxf(0,enter),"normal":normal}

func sweep_ball(a: Vector3,d: Vector3,radius: float=BALL_RADIUS,include_pillars: bool=true) -> Dictionary:
	var best={}
	for b in boundaries:
		if d.dot(b.normal)>=-EPS:continue
		var r: Rect2=b.rect
		var h=box_hit(a,d,Vector3(r.position.x,r.position.y,b.low),Vector3(r.end.x,r.end.y,b.high))
		if not h.is_empty() and (best.is_empty() or h.t<best.t):
			h.normal=b.normal
			h.name=b.name
			best=h
	for o in obstacles:
		var r: Rect2=o.rect
		var h=box_hit(a,d,Vector3(r.position.x-radius,r.position.y-radius,-1000),Vector3(r.end.x+radius,r.end.y+radius,o.height+radius))
		if not h.is_empty() and d.dot(h.normal)<-EPS and (best.is_empty() or h.t<best.t):
			h.name="practice"
			best=h
	for pillar in pillars:
		if not include_pillars:break
		if pillar.ball_knocked:continue
		var h=circle_hit(Vector2(a.x,a.y),Vector2(d.x,d.y),pillar.center,90.0)
		if not h.is_empty() and a.z+d.z*h.t>=0 and a.z+d.z*h.t<pillar.height and (best.is_empty() or h.t<best.t):
			h.normal=Vector3(h.normal.x,h.normal.y,0)
			h.name="pillar";h.damping=0.9;best=h
	return best

func sweep_object(position: Vector3,delta: Vector2,radius: float,restrictions: Array,owner: int) -> Dictionary:
	# Scripted Object movement uses center-trigger boundary regions. The normal
	# walk planner still uses footprints; do not let its artificial outer walls
	# swallow the region event before the player's center reaches it.
	var best={};var point=Vector2(position.x,position.y)
	for boundary in boundaries:
		var normal=Vector2(boundary.normal.x,boundary.normal.y)
		if delta.dot(normal)>=-EPS or position.z<boundary.low or position.z>boundary.high:continue
		var r: Rect2=boundary.rect
		var hit=box_hit(position,Vector3(delta.x,delta.y,0),Vector3(r.position.x,r.position.y,boundary.low),Vector3(r.end.x,r.end.y,boundary.high))
		if not hit.is_empty() and (best.is_empty() or hit.t<best.t):best={"t":hit.t,"normal":normal,"kind":"boundary","name":boundary.name}
	for team in range(guards.size()):
		for r in guards[team]:
			if not restrictions.has(r):continue
			var hit=box_hit(position,Vector3(delta.x,delta.y,0),Vector3(r.position.x,r.position.y,-10000),Vector3(r.end.x,r.end.y,10000))
			if not hit.is_empty() and (best.is_empty() or hit.t<best.t):best={"t":hit.t,"normal":Vector2(hit.normal.x,hit.normal.y),"kind":"goal","team":team}
	for o in obstacles:
		var hit=disk_rect_hit(point,delta,o.rect,radius)
		if not hit.is_empty() and (best.is_empty() or hit.t<best.t):hit.kind="practice";best=hit
	for raw in data.terrain_blocked:
		var hit=disk_rect_hit(point,delta,rect(raw),radius)
		if not hit.is_empty() and (best.is_empty() or hit.t<best.t):hit.kind="terrain";best=hit
	for pillar in pillars:
		if position.z>=pillar.height or pillar.knocked_units.has(owner):continue
		var hit=circle_hit(point,delta,pillar.center,pillar.radius+radius)
		if not hit.is_empty() and (best.is_empty() or hit.t<best.t):hit.kind="pillar";best=hit
	return best

func goal_hit(a: Vector3,d: Vector3) -> Dictionary:
	var best={}
	for i in range(goals.size()):
		var r: Rect2=goals[i]
		var h=box_hit(a,d,Vector3(r.position.x,r.position.y,0),Vector3(r.end.x,r.end.y,299.999))
		if not h.is_empty() and (best.is_empty() or h.t<best.t):
			h.team=1-i
			best=h
	return best

func in_guard(p: Vector2,team: int) -> bool:
	for r in guards[team]:
		if r.has_point(p):return true
	return false
