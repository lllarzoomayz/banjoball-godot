extends RefCounted
## Cosmetic-only randomness. Native 1.27 0x6f785330 maps Rarity to 2^-Rarity;
## 0x6f1a2f40 picks from cumulative weights. Gameplay RNG is never touched.
var rng=RandomNumberGenerator.new()
var stands=[]
var born=false

func _init():rng.randomize()

func setup(model):
	var ordinary=RegEx.new()
	ordinary.compile("(?i)^stand(?:\\s*-?\\s*(?:[0-9]+|var\\s*[0-9]+))?$")
	stands=[]
	for candidate in model.data.clips:
		if ordinary.search(str(candidate.name).strip_edges()):stands.append(candidate)
	# Static attachments may only contain a synthetic Stand; never mix explicit
	# Swim, Ready, Fourth or Portrait modifiers into ordinary idle candidates.
	stands.sort_custom(func(a,b):return int(a.get("source_index",0))<int(b.get("source_index",0)))
	born=model.play("Birth",true)
	if not born:next_stand(model)

static func pick(candidates: Array, fraction: float) -> Dictionary:
	if candidates.is_empty():return {}
	var total=0.0
	for candidate in candidates:total+=pow(2.0,-float(candidate.get("rarity",0.0)))
	var value=clampf(fraction,0.0,1.0)*total
	for candidate in candidates:
		var weight=pow(2.0,-float(candidate.get("rarity",0.0)))
		if value<weight:return candidate
		value-=weight
	return candidates.back()

func next_stand(model):
	born=false
	var chosen=pick(stands,rng.randf())
	if chosen.is_empty():return
	model.play(str(chosen.name),true)

func advance(model,delta: float):
	if delta<=0 or model.rate<=0 or model.one_shot:
		model.advance(delta);return
	# Slice at clip boundaries so event tracks and particle clocks receive the
	# full elapsed time, even when a frame spans Birth and several idle clips.
	var remaining=delta
	while remaining>0:
		var available=maxf(0.0,(float(model.clip.duration)-model.animation_time)/model.rate)
		if remaining<available:
			model.advance(remaining);return
		# Avoid firing the old clip's time-zero events again at the boundary.
		# This does not enable death/tail optimization on the living attachment.
		model.advance(available,false)
		remaining=maxf(0.0,remaining-available)
		if stands.is_empty() or float(model.clip.duration)<=0:
			model.advance(remaining);return
		next_stand(model)
		if remaining==0:model.advance(0)
