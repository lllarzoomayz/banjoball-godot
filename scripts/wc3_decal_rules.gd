extends RefCounted
## Source SLK phases; no simulation state or random numbers.
static func lifetime(row: Dictionary) -> float:
	var s=row.source
	return float(s.BirthTime)+float(s.PauseTime)+float(s.Decay) if row.kind=="UBR" else float(s.Lifespan)+float(s.Decay)

static func color(s: Dictionary,prefix: String) -> Color:
	return Color(float(s[prefix+"R"])/255,float(s[prefix+"G"])/255,float(s[prefix+"B"])/255,float(s[prefix+"A"])/255)

static func phase(row: Dictionary,age: float) -> Dictionary:
	var s=row.source;var first=float(s.get("BirthTime",s.get("Lifespan",0)))
	var hold=float(s.get("PauseTime",0));var decay=float(s.Decay)
	var start=color(s,"Start");var middle=color(s,"Middle");var end=color(s,"End")
	if age>=lifetime(row):return {"color":end,"cell":int(s.get("UVDecayEnd",0)),"alive":false}
	if row.kind=="UBR":
		var tint=start.lerp(middle,age/first) if age<first and first>0 else (middle if age<first+hold else middle.lerp(end,(age-first-hold)/maxf(.000001,decay)))
		return {"color":tint,"cell":0,"alive":true}
	var birth=age<first and first>0
	var factor=clampf(age/first if birth else (age-first)/maxf(.000001,decay),0,1)
	var prefix="UVLifespan" if birth else "UVDecay"
	var begin=int(s[prefix+"Start"]);var finish=int(s[prefix+"End"])
	var repeats=float(s.LifespanRepeat if birth else s.DecayRepeat)
	# MDX atlas intervals use end-start cells; fixed cells have equal endpoints.
	var cell=begin if finish<=begin else begin+posmod(floori((finish-begin)*repeats*factor),finish-begin)
	return {"color":start.lerp(middle,factor) if birth else middle.lerp(end,factor),"cell":mini(cell,int(s.Rows)*int(s.Columns)-1),"alive":true}
