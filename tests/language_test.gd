extends SceneTree
const Language=preload("res://scripts/language_settings.gd")
var game
var ui
var passed=0
var failures=[]
var untranslated=[]
var chinese=RegEx.new()
var target_locale="en"
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	if ok:passed+=1
	else:failures.append(message);printerr("FAIL "+message)
func audit(node):
	if (node is Control or node is Label3D) and node.is_visible_in_tree():
		if node is Label or node is Button or node is RichTextLabel or node is Label3D:
			var rendered=String(node.tr(node.text))
			if chinese.search(rendered.replace("中文","")) and not untranslated.has(rendered):untranslated.append(rendered)
	for child in node.get_children():audit(child)
func capture(name):
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://research/language-"+name+".png")
func run():
	chinese.compile("[\\x{4e00}-\\x{9fff}]")
	if "--test-locale=ru_RU" in OS.get_cmdline_user_args():target_locale="ru"
	for system in ["zh_CN","zh-TW","zh_Hant_HK","ZH_cn","en_US","en-GB","ru_RU","ru-BY","RU_ru","fr_FR","ja_JP",""]:
		var expected="zh" if system.to_lower().begins_with("zh") else ("ru" if system.to_lower().begins_with("ru") else "en")
		check(Language.resolve("auto",system)==expected,"system default "+system)
		for explicit in ["en","zh","ru"]:check(Language.resolve(explicit,system)==explicit,"manual override "+explicit+" / "+system)
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.set_process(false);ui=game.touch_controls
	check(TranslationServer.get_locale()==target_locale,"system startup: "+target_locale)
	check(game.menu_title.tr(game.menu_title.text)==("Banjoball · Single Player" if target_locale=="en" else "Banjoball · Одиночная игра"),"menu translated: "+target_locale)
	check(game.menu_title.text=="弹跳足球 · 单机比赛","display translation preserves source strings for logic")
	for letter in "РусскийЁёжй":check(game.font.has_char(letter.unicode_at(0)),"font contains Cyrillic glyph "+letter)
	var format=RegEx.new();format.compile("%[0-9.]*[sdf]")
	for source in Language.catalogs[target_locale].catalog:
		var sample=format.sub(source,"2",true)
		var rendered=String(TranslationServer.translate(sample))
		if chinese.search(rendered.replace("中文","")):untranslated.append({"source":sample,"rendered":rendered})
	if ui:
		ui.frame(0);audit(ui.root);await capture("mobile-menu-"+target_locale)
		ui.pick_language.pressed.emit();await process_frame
		check(ui.picker_overlay.visible and ui.picker_list.get_child_count()==4,"touch language list exposes all four choices")
		ui.choose_picker_item(1);check(TranslationServer.get_locale()=="zh","touch picker changes to Chinese")
		ui.pick_language.pressed.emit();ui.choose_picker_item(2);check(TranslationServer.get_locale()=="en","touch picker changes to English")
		ui.pick_language.pressed.emit();ui.choose_picker_item(3);check(TranslationServer.get_locale()=="ru","touch picker changes to Russian")
		ui.pick_language.pressed.emit();ui.choose_picker_item(Language.OPTIONS.find(target_locale))
		ui.pick_character.pressed.emit();await process_frame;audit(ui.root);await capture("mobile-picker-"+target_locale);ui.close_picker()
		for id in game.sim.Characters.IDS:
			ui.pick_character.select(game.sim.Characters.IDS.find(id));ui.update_selection();game.open_menu();ui.frame(0);await process_frame;audit(ui.root)
			check(ui.character_note.get_line_count()*ui.character_note.get_line_height()<=ui.character_note.size.y+1,"English hero description fits: "+id)
			game.character_select.select(game.sim.Characters.IDS.find(id));ui.start_practice();game.update_visuals(0);ui.frame(0);audit(ui.root)
			for key in ["ability","secondary","sprint","jump"]:
				var b=ui.buttons[key]
				if not b.visible:continue
				for line in String(b.tr(b.text)).split("\n"):
					check(game.font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,b.get_theme_font_size("font_size")).x<=b.size.x-8,"English skill line fits: "+id+" "+line)
		await capture("mobile-play-"+target_locale)
		ui.show_help();audit(ui.root);await capture("mobile-help-"+target_locale);ui.help_panel.hide()
		ui.start_match();game.sim.match_state="playing";game.sim.countdown=0;game.update_visuals(0);ui.frame(0);audit(ui.root)
		game.sim.award_goal(0);game.update_visuals(0);ui.frame(0);audit(ui.root)
		game.open_results();ui.frame(0);audit(ui.root);await capture("mobile-results-"+target_locale)
	else:
		audit(game);await capture("desktop-menu-"+target_locale)
		for id in game.sim.Characters.IDS:
			game.character_select.select(game.sim.Characters.IDS.find(id));game.character_select.item_selected.emit(game.character_select.selected)
			await process_frame;audit(game)
			check(game.character_note.get_line_count()*game.character_note.get_line_height()<=game.character_note.size.y+1,"desktop hero description fits: "+id)
		game.enter_practice();game.update_visuals(0);audit(game);await capture("desktop-play-"+target_locale)
	var score=game.sim.score.duplicate();var ball=game.sim.ball
	game.change_language(1)
	check(TranslationServer.get_locale()=="zh" and game.menu_title.tr(game.menu_title.text)==game.menu_title.text,"live switch restores Chinese without English fallback")
	check(game.experience.preferences.get_value("play","language")=="zh","manual choice enters saved preferences")
	var temp="user://language-preference-test.cfg"
	game.experience.preferences.save(temp)
	check(Language.read_preference(temp)=="zh","manual preference survives disk reload")
	Language.apply(Language.read_preference(temp),"en_US")
	check(TranslationServer.get_locale()=="zh","saved preference wins over a different system language")
	DirAccess.remove_absolute(temp)
	check(game.sim.score==score and game.sim.ball==ball,"switch preserves score and ball state")
	game.open_menu();if ui:ui.frame(0)
	await capture("mobile-menu-zh" if ui else "desktop-menu-zh")
	game.change_language(2);check(TranslationServer.get_locale()=="en","live switch returns to English")
	game.change_language(3)
	check(TranslationServer.get_locale()=="ru" and game.menu_title.tr(game.menu_title.text)=="Banjoball · Одиночная игра","live switch changes to Russian")
	game.experience.preferences.save(temp)
	Language.apply(Language.read_preference(temp),"zh_CN")
	check(TranslationServer.get_locale()=="ru","saved Russian choice overrides Chinese system")
	DirAccess.remove_absolute(temp)
	for language in ["ru","zh","en","ru"]:
		Language.apply(language)
		var message=String(TranslationServer.translate("距离 234 · 松手施放"))
		check(message=={"ru":"Дальность 234 · Отпустите для применения","en":"Range 234 · Release to cast","zh":"距离 234 · 松手施放"}[language],"dynamic translation caches stay separate: "+language)
	game.change_language(0);check(Language.choice=="auto" and game.experience.preferences.get_value("play","language")=="auto","follow system can be restored")
	check(untranslated.is_empty(),target_locale+" UI and catalog contain no untranslated Chinese")
	var name="mobile" if ui else "desktop"
	FileAccess.open("res://research/language-"+name+"-"+target_locale+"-test.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failures":failures,"untranslated":untranslated},"\t"))
	print("LANGUAGE ",name," ",target_locale," ",passed," passed; ",failures.size()," failed")
	quit(0 if failures.is_empty() else 1)
