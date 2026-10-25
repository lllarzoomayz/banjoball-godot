extends RefCounted
## QA orders run on the simulation's fixed movement ticks, never render frames.
const PROTOCOL="seeded-fixed-orders-v2"
const SEED=270127
var last_step=-1

func feed(sim):
	var step=floori((sim.clock_now()+.00000001)/2.0)
	if step==last_step:return
	last_step=step
	var target=[Vector2(1200,500),Vector2(-1200,500),Vector2(1000,-500),Vector2(-1000,-500)][step%4]
	sim.submit_command("move",sim.controlled,target)
	if step%3==1:sim.submit_command("ability",sim.controlled,target)
	if sim.has_ball(sim.controlled):sim.submit_command("kick",sim.controlled,Vector2(2200,0))
