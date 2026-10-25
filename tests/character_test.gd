extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var results=[]
var failed=false
func check(ok: bool,name: String,detail=""):
	results.append({"test":name,"passed":ok,"detail":detail})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))
func _initialize():call_deferred("run")
func scene(id: String):
	var s=Sim.new()
	s.selected_character=id
	s.reset()
	s.players[0].pos=Vector2(-1000,0)
	s.players[1].pos=Vector2(1000,1000)
	s.ball=Vector3(0,0,0)
	return s
func run():
	var s=scene("h028")
	s.take(0);s.step_ball()
	check(s.players[0].speed==400 and s.players[0].turn==1 and s.players[0].catch_height==150,"angel uses original unit attributes")
	s.Characters.use(s,0,Vector2(1000,0))
	check(s.velocity==Vector3(35,0,7) and s.holder==-1,"angel Q adds original 35/7 kick vector")
	s.players[0].sprint=true
	for i in range(32):s.step_ball()
	check(absf(s.players[0].mana-60)<0.001,"angel endurance net drain is 40 per second from 60 drain and 20 regen")
	s=scene("h00P")
	s.players[0].pos=Vector2.ZERO
	s.players[1].pos=Vector2(400,0)
	s.ball=Vector3(-300,0,0)
	s.Characters.use(s,0,Vector2.ZERO)
	s.advance(0.3)
	check(s.players[1].z==0 and s.ball.z==0,"slam has a windup before applying forces")
	s.advance(0.15)
	check(s.players[1].z>0 and s.ball.z>0 and s.players[0].z==0,"slam lifts nearby player and free ball without lifting caster",[s.players[1].z,s.ball.z])
	s.advance(8)
	check(s.players[1].z==0 and s.players[1].vz==0,"airborne player bounces then settles on ground")
	s=scene("h00Y")
	s.ball=Vector3(1000,0,0)
	s.Characters.use(s,0,Vector2.ZERO)
	s.advance(0.4)
	check(s.players[0].pos.x>-1000 and s.players[0].pull_time>0,"pull accelerates caster toward the ball")
	s.Characters.use(s,0,Vector2.ZERO)
	check(s.players[0].pull_time==0 and s.players[0].cooldown==10,"early pull cancellation sets ten-second cooldown")
	s=scene("h00Y")
	s.ball=Vector3(1900,1000,0)
	s.Characters.use(s,0,Vector2.ZERO)
	for i in range(120):
		s.players[0].pos=Vector2(-1000,0)
		s.step_ball()
	s.Characters.use(s,0,Vector2.ZERO)
	check(s.players[0].cooldown==30,"long pull has thirty-second cooldown")
	s=scene("h00Y")
	s.Characters.use(s,0,Vector2.ZERO)
	s.take(0)
	check(s.players[0].pull_time==0 and s.players[0].cooldown==10,"catching ball ends pull and starts cooldown")
	s=scene("h01I")
	s.Characters.use(s,0,Vector2.ZERO)
	s.advance(0.49)
	check(s.players[0].pos==Vector2(-1000,0),"shadow waits half a second")
	s.advance(0.02)
	check(s.players[0].pos.distance_to(Vector2(-600,0))<0.001 and s.players[0].shadow_return>0,"shadow blinks four hundred units and exposes recall")
	s.Characters.use(s,0,Vector2.ZERO)
	check(s.players[0].pos==Vector2(-1000,0) and s.players[0].cooldown==32,"shadow recall returns to origin and replaces cooldown")
	s=scene("h01I")
	s.arena.add_box(Rect2(-800,-100,40,200),240)
	s.Characters.use(s,0,Vector2.ZERO);s.advance(0.6)
	check(s.players[0].pos.x<=-830 and s.arena.point_free(s.players[0].pos,30),"shadow forward look cannot blink into a wall")
	s=scene("h003")
	s.Characters.use(s,0,Vector2(-200,0))
	check(s.skill_effects.size()==1 and s.skill_effects[0].power==0,"black hole begins at zero force")
	var caster: Vector2=s.players[0].pos
	s.players[1].pos=Vector2(0,150)
	# The growing inverse-square force must first exceed ground friction.
	s.advance(1.4)
	check(s.ball.x<0 and s.players[1].pos.x<0 and s.players[0].pos==caster,"growing black hole pulls free ball and other units but not caster",[s.ball,s.players[1].pos,s.players[0].pos])
	check(s.velocity.length()<=60.001,"black hole respects the original speed cap")
	s.advance(3)
	check(s.skill_effects.is_empty(),"black hole expires after its lifetime")
	s=scene("h003")
	s.Characters.use(s,0,Vector2(700,0))
	check(s.skill_effects.is_empty() and not s.players[0].ability_order.is_empty(),"distant black hole orders movement into cast range")
	s.advance(3)
	check(s.skill_effects.size()==1 and s.players[0].pos.distance_to(Vector2(700,0))<=900,"approach automatically casts at the requested point")
	s=scene("h005")
	s.players[0].z=400;s.players[0].previous_z=400
	s.ball=Vector3(-1000,0,0)
	check(s.catch_hit(s.ball,Vector3.ZERO).is_empty(),"high airborne player cannot catch a ground ball")
	s.take(0);s.step_ball()
	check(absf(s.ball.z-s.players[0].z)<0.001,"held ball follows airborne holder height")
	s=scene("h005")
	s.mixed_roster=true;s.start_match(6);s.controlled=-1
	s.advance(18)
	var ids={};var finite=true
	for p in s.players:
		ids[p.character]=true
		finite=finite and p.pos.is_finite() and is_finite(p.z) and p.z>=0 and absf(p.pos.x)<2530 and absf(p.pos.y)<1320
	check(ids.size()==mini(12,Sim.Characters.IDS.size()) and finite,"twelve distinct playable kits coexist in an AI match")
	for selected in Sim.Characters.IDS:
		s.selected_character=selected;s.start_match(6)
		for p in s.players:ids[p.character]=true
	check(ids.size()==Sim.Characters.IDS.size(),"rotated lineups cover every playable character")
	s.score=[1,0];s.reset()
	check(s.skill_effects.is_empty() and s.players[0].z==0 and s.players[0].pull_time==0,"round reset clears airborne motion and active skills")
	var f=FileAccess.open("res://research/character-tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":results},"\t"))
	quit(1 if failed else 0)
