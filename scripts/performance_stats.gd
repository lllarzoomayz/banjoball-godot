extends RefCounted
## Wall-clock frame intervals, not smoothed engine delta or CPU utilization.
const LIMIT=1200
const WINDOW_MS=10000.0
var samples=[]
var clock_ms=0.0
var total_frames=0
var total_ms=0.0
var slow50=0
var slow100=0
var worst={}

func clear():
	samples.clear();clock_ms=0;total_frames=0;total_ms=0;slow50=0;slow100=0;worst={}

func add(frame: Dictionary):
	var ms=float(frame.get("frame_ms",0))
	if not is_finite(ms) or ms<=0:return
	clock_ms+=ms;total_ms+=ms;total_frames+=1
	var sample=frame.duplicate();sample.time_ms=clock_ms;samples.append(sample)
	if ms>50:slow50+=1
	if ms>100:slow100+=1
	if ms>float(worst.get("frame_ms",0)):worst=sample.duplicate()
	while samples.size()>LIMIT or (samples.size()>1 and clock_ms-samples[0].time_ms>=WINDOW_MS):samples.pop_front()

static func summarize(rows: Array) -> Dictionary:
	if rows.is_empty():return {"frames":0}
	var times=[];var sum=0.0;var fps_ms=0.0;var fps_frames=0;var over50=0;var over100=0
	var averages={};var peaks={};var counts={};var worst_frame={}
	for row in rows:
		var ms=float(row.frame_ms);times.append(ms);sum+=ms
		if ms>50:over50+=1
		if ms>100:over100+=1
		if ms>float(worst_frame.get("frame_ms",0)):worst_frame=row
		for key in ["cpu_ms","sim_ms","visual_ms","ui_ms","goals_ms","actors_ms","effects_ms","buffs_ms","grid_ms","search_ms","smooth_ms","route_calls","render_cpu_ms","gpu_ms","draw_calls","primitives","render_memory_mb"]:
			var v=row.get(key)
			# Null means unavailable. Never turn missing GPU timing into zero load.
			if v==null or not is_finite(float(v)):continue
			averages[key]=float(averages.get(key,0))+float(v);counts[key]=int(counts.get(key,0))+1
			peaks[key]=maxf(float(peaks.get(key,0)),float(v))
	for i in range(rows.size()-1,-1,-1):
		fps_ms+=float(rows[i].frame_ms);fps_frames+=1
		if fps_ms>=1000:break
	for key in averages:averages[key]/=counts[key]
	times.sort()
	return {"frames":rows.size(),"seconds":sum/1000,"fps":1000*rows.size()/sum,"fps_recent":1000*fps_frames/fps_ms,"frame_ms":sum/rows.size(),"p95_ms":times[maxi(0,ceili(times.size()*0.95)-1)],"max_ms":times[-1],"over50":over50,"over100":over100,"average":averages,"peak":peaks,"worst":worst_frame}

func snapshot() -> Dictionary:
	var result=summarize(samples)
	result.session_frames=total_frames;result.session_seconds=total_ms/1000
	result.session_over50=slow50;result.session_over100=slow100;result.session_worst=worst
	return result
