extends RefCounted
## UI text only: statistics are retained by player index across round resets.
static func player_name(sim,index: int) -> String:
	if index<0:return "无人触球"
	var p=sim.players[index]
	return sim.team_name(p.team).trim_suffix("队")+str(p.number)+"号"

static func team_text(sim,team: int) -> String:
	var lines=PackedStringArray([sim.team_name(team)+"     进球 / 助攻 / 乌龙",""])
	for i in range(sim.players.size()):
		var p=sim.players[i]
		if p.team!=team:continue
		var row=sim.stats[i]
		lines.append("%d 号  %s"%[p.number,sim.Characters.DATA[p.character].name])
		lines.append("        %d  /  %d  /  %d"%[row.goals,row.assists,row.own_goals])
	return "\n".join(lines)

static func history_text(sim) -> String:
	if sim.goal_history.is_empty():return "尚无进球记录。"
	var lines=PackedStringArray()
	for event in sim.goal_history:
		var phase=("加时%d "%event.extra_period) if event.extra_period>0 else (("上半场 " if event.half==1 else "下半场 ") if sim.mode=="tournament" else "")
		var clock="%02d:%02d"%[int(event.elapsed)/60,int(event.elapsed)%60]
		var text=phase+clock+"  %d:%d  "%[event.score[0],event.score[1]]+player_name(sim,event.scorer)
		if event.own_goal:text+=" 乌龙"
		elif event.scorer>=0:text+=" 进球"
		if not event.assists.is_empty():
			var names=PackedStringArray()
			for i in event.assists:names.append(player_name(sim,i))
			text+=" · 助攻 "+"、".join(names)
		lines.append(text)
	return "\n".join(lines)
