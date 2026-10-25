extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var passed=0
var failures=[]
var traces=[]
func _initialize():call_deferred("run")
func check(ok: bool,label: String):
	if ok:passed+=1
	else:failures.append(label);printerr("FAIL "+label)
func fresh(body: float,heading: float):
	var s=Sim.new();s.start_practice();s.bot_enabled=false
	var p=s.players[0];p.pos=Vector2.ZERO;p.previous=p.pos;p.body=body;p.previous_body=body;p.angle=heading;p.spin=0
	s.players[1].pos=Vector2(1500,900);s.take(0);return s
func issue(s,angle: float):
	s.submit_command("kick",0,Vector2(s.ball.x,s.ball.y)+Vector2.from_angle(angle)*1600);s.consume_commands()
func run():
	# Exercise actual shot dispatch, both edges, and +/-PI wrap-around.
	for facing in [0.0,deg_to_rad(179),deg_to_rad(-179)]:
		for offset in [-90.0,-60.1,-60.0,-59.9,-30.0,0.0,30.0,59.9,60.0,60.1,90.0,180.0]:
			var s=fresh(facing,facing);var p=s.players[0];var angle=facing+deg_to_rad(offset)
			issue(s,angle)
			var immediate=absf(offset)<=60.0
			var label="facing %.1f offset %.1f"%[rad_to_deg(facing),offset]
			check((s.holder==-1)==immediate,label+": immediate only inside inclusive 60-degree cone")
			check(p.shot_order.is_empty()==immediate,label+": outside cone retains a pending turn")
			if immediate:check(Vector2(s.velocity.x,s.velocity.y).normalized().dot(Vector2.from_angle(angle))>.999,label+": direction is not clamped to facing")
	# The old double gate could silently narrow the visible cone while turning.
	var s=fresh(0,PI);issue(s,deg_to_rad(50))
	check(s.holder==-1,"body cone can fire despite lagging/opposite internal heading")
	s=fresh(0,PI/2);issue(s,PI/2)
	check(s.holder==0,"internal heading alignment cannot bypass a visible-body turn")
	for offset in [60.1,90.0,135.0,180.0,-90.0,-135.0]:
		s=fresh(0,0);var p=s.players[0];var angle=deg_to_rad(offset);issue(s,angle)
		var prior_error=absf(offset);var fired=false;var ticks=0;var fire_error=0.0
		for tick in range(40):
			prior_error=absf(rad_to_deg(wrapf(angle-p.body,-PI,PI)))
			s.advance(.03);ticks+=1
			fire_error=absf(rad_to_deg(wrapf(angle-p.body,-PI,PI)))
			if s.holder==-1:fired=true;break
		check(fired and prior_error>60 and fire_error<=60.0001,"fires on first eligible body update for "+str(offset))
		check(p.pos==Vector2.ZERO,"preparation holds position for "+str(offset))
		check(Vector2(s.velocity.x,s.velocity.y).normalized().dot(Vector2.from_angle(angle))>.999,"turn retains intended shot direction for "+str(offset))
		traces.append({"requested_degrees":offset,"turn_seconds":ticks*.03,"remaining_angle_at_release":fire_error})
	check(is_equal_approx(Sim.Native.ARRIVAL_ANGLE,.2),"navigation arrival tolerance remains independent of shot cone")
	FileAccess.open("res://research/shot-angle-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"traces":traces},"\t"))
	print("SHOT ANGLE ",passed," passed; ",failures.size()," failed");quit(0 if failures.is_empty() else 1)
