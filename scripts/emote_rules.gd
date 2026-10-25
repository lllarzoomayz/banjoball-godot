extends RefCounted
## Emotes___cast / Emotes___init: cosmetic text, independent five-second cooldowns.
const COOLDOWN=5.0
const TAUNTS=["lololo","u wot m8",">:D","\\o/","deal with it","mad?","mwahahaha",":]",":DDD",":J",":3"]
const SADFACES=["QQ",":(",":C","fffuuu",":<", ":[",":/",":\\",":S",":L","._."]

static func remaining(sim,index: int,kind: String) -> float:
	if index<0 or index>=sim.shout.states.size() or kind not in ["taunt","sadface"]:return INF
	var state=sim.shout.states[index]
	return maxf(0,maxf(state.unlock_at,state[kind+"_ready_at"])-sim.clock_now())

static func available(sim,index: int,kind: String) -> bool:
	return remaining(sim,index,kind)<=0 and sim.shout.can_act(sim,index)

static func cast(sim,index: int,kind: String) -> bool:
	if not available(sim,index,kind):return false
	var messages=TAUNTS if kind=="taunt" else SADFACES
	sim.shout.states[index][kind+"_ready_at"]=sim.clock_now()+COOLDOWN
	sim.emit_text(index,messages[sim.shout.random.randi_range(0,messages.size()-1)],3.0)
	return true
