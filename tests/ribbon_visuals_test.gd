extends SceneTree
const Ribbons=preload("res://scripts/wc3_ribbons.gd")
const Model=preload("res://scripts/wc3_model.gd")
const Sim=preload("res://scripts/match_sim.gd")
const Visuals=preload("res://scripts/spell_visuals.gd")
var checks=[]
var failed=false
var world: Node3D

class FixtureActor extends Node3D:
	var data={"materials":[{"Layers":[{"FilterMode":3}]}],"textures":[{"Image":"blue ribbon ne.blp","ReplaceableId":0}],"ribbons":[{"bone_index":0,"PivotPoint":[0,0,0],"MaterialID":0,"EmissionRate":30.0,"LifeSpan":0.5,"Gravity":0.0,"Rows":1,"Columns":1,"Color":[1,1,1]}]}
	var clip={"frames":2,"duration":10.0,"loop":true,"ribbons":[[[1,10,10,1,0]],[[1,10,10,1,0]]],"layer_alphas":[[[1]],[[1]]],"layer_textures":[[[0]],[[0]]]}
	var skeleton=Skeleton3D.new()
	var team_color=Color.WHITE
	var tint=Color.WHITE
	var fade_alpha=1.0
	var visibility_amount=1.0
	var animation_time=0.0
	var one_shot=false
	func _init():add_child(skeleton);skeleton.add_bone("ribbon")
	func texture_name(_source):return "res://assets/textures/blue_ribbon_ne.blp.png"

func check(ok: bool,name: String,detail=""):
	checks.append({"test":name,"passed":ok,"detail":detail});failed=failed or not ok
	print(("PASS " if ok else "FAIL ")+name+" "+str(detail))
func _initialize():call_deferred("run")
func fixture():
	var actor=FixtureActor.new();world.add_child(actor)
	var ribbon=Ribbons.new();actor.add_child(ribbon);ribbon.configure(actor)
	return {"actor":actor,"ribbon":ribbon}
func advance(f,delta: float):f.actor.animation_time+=delta;f.ribbon.advance(delta,0.0)
func linear(fps: float) -> Array:
	var f=fixture()
	# Prime at the creation location, then travel exactly 10 world units/s.
	advance(f,0.000001)
	for i in range(int(fps)):
		f.actor.position.x=float(i+1)/fps*10
		advance(f,1.0/fps)
	var snapshot=[]
	for section in f.ribbon.emitters[0].sections:snapshot.append([section.birth,section.above.x])
	f.actor.free();return snapshot
func run():
	world=Node3D.new();root.add_child(world)
	var camera=Camera3D.new();world.add_child(camera);camera.position=Vector3(0,10,10);camera.look_at(Vector3.ZERO);camera.current=true
	var f=fixture()
	f.actor.position=Vector3(100,0,0);advance(f,0.1)
	var emitter=f.ribbon.emitters[0]
	check(emitter.sections.size()==3,"emission rate emits every due section even in a slow render frame")
	check(emitter.sections.all(func(s):return is_equal_approx(s.above.x,100)),"newly placed model never draws a trail from world origin")
	check(emitter.sections[0].above.is_equal_approx(Vector3(100,0,-0.1)) and emitter.sections[0].below.is_equal_approx(Vector3(100,0,0.1)),"native local Y cross-section converts to Godot axes")
	var old=emitter.sections[0].above
	f.actor.position.x+=1;f.actor.rotation.y=PI/2;advance(f,0.1)
	check(emitter.sections[0].above==old,"moving and turning actor does not drag old trail vertices")
	check(emitter.nodes[0].visible and emitter.nodes[0].mesh.get_surface_count()==1,"live trail produces visible textured triangles")
	for slot in [0,3,7]:
		emitter.source.Rows=2;emitter.source.Columns=4;emitter.source.Gravity=100.0
		var values=[1,10,10,0.6,slot]
		var reference=f.ribbon.legacy_mesh(emitter,values).surface_get_arrays(0)
		var packed=f.ribbon.packed_mesh(emitter,values).surface_get_arrays(0)
		var indices=packed[Mesh.ARRAY_INDEX];var same=indices.size()==reference[Mesh.ARRAY_VERTEX].size()
		for v in range(indices.size()):
			var i=indices[v]
			same=same and packed[Mesh.ARRAY_VERTEX][i].is_equal_approx(reference[Mesh.ARRAY_VERTEX][v]) and packed[Mesh.ARRAY_TEX_UV][i].is_equal_approx(reference[Mesh.ARRAY_TEX_UV][v])
		check(same,"packed ribbon keeps original vertices and atlas coordinates "+str(slot))
		var native=f.ribbon.native_mesh(emitter,values).surface_get_arrays(0)
		var same_native=native[Mesh.ARRAY_INDEX].size()==indices.size()
		for v in range(indices.size()):
			var i=native[Mesh.ARRAY_INDEX][v]
			same_native=same_native and native[Mesh.ARRAY_VERTEX][i].is_equal_approx(reference[Mesh.ARRAY_VERTEX][v]) and native[Mesh.ARRAY_TEX_UV][i].is_equal_approx(reference[Mesh.ARRAY_TEX_UV][v])
		check(same_native,"native ribbon keeps original vertices and atlas coordinates "+str(slot))
	emitter.source.Rows=1;emitter.source.Columns=1
	var time=f.ribbon.clock;var count=f.ribbon.section_count()
	advance(f,0)
	check(f.ribbon.clock==time and f.ribbon.section_count()==count,"pause freezes trail lifetime and emission")
	f.ribbon.emitting=false;advance(f,0.55)
	check(f.ribbon.section_count()==0 and not emitter.nodes[0].visible,"stopped emitter drains and hides after original lifetime")
	f.actor.free()
	var first=linear(30);var second=linear(60);var third=linear(144)
	var equal=first.size()==second.size() and first.size()==third.size()
	var error=0.0
	if equal:
		for i in range(first.size()):error=maxf(error,maxf(absf(first[i][1]-second[i][1]),absf(first[i][1]-third[i][1])))
	check(equal and error<0.0001,"30/60/144 FPS preserve section timing and straight-flight shape",{"counts":[first.size(),second.size(),third.size()],"error":error})
	f=fixture();f.actor.data.ribbons[0].Gravity=100.0;advance(f,0.1)
	emitter=f.ribbon.emitters[0];f.ribbon.emitting=false;advance(f,0.2)
	var sample=emitter.sections[0];var age=f.ribbon.clock-sample.birth
	check(is_equal_approx(f.ribbon.section_point(sample,"above").y,-0.5*age*age),"gravity sag uses section age rather than render-frame count")
	f.actor.visible=false;advance(f,0.01)
	check(f.ribbon.section_count()==0 and not f.ribbon.visible,"hidden enemy does not leak its position through retained trails")
	f.actor.visible=true;advance(f,0)
	check(f.ribbon.section_count()==0,"revealing actor does not resurrect old hidden sections")
	var uv=f.ribbon.coordinates({"Columns":4,"Rows":2,"LifeSpan":0.5},5,0.25)
	check(uv.is_equal_approx(Vector2(0.375,0.5)),"non-square atlas uses columns for row lookup and maps age inside selected tile")
	f.actor.free()
	for id in ["h003","h010","h01I","h02E","fx_curveshot"]:
		var model=Model.new();world.add_child(model);model.load_actor(id,Color.WHITE)
		var peak=0
		for clip in model.data.clips:
			model.play(clip.name,true)
			for i in range(ceili(clip.duration*30)+1):
				model.position.x+=0.08;model.advance(1.0/30)
				peak=maxi(peak,model.ribbons.section_count())
		check(peak>1,"original model emits ribbons: "+id,peak)
		model.ribbons.emitting=false
		for i in range(60):model.advance(1.0/30)
		check(model.ribbons.section_count()==0,"original model ribbon tail drains: "+id)
		model.free()
	var scene=Visuals.new();world.add_child(scene)
	var s=Sim.new();s.selected_character="h012";s.reset();s.players[1].pos=Vector2(1500,1200);s.take(0);s.step_ball()
	s.Characters.use(s,0,Vector2(1600,0))
	for i in range(30):s.advance(1.0/60);scene.sync(s,1.0/60)
	check(scene.persistent.has("curve") and scene.persistent.curve.ribbons.section_count()>8,"real curved shot carries original three-emitter trail")
	var model=scene.persistent.curve
	var before=model.ribbons.section_count();scene.sync(s,0)
	check(model.ribbons.section_count()==before,"actual skill pause does not emit or expire ribbon sections")
	s.curve.clear();scene.sync(s,0.01)
	check(not scene.persistent.has("curve") and scene.bursts.any(func(e):return is_same(e.model,model)),"curve end keeps original model alive for death animation and tails")
	for i in range(240):scene.sync(s,1.0/60)
	check(scene.bursts.is_empty(),"curve death and residual trails finish without retained effect nodes")
	var file=FileAccess.open("res://research/ribbon-visuals-tests.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":not failed,"checks":checks},"\t"));file.close()
	world.free();quit(1 if failed else 0)
