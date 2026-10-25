extends RefCounted
## Flat-grid subset reconstructed from this Game.dll:
## neighbor order 0x110b20, scaled integer cost 0x110770, heap 0xf4b50/0xf49a0.
## This does NOT implement native coarse blocks, special links or dynamic routing.
var heap: Array=[]
var generation={}

static func distance_cost(a: Vector2i,b: Vector2i) -> int:
	var d=(a-b)*24
	return int(sqrt(float(d.x*d.x+d.y*d.y)))

static func closer_cell(candidate: Vector2i,current: Vector2i,goal: Vector2i) -> bool:
	# 0x110770: strict squared CELL distance. Equal distance retains the first
	# encountered node; world-point bias and cheaper later routes do not win ties.
	return (candidate-goal).length_squared()<(current-goal).length_squared()

func push(priority: int, id: Vector2i, version: int):
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

func find_path(grid: AStarGrid2D, start: Vector2i, goal: Vector2i, partial_offset: Vector2=Vector2.ZERO) -> PackedVector2Array:
	heap.clear()
	generation.clear()
	var scores={start:0}
	var parent={}
	var closest=start
	generation[start]=1
	push(distance_cost(start,goal),start,1)
	var expanded=0
	while not heap.is_empty() and expanded<grid.region.size.x*grid.region.size.y*3:
		var item=pop()
		var current: Vector2i=item[1]
		if item[2]!=generation.get(current,0):continue
		expanded+=1
		if current==goal:
			closest=goal
			break
		var cardinal=[Vector2i(0,-1),Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0)]
		var open=[]
		var neighbors=[]
		for offset in cardinal:
			var q: Vector2i=current+offset
			var ok=grid.region.has_point(q) and not grid.is_point_solid(q)
			open.append(ok)
			if ok:neighbors.append(q)
		for pair in [[0,1],[1,2],[2,3],[3,0]]:
			if open[pair[0]] and open[pair[1]]:
				var q: Vector2i=current+cardinal[pair[0]]+cardinal[pair[1]]
				if grid.region.has_point(q) and not grid.is_point_solid(q):neighbors.append(q)
		for q in neighbors:
			var score: int=scores[current]+distance_cost(current,q)
			if scores.has(q) and scores[q]<=score:continue
			parent[q]=current
			scores[q]=score
			generation[q]=generation.get(q,0)+1
			push(score+distance_cost(q,goal),q,generation[q])
			if closer_cell(q,closest,goal):closest=q
	var path=PackedVector2Array()
	var cursor=closest
	path.append(grid.get_point_position(cursor))
	while parent.has(cursor):
		cursor=parent[cursor]
		path.append(grid.get_point_position(cursor))
	path.reverse()
	# The caller supplies the original endpoint bias for its grid coordinate
	# system. Parent-chain intermediates retain the regular fine-point bias.
	if closest!=goal and path.size()>1:path[-1]+=partial_offset
	return path
