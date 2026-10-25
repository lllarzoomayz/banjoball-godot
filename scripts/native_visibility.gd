extends RefCounted
## Verified small-radius fine-ray kernels. Inputs are native grid coordinates.
## This is not wired over the match's circle geometry: native world/object cell
## rasterization and radius-class selection still need reconstruction first.

static func transition_cells(cell: Vector2i,mask: int,mode: int) -> Array[Vector2i]:
	var x=cell.x;var y=cell.y
	if mode==0:
		var result: Array[Vector2i]=[cell]
		if mask in [3,6,9,12]:
			result.append(Vector2i(x+(-1 if mask in [3,6] else 1),y))
			result.append(Vector2i(x,y+(1 if mask in [3,9] else -1)))
		return result
	if mode!=1:return []
	match mask:
		1:return [Vector2i(x-1,y-1),Vector2i(x,y-1)]
		2:return [Vector2i(x,y-1),Vector2i(x,y)]
		4:return [Vector2i(x-1,y),Vector2i(x,y)]
		8:return [Vector2i(x-1,y-1),Vector2i(x-1,y)]
	if mask in [3,6,9,12]:
		var left=x-2 if mask in [3,6] else x-1
		var row=y-1 if mask in [3,9] else y
		var column=x if mask in [3,6] else x-1
		var bottom=y if mask in [3,9] else y-2
		return [Vector2i(left,row),Vector2i(left+1,row),Vector2i(left+2,row),Vector2i(column,bottom),Vector2i(column,bottom+1)]
	return [Vector2i(x-1,y-1),Vector2i(x,y-1),Vector2i(x-1,y),Vector2i(x,y)]

static func transition_clear(cell: Vector2i,mask: int,mode: int,walkable: Callable) -> bool:
	if mode not in [0,1]:return false
	for query in transition_cells(cell,mask,mode):
		if not walkable.call(query):return false
	return true

static func ray_clear(origin: Vector2,step: Vector2,length: float,mode: int,walkable: Callable) -> bool:
	if mode not in [0,1] or not origin.is_finite() or not step.is_finite() or not is_finite(length):return false
	# 0x115480 discards the first two floor results and starts previous at 0,0.
	# It samples at 1,2,... STRICTLY less than length, never the endpoint.
	var previous=Vector2i.ZERO
	var distance=1.0
	while distance<length:
		# Separate Vector2 operations retain the two float32 roundings verified
		# against original software multiply/add for the fixture's input domain.
		var scaled=step*distance
		var cell=Vector2i((origin+scaled).floor())
		if cell!=previous:
			var mask=8 if cell.x<previous.x else (2 if cell.x>previous.x else 0)
			mask|=1 if cell.y<previous.y else (4 if cell.y>previous.y else 0)
			if not transition_clear(cell,mask,mode,walkable):return false
		previous=cell
		distance+=1.0
	return true
