extends Node3D
## Rendering-only bridge from real skill state/events to local Warcraft assets.
const Model=preload("res://scripts/wc3_model.gd")
const Lightning=preload("res://scripts/wc3_lightning.gd")
const Sfx=preload("res://scripts/sfx_rules.gd")
const Buffs=preload("res://scripts/buff_visuals.gd")
var lightning
var bursts=[]
var timed=[]
var persistent={}
var seen_effects=[]
var player_ref
var last_event=0
var last_goal_flash={}
var particle_batches={}
var pass_tags=[]

static func point(value: Vector3) -> Vector3:
	return Vector3(value.x,value.z,-value.y)/100.0

static func hook_position(sim,projectile: Dictionary,paused: bool=false) -> Vector3:
	var alpha=clampf((sim.timeline-sim.next_ball+sim.BALL_DT)/sim.BALL_DT,0,1) if not paused else 1.0
	return projectile.previous.lerp(projectile.pos,alpha)

static func hook_link(sim,projectile: Dictionary,paused: bool=false) -> Dictionary:
	var p=sim.players[projectile.owner]
	var alpha=clampf((sim.timeline-sim.next_move+sim.MOVE_DT)/sim.MOVE_DT,0,1) if not paused else 1.0
	var ball_alpha=clampf((sim.timeline-sim.next_ball+sim.BALL_DT)/sim.BALL_DT,0,1) if not paused else 1.0
	var xy: Vector2=p.previous.lerp(p.pos,alpha)
	var owner=Vector3(xy.x,xy.y,lerpf(p.previous_z,p.z,ball_alpha))
	# Native AddLightningEx starts at +100; MoveLightningEx uses +75 on
	# subsequent ticks. Only the hook head receives enemy/friendly tint.
	var height=100.0 if projectile.age==0 else 75.0
	return {"code":"ROPE","a":owner+Vector3(0,0,height),"b":hook_position(sim,projectile,paused)+Vector3(0,0,height)}

static func rift_link(rift: Dictionary) -> Dictionary:
	# The original lightning meets the inner edges of the two 50-unit rings.
	var offset: Vector3=rift.b-rift.a;offset.z=0
	offset=offset.normalized()*50.0
	return {"code":"RIFT","a":rift.a+offset,"b":rift.b-offset}

static func black_hole_visual(effect: Dictionary,ground: float=0.0) -> Dictionary:
	# war3map.j BlackHole_iterate32 decrements count before the strict
	# remaining > (3.5 - 1.1) growth check: 35 increments, not a clamp to .5.
	# BlackHoleCast expires on its 36th 32Hz update (1.125 seconds).
	var ticks=maxi(0,floori(float(effect.age)*32.0+.000001))
	return {"position":Vector3(effect.pos.x,effect.pos.y,ground+50.0),
		"scale":.01+mini(ticks,35)*(.5-.01)/1.1/32.0,
		"beam":ticks<36,"caster_height":80.0 if ticks==0 else 60.0}

func clear():
	for child in get_children():child.queue_free()
	bursts.clear();timed.clear();persistent.clear();seen_effects.clear()
	last_goal_flash.clear()
	particle_batches.clear()
	pass_tags.clear()
	last_event=0
	lightning=null

func create(id: String,pos: Vector3,size: float=1.0,looped: bool=false):
	var model=Model.new();add_child(model)
	model.load_actor(id,Color.WHITE)
	if is_instance_valid(model.particles):model.particles.defer_geometry=true
	model.position=point(pos);model.scale=Vector3.ONE*size
	model.one_shot=not looped
	if looped:model.play("Stand",true)
	elif not model.play("Birth",true):model.play(model.data.clips[0].name,true)
	return model

func burst(id: String,pos: Vector3,size: float=1.0,facing: float=0.0,age: float=0.0,pitch: float=-1.0):
	var model=create(id,pos,size)
	# This source effect is immediately destroyed after the wisp enters the
	# ball; the original missile emits its particles in the Death sequence.
	if id=="fx_possess":model.play("Death",true)
	if id=="h02A":model.play("Death",true)
	if id=="fx_pass_me":model.play("Death",true)
	model.rotation.y=facing
	# GoalBlock and EarthPillar use Sfx(..., pitch=0), on h00X's Origin Ref.
	# dummy.mdx sequence 0 rotates native +Z onto +X (+90 deg about Y).
	# Without that attachment pitch the animated blue cap points skyward;
	# yaw alone cannot face it toward the rejected player. Godot maps native
	# Y to -Z, so apply this in model space after the contact-facing yaw.
	if pitch<0:
		pitch=0 if id in ["fx_goal_block","fx_earth_pillar","fx_earth_pillar_end","fx_hook","fx_shadow","fx_metamorph","fx_smash","fx_player_bump","fx_angelic_kick"] else (180 if id=="fx_ball_bump" else 90)
	# Sfx selects a dummy animation by R2I(pitch), not a continuous angle.
	# AngelicKick passes 0.50, therefore uses index 0 just like contact flashes.
	model.rotate_object_local(Vector3.FORWARD,deg_to_rad(90-int(pitch)))
	var tail=0.0
	for emitter in model.data.get("emitters",[]):tail=maxf(tail,float(emitter.LifeSpan))
	for ribbon in model.data.get("ribbons",[]):tail=maxf(tail,float(ribbon.LifeSpan))
	var remaining=age
	while remaining>0.00001:
		var step=minf(remaining,1.0/60);model.advance(step);remaining-=step
	bursts.append({"model":model,"age":age,"life":0.25 if id=="h02A" else float(model.clip.duration)+tail,"fresh":true})
	return model

func attach(key: String,id: String,pos: Vector3,size: float,alive: Dictionary):
	alive[key]=true
	if not persistent.has(key):persistent[key]=create(id,pos,size,true)
	var model=persistent[key]
	model.position=point(pos);model.scale=Vector3.ONE*size
	return model

func attach_buff(key: String,id: String,actor,attachment: String,alive: Dictionary):
	alive[key]=true
	if not persistent.has(key):
		var effect=create(id,Vector3.ZERO,1.0,true)
		if effect.play("Birth",true):effect.one_shot=true;effect.set_meta("buff_birth",true)
		persistent[key]=effect
	var model=persistent[key]
	model.set_meta("bound_actor",actor);model.set_meta("attachment",attachment)
	model.global_transform=actor.attachment_transform(attachment)
	model.visibility_amount=actor.visibility_amount
	return model

func advance_bound(model,delta: float):
	if model.has_meta("bound_actor"):
		var actor=model.get_meta("bound_actor")
		if not is_instance_valid(actor) or not actor.visible:
			model.hide();return
		model.global_transform=actor.attachment_transform(model.get_meta("attachment"))
		model.visibility_amount=actor.visibility_amount
	if delta>0 and model.get_meta("buff_birth",false):
		var birth_left=maxf(0,float(model.clip.duration)-model.animation_time)/maxf(.000001,model.rate)
		var first=minf(delta,birth_left)
		model.advance(first);delta-=first
		if first>=birth_left:
			model.remove_meta("buff_birth")
			# A model without Stand holds its final Birth pose until destruction.
			if model.play("Stand",true):model.one_shot=false
	model.advance(delta)

func schedule_effect(event: Dictionary,pos: Vector3):
	var model=create(event.model,pos,event.scale)
	model.rotation.y=event.facing
	if model.active_clip.to_lower().begins_with("birth"):model.set_meta("buff_birth",true)
	var entry={"model":model,"time":event.time,"elapsed":0.0,"destroy_after":float(event.destroy_after),"destroyed":false}
	timed.append(entry)
	return entry

func advance_timed(entry: Dictionary,target_age: float):
	# Absolute simulation time retains the original timer through a skipped
	# render frame or an early cooldown reset. It cannot advance while paused.
	while entry.elapsed<target_age or (not entry.destroyed and entry.elapsed>=entry.destroy_after):
		if not entry.destroyed and entry.elapsed>=entry.destroy_after:
			entry.destroyed=true;entry.model.remove_meta("buff_birth");entry.model.one_shot=true
			entry.model.play("Death",true);entry.model.advance(0)
			if entry.model.visual_tail_finished():break
		var step=minf(1.0/60,target_age-entry.elapsed)
		if not entry.destroyed:step=minf(step,entry.destroy_after-entry.elapsed)
		if step<=0:break
		advance_bound(entry.model,step);entry.elapsed+=step
		if entry.destroyed and entry.model.visual_tail_finished():break

static func text_visible(sim,event: Dictionary) -> bool:
	if event.has("audience_owner") and event.audience_owner!=sim.controlled:return false
	if event.has("audience_team") and event.audience_team!=sim.players[sim.controlled].team:return false
	return true

func sync(sim,delta: float,paused: bool=false,actors: Array=[],ball_actor=null,ground_sampler: Callable=Callable()):
	if sim.players.is_empty():clear();return
	if player_ref==null or not is_same(player_ref,sim.players[0]):
		clear();player_ref=sim.players[0]
	var alive={}
	if not is_instance_valid(lightning):lightning=Lightning.new();add_child(lightning)
	var links=[]
	var currently_seen=[]
	for effect in sim.skill_effects:
		currently_seen.append(effect)
		if effect.kind=="black_hole":
			var key="black_hole:"+str(effect.owner)+":"+str(effect.pos)
			var ground=float(ground_sampler.call(Vector2(effect.pos.x,effect.pos.y))) if ground_sampler.is_valid() else 0.0
			var visual=black_hole_visual(effect,ground)
			# This is CreateUnit(h002), not AddSpecialEffect: it starts in Stand.
			attach(key,"fx_black_hole",visual.position,visual.scale,alive)
			if visual.beam:links.append({"code":"BKHL","a":visual.position,"b":sim.Characters.world_position(sim.players[effect.owner])+Vector3(0,0,visual.caster_height)})
			continue
		var known=false
		for previous in seen_effects:
			if is_same(previous,effect):known=true;break
		if known:continue
		match effect.kind:
			"slam":burst("fx_slam",effect.pos,1.0,0.0,effect.age)
			"blink":burst(effect.get("model","fx_shadow"),effect.pos,1.0,0.0,effect.age)
			"body_bump":
				var id=effect.get("model","fx_player_bump")
				# Keep the original blue asset and scale. Coalesce repeated contact
				# flashes from one held stick; gameplay entry events remain intact.
				if id=="fx_goal_block":
					if sim.timeline-float(last_goal_flash.get(effect.owner,-INF))<0.12:continue
					last_goal_flash[effect.owner]=sim.timeline
				burst(id,effect.pos,effect.get("scale",0.7),effect.get("facing",0.0),effect.age)
			"swap_link":
				burst("fx_swap_caster",effect.pos,1.0,0.0,effect.age)
				burst("fx_swap_target",effect.end,1.0,0.0,effect.age)
			"smash":
				var forward=Vector3(cos(effect.facing),sin(effect.facing),0)*350.0
				for i in range(3):burst("fx_smash",effect.pos+forward*float(i+1)/4.0,[0.01,0.1,0.5][i],effect.facing+PI if i==2 else 0.0,effect.age)
	seen_effects=currently_seen
	for event in sim.native_visuals:
		if event.id<=last_event:continue
		last_event=event.id
		var text_life=float(event.get("text_lifetime",3.0))
		if sim.timeline-event.time>=maxf(text_life,float(event.get("destroy_after",0))+3.0 if event.model!="" else 0.0):continue
		var owner=int(event.get("owner",-1))
		if owner>=0 and (owner>=actors.size() or not actors[owner].visible):continue
		if event.model!="":
			var position: Vector3=event.pos
			if event.get("sfx_clamp_to_terrain",false) or event.get("on_terrain",false):
				var ground=float(ground_sampler.call(Vector2(position.x,position.y))) if ground_sampler.is_valid() else 0.0
				position=Sfx.terrain_position(position,ground) if not event.get("on_terrain",false) else Vector3(position.x,position.y,ground)
			var model
			if event.has("destroy_after"):model=schedule_effect(event,position).model
			else:model=burst(event.model,position,event.scale,event.facing,maxf(0,sim.timeline-event.time),event.get("pitch",-1.0))
			if owner>=0:
				model.set_meta("bound_actor",actors[owner]);model.set_meta("attachment",event.attachment)
				model.global_transform=actors[owner].attachment_transform(event.attachment)
				model.visibility_amount=actors[owner].visibility_amount
		if event.has("message") and sim.timeline-event.time<text_life and text_visible(sim,event):
			var tag=Label3D.new();tag.text=event.message;tag.font=load("res://assets/fonts/msyh.ttc")
			tag.font_size=roundi(40*float(event.get("text_size",.022))/.022);tag.pixel_size=.01;tag.outline_size=8;tag.modulate=Color(event.get("text_color","a9d5f5"))
			tag.billboard=BaseMaterial3D.BILLBOARD_ENABLED;tag.no_depth_test=true
			add_child(tag)
			pass_tags.append({"node":tag,"time":event.time,"life":text_life,"origin":point(event.pos+event.get("text_offset",Vector3(-40,0,150)))})
	for effect in sim.skill_effects:
		if effect.kind=="swap_link" and effect.age<0.4:links.append({"code":"SWAP","a":effect.pos+Vector3(0,0,100),"b":effect.end+Vector3(0,0,100)})
	for index in range(sim.players.size()):
		var p=sim.players[index]
		if p.shadow_return>0:
			var shadow_key="shadow:"+str(index);alive[shadow_key]=true
			if not persistent.has(shadow_key):
				var ghost=Model.new();add_child(ghost)
				ghost.load_actor("h02B",sim.team_color(p.team),true)
				ghost.tint=Color(128.0/255,128.0/255,128.0/255);ghost.fade_alpha=128.0/255
				ghost.set_meta("remove_immediately",true);persistent[shadow_key]=ghost
			persistent[shadow_key].position=point(Vector3(p.shadow_origin.x,p.shadow_origin.y,0))
			persistent[shadow_key].rotation.y=p.get("shadow_facing",0.0)
			persistent[shadow_key].set_team_color(sim.team_color(p.team))
		if p.invisible and p.team!=0:continue
		if index<actors.size() and is_instance_valid(actors[index]) and actors[index].visible:
			for entry in Buffs.attachments(p,sim.timeline):
				attach_buff("buff:"+str(index)+":"+entry[0],entry[1],actors[index],entry[2],alive)
		if p.pull_time>0:links.append({"code":"DRAL","a":sim.Characters.world_position(p)+Vector3(0,0,60),"b":sim.ball})
		if p.ability_kind=="powershot" and p.ability_delay>0:
			if index<actors.size() and is_instance_valid(actors[index]) and actors[index].visible:
				attach_buff("charge:"+str(index),"fx_powershot_charge",actors[index],"overhead",alive)
			elif actors.is_empty():
				# Standalone simulation previews have no rendered attachment owner.
				attach("charge:"+str(index),"fx_powershot_charge",sim.Characters.world_position(p)+Vector3(0,0,p.catch_height),1.0,alive)
	if not sim.curve.is_empty():
		if is_instance_valid(ball_actor):
			# Curveshot__cast attaches to the ball's chest, not its velocity.
			# Use the rendered ball so fixed-step interpolation cannot separate them.
			if ball_actor.visible:attach_buff("curve","fx_curveshot",ball_actor,"chest",alive)
		else:
			attach("curve","fx_curveshot",sim.ball,1.0,alive)
	for projectile in sim.projectiles:
		var owner_pos=sim.Characters.world_position(sim.players[projectile.owner])
		if projectile.kind=="hook":links.append(hook_link(sim,projectile,paused))
		elif projectile.kind=="swap":links.append({"code":"LINK","a":owner_pos+Vector3(0,0,80),"b":projectile.pos})
	for rift in sim.rifts:
		if rift.a!=null and rift.b!=null:links.append(rift_link(rift))
	lightning.update_links(links,sim.timeline)
	for key in persistent.keys():
		if not alive.has(key):
			var model=persistent[key]
			if model.get_meta("remove_immediately",false):
				model.queue_free();persistent.erase(key);continue
			# Hidden enemy effects must vanish without a revealing death trail.
			if model.has_meta("bound_actor"):
				var actor=model.get_meta("bound_actor")
				if not is_instance_valid(actor) or not actor.visible:
					model.hide();model.queue_free();persistent.erase(key);continue
			model.remove_meta("buff_birth")
			model.one_shot=true
			if model.play("Death",true):
				var tail=0.0
				for emitter in model.data.get("emitters",[]):tail=maxf(tail,float(emitter.LifeSpan))
				for ribbon in model.data.get("ribbons",[]):tail=maxf(tail,float(ribbon.LifeSpan))
				bursts.append({"model":model,"age":0.0,"life":float(model.clip.duration)+tail})
			else:model.queue_free()
			persistent.erase(key)
		else:advance_bound(persistent[key],delta)
	var held=[]
	for entry in timed:
		advance_timed(entry,maxf(0,sim.timeline-entry.time))
		if entry.destroyed and entry.model.visual_tail_finished():entry.model.queue_free()
		else:held.append(entry)
	timed=held
	var survivors=[]
	for entry in bursts:
		if entry.get("fresh",false):entry.fresh=false
		else:entry.age+=delta;advance_bound(entry.model,delta)
		if entry.age<entry.life and not entry.model.visual_tail_finished():survivors.append(entry)
		else:entry.model.queue_free()
	bursts=survivors
	for entry in pass_tags:
		var age=maxf(0,sim.timeline-entry.time)
		entry.node.position=entry.origin+Vector3.UP*age*.5
		entry.node.modulate.a=clampf((entry.life-age)/.5,0,1)
		if age>=entry.life:entry.node.queue_free()
	pass_tags=pass_tags.filter(func(entry):return sim.timeline-entry.time<entry.life)
	flush_particles()

func flush_particles():
	# Additive emitters with the same source texture/material can share a mesh.
	# Integrate all effects first, then render each emitter exactly once, including
	# effects that needed several catch-up steps during their creation.
	for batch in particle_batches.values():batch.geometry.begin()
	for model in get_children():
		if not model is Model or model.is_queued_for_deletion() or not model.visible:continue
		if not is_instance_valid(model.particles):continue
		for index in range(model.particles.emitters.size()):
			var emitter=model.particles.emitters[index]
			if int(emitter.source.FilterMode)==1:
				var key=str(model.data.actor.id)+":"+str(index)+":"+model.team_color.to_html()
				if not particle_batches.has(key):
					var node=MeshInstance3D.new();node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					node.material_override=emitter.mesh.material_override;add_child(node)
					var geometry=preload("res://scripts/particle_geometry.gd").new()
					geometry.begin();particle_batches[key]={"node":node,"geometry":geometry}
				emitter.batch_geometry=particle_batches[key].geometry
			model.particles.draw_emitter(emitter)
	for batch in particle_batches.values():batch.geometry.commit(batch.node)
