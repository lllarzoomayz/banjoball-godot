extends RefCounted
## These bounded rules were reconstructed from Game.dll 1.27.0.52240 and
## compared with executing its original x86 instructions in Unicorn.
## Native scheduler, geometry rasterization and route search remain separate.
## 0x03e790/0x03f230 clamp supplied stop radius /32 to at least 0.49;
## 0x11b060 stops translation there and waits until heading error <=0.2.
const MIN_POINT_STOP=0.49000000953674316*32.0
const ARRIVAL_ANGLE=0.20000000298023224
const PATH_CELL_SIZE=32.0
const FINE_POINT_OFFSET=24.0
const PARTIAL_POINT_OFFSET=16.0

static func path_cell(point: Vector2,origin: Vector2=Vector2.ZERO) -> Vector2i:
	# Native input conversion floors grid coordinates, independently of the
	# later waypoint bias. Rounding around the biased point shifts cell borders.
	return Vector2i(((point-origin)/PATH_CELL_SIZE).floor())

static func fine_grid_point(cell: Vector2i,origin: Vector2=Vector2.ZERO) -> Vector2:
	# 0x10f180, flat small-unit mode: integer cell + (0.5 + 0.25), then x32.
	return origin+Vector2(cell)*PATH_CELL_SIZE+Vector2.ONE*FINE_POINT_OFFSET

static func partial_grid_point(cell: Vector2i,origin: Vector2=Vector2.ZERO) -> Vector2:
	# 0x10f390 uses +0.5 for the accessible partial endpoint, not +0.75.
	return origin+Vector2(cell)*PATH_CELL_SIZE+Vector2.ONE*PARTIAL_POINT_OFFSET

static func arrival_state(distance: float,angle_error: float,stop_radius: float=MIN_POINT_STOP,forced: bool=false) -> Vector2i:
	var stop_translation=forced or distance<=stop_radius
	return Vector2i(int(stop_translation),int(stop_translation and absf(angle_error)<=ARRIVAL_ANGLE))

static func turn_step(angle_error: float, facing: float, turn_rate: float, prop_window: float, velocity: float, increment: float, force_stop: bool) -> Vector2:
	var next_velocity=0.0 if force_stop or absf(angle_error)>=prop_window else velocity+increment
	var next_facing=facing+clampf(angle_error,-turn_rate,turn_rate)
	return Vector2(next_velocity,next_facing)

static func visible_waypoint_index(point_count: int, visible: Callable) -> int:
	# 0x114340 / 0x1125b0. Forward-array equivalent of the native reversed
	# fine route: after reaching point 0, point 1 is the fallback. Test 2,3,...
	# in order and stop at the FIRST failed ray, even if a later point is clear.
	# The original native collision query is supplied by the caller, not ported
	# by this selection routine. Coarse-route transitions are also separate.
	if point_count<=1:return 0
	for candidate in range(2,point_count):
		if not visible.call(candidate):return candidate-1
	return point_count-1

static func cell_blocked(cell_bits: int, query_mask: int, objects: Array, include_moving: bool=true) -> bool:
	if cell_bits & query_mask & 0xff000000: return true
	for object in objects:
		var mask: int=object.mask
		var flags: int=object.flags
		if (mask & 0x01000000)==0: continue
		if flags & 0x8fffffff: continue
		if not include_moving and (flags & 0x60000000): continue
		if mask & query_mask & 0xffffff: return true
	return false
