extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var checks=[]
var failed=false

func check(ok: bool,name: String,detail=""):
	checks.append({"test":name,"passed":ok,"detail":str(detail)})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))

func scene(id="h005"):
	var s=Sim.new();s.selected_character=id;s.reset()
	s.players[0].pos=Vector2(-600,0);s.players[0].angle=0;s.players[0].body=0
	s.players[1].pos=Vector2(1400,800);s.ball=Vector3(1200,-900,0)
	return s

func attach(s,friendly=false):
	s.Characters.configure(s.players[1],"h01R")
	s.players[1].team=0 if friendly else 1;s.players[1].pos=Vector2(-1400,0)
	s.Characters.use(s,1,Vector2(600,0),friendly)
	var h=s.players[1].hook;h.pos=s.Characters.world_position(s.players[0])
	s.Characters.Complex.hook_attach(s,h,0)
	return h

func corridor():
	var s=scene();s.players[0].pos=Vector2(-400,0);s.players[1].pos=Vector2.ZERO
	s.arena.add_box(Rect2(-1000,64,2000,1500),200)
	s.arena.add_box(Rect2(-1000,-1564,2000,1500),200)
	s.command(0,Vector2(400,0))
	for n in range(140):s.step_movement()
	return s

func _initialize():call_deferred("run")

func run():
	var s=scene();var p=s.players[0]
	check(s.navigation_solid(p) and not p.object_active,"new player starts with pathing enabled and Object asleep")
	s.tackle(0,Vector2(600,0))
	check(not s.navigation_solid(p),"Tackle cast disables unit pathing")
	s.step_object_impulses()
	check(not s.navigation_solid(p) and p.tackle==640,"idle Object does not undo a skill's pathing write")
	s.apply_impulse(0,Vector3.ZERO);s.step_object_impulses()
	check(s.navigation_solid(p) and p.tackle==640 and not p.object_active,"zero-vector Object callback enables pathing before stopping despite active tackle")
	s.step_tackles()
	check(s.navigation_solid(p) and p.tackle>0,"Tackle movement does not re-disable pathing on every step")
	var h=attach(s)
	check(not s.navigation_solid(p) and p.tackle>0,"later Hook attachment overrides prior Object enable")
	s.step_object_impulses()
	check(not s.navigation_solid(p),"stopped Object iterator does not overwrite later Hook attachment")
	s.finish_tackle(0)
	check(s.navigation_solid(p) and p.hooked==h.id,"Tackle end enables pathing even while Hook is attached")
	s.Characters.Complex.hook_drop(s,h)
	check(s.navigation_solid(p) and p.hooked==0,"Hook drop also explicitly enables pathing")
	s=scene();p=s.players[0];h=attach(s,true)
	s.tackle(0,Vector2(600,0));s.Characters.Complex.hook_drop(s,h)
	check(s.navigation_solid(p) and p.tackle>0,"Hook drop enables pathing even while a friendly hooked tackle continues")
	s=scene();p=s.players[0];s.tackle(0,Vector2(600,0));s.command(0,Vector2(600,100))
	check(not s.navigation_solid(p) and p.object_active,"smart order schedules Object without eagerly changing pathing")
	s.step_object_impulses()
	check(s.navigation_solid(p) and p.tackle>0 and p.want_move,"ground smart-order callback enables pathing during tackle steering")
	s=scene();p=s.players[0];s.apply_impulse(0,Vector3(1,0,0));s.step_object_impulses()
	check(p.object_active and absf(p.knock.x-0.35)<0.001,"friction leaves active Object until the final low-speed callback")
	s.set_unit_pathing(0,false);s.step_object_impulses()
	check(s.navigation_solid(p) and p.knock==Vector2.ZERO and not p.object_active,"final ground-friction callback restores pathing and sleeps")
	s.set_unit_pathing(0,false);s.step_object_impulses()
	check(not s.navigation_solid(p),"sleeping zero-speed Object does not continuously force collision on")
	s=scene();s.selected_field=2;s.start_practice();p=s.players[0]
	p.pos=Vector2(2020,700);p.angle=0;p.body=0;s.command(0,Vector2(10000,700));s.step_object_impulses()
	check(p.slide_order and p.knock==Vector2.ZERO and not p.object_active,"ice boundary cancels outward thrust and stops Object even with a pending smart order")
	s.set_unit_pathing(0,false)
	for n in range(8):s.step_object_impulses()
	check(not s.navigation_solid(p) and not p.object_active,"stopped ice callback is not resurrected by stale smart-order latch")
	s.command(0,Vector2(10000,700));s.step_object_impulses()
	check(s.navigation_solid(p),"new smart order explicitly wakes the stopped ice callback")
	s=scene();p=s.players[0];s.apply_impulse(0,Vector3(0,0,4));s.step_object_impulses()
	check(p.z>1 and not s.navigation_solid(p),"Object ascent disables pathing after applying vertical displacement")
	s.set_unit_pathing(0,true)
	check(s.navigation_solid(p) and p.z>1,"explicit enable is not silently overridden by a height-derived predicate")
	s.step_object_impulses()
	check(not s.navigation_solid(p),"next airborne Object callback can disable pathing again")
	var landing_seen=false
	for n in range(60):
		s.step_object_impulses()
		if p.z==0:
			landing_seen=true;break
	check(landing_seen and not s.navigation_solid(p) and p.object_active,"landing branch keeps the previous flag until the next ground callback")
	s.step_object_impulses()
	check(s.navigation_solid(p) and not p.object_active,"zero-bounce landing receives its final enabling callback")
	s=scene("h00R");p=s.players[0];s.Characters.use(s,0,p.pos)
	check(not s.navigation_solid(p) and p.flip_time>0,"Backflip cast writes pathing off")
	p.flip_time=0.001;p.z=50 # Expiry callback isolated from the next Object phase.
	s.Characters.step(s)
	check(s.navigation_solid(p) and p.z==50,"Backflip expiry enables pathing even before an elevated unit lands")
	s.step_object_impulses()
	check(not s.navigation_solid(p),"airborne Object can overwrite Backflip expiry enable")
	s=scene("h004");p=s.players[0];s.set_sprint(0,true)
	check(not s.navigation_solid(p) and p.sprint,"SuperSprint start writes pathing off")
	s.step_object_impulses()
	check(not s.navigation_solid(p) and p.sprint and p.knock.length()>0,"moving ground Object re-disables pathing at absolute-height branch")
	s.set_unit_pathing(0,false);s.set_sprint(0,false)
	check(s.navigation_solid(p),"SuperSprint off order restores pathing")
	s=scene("h004");p=s.players[0];s.set_sprint(0,true);p.mana=0.1;s.step_ball()
	check(not s.navigation_solid(p) and not p.sprint and p.knock.length()>0,"mana exhaustion enable is overwritten while remaining ground momentum moves")
	for n in range(100):s.step_ball()
	check(s.navigation_solid(p) and p.knock==Vector2.ZERO,"exhausted SuperSprint restores collision after momentum settles")
	s=scene("h010");p=s.players[0];s.take(0);s.step_ball();s.Characters.use(s,0,p.pos)
	check(not p.pathing_enabled and p.flight_steps==3,"possession entry flight disables pathing")
	for n in range(3):s.Characters.fly_into_ball(s,0)
	check(p.pathing_enabled and p.possess_time>0 and not s.navigation_solid(p),"flight end restores flag while possession's hidden player stays absent")
	s.Characters.eject(s,0);s.step_object_impulses()
	check(not s.navigation_solid(p) and p.z>0,"ejected player's Object ascent disables restored flag again")
	s=corridor();p=s.players[1];s.set_unit_pathing(1,false)
	var changed=s.blocker_stamp(0);var same=s.blocker_stamp(0)
	p.tackle=640;p.hooked=77;p.flip_time=1.09
	check(changed==s.blocker_stamp(0) and changed==same,"skill labels do not change a previously disabled occupancy stamp")
	for n in range(40):s.step_movement()
	check(s.players[0].pos.x>100,"waiting route opens when the actual blocker flag turns off")
	s=corridor();p=s.players[1];s.set_unit_pathing(1,false);s.command(0,Vector2(400,0))
	p.tackle=640;p.hooked=77;s.set_unit_pathing(1,true)
	check(not s.free_point(p.pos,0) and not s.segment(s.players[0].pos,p.pos,0),"enabled blocker is occupied despite active skill labels")
	for n in range(140):s.step_movement()
	check(s.players[0].pos.x<0 and s.players[0].pos.distance_to(p.pos)>=59.99 and s.players[0].want_move,"route stops when explicit enable closes the corridor again",s.players[0].pos)
	s=scene();s.players[1].pos=s.players[0].pos+Vector2(60,0)
	s.set_unit_pathing(0,false)
	check(s.free_point(s.players[1].pos,0) and s.segment(s.players[0].pos,s.players[1].pos,0),"disabled owner ignores a standing player's footprint")
	s.set_unit_pathing(0,true)
	check(not s.free_point(s.players[1].pos,0),"enabled owner checks footprints again")
	s=scene();s.players[0].team=0;s.players[0].pos=Vector2(-1400,0);s.players[1].team=0;s.players[1].pos=Vector2(-2200,0)
	s.set_unit_pathing(1,false)
	check(s.goal_blocked(0,0),"pathing-disabled but present keeper still occupies the protected goal")
	s.reset()
	check(s.players.all(func(player):return player.pathing_enabled and not player.object_active),"new round clears prior flag writes and Object wake state")
	var a=scene();var b=scene()
	for sim in [a,b]:
		sim.tackle(0,Vector2(600,0));sim.command(0,Vector2(600,400));sim.apply_impulse(0,Vector3(2,0,18))
	for n in range(90):a.advance(1.0/30)
	for n in range(432):b.advance(1.0/144)
	check(a.players[0].pos.is_equal_approx(b.players[0].pos) and a.players[0].pathing_enabled==b.players[0].pathing_enabled and a.players[0].object_active==b.players[0].object_active,"collision callbacks and route recovery agree at 30/144 render FPS")
	var f=FileAccess.open("res://research/pathing-callbacks-tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"basis":"JASS direct SetUnitPathing writes and Object stop/landing branches. Cross-system native scheduling and native collision rasterization remain separate.","checks":checks},"\t"))
	quit(1 if failed else 0)
