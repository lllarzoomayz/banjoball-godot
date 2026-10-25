extends SceneTree
const Model=preload("res://scripts/wc3_model.gd")
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok,message):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func run():
	var reference=JSON.parse_string(FileAccess.get_file_as_string("res://research/model-light-reference.json"))
	var models={};var max_position_error=0.0
	for row in reference.rows:
		if not models.has(row.id):
			var a=Model.new();root.add_child(a);a.load_actor(row.id,Color.WHITE);a.events_enabled=false;models[row.id]=a
		var actor=models[row.id];actor.one_shot=true;actor.play(row.clip,true);actor.advance(float(row.time))
		for i in range(row.lights.size()):
			var native=row.lights[i];var light=actor.lights.nodes[i]
			check(light.visible==(native.visibility>0 and native.intensity>0 and native.end>0),row.id+" source visibility "+row.clip+" "+str(row.time))
			check(is_equal_approx(light.light_energy,float(native.visibility)*float(native.intensity)),row.id+" original intensity at "+str(row.time))
			check(is_equal_approx(light.omni_range,float(native.end)/100) and not light.shadow_enabled,row.id+" source outer radius and no added shadows")
			check(light.light_color.is_equal_approx(Color(native.color[0],native.color[1],native.color[2])),row.id+" original RGB")
			# Node motion uses the same 30Hz baked interpolation as model bones.
			var error=light.position.distance_to(Model.CONVERSION*actor.vec(native.position)/100)
			max_position_error=maxf(max_position_error,error)
			check(error<.06,row.id+" light follows original animated pivot within 6 native units")
	var actor=models.h01I;actor.play("Attack Slam",true);actor.advance(.1)
	var before=actor.lights.nodes[0].position;actor.position=Vector3(3,2,1);actor.rotation.y=.7;actor.scale=Vector3.ONE*2
	check(actor.lights.nodes[0].global_position.distance_to(actor.global_transform*before)<.0001,"light follows moved rotated scaled parent")
	actor.hide();check(not actor.lights.nodes[0].is_visible_in_tree(),"hidden actor cannot illuminate its location");actor.show()
	actor.visibility_amount=0;actor.advance(0);check(not actor.lights.nodes[0].visible,"invisible actor disables light even without advancing time")
	actor.visibility_amount=1;actor.fade_alpha=.25;actor.advance(0);check(is_equal_approx(actor.lights.nodes[0].light_energy,3.5),"fading effect fades its light")
	actor.play("Walk",true);actor.advance(0);check(not actor.lights.nodes[0].visible,"switching away from attack extinguishes light immediately")
	var ghost=Model.new();root.add_child(ghost);ghost.load_actor("h01I",Color.WHITE,true);check(not is_instance_valid(ghost.lights),"translucent copies do not duplicate point lights");ghost.free()
	for a in models.values():a.free()
	FileAccess.open("res://research/model-light-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"samples":reference.rows.size(),"max_position_error_world":max_position_error},"\t"))
	print("MODEL LIGHTS ",passed," passed; ",failures.size()," failed");quit(1 if not failures.is_empty() else 0)
