extends Node3D
## Original MDX light timing/color/position, rendered with Godot point lights.
## Godot falloff/energy are a bridge, not calibrated Warcraft photometry.
const Tracks=preload("res://scripts/wc3_uv.gd")
var actor
var nodes=[]

func configure(model):
	actor=model
	for source in actor.data.lights:
		assert(int(source.LightType)==0,"Only source omni lights have been audited")
		var node=OmniLight3D.new()
		node.name=str(source.Name)
		node.shadow_enabled=false
		node.light_specular=0
		node.omni_attenuation=1.0
		node.hide();add_child(node);nodes.append(node)

func sample(source,key,default_value: Array) -> Array:
	var value=source.get(key)
	if value is Array:return value
	if value is float or value is int:return [float(value)]
	return Tracks.sample(value,default_value,float(actor.clip.interval[0])+actor.animation_time*1000,actor.clip.interval,actor.visual_time,actor.data.global_sequences)

func advance():
	if actor.clip.is_empty():return
	var frame=minf(actor.animation_time*30,float(actor.clip.frames)-1)
	var first=int(frame);var second=mini(first+1,int(actor.clip.frames)-1);var blend=frame-first
	for i in range(nodes.size()):
		var node=nodes[i];var source=actor.data.lights[i]
		var visibility=float(sample(source,"Visibility",[1])[0])
		var intensity=maxf(0,float(sample(source,"Intensity",[0])[0]))
		var ambient=float(sample(source,"AmbIntensity",[0])[0])
		assert(is_zero_approx(ambient),"Nonzero source ambient light requires a separate implementation")
		var end=float(sample(source,"AttenuationEnd",[0])[0])
		var start=float(sample(source,"AttenuationStart",[0])[0])
		var color=sample(source,"Color",[1,1,1])
		node.light_color=Color(color[0],color[1],color[2])
		node.light_energy=intensity*clampf(visibility,0,1)*actor.visibility_amount*actor.fade_alpha
		# The source radius is in Warcraft units. Node scale does not alter
		# Godot light range; native scale/falloff behavior still needs comparison.
		node.omni_range=maxf(.001,end/100.0)
		node.set_meta("native_attenuation_start",start)
		node.set_meta("native_attenuation_end",end)
		var a=actor.clip.light_positions[first][i];var b=actor.clip.light_positions[second][i]
		node.position=actor.CONVERSION*Vector3(a[0],a[1],a[2]).lerp(Vector3(b[0],b[1],b[2]),blend)/100.0
		node.visible=end>0 and node.light_energy>.0001
