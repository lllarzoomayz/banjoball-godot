extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var checks=[]
var failed=false
func check(ok: bool,label: String):
	checks.append({"test":label,"passed":ok})
	if not ok:failed=true;push_error(label)
func scene(offset: float=0.0):
	var s=Sim.new()
	s.players[0].pos=Vector2(-400,offset);s.players[0].body=0;s.players[0].angle=0
	s.players[1].pos=Vector2.ZERO;s.players[1].body=PI;s.players[1].angle=PI
	s.take(0)
	return s
func _initialize():call_deferred("run")
func run():
	for offset in [0.0,60.0]:
		for fps in [30,60,144]:
			var s=scene(offset);s.DirectionalMotion.order(s,0,Vector2.RIGHT)
			var changes=0;var owner=0
			for i in range(fps*3):
				s.advance(1.0/fps)
				if s.holder!=owner:changes+=1;owner=s.holder
			check(s.holder==1 and changes==1,"front dribble stolen once without ping-pong: offset %s fps %d"%[offset,fps])
	var s=scene()
	check(s.ball==Vector3(-300,0,0),"ownership places ball in front immediately")
	s.players[0].pos=Vector2(-180,0);s.step_ball()
	check(s.holder==1 and s.ball.distance_to(Vector3(-100,0,0))<0.001 and s.no_steal==0,"steal updates hand position without artificial timed immunity")
	for i in range(20):s.step_ball()
	check(s.holder==1,"remaining overlapped does not retrigger possession every tick")
	s.players[0].pos=Vector2(-300,0);s.step_ball();s.players[0].pos=Vector2(-180,0);s.step_ball()
	check(s.holder==0,"leaving then re-entering allows a genuine counter-steal")
	s=scene(60);s.players[0].pos=Vector2(200,60);s.step_ball()
	check(s.holder==1,"fast carried-ball segment cannot tunnel through defender between ticks")
	s=scene();s.players[1].pos=Vector2(-600,0);s.take(0)
	s.players[1].pos=Vector2(-100,0);s.step_ball()
	check(s.holder==1,"relative sweep detects a fast defender crossing the held ball")
	s=scene();s.players[0].pos=Vector2(-20,0);s.players[0].body=PI;s.take(0)
	s.players[0].pos=Vector2(-10,0);s.step_ball()
	check(s.holder==0,"body proximity alone cannot steal a ball shielded on opposite side")
	s=scene(120);s.players[0].pos=Vector2(200,120);s.step_ball()
	check(s.holder==0,"outside original ninety-unit catch range remains a valid dribble")
	s=scene();s.players[0].z=500;s.take(0);s.players[0].pos=Vector2(-180,0);s.step_ball()
	check(s.holder==0,"ball above defender catch height is not stolen")
	s=scene();s.no_steal=2;s.players[0].pos=Vector2(-180,0);s.step_ball()
	check(s.holder==0 and s.no_steal==1,"original skill protection still suppresses entry")
	s.step_ball();check(s.holder==1,"skill protection expiry rearms an already overlapping defender")
	s=scene();s.players[1].team=0;s.players[0].pos=Vector2(-180,0);s.step_ball()
	check(s.holder==1,"original teammate interception remains allowed")
	s=scene();s.players[0].pos=Vector2(300,0);s.Possession.relocated(s,0);s.step_ball()
	check(s.holder==0,"teleport does not simulate contact along skipped space")
	s=scene();s.players[0].pos=Vector2(-180,0);s.Possession.relocated(s,0);s.step_ball()
	check(s.holder==1,"teleport still tests the actual destination for a catch")
	s=scene();s.players[0].pos=Vector2(-180,0);s.arena.add_box(Rect2(-50,-100,10,200),300);s.step_ball()
	check(s.holder==0,"solid obstruction blocks reaching through to held ball")
	s.reset();check(s.held_ball_contacts.is_empty() and s.held_contact_owner==-1,"reset clears previous encounter state")
	FileAccess.open("res://research/held-ball-entry-test.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks},"\t"))
	print("Held-ball entry checks: ",checks.size(),"; failed: ",failed)
	quit(1 if failed else 0)
