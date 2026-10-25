extends RefCounted
## Playable native-unit aftermath. Source unit statistics and combat timings,
## with local navigation/contact scheduling (not bit-identical engine AI).
const DT=.03
const Native=preload("res://scripts/native_rules.gd")
var host: WeakRef
var catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/scenery/aftermath-units.json"))
var units=[]
var arrows=[]
var arrow_ends=[]
var next_time=INF
var clock=0.0
var selected=-1
var arrow_sequence=0
var arrow_end_sequence=0
var grid: AStarGrid2D
var grid_origin=Vector2.ZERO
var grid_size=Vector2i.ZERO

func setup(adapter):host=weakref(adapter);clock=adapter.rules.clock
func alive(id: int) -> bool:return id>=0 and id<units.size() and units[id].hp>0
func active() -> bool:return not units.is_empty()
func local_owner(id: int) -> bool:return alive(id) and units[id].owner==0
func spec(unit: Dictionary) -> Dictionary:return catalog.units[unit.rawcode]
func xy(unit: Dictionary) -> Vector2:return Vector2(unit.pos.x,unit.pos.y)
func adapter():return host.get_ref()
func sim():return adapter().host.get_ref()

func create_grid():
	grid=AStarGrid2D.new()
	var bounds=sim().arena.bounds.grow(384)
	grid_origin=(bounds.position/32).floor()*32;grid_size=Vector2i((bounds.size/32).ceil())
	grid.region=Rect2i(Vector2i.ZERO,grid_size);grid.cell_size=Vector2(32,32);grid.offset=grid_origin+Vector2(16,16)
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES;grid.update()
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var point=grid.offset+Vector2(x,y)*32
			grid.set_point_solid(Vector2i(x,y),not walkable(point,32))

func walkable(point: Vector2,radius: float) -> bool:
	return sim().arena.terrain_walkable(point) and sim().arena.point_free(point,radius)

func spawn(row: Dictionary):
	if grid==null:create_grid()
	var p=adapter().local(row.position);var data=catalog.units[row.rawcode]
	# CreateUnit can displace a blocked spawn. Local nearest-free search avoids
	# starting embedded in another body; exact native placement ties differ.
	var desired=Vector2(p.x,p.y);var placed=desired
	for attempt in range(129):
		var point=desired if attempt==0 else desired+Vector2.from_angle(attempt*2.399963)*sqrt(attempt)*24
		if walkable(point,data.radius) and units.all(func(u):return u.hp<=0 or xy(u).distance_to(point)>=float(spec(u).radius)+float(data.radius)):
			placed=point;break
	p=ground(placed)
	var unit={"id":units.size(),"rawcode":row.rawcode,"model":row.model,"owner":row.owner,"team":row.team,"pos":p,"previous":p,"angle":row.facing,"hp":float(data.hp),"order":"idle","destination":placed,"path":PackedVector2Array(),"axis":Vector2.ZERO,"target":-1,"cooldown_until":0.0,"hit_at":INF,"attack_serial":0,"attack_at":-INF,"dead_at":INF,"moving":false,"repath_at":0.0,"spawn_at":float(row.time)}
	row.unit_id=unit.id;units.append(unit)
	if selected<0 and unit.owner==0:selected=unit.id
	if next_time==INF:next_time=float(row.time)+DT

func ground(point: Vector2) -> Vector3:
	var p=adapter().absolute(Vector3(point.x,point.y,0))
	return Vector3(point.x,point.y,adapter().rules.world.ground_height(Vector2(p.x,p.y))-sim().arena.world_height_offset)

func choose(id: int) -> bool:
	if not local_owner(id):return false
	if alive(selected):
		units[selected].axis=Vector2.ZERO
		if units[selected].order=="direct":units[selected].order="idle"
	selected=id;return true

func cycle():
	var ids=[]
	for u in units:
		if local_owner(u.id):ids.append(u.id)
	if not ids.is_empty():choose(ids[(ids.find(selected)+1)%ids.size()])

func command(kind: String,point=Vector2.ZERO,target: int=-1) -> bool:
	if not local_owner(selected):return false
	var u=units[selected]
	if kind=="attack":
		if not alive(target) or units[target].team==u.team:return false
		if u.target!=target:u.hit_at=INF;u.attack_at=-INF
		u.target=target;u.order="attack";u.axis=Vector2.ZERO;u.path=PackedVector2Array();u.repath_at=0
		return true
	if kind not in ["move","move_direction","move_release","stop"]:return false
	u.hit_at=INF;u.attack_at=-INF;u.target=-1;u.path=PackedVector2Array()
	u.axis=point.limit_length(1) if kind=="move_direction" else Vector2.ZERO
	u.order="direct" if kind=="move_direction" else ("move" if kind=="move" else "idle")
	u.destination=point;u.repath_at=0
	return true

func acquire(u: Dictionary) -> int:
	var found=-1;var distance=float(spec(u).acquire)
	for other in units:
		if other.hp<=0 or other.team==u.team:continue
		var d=xy(u).distance_to(xy(other))
		if d<distance:found=other.id;distance=d
	return found

func attack_nearest() -> bool:
	if not local_owner(selected):return false
	return command("attack",Vector2.ZERO,acquire(units[selected]))

func cell(point: Vector2) -> Vector2i:
	return Vector2i(((point-grid.offset)/32).round()).clamp(Vector2i.ZERO,grid_size-Vector2i.ONE)

func route(u: Dictionary,target: Vector2):
	u.repath_at=clock+.45
	if sim().arena.sweep_unit(xy(u),target-xy(u),spec(u).radius).is_empty() and walkable(target,spec(u).radius):
		u.path=PackedVector2Array([target]);return
	var a=cell(xy(u));var b=cell(target)
	if grid.is_point_solid(a) or grid.is_point_solid(b):u.path=PackedVector2Array();return
	u.path=grid.get_point_path(a,b,true)
	if not u.path.is_empty():u.path.remove_at(0)

func sweep(u: Dictionary,delta: Vector2) -> Dictionary:
	var hit=sim().arena.sweep_unit(xy(u),delta,spec(u).radius)
	for other in units:
		if other.id==u.id or other.hp<=0:continue
		var found=sim().arena.circle_hit(xy(u),delta,xy(other),float(spec(u).radius)+float(spec(other).radius))
		if not found.is_empty() and (hit.is_empty() or found.t<hit.t):hit=found
	return hit

func walk(u: Dictionary,direction: Vector2,distance: float):
	if direction.length_squared()<.0001:return
	var data=spec(u);var error=wrapf(direction.angle()-u.angle,-PI,PI)
	var motion=Native.turn_step(error,u.angle,data.turn,deg_to_rad(data.prop_window),0,data.speed*DT,false)
	u.angle=wrapf(motion.y,-PI,PI)
	var delta=Vector2.from_angle(u.angle)*minf(motion.x,distance)
	var hit=sweep(u,delta)
	if not hit.is_empty():delta*=maxf(0,float(hit.t)-.002)
	var target=xy(u)+delta
	if walkable(target,data.radius):u.pos=ground(target)
	u.moving=u.previous.distance_to(u.pos)>.01

func damage(target: int,value: float):
	if not alive(target):return
	var u=units[target];var armor=float(spec(u).armor)
	u.hp=maxf(0,u.hp-value/(1+float(catalog.armor_factor)*armor))
	if u.hp==0:
		u.dead_at=clock;u.hit_at=INF;u.axis=Vector2.ZERO;u.path=PackedVector2Array();u.moving=false
		if selected==target:cycle()

func release_attack(u: Dictionary):
	u.hit_at=INF
	if not alive(u.target):return
	var target=units[u.target];var data=spec(u)
	if xy(u).distance_to(xy(target))>float(data.range)+float(data.range_buffer):return
	var value=float(data.damage_base)
	for i in range(int(data.damage_dice)):value+=sim().random.randi_range(1,int(data.damage_sides))
	if not data.missile:damage(target.id,value);return
	var launch=data.launch;var forward=Vector2.from_angle(u.angle);var side=Vector2(-forward.y,forward.x)
	var offset=forward*float(launch[1])+side*float(launch[0])
	var start=u.pos+Vector3(offset.x,offset.y,float(launch[2]))
	arrow_sequence+=1
	arrows.append({"id":arrow_sequence,"owner":u.id,"target":target.id,"time":clock,"start":start,"pos":start,"previous":start,"distance":start.distance_to(target.pos+Vector3(0,0,data.impact)),"travel":0.0,"speed":float(data.missile_speed),"arc":float(data.missile_arc),"impact":float(data.impact),"damage":value,"alive":true})

func tick(now: float):
	clock=now
	for arrow in arrows:
		if not arrow.alive:continue
		var target=units[arrow.target].pos+Vector3(0,0,arrow.impact)
		arrow.previous=arrow.pos;arrow.travel+=arrow.speed*DT
		var progress=clampf(arrow.travel/maxf(1,arrow.distance),0,1)
		arrow.pos=arrow.start.lerp(target,progress)+Vector3(0,0,4*progress*(1-progress)*arrow.distance*arrow.arc)
		if progress>=1:
			arrow.alive=false;damage(arrow.target,arrow.damage)
			arrow_end_sequence+=1
			var ended=arrow.duplicate();ended.ended=clock;ended.event_id=arrow_end_sequence;arrow_ends.append(ended)
			if arrow_ends.size()>256:arrow_ends.pop_front()
	arrows=arrows.filter(func(a):return a.alive)
	for u in units:
		u.previous=u.pos;u.moving=false
		if u.hp<=0:continue
		var data=spec(u)
		if data.regen_type=="always":u.hp=minf(float(data.hp),u.hp+float(data.regen)*DT)
		# Current fields contain no blight, so warrior's blight-only regen stays off.
		if u.hit_at<=clock:release_attack(u)
		if u.hit_at!=INF:continue
		if u.order=="direct":walk(u,u.axis,data.speed*DT*u.axis.length());continue
		if u.order=="move":
			if xy(u).distance_to(u.destination)<=Native.MIN_POINT_STOP:u.order="idle";continue
			if clock>=u.repath_at:route(u,u.destination)
		else:
			if not alive(u.target):u.target=acquire(u)
			if not alive(u.target):continue
			var target=units[u.target];var offset=xy(target)-xy(u)
			if offset.length()<=float(data.range):
				var error=wrapf(offset.angle()-u.angle,-PI,PI)
				u.angle=wrapf(u.angle+clampf(error,-data.turn,data.turn),-PI,PI)
				if absf(error)<=.5 and clock>=u.cooldown_until:
					u.attack_serial+=1;u.attack_at=clock;u.hit_at=clock+float(data.attack_point);u.cooldown_until=clock+float(data.cooldown)
				continue
			if clock>=u.repath_at:route(u,xy(target))
		if not u.path.is_empty():
			var delta=u.path[0]-xy(u)
			if delta.length()<16:u.path.remove_at(0)
			else:walk(u,delta.normalized(),delta.length())

func step(now: float):
	if next_time<=now+1e-8:tick(next_time);next_time+=DT
