extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var checks=[]
var failed=false

func check(ok: bool,name: String,detail=""):
	checks.append({"test":name,"passed":ok,"detail":str(detail)})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))

func scene(friendly=false,borrowed=false):
	var s=Sim.new();s.players=[]
	var caster=s.make_player(Vector2(-1100,0),0)
	s.Characters.configure(caster,"h01R");s.players.append(caster)
	var victim=s.make_player(Vector2.ZERO,0 if friendly else 1)
	if borrowed:
		s.Characters.configure(victim,"h029");victim.morph_kit="h005";victim.morph_casts=3
	victim.angle=PI/2;victim.body=PI/2;victim.previous_body=PI/2;s.players.append(victim)
	s.ball=Vector3(1400,-900,0)
	return s

func attach(s,friendly=false):
	s.Characters.use(s,0,Vector2(800,0),friendly)
	var h=s.players[0].hook
	h.pos=s.Characters.world_position(s.players[1])
	s.Characters.Complex.hook_attach(s,h,1)
	return h

func real_encounter():
	var s=scene()
	s.players[0].pos=Vector2(-850,0)
	s.players[1].angle=PI;s.players[1].body=PI;s.players[1].previous_body=PI
	s.submit_command("ability",0,Vector2(500,0))
	s.submit_command("ability",1,Vector2(-1600,0))
	return s

func _initialize():call_deferred("run")

func run():
	for friendly in [false,true]:
		var s=scene(friendly)
		s.tackle(1,Vector2(0,1000));s.step_tackles()
		var remaining=s.players[1].tackle;var stamp=s.players[1].tackle_order
		var h=attach(s,friendly)
		check(s.players[1].tackle==remaining and s.players[1].tackle_order==stamp,"hook preserves active tackle and activation order, ally="+str(friendly))
		check((s.players[1].silence>0)!=friendly,"only enemy hook applies silence, ally="+str(friendly))
		var before=s.players[1].pos
		s.step_tackles()
		check(s.players[1].pos.distance_to(before+Vector2(0,44.6))<0.001 and absf(s.players[1].tackle-(remaining-44.6))<0.001,"scripted slide still advances under hook, ally="+str(friendly),s.players[1].pos)
		s.Characters.Complex.hook_drop(s,h)
		check(s.players[1].hooked==0 and s.players[1].tackle>0,"early hook release leaves independent tackle alive, ally="+str(friendly))
		for n in range(13):s.step_tackles()
		check(s.players[1].tackle==0 and s.players[1].tackle_order==0 and s.tackle_shadows.size()==15,"released tackle expires with all fifteen source shadows, ally="+str(friendly),s.tackle_shadows.size())
		check(s.navigation_solid(s.players[1]),"ordinary collision eligibility returns after both effects, ally="+str(friendly))
	var s=scene();s.tackle(1,Vector2(0,1000));var h=attach(s)
	for n in range(15):s.step_tackles()
	check(s.players[1].tackle==0 and s.players[1].hooked==h.id and h.caught==1,"finishing tackle does not detach an ongoing hook")
	check(not s.Characters.q_available(s.players[1]) and not s.Characters.use(s,1,Vector2(1000,0)),"enemy silence still blocks new spell casts")
	s.Characters.Complex.hook_drop(s,h);s.advance(0.6)
	s.command(1,Vector2(700,900));var before=s.players[1].pos;s.advance(1.2)
	check(s.players[1].pos.distance_to(before)>150 and s.players[1].want_move,"movement order resumes after both effects end",s.players[1].pos)
	s=scene();s.players[1].angle=PI;s.players[1].body=PI
	s.tackle(1,Vector2(1000,0));h=attach(s)
	check(not s.players[1].cast_pending and s.players[1].tackle==0 and s.players[1].cooldown==0,"enemy hook cancels uncast turn preparation without creating a slide")
	# Hook writes XY through Object.setX/Y; it neither clears Object velocity
	# nor stops its 32 Hz iterator. Exercise that phase independently of the
	# still-unported native ordering between Object, Hook and Tackle callbacks.
	s=scene();h=attach(s);s.players[1].knock=Vector2(10,0)
	s.step_object_impulses()
	check(absf(s.players[1].knock.x-9.35)<0.001 and absf(s.players[1].pos.x-9.35)<0.001,"hooked horizontal impulse continues with original ground friction",s.players[1].pos)
	for n in range(15):s.step_object_impulses()
	check(s.players[1].knock==Vector2.ZERO,"hooked momentum decays instead of being stored until release")
	s=scene();h=attach(s);s.players[1].z=200;s.players[1].vz=5
	s.step_object_impulses()
	# JASS subtracts 1.5 gravity and then 0.08 air friction: 5 -> 3.42.
	check(absf(s.players[1].z-203.42)<0.001 and absf(s.players[1].vz-3.42)<0.001,"hook does not suspend airborne gravity or retain frozen height",s.players[1].z)
	for n in range(100):s.step_object_impulses()
	check(s.players[1].z==0 and s.players[1].vz==0,"hooked airborne player can land while still attached")
	s=scene();s.tackle(1,Vector2(0,1000));h=attach(s)
	var other=s.make_player(Vector2(0,144.6),1);s.players.append(other)
	s.step_tackles()
	check(s.players[1].tackle==0 and s.players[1].hooked==h.id and s.players[1].knock.y>4.99 and s.players[2].knock.y>9.99,"hooked tackle still hits a forward ally and ends normally")
	s.players[2].pos=Vector2(1200,800);s.step_object_impulses()
	check(absf(s.players[1].knock.y-4.35)<0.001,"push generated during hooked tackle is integrated on next object phase")
	s=scene(false,true);s.tackle(1,Vector2(0,1000));h=attach(s)
	check(s.players[1].morph_casts==2 and s.players[1].tackle>0,"hook preserves a borrowed active tackle without spending another charge")
	for n in range(15):s.step_tackles()
	check(s.players[1].morph_ghost==2.0 and s.players[1].morph_casts==2,"borrowed tackle reaches its normal completion callback")
	s=scene();s.tackle(1,Vector2(0,1000));h=attach(s);s.players[1].stun=1
	s.stop(1,false);s.KeeperRules.hold(s,1);s.step_tackles()
	check(s.players[1].tackle>0 and s.players[1].hooked==h.id and s.tackle_shadows.size()==1,"stop hold and stun do not cancel an already-running scripted slide")
	s.reset()
	check(s.projectiles.is_empty() and s.tackle_shadows.is_empty() and s.players.all(func(p):return p.tackle==0 and p.hooked==0 and p.silence==0),"round reset clears both effects")
	s=real_encounter();s.advance(0.35)
	check(s.players[1].hooked!=0 and s.players[1].tackle>0 and s.tackle_shadows.size()==11,"normal queued casts produce overlapping hook and slide",[s.players[1].hooked,s.players[1].tackle,s.tackle_shadows.size()])
	s.advance(1.5)
	check(s.players[1].hooked==0 and s.players[1].tackle==0 and s.projectiles.is_empty() and s.players[1].pos.is_finite(),"full encounter finishes without a stuck hook or slide")
	var a=real_encounter();var b=real_encounter()
	for frame in range(30):a.advance(1.0/30)
	for frame in range(144):b.advance(1.0/144)
	check(a.players[1].pos.is_equal_approx(b.players[1].pos) and a.players[1].knock.is_equal_approx(b.players[1].knock) and a.tackle_shadows==b.tackle_shadows,"hook-slide interaction agrees at 30 and 144 render FPS")
	var f=FileAccess.open("res://research/hook-tackle-tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"basis":"Local JASS Hook never destroys Tackle or stops Object. Native inter-system callback ordering and pathing flag overrides are not proven by these checks.","checks":checks},"\t"))
	quit(1 if failed else 0)
