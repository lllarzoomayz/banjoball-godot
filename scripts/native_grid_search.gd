extends RefCounted
## Flat-grid subset reconstructed from this Game.dll:
## neighbor order 0x110b20, scaled integer cost 0x110770, heap 0xf4b50/0xf49a0.
## This does NOT implement native coarse blocks, special links or dynamic routing.
var heap: Array=[]
var generation={}
var packed_heap=PackedInt32Array()
var heap_count=0
var popped_id=0
var popped_version=0
var accelerator=preload("res://scripts/acceleration.gd").create()
const DIRECTIONS=[Vector2i(0,-1),Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0),Vector2i(1,-1),Vector2i(1,1),Vector2i(-1,1),Vector2i(-1,-1)]
const CORNERS=[3,6,12,9]

static func distance_cost(a: Vector2i,b: Vector2i) -> int:
	var d=(a-b)*24
	return int(sqrt(float(d.x*d.x+d.y*d.y)))

static func closer_cell(candidate: Vector2i,current: Vector2i,goal: Vector2i) -> bool:
	# 0x110770: strict squared CELL distance. Equal distance retains the first
	# encountered node; world-point bias and cheaper later routes do not win ties.
	return (candidate-goal).length_squared()<(current-goal).length_squared()

func push(priority: int, id, version: int):
	var item=[priority,id,version]
	heap.append(item)
	var i=heap.size()-1
	while i>0:
		var parent=(i-1)>>1
		# Original insertion bubbles equal-priority entries upward.
		if heap[parent][0]<priority:break
		heap[i]=heap[parent]
		i=parent
	heap[i]=item

func pop() -> Array:
	var result=heap[0]
	var last=heap.pop_back()
	if heap.is_empty():return result
	var i=0
	while i*2+1<heap.size():
		var child=i*2+1
		if child+1<heap.size() and heap[child+1][0]<=heap[child][0]:child+=1
		if last[0]<=heap[child][0]:break
		heap[i]=heap[child]
		i=child
	heap[i]=last
	return result

func packed_push(priority: int,id: int,version: int):
	var i: int=heap_count;heap_count+=1
	if heap_count*3>packed_heap.size():packed_heap.resize(maxi(192,packed_heap.size()*2))
	while i>0:
		var p: int=(i-1)>>1
		if packed_heap[p*3]<priority:break
		packed_heap[i*3]=packed_heap[p*3];packed_heap[i*3+1]=packed_heap[p*3+1];packed_heap[i*3+2]=packed_heap[p*3+2]
		i=p
	packed_heap[i*3]=priority;packed_heap[i*3+1]=id;packed_heap[i*3+2]=version

func packed_pop():
	popped_id=packed_heap[1];popped_version=packed_heap[2];heap_count-=1
	if heap_count==0:return
	var priority: int=packed_heap[heap_count*3];var id: int=packed_heap[heap_count*3+1];var version: int=packed_heap[heap_count*3+2]
	var i: int=0
	while i*2+1<heap_count:
		var child: int=i*2+1
		if child+1<heap_count and packed_heap[(child+1)*3]<=packed_heap[child*3]:child+=1
		if priority<=packed_heap[child*3]:break
		packed_heap[i*3]=packed_heap[child*3];packed_heap[i*3+1]=packed_heap[child*3+1];packed_heap[i*3+2]=packed_heap[child*3+2]
		i=child
	packed_heap[i*3]=priority;packed_heap[i*3+1]=id;packed_heap[i*3+2]=version

func find_path(grid: AStarGrid2D, start: Vector2i, goal: Vector2i, partial_offset: Vector2=Vector2.ZERO, blocked: PackedByteArray=PackedByteArray()) -> PackedVector2Array:
	heap_count=0
	var region: Rect2i=grid.region
	var width: int=region.size.x;var height: int=region.size.y;var count: int=width*height
	if not region.has_point(start) or not region.has_point(goal):return PackedVector2Array()
	if blocked.size()!=count:
		blocked.resize(count)
		for y in range(height):
			for x in range(width):blocked[y*width+x]=int(grid.is_point_solid(Vector2i(x,y)+region.position))
	if accelerator!=null:
		var a=start-region.position;var b=goal-region.position
		var ids: PackedInt32Array=accelerator.find_cells(width,height,a.y*width+a.x,b.y*width+b.x,blocked)
		var result=PackedVector2Array()
		for id in ids:result.append(grid.get_point_position(Vector2i(id%width,id/width)+region.position))
		if ids.size()>1 and ids[-1]!=b.y*width+b.x:result[-1]+=partial_offset
		return result
	var scores=PackedInt32Array();scores.resize(count);scores.fill(2147483647)
	var parent=PackedInt32Array();parent.resize(count);parent.fill(-1)
	var versions=PackedInt32Array();versions.resize(count)
	var origin: Vector2i=start-region.position;var target: Vector2i=goal-region.position
	var start_id: int=origin.y*width+origin.x;var goal_id: int=target.y*width+target.x
	var closest: int=start_id;var closest_distance: int=(origin-target).length_squared()
	scores[start_id]=0;versions[start_id]=1
	packed_push(distance_cost(start,goal),start_id,1)
	var expanded: int=0
	while heap_count>0 and expanded<count*3:
		packed_pop()
		var current: int=popped_id
		if popped_version!=versions[current]:continue
		expanded+=1
		if current==goal_id:
			closest=goal_id
			break
		var cx: int=current%width;var cy: int=current/width;var open_mask: int=0
		# Same cardinal/diagonal order and equal-priority heap behavior as before.
		# Flat typed arrays avoid thousands of Dictionary/API calls per search.
		for direction in range(8):
			if direction>=4 and (open_mask & CORNERS[direction-4])!=CORNERS[direction-4]:continue
			var x: int=cx+DIRECTIONS[direction].x;var y: int=cy+DIRECTIONS[direction].y
			if x<0 or y<0 or x>=width or y>=height:continue
			var q: int=y*width+x
			if blocked[q]!=0:continue
			if direction<4:open_mask|=1<<direction
			var score: int=scores[current]+(24 if direction<4 else 33)
			if scores[q]<=score:continue
			parent[q]=current
			scores[q]=score
			versions[q]+=1
			var dx: int=x-target.x;var dy: int=y-target.y;var distance: int=dx*dx+dy*dy
			packed_push(score+int(sqrt(float(distance*576))),q,versions[q])
			if distance<closest_distance:closest=q;closest_distance=distance
	var path=PackedVector2Array()
	var cursor: int=closest
	path.append(grid.get_point_position(Vector2i(cursor%width,cursor/width)+region.position))
	while parent[cursor]>=0:
		cursor=parent[cursor]
		path.append(grid.get_point_position(Vector2i(cursor%width,cursor/width)+region.position))
	path.reverse()
	# The caller supplies the original endpoint bias for its grid coordinate
	# system. Parent-chain intermediates retain the regular fine-point bias.
	if closest!=goal_id and path.size()>1:path[-1]+=partial_offset
	return path
