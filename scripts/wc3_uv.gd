extends RefCounted
## MDX texture animation tracks. Global sequences use an independent model
## clock; atlas steps are discrete and do not blur between texture cells.

static func quaternion(values: Array) -> Quaternion:
	return Quaternion(values[0],values[1],values[2],values[3]).normalized()

static func sample(track,default_value: Array,local_frame: float,interval: Array,global_time: float,periods: Array,is_rotation: bool=false) -> Array:
	if not track is Dictionary:return default_value
	var frame=local_frame;var start=float(interval[0]);var end=float(interval[1])
	if track.get("GlobalSeqId")!=null:
		var period=float(periods[int(track.GlobalSeqId)])
		start=0;end=period;frame=fposmod(global_time*1000,period) if period>0 else 0.0
	var previous;var following
	for key in track.Keys:
		if key.Frame<start or key.Frame>end:continue
		if key.Frame<=frame:previous=key
		elif following==null:following=key;break
	if previous==null:previous=following
	if following==null:following=previous
	if previous==null:return default_value
	var mode=int(track.LineType)
	if previous.Frame==following.Frame or mode==0:return previous.Vector
	var t=clampf((frame-previous.Frame)/(following.Frame-previous.Frame),0,1)
	if is_rotation:
		var q=quaternion(previous.Vector).slerp(quaternion(following.Vector),t)
		if mode in [2,3]:q=q.slerp(quaternion(previous.OutTan).slerp(quaternion(following.InTan),t),2*t*(1-t))
		return [q.x,q.y,q.z,q.w]
	var values=[]
	for i in range(previous.Vector.size()):
		var a=float(previous.Vector[i]);var b=float(following.Vector[i])
		if mode==2:
			values.append((2*t*t*t-3*t*t+1)*a+(t*t*t-2*t*t+t)*previous.OutTan[i]+(t*t*t-t*t)*following.InTan[i]+(-2*t*t*t+3*t*t)*b)
		elif mode==3:
			var u=1-t
			values.append(u*u*u*a+3*u*u*t*previous.OutTan[i]+3*u*t*t*following.InTan[i]+t*t*t*b)
		else:values.append(lerpf(a,b,t))
	return values

static func transform(anim: Dictionary,local_frame: float,interval: Array,global_time: float,periods: Array) -> Basis:
	var translation=sample(anim.get("Translation"),[0,0,0],local_frame,interval,global_time,periods)
	var scale=sample(anim.get("Scaling"),[1,1,1],local_frame,interval,global_time,periods)
	var rotation=sample(anim.get("Rotation"),[0,0,0,1],local_frame,interval,global_time,periods,true)
	var matrix=Basis(quaternion(rotation))*Basis.from_scale(Vector3(scale[0],scale[1],scale[2]))
	return Basis(Vector3(matrix.x.x,matrix.x.y,0),Vector3(matrix.y.x,matrix.y.y,0),Vector3(translation[0],translation[1],1))
