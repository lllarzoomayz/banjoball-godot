extends SceneTree
const Arena=preload("res://scripts/arena_collision.gd")
const Sim=preload("res://scripts/match_sim.gd")
var checks=[]
var failed=false

func check(ok: bool,label: String,detail=""):
	checks.append({"test":label,"passed":ok,"detail":str(detail)})
	failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+label+" "+str(detail))

func _initialize():call_deferred("run")

func run():
	for field in range(4):
		var arena=Arena.new();arena.set_field(field)
		var shift=(float(arena.data.block_width)-32)*64
		var authored=arena.authored_pathing[field]
		check(authored.instances.size()==(248 if field in [0,2] else 280),"field %d retains every original ground-blocker placement"%field)
		# Concrete coordinates from DOO: blocker centers at +/-2080, +/-288;
		# solid 2x2 path texture => inner edges +/-2048 and +/-256, not the
		# scripted Field (2016) / Goal_Area (224) rectangles.
		for side in [-1.0,1.0]:
			var x=side*(2300+shift)
			for edge in [-1.0,1.0]:
				check(arena.point_free(Vector2(x,edge*210),30),"field %d side %d edge %d removes premature goal-side wall"%[field,int(side),int(edge)])
				check(not arena.point_free(Vector2(x,edge*240),30),"field %d side %d edge %d respects original post-side footprint"%[field,int(side),int(edge)])
				var hit=arena.sweep_unit(Vector2(x,0),Vector2(0,edge*400),30)
				check(not hit.is_empty() and absf(hit.t-226.0/400)<0.0001,"field %d side %d edge %d walking contact at original edge minus unit radius"%[field,int(side),int(edge)],hit)
				var ball_hit=arena.sweep_ball(Vector3(x,edge*200,80),Vector3(0,edge*60,0))
				check(not ball_hit.is_empty() and absf(ball_hit.t-0.4)<0.0001,"field %d side %d edge %d preserves separate original ball boundary"%[field,int(side),int(edge)])
			check(arena.point_free(Vector2(side*(2010+shift),450),30),"field %d side %d removes premature outer-mouth wall"%[field,int(side)])
			check(not arena.point_free(Vector2(side*(2030+shift),450),30),"field %d side %d mouth corner remains solid"%[field,int(side)])
			var rear=arena.sweep_unit(Vector2(side*(2450+shift),0),Vector2(side*200,0),30)
			check(not rear.is_empty() and absf(rear.t-0.4)<0.0001,"field %d side %d rear collision follows placed blocker at 2560"%[field,int(side)],rear)
			check(arena.sweep_unit(Vector2(side*(1800+shift),0),Vector2(side*600,0),30).is_empty(),"field %d side %d goal mouth stays open"%[field,int(side)])
		# Exercise the real route planner in the formerly blocked goal-side strip.
		var sim=Sim.new();sim.arena.set_field(field)
		sim.players[0].pos=Vector2(-2100-shift,150)
		sim.players[1].pos=Vector2(1200,900);sim.ball=Vector3(1200,-900,0)
		var target=Vector2(-2350-shift,210)
		sim.command(0,target,false)
		var safe=true
		for i in range(200):
			sim.step_movement()
			safe=safe and sim.arena.point_free(sim.players[0].pos,30)
		check(safe and sim.players[0].pos.distance_to(target)<=Sim.Native.MIN_POINT_STOP+0.001,"field %d defender can walk along the original goal-side gap"%field,sim.players[0].pos)
		# Eligibility remains a game rule, not part of the prop's footprint.
		check(not sim.goal_restrictions(1).is_empty(),"field %d attacker goal restrictions remain active"%field)
	FileAccess.open("res://research/authored-pathing-tests.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks},"\t"))
	quit(1 if failed else 0)
