extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var checks=[]
var failed=false
func check(ok: bool,label: String,detail=""):
	checks.append({"test":label,"passed":ok,"detail":str(detail)})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+label+" "+str(detail))
func scene(field: int):
	var s=Sim.new();s.selected_field=field;s.start_practice()
	s.players[1].pos=Vector2(1000,-900);s.ball=Vector3(-1000,-900,0)
	return s
func _initialize():call_deferred("run")
func run():
	for field in range(4):
		for side in [-1.0,1.0]:
			for edge in [-1.0,1.0]:
				var s=scene(field);var shift=(float(s.arena.data.block_width)-32)*64
				var p=s.players[0];p.team=0 if side<0 else 1
				p.pos=Vector2(side*(2300+shift),edge*180)
				p.body=edge*PI/2;p.tackle=640
				var old: Vector2=p.pos
				var target=old+Vector2(0,edge*44.6)
				check(s.arena.point_free(target,30),"field %d side %d edge %d ordinary footprint fits the authored gap"%[field,int(side),int(edge)])
				for i in range(15):s.step_tackle(0)
				check(p.pos==old and p.tackle==0 and s.tackle_shadows.size()==15,"field %d side %d edge %d tackle rejects outside its playable union and consumes all steps"%[field,int(side),int(edge)],p.pos)
			var s=scene(field);var shift=(float(s.arena.data.block_width)-32)*64
			var p=s.players[0];p.team=0 if side<0 else 1
			p.pos=Vector2(side*(2485+shift),0);p.body=PI if side<0 else 0;p.tackle=640
			var old: Vector2=p.pos
			check(s.arena.point_free(old+Vector2(side*44.6,0),30),"field %d side %d ordinary rear footprint still fits"%[field,int(side)])
			s.step_tackle(0)
			check(p.pos==old and is_equal_approx(p.tackle,595.4),"field %d side %d tackle respects original rear limit 2528"%[field,int(side)])
			# Crossing Field -> Goal_Area is allowed; only the union's outside is rejected.
			s=scene(field);p=s.players[0];p.team=0 if side<0 else 1
			p.pos=Vector2(side*(2000+shift),0);p.body=PI if side<0 else 0;p.tackle=640;old=p.pos
			s.step_tackle(0)
			check(p.pos.is_equal_approx(old+Vector2(side*44.6,0)),"field %d side %d tackle crosses the open mouth without a seam"%[field,int(side)],p.pos)
		# No extra footprint shrinking: the original condition tests the target point.
		var s=scene(field);var p=s.players[0]
		p.pos=Vector2(0,s.arena.half_size.y-50);p.body=PI/2;p.tackle=640
		var old: Vector2=p.pos;s.step_tackle(0)
		check(p.pos.is_equal_approx(old+Vector2(0,44.6)),"field %d tackle can reach within 5.4 units of the touchline"%field)
		old=p.pos;s.step_tackle(0)
		check(p.pos==old,"field %d next tackle step cannot cross the touchline"%field)
	FileAccess.open("res://research/tackle-playable-region-tests.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks},"\t"))
	quit(1 if failed else 0)
