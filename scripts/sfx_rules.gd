extends RefCounted
## Game.dll 1.27 SetUnitFlyHeight wrapper (0x6f1f7630): non-positive
## requested heights become 0.01, but small POSITIVE heights are preserved.
## See tools/verify_native_fly_height.py; this does not model unit scheduling.
static func fly_height(requested: float) -> float:
	return requested if requested>0 else .01

static func terrain_position(requested: Vector3,ground: float) -> Vector3:
	return Vector3(requested.x,requested.y,ground+fly_height(requested.z-ground))
