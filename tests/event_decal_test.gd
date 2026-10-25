extends SceneTree
const Rules=preload("res://scripts/wc3_decal_rules.gd")
var passed=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func run():
	var catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/events/decals.json"))
	check(catalog.terrain_native_water_vertices==0,"actual map has no native W3E water; decorative pools are not water classification")
	var foot=catalog.definitions["FPT:FBR1"]
	check(Rules.lifetime(foot)==7,"original foot lasts 2 plus 5 seconds")
	check(Rules.phase(foot,0).cell==81 and Rules.phase(foot,6.9).cell==81,"foot keeps the original atlas cell through fade")
	check(is_equal_approx(Rules.phase(foot,0).color.a,128.0/255) and is_equal_approx(Rules.phase(foot,2).color.a,128.0/255),"original footprint alpha holds for two seconds")
	check(is_equal_approx(Rules.phase(foot,4.5).color.a,64.0/255) and not Rules.phase(foot,7).alive,"five-second fade reaches half at 4.5 and expires at seven")
	var blood=catalog.definitions["SPL:EBL1"]
	check(Rules.phase(blood,0).cell==16 and Rules.phase(blood,1).cell==23 and Rules.phase(blood,1.999).cell==30 and Rules.phase(blood,2).cell==31,"source blood sequence transitions from lifespan interval to fixed decay frame")
	check(Rules.lifetime(blood)==122,"long ground stains keep source 120-second decay")
	var uber=catalog.definitions["UBR:THND"]
	check(is_equal_approx(Rules.lifetime(uber),4.2),"ThunderClap source lifetime includes birth hold decay")
	check(is_equal_approx(Rules.phase(uber,.1).color.a,.5) and Rules.phase(uber,1).color.a==1 and is_equal_approx(Rules.phase(uber,3.2).color.a,.5),"UberSplat fades in holds then fades out")
	for key in catalog.definitions:
		var row=catalog.definitions[key];var state=Rules.phase(row,0)
		check(state.cell>=0 and state.cell<int(row.source.get("Rows",1))*int(row.source.get("Columns",1)),"valid initial tile "+key)
	var game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.enter_practice()
	var renderer=game.event_decals;var actor=game.actors[0];actor.play("Walk",true);actor.position=Vector3.ZERO
	actor.advance(.5)
	check(renderer.live_count()>0,"real actor Walk events create ground instances")
	check(renderer.batches.size()==1,"footprints share one atlas and draw batch")
	var before=renderer.live_count();var batch=renderer.batches.values()[0];var fixed=batch.entries[0].transform
	actor.position=Vector3(8,0,3);actor.advance(.5)
	check(batch.entries[0].transform==fixed,"old footprints remain fixed when the character moves away")
	check(renderer.live_count()>before,"later footfall emits another independent ground instance")
	game.paused=true;var clock=renderer.clock;renderer.advance(3)
	check(renderer.clock==clock,"pause freezes decal age even if called with a positive delta")
	game.paused=false;renderer.advance(7.1);check(renderer.live_count()==0 and batch.mesh.visible_instance_count==0,"expired footprints stop drawing and release pool slots")
	var fake={"type":"FPT","code":"FBR1","rotation":[0,0,0,1]}
	actor.position=Vector3.ZERO;actor.rotation.y=.75
	for i in range(65):renderer.model_event(actor,fake,Vector3(float(i)/100,0,0))
	batch=renderer.batches.values()[0]
	check(batch.capacity==128 and batch.entries.size()==65 and batch.mesh.visible_instance_count==65,"instance storage grows without losing earlier footprints")
	check(absf(batch.entries[0].transform.basis.get_euler().y-.75)<.00001,"original footprint rotates with actor heading")
	var half_extent=batch.entries[0].transform.basis.x.length();actor.scale=Vector3.ONE*3
	renderer.model_event(actor,fake,Vector3.ZERO)
	check(is_equal_approx(batch.entries[-1].transform.basis.x.length(),half_extent),"SLK footprint extent is independent of character mesh scale")
	var n=renderer.live_count();actor.hide();renderer.model_event(actor,fake,Vector3.ZERO)
	check(renderer.live_count()==n,"invisible enemy cannot leave a revealing new stamp");actor.show()
	renderer.model_event(actor,fake,Vector3(1000,0,1000));check(renderer.live_count()==n,"events outside original terrain are not projected onto a clamped edge")
	actor.rotation=Vector3(0,0,PI/2);renderer.model_event(actor,{"type":"UBR","code":"THND","rotation":[0,0,0,1]},Vector3.ZERO)
	var circle=renderer.batches.values()[-1].entries[-1].transform
	check(absf(circle.basis.x.cross(circle.basis.z).y)>1,"pitched effect still creates a nondegenerate horizontal ground mark")
	game.rebuild_actors();check(renderer.live_count()==0,"new match clears old field stamps")
	game.free()
	FileAccess.open("res://research/event-decal-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures},"\t"))
	print("EVENT DECALS ",passed," passed; ",failures.size()," failed");quit(1 if not failures.is_empty() else 0)
