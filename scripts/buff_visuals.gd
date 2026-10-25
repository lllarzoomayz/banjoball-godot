extends RefCounted
## Native war3map.w3h art. These states are already simulated; presentation
## never changes a buff's duration, gameplay RNG, collisions or movement.
static func attachments(p: Dictionary,now: float=0.0) -> Array:
	var result=[]
	if p.possess_time>0:return result
	if p.character=="h01I":result.append(["shadow_trail","fx_shadow_trail","chest"])
	if p.sprint:
		match p.character:
			"h004":result.append(["sprint","fx_super_sprint","origin"])
			"h026":
				result.append(["sprint_left","fx_ogre_left","hand,left"])
				result.append(["sprint_right","fx_ogre_right","hand,right"])
			"h010":result.append(["sprint","fx_sprint","chest"])
			_:
				var effect="fx_stealth_sprint" if p.character=="h00R" else ("fx_divine" if p.character=="h028" else "fx_sprint")
				result.append(["sprint_left",effect,"foot,left"])
				result.append(["sprint_right",effect,"foot,right"])
	if p.slow>0:result.append(["tackle_slow","fx_slow","overhead"])
	if p.ogre_slow>0:result.append(["ogre_slow","fx_slow","overhead"])
	if p.stun>0:result.append(["stun","fx_stun","overhead"])
	if p.silence>0:result.append(["silence","fx_silence","overhead"])
	if p.get("shout_state",{}).get("adrenaline_until",0.0)>now:result.append(["adrenaline","fx_adrenaline","chest"])
	return result
