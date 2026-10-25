extends RefCounted
## Original s__Tackle_iterate32 and Alpha timings. Presentation only.
const MODEL="h00E"
const LIFETIME=1.40
const FAST_TIME=0.10
const COLOR=Color(155.0/255,155.0/255,1.0)

static func animation_time(age: float) -> float:
	return minf(age,FAST_TIME)*4.0+maxf(0,age-FAST_TIME)*0.30

static func alpha(age: float) -> float:
	return maxf(0,127-3*floori((age+0.00000001)*32))/255.0

static func create(sim,index: int):
	var p=sim.players[index]
	sim.next_tackle_shadow+=1
	sim.tackle_shadows.append({"id":sim.next_tackle_shadow,"owner":index,"team":p.team,
		"pos":sim.Characters.world_position(p),"angle":p.body,"age":0.0,"model":MODEL})

static func step(sim):
	for shadow in sim.tackle_shadows:shadow.age+=sim.BALL_DT
	sim.tackle_shadows=sim.tackle_shadows.filter(func(shadow):return not shadow.get("removed",false) and shadow.age<LIFETIME)
