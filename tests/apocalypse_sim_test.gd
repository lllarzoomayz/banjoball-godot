extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var passed=0
var failures=[]
var observations={}
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func start(timed=false):
	var sim=Sim.new()
	if timed:sim.start_match(3,10,120)
	else:sim.start_practice()
	sim.bot_enabled=false
	sim.advance(40)
	sim.prepare_apocalypse()
	return sim
func run():
	var sim=start(true);var state=sim.apocalypse
	var remaining=sim.time_left;var elapsed=sim.elapsed
	sim.players[0].pos=Vector2.ZERO;sim.players[0].z=200
	sim.players[0].ability_delay=.2;sim.players[0].ability_kind="pillar";sim.players[0].ability_target=Vector2(30,0)
	sim.players[0].flight_steps=3 # Hidden but still a native ANCIENT unit.
	sim.players[0].cast_pending=true;sim.players[0].direct_axis=Vector2.RIGHT
	sim.players[3].pos=Vector2(1300,1000) # Keep the post-drop catch volume clear.
	sim.ball=Vector3(500,0,100);sim.previous_ball=sim.ball;sim.holder=3;sim.velocity=Vector3.ZERO
	var old_walls=sim.arena.walls.size();var revision=sim.arena.revision
	check(state.vote(0),"single local human can activate after field gate")
	check(sim.arena.walls.size()<old_walls and sim.arena.revision>revision,"real arena removes authored path blockers and invalidates routes")
	check(sim.arena.walls.size()==sim.arena.data.stall_blocked.size(),"terrain blockers retained")
	sim.advance(1.0/32)
	check(not sim.unit_present(0) and sim.Characters.absent(sim.players[0]),"hidden native player at black-hole center is removed")
	check(not sim.players[0].cast_pending and sim.players[0].ability_delay==0 and sim.players[0].direct_axis==Vector2.ZERO,"removal cancels pending input and uncast ability")
	check(sim.holder==-1 and sim.velocity.x<0,"actual pull drops a held ball and accelerates toward center")
	check(sim.time_left==remaining and sim.elapsed==elapsed,"timed match countdown pauses while simulation continues")
	var position=sim.players[0].pos
	sim.command(0,Vector2(1000,500));sim.DirectionalMotion.order(sim,0,Vector2.UP)
	sim.submit_command("ability",0,Vector2.ZERO);sim.apply_impulse(0,Vector3.ONE*50)
	sim.tackle(0,Vector2.RIGHT*100);sim.begin_tackle(0);sim.approach_cast(0,Vector2.ONE,700)
	sim.take(0)
	check(sim.holder==-1 and sim.pending_commands.is_empty() and sim.players[0].knock==Vector2.ZERO,"removed player cannot issue commands, receive impulse or catch")
	check(not sim.Characters.use(sim,0,Vector2.ZERO) and not sim.select_player(0),"removed player cannot cast or be selected")
	check(not sim.players[0].cast_pending and sim.players[0].tackle==0 and sim.players[0].ability_order.is_empty(),"direct stale tackle and approach callbacks are inert")
	check(not sim.Characters.exchange_players(sim,0,1),"swap cannot relocate a removed caster or target")
	sim.advance(.5)
	check(sim.players[0].pos==position and sim.arena.pillars.is_empty(),"removed player does not move or complete delayed pillar")
	# Real ball gets its distinct absorption test; callbacks cannot recreate it.
	sim.ball=Vector3(0,0,200);sim.previous_ball=sim.ball;sim.velocity=Vector3.ZERO
	sim.advance(1.0/32)
	check(not sim.ball_present and sim.holder==-1,"real ball absorbed and removed from simulation")
	var ball=sim.ball;var score=sim.score.duplicate()
	sim.take(1);sim.award_goal(1);sim.travel_ball(Vector3(1000,0,0))
	check(sim.catch_hit(ball,Vector3.ZERO).is_empty(),"removed ball has no catch candidates")
	check(sim.ball==ball and sim.score==score and sim.holder==-1,"direct stale ball callbacks cannot score, move or catch")
	var fake={"id":12,"creator":1,"team":sim.players[1].team,"position":Vector3(700,300,0),"previous":Vector3(700,300,0),"velocity":Vector3(1,0,0),"holder":-1,"last_owner":1,"intercept":0,"life":10.0}
	sim.fake_balls.append(fake)
	sim.Copies.take(sim,fake,1)
	check(fake.holder==1 and sim.has_ball(1),"native fake ball remains a separate catchable object until cleanup")
	sim.reset()
	check(not sim.unit_present(0) and not sim.ball_present,"goal/reset cannot resurrect removed native units")
	check(not sim.PracticeRules.recall_ball(sim,1),"practice recall cannot restore a removed real ball")
	# A live zero-radius tree is pulled through the same clock as player/ball.
	var tree=state.rules.world.candidates().filter(func(row):return row.id=="LTlt")[0]
	var result=state.rules.world.lift(tree.uid,2);result.time=sim.clock_now()
	state.on_event("tree",result)
	var object=state.trees[-1];object.pos=Vector3(200,0,60);object.previous=object.pos;object.apoc_velocity=Vector3(0,0,10)
	var initial=object.pos
	state.step_objects()
	check(absf(object.pos.z-initial.z-10)<.001 and object.apoc_velocity.z==10,"zero-radius tree has no gravity, friction or player bounce loss")
	var before=object.pos
	sim.advance(.25)
	check(object.pos!=before and object.apoc_velocity.x<0,"actual tree moves toward the black hole")
	# Force interception for native projectile and referee objects as well.
	sim.selected_character="h01R";sim.Characters.configure(sim.players[1],"h01R")
	sim.players[1].pos=Vector2(-500,300)
	check(sim.Characters.Complex.hook_cast(sim,1,Vector2(500,300),false),"test hook exists")
	var hook=sim.projectiles[-1];hook.pos=Vector3(0,0,200);hook.previous=hook.pos
	sim.referee={"pos":Vector3(0,0,200),"age":0.0,"kicked":true}
	sim.advance(1.0/32)
	check(hook.life<=0 and sim.players[1].hook.is_empty(),"native hook projectile can be absorbed")
	check(sim.referee.is_empty(),"native referee can be absorbed")
	# Run the actual MatchSim scheduler through the whole event.
	sim.advance(92-sim.timeline)
	check(state.cleaned and sim.players.all(func(p):return p.removed) and not sim.ball_present,"51.5-second cleanup removes every roster unit and ball")
	check(sim.projectiles.is_empty() and sim.fake_balls.is_empty() and sim.rifts.is_empty() and sim.arena.pillars.is_empty(),"cleanup removes pending native props and collision")
	check(state.rules.decorations.size()==230,"live clock generates original 230 aftermath decorations")
	sim.advance(20)
	check(state.rules.skeletons.size()==60 and state.rules.phase=="aftermath","live scheduler reaches six owners times ten skeleton spawns")
	observations={"elapsed":sim.timeline,"visual_events":state.visual_sequence,"tree_count":state.trees.size(),"terrain_repair_requests":state.terrain_repair_requests,"skeletons":state.rules.skeletons.size()}
	sim.start_practice()
	check(sim.apocalypse==null and sim.ball_present and sim.players.all(func(p):return not p.removed),"new game restores ordinary native units and removes apocalypse state")
	check(sim.arena.walls.size()==old_walls,"new game restores authored field blockers")
	# The explicit loss parameter must preserve the native nonplayer special
	# case: BoundaryCheck removes inward motion, without adding a reflection.
	var arena=sim.arena
	var boundary=arena.boundaries[0];var xy=boundary.rect.get_center()
	var pos=Vector3(xy.x,xy.y,maxf(0,boundary.low))
	var input=-boundary.normal*20
	var output=sim.ObjectMotion.check_force(arena,pos,input,0)
	check(output.length()<.001,"zero-loss BoundaryCheck cancels incoming projection")
	# Every character's actual skill path must leave a removed real ball alone.
	for character in sim.Characters.IDS:
		var sample=Sim.new();sample.selected_character=character;sample.start_practice()
		var adapter=sample.prepare_apocalypse();sample.ball=Vector3(120,60,100)
		adapter.remove_ball();var old_ball=sample.ball
		sample.Characters.use(sample,0,Vector2(60,60));sample.advance(2)
		check(not sample.ball_present and sample.ball==old_ball and sample.velocity==Vector3.ZERO,"no stale real-ball skill work: "+character)
	var sample=Sim.new();sample.start_practice();var adapter=sample.prepare_apocalypse()
	check(adapter.properties.h00T.radius==30 and adapter.properties.h00V.radius==0,"custom JASS collision table overrides misleading SLK radius")
	check(not adapter.properties.has("h00U") and not adapter.properties.has("h02D"),"black-hole art and pillar TAUREN are not ANCIENT objects")
	sample.referee={"pos":Vector3(400,400,100),"age":0.0,"kicked":true,"apoc_velocity":Vector3(0,0,10)}
	adapter.step_objects()
	check(absf(sample.referee.apoc_velocity.z-8.42)<.0001,"referee uses positive-radius gravity and air friction")
	sample.TackleVisuals.create(sample,0);var shadow=sample.tackle_shadows[-1];shadow.pos=Vector3(0,0,200)
	adapter.on_event("pull",{"time":0.0});sample.TackleVisuals.step(sample)
	check(sample.tackle_shadows.is_empty(),"ANCIENT tackle shadow absorbed and removed from visual lifetime list")
	var external={"pos":Vector3(400,400,10)}
	check(not adapter.register_external("h00U",external),"pure visual unit cannot enter physical external registry")
	check(adapter.register_external("h01K",external) and not adapter.register_external("h01K",external),"BizTree native object can register once by identity")
	FileAccess.open("res://research/apocalypse-sim-verification.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"observations":observations,"presentation_connected":false,"native_terrain_repair_calibrated":false},"\t"))
	print("APOCALYPSE SIM ",passed," passed; ",failures.size()," failures ",observations)
	quit(0 if failures.is_empty() else 1)
