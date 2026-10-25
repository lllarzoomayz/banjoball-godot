extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var results=[]
var failed=false
func check(ok: bool,name: String,detail=""):
	results.append({"test":name,"passed":ok,"detail":str(detail)})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))
func _initialize():call_deferred("run")
func scene(id: String):
	var s=Sim.new();s.selected_character=id;s.reset()
	s.players[0].pos=Vector2(-600,0);s.players[1].pos=Vector2(1700,1000)
	s.ball=Vector3(1400,-900,0)
	return s
func run():
	var s=scene("h004");var p=s.players[0]
	check(not s.Characters.q_available(p) and not s.Characters.use(s,0,Vector2.ZERO),"demon has no invented Q ability")
	s.toggle_sprint(0)
	check(p.sprint and absf(p.knock.x-20.2)<0.001 and p.sprint_cooldown==6,"demon activation gives original propulsion and six-second cooldown")
	s.advance(0.5)
	check(p.pos.x>-300 and p.knock.x>20.2 and absf(p.mana-80)<0.001,"demon accelerates physically and drains forty net mana",[p.pos,p.knock,p.mana])
	s.toggle_sprint(0);var previous=p.pos.x
	s.advance(0.1)
	check(not p.sprint and p.pos.x>previous+20,"stopping demon sprint retains physical momentum")
	s.toggle_sprint(0)
	check(not p.sprint,"demon cannot bypass the restart cooldown")
	s=scene("h004");p=s.players[0]
	s.arena.add_box(Rect2(-300,-100,30,200),240)
	s.set_sprint(0,true);s.advance(0.7)
	check(p.pos.x<=-329.9 and not p.sprint,"demon cannot cross a wall and stalls out at low velocity",p.pos)
	s=scene("h004");p=s.players[0]
	s.players[1].pos=Vector2(-400,0);s.set_sprint(0,true);s.advance(0.3)
	check(s.players[1].knock.x>5,"demon charge transfers impact through object collision",s.players[1].knock)
	s=scene("h00R");p=s.players[0];s.take(0);s.step_ball()
	check(s.Characters.use(s,0,p.pos) and p.cooldown==24 and absf(p.vz-26.16)<0.001 and s.no_steal==10,"ninja flip has original launch, cooldown and initial steal protection")
	var start=p.pos
	s.advance(0.3)
	check(p.z>100 and p.pos.x>start.x+120 and s.holder==0,"ninja carries the ball through a real aerial trajectory",[p.pos,p.z])
	check(s.kick(0,Vector2(1700,0)) and s.ball.z>100,"ninja can shoot from the air without an invented velocity inheritance")
	s.advance(2)
	check(p.z<1 and p.flip_time==0,"ninja completes flip and returns to ground",[p.z,p.flip_time])
	s=scene("h00R");p=s.players[0];p.z=50
	check(not s.Characters.use(s,0,p.pos) and p.cooldown==0,"ninja rejects an airborne recast without consuming cooldown")
	s=scene("h00R");p=s.players[0];s.set_sprint(0,true);s.advance(0.9)
	check(not p.invisible,"ninja remains visible during stealth warmup")
	s.advance(0.12)
	check(p.invisible,"ninja gains stealth after one second")
	s.set_sprint(0,false)
	check(not p.invisible and p.stealth_time==0,"stopping stealth sprint immediately reveals ninja")
	s=scene("h010");p=s.players[0]
	check(not s.Characters.use(s,0,p.pos) and p.cooldown==0,"wisp possession requires a held ball")
	s.take(0);s.step_ball();s.Characters.use(s,0,p.pos)
	check(s.holder==-1 and p.flight_steps==3 and p.cooldown==40,"wisp releases ball and starts the four-step entry flight immediately")
	s.advance(0.1)
	check(p.possess_time>7.9 and p.flight_steps==0 and s.holder==-1,"wisp completes entry without recatching its own ball")
	s.command(0,Vector2(1700,0))
	check(not p.jump_due and s.velocity.x>19 and s.velocity.z>23 and s.last_owner==0,"right-click launches the possessed ball with original fifty-degree vector")
	s.advance(0.15);s.command(0,Vector2(-1700,0))
	check(p.jump_due and s.velocity.x>0,"airborne right-click queues a direction without changing flight immediately")
	var reversed=false
	for i in range(120):
		s.advance(0.03125)
		if not p.jump_due and s.velocity.x<0:reversed=true;break
	check(reversed,"queued possession jump executes on landing")
	s=scene("h010");p=s.players[0];s.take(0);s.step_ball();s.Characters.use(s,0,p.pos);s.advance(0.15)
	s.players[1].pos=Vector2(s.ball.x,s.ball.y);s.step_ball()
	check(s.holder==1 and p.possess_time>0,"another player can take a possessed ball without ejecting the wisp early")
	s.command(0,Vector2(1700,0));s.advance(0.1)
	check(p.jump_due and s.holder==1,"possession cannot force a held ball to jump")
	s.Characters.eject(s,0)
	check(p.possess_time==0 and p.eject_time==1 and absf(Vector3(p.knock.x,p.knock.y,p.vz).length()-38)<0.001,"ejection applies original impulse and one-second catch exclusion")
	s.holder=-1;s.players[1].pos=Vector2(1700,1000);s.ball=s.Characters.world_position(p)
	check(s.catch_hit(s.ball,Vector3.ZERO).is_empty(),"just-ejected wisp cannot immediately recatch the ball")
	s=scene("h010");p=s.players[0];s.take(0);s.step_ball();s.Characters.use(s,0,p.pos);s.advance(8.1)
	check(p.possess_time==0 and p.eject_time>0,"possession ends and ejects after eight seconds")
	s=scene("h010");s.take(0);s.step_ball();s.Characters.use(s,0,Vector2.ZERO);s.advance(0.2);s.reset()
	check(not s.Characters.absent(s.players[0]) and not s.players[0].jump_due and s.no_steal==0,"round reset clears entry, possession and protection")
	var a=scene("h010");var b=scene("h010")
	for sim in [a,b]:sim.take(0);sim.step_ball();sim.Characters.use(sim,0,Vector2.ZERO)
	for i in range(270):a.advance(1.0/30)
	for i in range(1296):b.advance(1.0/144)
	check(a.players[0].pos.distance_to(b.players[0].pos)<0.001 and absf(a.players[0].z-b.players[0].z)<0.001,"ejection randomness and flight stay independent of render frame rate")
	FileAccess.open("res://research/mobility-skills-tests.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	quit(1 if failed else 0)
