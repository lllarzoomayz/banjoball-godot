extends RefCounted
const Catalog=preload("res://scripts/localized_translation.gd")
const OPTIONS=["auto","zh","en","ru"]
const LABELS=["语言：跟随系统","中文","English","Русский"]
static var catalogs={}
static var choice="auto"
static func resolve(saved: String,system_locale: String) -> String:
	if saved in ["zh","en","ru"]:return saved
	var language=system_locale.replace("-","_").to_lower().split("_")[0]
	return language if language in ["zh","ru"] else "en"
static func apply(saved: String,system_locale: String=""):
	choice=saved if saved in OPTIONS else "auto"
	for language in ["en","ru"]:
		if not catalogs.has(language):
			var translation=Catalog.new(language)
			catalogs[language]=translation;TranslationServer.add_translation(translation)
	TranslationServer.set_locale(resolve(choice,OS.get_locale() if system_locale=="" else system_locale))
static func read_preference(path: String) -> String:
	var preferences=ConfigFile.new()
	preferences.load(path)
	return str(preferences.get_value("play","language","auto"))

static func load_choice():
	var saved="auto" if "--test-ui" in OS.get_cmdline_user_args() else read_preference("user://preferences.cfg")
	apply(saved)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-locale="):apply("auto",arg.trim_prefix("--test-locale="))

static func release():
	# Release scripted translation callbacks before the scripting runtime shuts down.
	for translation in catalogs.values():TranslationServer.remove_translation(translation)
	catalogs.clear()
