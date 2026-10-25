extends SceneTree
const Sim=preload("res://scripts/match_sim.gd")
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func scene(id="h005"):
	var s=Sim.new();s.selected_character=id;s.reset();s.bot_enabled=false
	s.players[0].pos=Vector2(-400,0);s.players[1].pos=Vector2(1500,900);s.ball=Vector3(1500,-900,0)
	return s
func texts(s):return s.native_visuals.filter(func(e):return e.model=="" and e.has("message"))
func portal(s,paired=false):
	var r={"id":1,"owner":0,"a":Vector3.ZERO,"b":Vector3(700,0,0) if paired else null,"life":3.0 if paired else 5.0,"age":0.0,"unlock":0.0,"projectile":0,"traveled":{}}
	s.rifts.append(r);s.players[0].rift=r;return r
func run():
	var s=scene("h026");s.Characters.use(s,0,Vector2.ZERO)
	s.advance(.125);check(texts(s).is_empty(),"SMASH text waits for impact, not button press")
	s.advance(s.BALL_DT);var tag=texts(s)[0]
	check(tag.message=="OGRE SMASH!" and tag.text_lifetime==1.0 and tag.owner==0,"original one-second smash text emitted at bump")
	check(is_equal_approx(tag.time,.15625),"impact uses 32Hz action completion timestamp")
	s.advance(.5);check(texts(s).size()==1,"smash text emitted once per impact")
	s=scene("h01I");s.Characters.blink(s,0);var origin=s.players[0].shadow_origin
	s.advance(.49);check(texts(s).is_empty(),"shadow first callback waits half a second")
	s.advance(.01);check(texts(s)[0].message=="2.0!" and texts(s)[0].audience_owner==0,"shadow starts with source counter 2.0, restricted to owner")
	s.advance(1.5);var tags=texts(s)
	check(tags.map(func(e):return e.message)==["2.0!","1.5!","1.0!","0.5!"],"shadow follows all four original callbacks")
	check(tags.all(func(e):return e.pos==Vector3(origin.x,origin.y,0) and e.text_lifetime==.75),"countdown anchored to stationary shadow with .75s lifespan")
	check(tags.map(func(e):return e.time)==[.5,1.0,1.5,2.0],"shadow callback cadence is exactly half a second")
	s.advance(.5);check(s.players[0].shadow_return==0 and texts(s).size()==4,"expiry emits no zero countdown")
	s=scene("h01I");s.Characters.blink(s,0);s.advance(.5);s.Characters.use(s,0,Vector2.ZERO);s.advance(1)
	check(texts(s).size()==1,"early recall cancels remaining countdown callbacks")
	s=scene("h027");var r=portal(s);s.advance(s.BALL_DT)
	check(texts(s)[0].message=="5.0!" and texts(s)[0].audience_owner==0,"single portal starts five-second owner-only countdown")
	check(texts(s)[0].text_offset==Vector3(-35,0,150),"portal uses source -35/+150 offset")
	s.advance(4.5);tags=texts(s)
	check(tags.size()==10 and tags[-1].message=="0.5!","single portal emits ten half-second values")
	s.advance(.5);check(s.rifts.is_empty() and texts(s).size()==10,"lone entry expires at original timer boundary without zero text")
	s=scene("h027");r=portal(s,true);s.advance(s.BALL_DT)
	check(texts(s).size()==2 and texts(s).all(func(e):return e.message=="3.0!" and e.audience_team==0),"paired portals both show friendly three-second countdown")
	s.advance(2.5);tags=texts(s)
	check(tags.size()==12 and tags[-1].message=="0.5!","six synchronized messages at each endpoint")
	s.advance(.5);check(s.rifts.is_empty(),"paired lifetime includes exactly three seconds from first callback")
	# Source keeps entrance timer advancing while second projectile is airborne.
	s=scene("h027");r=portal(s);s.advance(4.75);r.projectile=999;s.advance(.75)
	check(not s.rifts.is_empty() and r.age>5 and texts(s).size()==10,"flight defers destruction but does not pause timeout or add countdown values")
	r.projectile=0;s.advance(s.BALL_DT);check(s.rifts.is_empty(),"expired entrance closes as soon as flight ends without landing")
	# An actual second projectile landing resets both the lifetime and message phase.
	s=scene("h027");s.Characters.use(s,0,Vector2.ZERO);s.advance(1.51)
	s.Characters.use(s,0,Vector2(-400,-500));s.advance(1)
	check(s.rifts.size()==1 and s.rifts[0].b!=null,"real casts create both portals")
	tags=texts(s).filter(func(e):return e.get("audience_team",-1)==0)
	check(tags.size()>=2 and tags[0].message=="3.0!" and tags[1].message=="3.0!","second landing resets first portal countdown as well")
	# Warning is a one-shot point in space, not a permanently attached label.
	s=scene();s.start_match(3);s.countdown=0;s.match_state="playing";s.bot_enabled=false
	s.ball=Vector3(-1800,0,0);s.holder=-1;s.stall_counter=209;s.StallRules.step(s)
	tag=texts(s)[0]
	check(tag.message=="!" and tag.text_lifetime==1.5 and tag.text_color=="ffcc00" and is_equal_approx(tag.text_size,.0235),"stall warning retains source color, font scale and lifespan")
	check(tag.text_offset==Vector3(6,0,100) and tag.pos==Vector3(-1800,0,0),"warning anchors to the ball's location when threshold is reached")
	s.StallRules.step(s);check(texts(s).size()==1,"warning does not repeat while flagged")
	s.reset();check(texts(s).is_empty(),"round reset clears outstanding world text")
	FileAccess.open("res://research/skill-text-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("SKILL TEXT ",passed," passed; ",failures.size()," failed");quit(1 if not failures.is_empty() else 0)
