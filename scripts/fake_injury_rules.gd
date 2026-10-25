extends RefCounted
## FakeInjury___fakeInjury / resetMultipress / resetAnimation from war3map.j.
## This only changes presentation. It never disables collision or catching.
const PRESS_WINDOW=0.25
const RESET_DELAYS={"h00P":2.0,"h003":1.0,"h010":1.0}

static func configure(p: Dictionary):
	p.injury_generation=int(p.get("injury_generation",0))+1
	p.injury_window=false;p.injury_pose=false;p.injury_start=0.0;p.injury_count=0

static func cancel_pose(p: Dictionary):
	p.injury_pose=false
	# Native timer callbacks are independent. A new order does not cancel them
	# or renew the stop multipress window.

static func schedule(sim,p: Dictionary,kind: String,delay: float):
	sim.injury_sequence+=1
	sim.injury_events.append({"unit":p,"generation":p.injury_generation,"kind":kind,"due":sim.clock_now()+delay,"sequence":sim.injury_sequence})
	# Equal deadlines have a deterministic creation order. Native tie ordering
	# has not been measured; do not let an unstable sort choose it differently.
	sim.injury_events.sort_custom(func(a,b):return a.due<b.due if a.due!=b.due else a.sequence<b.sequence)
	sim.next_injury=sim.injury_events[0].due

static func stop_order(sim,index: int):
	var p=sim.players[index]
	if sim.Characters.absent(p):return
	# Expire earlier independent timers before evaluating a new order, including
	# orders submitted directly by a test or AI outside the timestamp dispatcher.
	step(sim,sim.clock_now())
	if p.injury_window and sim.holder!=index and sim.fake_injury_enabled:
		p.injury_pose=true;p.injury_start=sim.clock_now();p.injury_count+=1
		if RESET_DELAYS.has(p.character):schedule(sim,p,"stand",RESET_DELAYS[p.character])
		if index==sim.controlled:sim.notice="假摔：仍可碰撞和接球；右键移动可起身。"
	p.injury_window=true
	schedule(sim,p,"window",PRESS_WINDOW)

static func step(sim,now: float):
	while not sim.injury_events.is_empty() and sim.injury_events[0].due<=now+0.00000001:
		var event=sim.injury_events.pop_front()
		var p: Dictionary=event.unit
		if p.injury_generation!=event.generation:continue
		if event.kind=="window":p.injury_window=false
		elif not p.injury_window:p.injury_pose=false
	sim.next_injury=INF if sim.injury_events.is_empty() else sim.injury_events[0].due

static func reset(sim):
	sim.injury_events.clear();sim.next_injury=INF;sim.injury_sequence=0
