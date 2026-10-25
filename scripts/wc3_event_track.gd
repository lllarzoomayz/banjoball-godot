extends RefCounted
## Animation-local EVTS crossings. Sampling/zero-delta pose updates are silent.
## Export rejects global-sequence events until their separate clock is supported.
static func crossed(events: Array,from: float,delta: float,duration: float,looped: bool,start: bool) -> Array:
	if delta<=0 or events.is_empty():return []
	var found=[]
	var end=from+delta if looped else minf(duration,from+delta)
	for event in events:
		var time=float(event.time)
		if looped:
			var cycle=maxi(0,ceili((from-time)/duration))
			var at=time+cycle*duration
			if at<=from+0.000000001 and not (start and from==0 and at==0):
				cycle+=1;at=time+cycle*duration
			while at<=end+0.000000001:
				found.append({"event":event,"at":at});cycle+=1;at=time+cycle*duration
		elif time<=end+0.000000001 and (time>from+0.000000001 or (start and from==0 and time==0)):
			found.append({"event":event,"at":time})
	found.sort_custom(func(a,b):return a.at<b.at)
	return found.map(func(entry):return entry.event)
