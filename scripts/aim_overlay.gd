extends Control
## Presentation only: target preview never changes the simulation's aim/ball.
const Preview=preload("res://scripts/aim_preview.gd")
var game
var pointer=Vector2.ZERO
var pointer_valid=false
var mobile=false
var target_world=Vector2.ZERO
var cancelled=false
var preview={}
var preview_key=""
var preview_state=[]

func refresh(_delta: float):
	if not pointer_valid or game.aim=="":preview.clear();preview_key="";return
	var p=game.sim.players[game.sim.controlled]
	var key=str(game.sim.controlled)+game.aim+p.character+p.get("morph_kit","")
	var sim=game.sim
	var copy=sim.Copies.held(sim,sim.controlled) if sim.holder!=sim.controlled else {}
	var preaim=game.aim=="kick" and sim.holder!=sim.controlled and copy.is_empty()
	var state=[p.pos,p.body,p.z,target_world,preaim,Vector3.ZERO if preaim else sim.ball,Vector3.ZERO if preaim else sim.velocity,sim.last_owner,sim.selected_field,sim.powershot_active,p.pull_time>0,p.shadow_return>0,p.hook.is_empty(),p.rift.get("count",0),copy.get("position",Vector3.ZERO),copy.get("velocity",Vector3.ZERO)]
	# Cheap, collision-free geometry can follow every changed frame. Reuse it
	# while stationary instead of the old 80 ms stepping during finger drags.
	if state!=preview_state or key!=preview_key:
		preview=Preview.build(game.sim,game.sim.controlled,game.aim,target_world)
		preview_state=state;preview_key=key
	queue_redraw()

func project(point: Vector3) -> Vector2:
	return game.camera.unproject_position(Vector3(point.x/100.0,maxf(0.05,point.z/100.0),-point.y/100.0))

func stroke(points: PackedVector3Array,color: Color,width: float):
	if points.size()<2:return
	var screen=PackedVector2Array()
	for point in points:screen.append(project(point))
	draw_polyline(screen,color,width,true)

func draw_mobile():
	var blue=Color("fb7777") if cancelled else Color("68dfff")
	var gold=Color("fb7777") if cancelled else Color("ffda70")
	for area in preview.get("areas",[]):stroke(area,blue*Color(1,1,1,0.75),2.0)
	for line in preview.get("lines",[]):stroke(line,gold,3.0)
	var trajectory: PackedVector3Array=preview.get("trajectory",PackedVector3Array())
	if trajectory.size()>1:
		stroke(preview.ground,blue*Color(1,1,1,0.55),2);stroke(trajectory,gold,3.5)
		draw_arc(project(trajectory[-1]),8,0,TAU,20,gold,2,true)
	else:draw_arc(project(Preview.world(target_world)),12,0,TAU,24,gold,2,true)

func _ready():
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw():
	if not is_instance_valid(game) or game.paused or game.aim=="" or not pointer_valid:return
	if mobile:draw_mobile();return
	var p=game.sim.players[game.sim.controlled]
	var world=Vector3(p.pos.x/100.0,0.2,-p.pos.y/100.0)
	if game.camera.is_position_behind(world):return
	var origin=game.camera.unproject_position(world)
	var direction=(pointer-origin).normalized()
	var color=Color("f9d16c") if game.aim=="kick" else Color("7de8df")
	draw_line(origin,pointer,color*Color(1,1,1,0.65),3.0,true)
	draw_arc(pointer,19,0,TAU,40,color,3,true)
	var tip=pointer-direction*25
	draw_line(tip,tip-direction.rotated(0.5)*20,color,3,true)
	draw_line(tip,tip-direction.rotated(-0.5)*20,color,3,true)

func _process(_delta):
	if not mobile:
		pointer=get_viewport().get_mouse_position();pointer_valid=true
	queue_redraw()
